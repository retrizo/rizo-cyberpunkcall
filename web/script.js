// ==== ELEMENTOS ====
const precall = document.getElementById('precall')
const precallName = document.getElementById('precall-name')

// mini HUD cyberpunk
const precallAvatarImg = document.getElementById('precall-avatar')

// painel principal + legenda
const callPanel = document.getElementById('call-panel')
const subtitle = document.getElementById('subtitle')
const avatar = document.getElementById('avatar')
const callerName = document.getElementById('caller-name')
const subName = document.getElementById('subtitle-name')
const subText = document.getElementById('subtitle-text')

// ==== PLAYER ÚNICO (serve para .ogg local e TTS/base64) ====
const lineAudio = document.getElementById('line-audio')
let currentUrl = null   // para revogar blob URL do TTS
let queue = []
let busy = false
let pendingName = 'UNKNOWN'
let pendingText = ''

function setPendingSubtitle(name, text) {
  if (typeof name === 'string') pendingName = name
  if (typeof text === 'string') pendingText = text
}
function applySubtitleNow() {
  subName.textContent = pendingName || 'UNKNOWN'
  subText.textContent = pendingText || ''
}

// logs de erro detalhados
function logAudioState(prefix) {
  if (!lineAudio) return
  console.log(prefix, {
    src: lineAudio.src,
    error: lineAudio.error && lineAudio.error.code,
    networkState: lineAudio.networkState,
    readyState: lineAudio.readyState
  })
}

if (lineAudio) {
  lineAudio.autoplay = false
  lineAudio.muted = false
  lineAudio.preload = 'auto'
  lineAudio.volume = 1.0

  lineAudio.onplay = () => {
    applySubtitleNow()
    subtitle.classList.remove('hidden')
  }
  lineAudio.onended = () => {
    subtitle.classList.add('hidden')
    // Cleanup is now handled by AudioQueue
    audioQueue.busy = false
    audioQueue._processNext()
  }
  lineAudio.onerror = () => {
    logAudioState('[NUI] line-audio onerror')
    subtitle.classList.add('hidden')
    // Error handling is now managed by AudioQueue
    audioQueue._handlePlaybackError(new Error('Audio element error'))
  }
}

// ===== OPTIMIZED AUDIO QUEUE SYSTEM =====

/**
 * Audio queue management with performance optimizations and resource cleanup
 */
class AudioQueue {
  constructor() {
    this.queue = []
    this.busy = false
    this.currentUrl = null
    this.maxQueueSize = 10 // Prevent memory overflow
    this.retryAttempts = 3
    this.retryDelay = 100 // ms
  }

  /**
   * Add audio item to queue with validation and deduplication
   * @param {Object} item - Audio item {kind, src/base64, volume, priority}
   */
  enqueue(item) {
    if (!this._validateItem(item)) {
      debugLog('Invalid audio item rejected:', item)
      return false
    }

    // Queue size management
    if (this.queue.length >= this.maxQueueSize) {
      debugLog('Queue full, removing oldest item')
      this._cleanupQueueItem(this.queue.shift())
    }

    // Priority queue insertion
    const priority = item.priority || 0
    let insertIndex = this.queue.findIndex(queued => (queued.priority || 0) < priority)
    if (insertIndex === -1) insertIndex = this.queue.length

    this.queue.splice(insertIndex, 0, item)
    debugLog('Audio queued:', { type: item.kind, priority, queueSize: this.queue.length })

    this._processNext()
    return true
  }

  /**
   * Process next item in queue with error handling and retry logic
   */
  async _processNext() {
    if (this.busy || this.queue.length === 0 || !lineAudio) return

    this.busy = true
    const item = this.queue.shift()

    try {
      await this._prepareAudio()
      await this._loadAudioSource(item)
      await this._playWithRetry(item)
    } catch (error) {
      debugLog('Audio processing failed:', error)
      this._handlePlaybackError(error)
    }
  }

  /**
   * Prepare audio element for new source
   */
  async _prepareAudio() {
    return new Promise(resolve => {
      // Stop current playback
      if (!lineAudio.paused) {
        lineAudio.pause()
      }
      lineAudio.currentTime = 0

      // Cleanup previous URL
      this._cleanupCurrentUrl()

      // Wait for reset to complete
      requestAnimationFrame(() => resolve())
    })
  }

  /**
   * Load audio source with optimized blob handling
   * @param {Object} item - Audio item
   */
  async _loadAudioSource(item) {
    // Set volume first
    lineAudio.volume = Math.max(0, Math.min(1, item.volume || 1.0))

    if (item.kind === 'file') {
      this.currentUrl = this._normalizeFilePath(item.src)
      lineAudio.src = this.currentUrl
    } else if (item.kind === 'b64') {
      this.currentUrl = await this._createOptimizedBlob(item.base64, item.mime)
      lineAudio.src = this.currentUrl
    } else {
      throw new Error(`Unknown audio type: ${item.kind}`)
    }

    // Preload for better performance
    if (lineAudio.load) lineAudio.load()
  }

  /**
   * Play audio with retry mechanism
   * @param {Object} item - Audio item for context
   */
  async _playWithRetry(item, attempt = 1) {
    try {
      const playPromise = lineAudio.play()

      if (playPromise && typeof playPromise.catch === 'function') {
        await playPromise
      }

      debugLog('Audio playing successfully:', { type: item.kind, attempt })
    } catch (error) {
      if (attempt < this.retryAttempts) {
        debugLog(`Play attempt ${attempt} failed, retrying...`, error)
        await new Promise(resolve => setTimeout(resolve, this.retryDelay * attempt))
        return this._playWithRetry(item, attempt + 1)
      }

      // Final attempt failed
      if (error.name === 'NotAllowedError' && !audioUnlocked) {
        this._handleUnlockRequired()
      } else {
        throw error
      }
    }
  }

  /**
   * Handle playback errors and cleanup
   */
  _handlePlaybackError(error) {
    debugLog('Playback error handled:', error.message)
    this._cleanupCurrentUrl()
    this.busy = false

    // Continue with next item after short delay
    setTimeout(() => this._processNext(), 50)
  }

  /**
   * Handle audio unlock requirement
   */
  _handleUnlockRequired() {
    debugLog('Audio unlock required')
    if (!audioUnlocked) {
      showUnlockOverlay(() => {
        // Retry current item after unlock
        this._playWithRetry({ kind: 'retry' }).catch(() => {
          this.busy = false
          this._processNext()
        })
      })
    }
  }

  /**
   * Validate audio item structure
   */
  _validateItem(item) {
    if (!item || typeof item !== 'object') return false
    if (!['file', 'b64'].includes(item.kind)) return false

    if (item.kind === 'file' && !item.src) return false
    if (item.kind === 'b64' && !item.base64) return false

    return true
  }

  /**
   * Normalize file path for consistent loading
   */
  _normalizeFilePath(src) {
    let path = String(src || '').replace(/\\/g, '/')
    if (!/^assets\//i.test(path) && /\.(ogg|mp3|wav)$/i.test(path)) {
      path = 'assets/' + path
    }
    return path
  }

  /**
   * Create optimized blob from base64 with worker offloading for large files
   */
  async _createOptimizedBlob(base64, mime = 'audio/mpeg') {
    try {
      // For large base64 strings, consider using a worker
      if (base64.length > 1000000) { // > 1MB
        return await this._createBlobWithWorker(base64, mime)
      }

      // Standard blob creation for smaller files
      const byteChars = atob(base64)
      const bytes = new Uint8Array(byteChars.length)

      for (let i = 0; i < byteChars.length; i++) {
        bytes[i] = byteChars.charCodeAt(i)
      }

      const blob = new Blob([bytes], { type: mime })
      return URL.createObjectURL(blob)
    } catch (error) {
      debugLog('Blob creation failed:', error)
      throw new Error('Failed to create audio blob')
    }
  }

  /**
   * Create blob using Web Worker for large files (future enhancement)
   */
  async _createBlobWithWorker(base64, mime) {
    // Fallback to standard method for now
    // In production, implement Web Worker for heavy operations
    return this._createOptimizedBlob(base64, mime)
  }

  /**
   * Cleanup current URL resources
   */
  _cleanupCurrentUrl() {
    if (this.currentUrl && this.currentUrl.startsWith('blob:')) {
      URL.revokeObjectURL(this.currentUrl)
      this.currentUrl = null
    }
  }

  /**
   * Cleanup queue item resources
   */
  _cleanupQueueItem(item) {
    if (item && item.kind === 'b64' && item._blobUrl) {
      URL.revokeObjectURL(item._blobUrl)
    }
  }

  /**
   * Clear entire queue and cleanup resources
   */
  clear() {
    // Cleanup all queued blob URLs
    this.queue.forEach(item => this._cleanupQueueItem(item))

    this.queue = []
    this.busy = false
    this._cleanupCurrentUrl()

    if (lineAudio && !lineAudio.paused) {
      lineAudio.pause()
      lineAudio.currentTime = 0
    }

    debugLog('Audio queue cleared')
  }

  /**
   * Get queue status for debugging
   */
  getStatus() {
    return {
      queueLength: this.queue.length,
      busy: this.busy,
      hasCurrentUrl: !!this.currentUrl,
      audioReady: lineAudio && lineAudio.readyState >= 2
    }
  }
}

// Create global audio queue instance
const audioQueue = new AudioQueue()

// Legacy functions for compatibility
function enqueue(item) {
  return audioQueue.enqueue(item)
}

function playNext() {
  // This is now handled internally by AudioQueue
  audioQueue._processNext()
}

// ==== AUDIO PRECALL ====
let precallAudio = document.getElementById('precall-audio')
if (!precallAudio) {
  precallAudio = document.createElement('audio')
  precallAudio.id = 'precall-audio'
  precallAudio.src = 'assets/precall.ogg'
  precallAudio.preload = 'auto'
  precallAudio.style.display = 'none'
  document.body.appendChild(precallAudio)
}

function playPrecallSound(volume = 0.6, loop = false) {
  if (!precallAudio) return
  try {
    precallAudio.pause()
    precallAudio.currentTime = 0
    precallAudio.volume = volume
    precallAudio.loop = !!loop
    precallAudio.play().catch(() => {})
  } catch (e) {}
}
function stopPrecallSound() {
  if (!precallAudio) return
  try {
    precallAudio.pause()
    precallAudio.currentTime = 0
    precallAudio.loop = false
  } catch (e) {}
}

// ==== ESTÁGIO / TIMERS ====
let stageTimer = null
let autoTimeoutTimer = null
let callAnswered = false
let currentPayload = null
let currentCallId = null
let debugMode = false // Will be set by payload from client

// Debug function
function debugLog(...args) {
  if (debugMode) {
    console.log('[NUI]', ...args)
  }
}

function clearStageTimer() {
  if (stageTimer) {
    clearTimeout(stageTimer)
    stageTimer = null
  }
}

function clearAutoTimeout() {
  if (autoTimeoutTimer) {
    clearTimeout(autoTimeoutTimer)
    autoTimeoutTimer = null
  }
}

// ==== CALL ACTION HANDLER ====
function handleCallAction(action) {
  debugLog('handleCallAction called with:', action, 'for Call ID:', currentCallId)

  // Send action to client.lua with call ID
  fetch(`https://rizo-cyberpunkcall/callAction`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ action: action, callId: currentCallId })
  }).catch(() => {});

  // Clear timers since user interacted
  clearAutoTimeout();
  clearStageTimer();

  if (action === 'accept') {
    callAnswered = true;
    // Hide precall and show full panel for answered call
    hidePrecall();
    stopPrecallSound();

    // Show the full call panel since call was answered
    setTimeout(() => {
      showFullPanel(currentPayload || {});
    }, 200);
  } else {
    // For reject or timeout, just hide everything
    hidePrecall();
    stopPrecallSound();
  }
}

// ==== UPDATE KEY HINTS ====
function updateKeyHints(answerKey, rejectKey, showHints) {
  const answerKeyElement = document.getElementById('answer-key')
  const rejectKeyElement = document.getElementById('reject-key')
  const actionsElement = document.getElementById('precall-actions')

  if (answerKeyElement) answerKeyElement.textContent = answerKey || 'E'
  if (rejectKeyElement) rejectKeyElement.textContent = rejectKey || 'R'

  if (actionsElement) {
    actionsElement.style.display = showHints ? 'flex' : 'none'
  }
}

// ==== MINI HUD ====
function showPrecall(name, autoTimeout = 5000) {
  precallName.textContent = name || 'UNKNOWN'
  precall.classList.remove('hidden')

  // Set auto timeout if configured
  if (autoTimeout && autoTimeout > 0) {
    clearAutoTimeout()
    const timeoutCallId = currentCallId // Capture the call ID for this timeout
    debugLog('Setting timeout for Call ID:', timeoutCallId, 'duration:', autoTimeout)
    autoTimeoutTimer = setTimeout(() => {
      // Only timeout if this is still the current call
      if (currentCallId === timeoutCallId) {
        debugLog('Timeout executing for valid Call ID:', timeoutCallId)
        handleCallAction('timeout')
      } else {
        debugLog('Timeout ignored for old Call ID:', timeoutCallId, 'current:', currentCallId)
      }
    }, autoTimeout)
  }
}
function hidePrecall() {
  clearAutoTimeout()
  precall.classList.add('precall-hide')
  stageTimer = setTimeout(() => {
    precall.classList.remove('precall-hide')
    precall.classList.add('hidden')
  }, 180)
}

// ==== PAINEL COMPLETO ====
function showFullPanel(payload) {
  avatar.src = payload.avatar || 'assets/judy.webp'
  const nm = payload.name || 'UNKNOWN'
  const sub = payload.subtitle || ''

  callerName.textContent = nm
  // guardamos legenda como pendente; ela aparece no onplay do áudio
  setPendingSubtitle(nm, sub)

  callPanel.classList.remove('hidden')

  // micro “impacto”
  callPanel.style.animation = 'none'
  void callPanel.offsetWidth
  callPanel.style.animation = ''
}

// ==== DESBLOQUEIO DE ÁUDIO ====
let audioUnlocked = false
let unlockOverlay = null
function showUnlockOverlay(onDone) {
  if (audioUnlocked) { onDone && onDone(); return }
  if (!unlockOverlay) {
    unlockOverlay = document.createElement('div')
    unlockOverlay.style.cssText = 'position:fixed;inset:0;display:flex;align-items:center;justify-content:center;background:rgba(0,0,0,.35);z-index:9999;pointer-events:auto'
    unlockOverlay.innerHTML = `
      <div style="backdrop-filter: blur(4px); background: rgba(0,0,0,.75); border: 1px solid #444; border-left: 3px solid #fff; color: #fff; padding: 16px 18px; border-radius: 10px; box-shadow: 0 10px 28px rgba(0,0,0,.45); font-family: ui-sans-serif, system-ui, -apple-system, 'Inter', Arial, sans-serif;">
        <div style="font-weight:800; margin-bottom:6px;">Clique para habilitar o áudio</div>
        <div style="opacity:.85; font-size: 13px;">Depois disso, a voz e os áudios vão tocar normalmente.</div>
      </div>
    `
  }
  const prev = document.body.style.pointerEvents
  document.body.style.pointerEvents = 'auto'
  document.body.appendChild(unlockOverlay)
  unlockOverlay.onclick = async () => {
    try {
      const Ctx = window.AudioContext || window.webkitAudioContext
      if (Ctx) {
        const ctx = new Ctx()
        if (ctx.state === 'suspended') await ctx.resume()
      }
      // “ping” silencioso
      if (lineAudio) {
        lineAudio.muted = true
        lineAudio.src = 'assets/precall.ogg'
        try { await lineAudio.play() } catch {}
        try { lineAudio.pause(); lineAudio.currentTime = 0 } catch {}
        lineAudio.muted = false
      }
      audioUnlocked = true
      unlockOverlay.remove()
    } finally {
      document.body.style.pointerEvents = prev || ''
      // avisa o client pra tirar o foco
      fetch('https://daydream-speech/unlock-done', { method:'POST', headers:{'Content-Type':'application/json'}, body:'{}' }).catch(()=>{})
      onDone && onDone()
    }
  }
}

// ==== HANDLER DE MENSAGENS ====
window.addEventListener('message', (event) => {
  const { action, payload } = event.data || {}

  if (action === 'show') {
    clearStageTimer()
    clearAutoTimeout()

    // Reset call state
    callAnswered = false
    currentPayload = payload || {}
    currentCallId = payload?.callId || null
    debugMode = payload?.debug || false
    debugLog('New call received with ID:', currentCallId)

    if (precallAvatarImg) {
      precallAvatarImg.src = (payload && payload.avatar) || 'assets/judy.webp'
    }

    const precallVolume = payload?.precallVolume ?? 0.6
    const precallLoop   = payload?.precallLoop   ?? false
    const precallMs     = payload?.precallMs     ?? 2000
    const autoTimeout   = payload?.autoTimeout   ?? 5000
    const answerKey     = payload?.answerKey     ?? 'E'
    const rejectKey     = payload?.rejectKey     ?? 'R'
    const showHints     = payload?.showHints     ?? true

    // Update key hints
    updateKeyHints(answerKey, rejectKey, showHints)

    playPrecallSound(precallVolume, precallLoop)
    showPrecall(payload?.name, autoTimeout)

    // Only proceed to full panel if call was answered, otherwise just wait for user action
    // The handleCallAction function will control the flow
  }

  if (action === 'panel:hide') {
    callPanel.classList.add('hidden')
    stopPrecallSound()
  }

  if (action === 'subtitle:update') {
    const nm = (payload && payload.name) || 'UNKNOWN'
    const tx = (payload && payload.text) || ''
    setPendingSubtitle(nm, tx)
    // legenda entra no onplay do áudio
  }

  if (action === 'subtitle:hide') {
    subtitle.classList.add('hidden')
  }

  if (action === 'hide') {
    clearStageTimer()
    clearAutoTimeout()
    stopPrecallSound()

    // Reset call state
    callAnswered = false
    currentPayload = null
    currentCallId = null
    debugLog('Call state reset, call ID cleared')

    precall.classList.add('hidden')
    callPanel.classList.add('hidden')
    subtitle.classList.add('hidden')

    // Use optimized queue cleanup
    audioQueue.clear()
  }

  // ======== LOCAL: tocar arquivo .ogg por fala ========
  if (action === 'voice:playFile' && payload?.src && lineAudio) {
    enqueue({ kind:'file', src: payload.src, volume: payload.volume })
  }

  if (action === 'voice:stop') {
    // Use optimized queue cleanup
    audioQueue.clear()
    subtitle.classList.add('hidden')
  }

  // ======== IA: tocar BASE64 do ElevenLabs ========
  if (action === 'tts:play' && payload?.base64) {
    enqueue({ kind:'b64', base64: payload.base64, mime: payload.mime || 'audio/mpeg', volume: 1.0 })
  }

  // ======== desbloqueio por comando do client ========
  if (action === 'tts:showUnlock') {
    showUnlockOverlay()
  }

  // ======== Cancel timeout from client ========
  if (action === 'cancelTimeout') {
    debugLog('Timeout cancelled by client action')
    clearAutoTimeout()
    clearStageTimer()
  }

  // ======== Call accepted from client ========
  if (action === 'callAccepted') {
    debugLog('Call accepted by client - showing full panel')
    callAnswered = true
    hidePrecall()
    stopPrecallSound()

    // Show the full call panel since call was answered
    setTimeout(() => {
      showFullPanel(currentPayload || {})
    }, 200)
  }

  // ======== State synchronization from Lua ========
  if (action === 'state:sync') {
    debugLog('State synchronization received:', payload)

    // Update global state variables
    if (payload?.debug !== undefined) {
      debugMode = payload.debug
    }

    // Update configuration if provided
    if (payload?.config) {
      // Update key hints if configuration changed
      if (payload.config.answerKey || payload.config.rejectKey || payload.config.showHints !== undefined) {
        updateKeyHints(
          payload.config.answerKey || 'E',
          payload.config.rejectKey || 'R',
          payload.config.showHints !== false
        )
      }
    }

    // Validate call state consistency
    if (payload?.callActive !== undefined) {
      if (!payload.callActive && currentCallId) {
        // Server says no active call but we have one - cleanup
        debugLog('State desync detected - cleaning up local call state')
        currentCallId = null
        currentPayload = null
        callAnswered = false
      } else if (payload.callActive && payload.callId && payload.callId !== currentCallId) {
        // Server has different call ID - update local state
        debugLog('Call ID updated from server:', payload.callId)
        currentCallId = payload.callId
      }
    }
  }
})
