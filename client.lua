local hideTimer = nil
local callActive = false
local keyControlsEnabled = false
local currentCallId = 0 -- Unique identifier for each call
local keyControlThread = nil

-- ===== DEBUG FUNCTION =====
local function debugPrint(...)
  -- Will be updated after CFG is loaded
  print("[DEBUG]", ...)
end

-- ===== KEY CONTROL FUNCTIONS =====
local function stopKeyControlThread()
  if keyControlThread then
    keyControlThread = nil
    debugPrint("Key control thread stopped")
  end
end

local function createKeyControlThread()
  if keyControlThread then
    keyControlThread = nil -- Clean up existing thread
  end

  debugPrint("Starting optimized key control thread")

  keyControlThread = Citizen.CreateThread(function()
    local answerControlId = getControlId(getConfig().call_buttons.answer_key)
    local rejectControlId = getControlId(getConfig().call_buttons.reject_key)

    while keyControlsEnabled and callActive do
      Citizen.Wait(0)

      -- Disable controls to prevent default actions
      if answerControlId then
        DisableControlAction(0, answerControlId, true)
      end
      if rejectControlId then
        DisableControlAction(0, rejectControlId, true)
      end

      -- Check for answer key
      if answerControlId and IsDisabledControlJustPressed(0, answerControlId) then
        debugPrint(getConfig().call_buttons.answer_key, "key pressed - answering call [Call ID:", currentCallId, "]")
        handleCallAction('accept', currentCallId)
        break -- Exit thread after action
      end

      -- Check for reject key
      if rejectControlId and IsDisabledControlJustPressed(0, rejectControlId) then
        debugPrint(getConfig().call_buttons.reject_key, "key pressed - rejecting call [Call ID:", currentCallId, "]")
        handleCallAction('reject', currentCallId)
        break -- Exit thread after action
      end
    end

    debugPrint("Key control thread terminated")
  end)
end

local function enableKeyControls()
  keyControlsEnabled = true
  createKeyControlThread()
  debugPrint("Key controls enabled, keyControlsEnabled:", keyControlsEnabled)
end

local function disableKeyControls()
  keyControlsEnabled = false
  stopKeyControlThread()
  debugPrint("Key controls disabled, keyControlsEnabled:", keyControlsEnabled)
end

-- Forward declaration for handleCallAction (full definition later)
-- handleCallAction will be defined as global function later

-- ===== RESOURCE MANAGEMENT SYSTEM =====
local ResourceManager = {
  timers = {},
  eventHandlers = {},
  activeCall = nil,

  -- Add timer with automatic cleanup
  addTimer = function(self, name, timer, callId)
    if self.timers[name] then
      ClearTimeout(self.timers[name].timer)
    end

    self.timers[name] = {
      timer = timer,
      callId = callId or currentCallId,
      created = GetGameTimer()
    }

    debugPrint("Timer added:", name, "for call ID:", callId or currentCallId)
  end,

  -- Remove specific timer
  removeTimer = function(self, name)
    if self.timers[name] then
      ClearTimeout(self.timers[name].timer)
      self.timers[name] = nil
      debugPrint("Timer removed:", name)
    end
  end,

  -- Add event handler with automatic cleanup
  addEventHandler = function(self, eventName, handler, callId)
    local handlerRef = AddEventHandler(eventName, handler)

    table.insert(self.eventHandlers, {
      name = eventName,
      handler = handlerRef,
      callId = callId or currentCallId,
      created = GetGameTimer()
    })

    debugPrint("Event handler added:", eventName, "for call ID:", callId or currentCallId)
    return handlerRef
  end,

  -- Cleanup resources for specific call
  cleanupCall = function(self, callId)
    callId = callId or currentCallId

    -- Clean timers for this call
    for name, timerData in pairs(self.timers) do
      if timerData.callId == callId then
        ClearTimeout(timerData.timer)
        self.timers[name] = nil
        debugPrint("Timer cleaned up:", name, "for call ID:", callId)
      end
    end

    -- Clean event handlers for this call
    for i = #self.eventHandlers, 1, -1 do
      local handlerData = self.eventHandlers[i]
      if handlerData.callId == callId then
        RemoveEventHandler(handlerData.handler)
        table.remove(self.eventHandlers, i)
        debugPrint("Event handler cleaned up:", handlerData.name, "for call ID:", callId)
      end
    end
  end,

  -- Complete cleanup - all resources
  cleanupAll = function(self)
    -- Clean all timers
    for name, timerData in pairs(self.timers) do
      ClearTimeout(timerData.timer)
    end
    self.timers = {}

    -- Clean all event handlers
    for _, handlerData in pairs(self.eventHandlers) do
      RemoveEventHandler(handlerData.handler)
    end
    self.eventHandlers = {}

    -- Reset global variables
    _G['__rizoCallFirstLine'] = nil
    _G['__rizoCallDuration'] = nil

    -- Reset state
    self.activeCall = nil
    callActive = false
    keyControlsEnabled = false

    -- Stop threads
    stopKeyControlThread()

    debugPrint("Complete resource cleanup performed")
  end,

  -- Cleanup old resources (older than 5 minutes)
  cleanupOld = function(self)
    local now = GetGameTimer()
    local oldThreshold = 300000 -- 5 minutes

    -- Clean old timers
    for name, timerData in pairs(self.timers) do
      if (now - timerData.created) > oldThreshold then
        ClearTimeout(timerData.timer)
        self.timers[name] = nil
        debugPrint("Old timer cleaned up:", name)
      end
    end

    -- Clean old event handlers
    for i = #self.eventHandlers, 1, -1 do
      local handlerData = self.eventHandlers[i]
      if (now - handlerData.created) > oldThreshold then
        RemoveEventHandler(handlerData.handler)
        table.remove(self.eventHandlers, i)
        debugPrint("Old event handler cleaned up:", handlerData.name)
      end
    end
  end,

  -- Alias for cleanupAll for compatibility
  cleanup = function(self)
    return self:cleanupAll()
  end
}

-- Automatic cleanup on resource stop
AddEventHandler('onResourceStop', function(resourceName)
  if resourceName == GetCurrentResourceName() then
    ResourceManager:cleanupAll()
    debugPrint("Resource stopped - all resources cleaned up")
  end
end)

-- Periodic cleanup of old resources
Citizen.CreateThread(function()
  while true do
    Citizen.Wait(300000) -- 5 minutes
    ResourceManager:cleanupOld()
  end
end)

-- ===== MODULAR COMPONENTS =====

-- Configuration Manager with validation
local ConfigManager = {
  defaults = {
    mode = 'elevenlabs',
    debug = false,
    precall = { enabled = true, ms = 2000, loop = false, volume = 0.6 },
    call_buttons = {
      enabled = true,
      auto_timeout = 5000,
      answer_key = 'E',
      reject_key = 'R',
      show_key_hints = true,
      answer_callback = nil,
      reject_callback = nil
    },
    default_volume = 1.0,
    allow_tts_fallback_when_local = false
  },

  keyMap = {
    ['A'] = 34, ['B'] = 29, ['C'] = 26, ['D'] = 9, ['E'] = 38,
    ['F'] = 23, ['G'] = 47, ['H'] = 74, ['I'] = 73, ['J'] = 44,
    ['K'] = 311, ['L'] = 182, ['M'] = 244, ['N'] = 249, ['O'] = 20,
    ['P'] = 199, ['Q'] = 44, ['R'] = 19, ['S'] = 8, ['T'] = 245,
    ['U'] = 303, ['V'] = 0, ['W'] = 32, ['X'] = 73, ['Y'] = 246, ['Z'] = 20
  },

  -- Comprehensive validation with detailed rules
  validate = function(self, config)
    local validated = {}

    -- Deep copy defaults first
    for k, v in pairs(self.defaults) do
      if type(v) == 'table' then
        validated[k] = {}
        for subK, subV in pairs(v) do
          validated[k][subK] = subV
        end
      else
        validated[k] = v
      end
    end

    -- Apply user configuration with validation
    if config then
      -- Validate mode
      validated.mode = (config.mode == 'local') and 'local' or 'elevenlabs'

      -- Validate debug
      validated.debug = config.debug == true

      -- Validate volume
      validated.default_volume = math.max(0, math.min(1, tonumber(config.default_volume) or 1.0))

      -- Validate TTS fallback
      validated.allow_tts_fallback_when_local = config.allow_tts_fallback_when_local == true

      -- Validate precall settings
      if config.precall then
        validated.precall.enabled = config.precall.enabled ~= false
        validated.precall.ms = math.max(0, math.min(10000, tonumber(config.precall.ms) or 2000))
        validated.precall.loop = config.precall.loop == true
        validated.precall.volume = math.max(0, math.min(1, tonumber(config.precall.volume) or 0.6))
      end

      -- Validate call buttons with enhanced checks
      if config.call_buttons then
        validated.call_buttons.enabled = config.call_buttons.enabled ~= false
        validated.call_buttons.auto_timeout = math.max(1000, math.min(30000, tonumber(config.call_buttons.auto_timeout) or 5000))
        validated.call_buttons.show_key_hints = config.call_buttons.show_key_hints ~= false

        -- Enhanced key validation with warnings
        if self:isValidKey(config.call_buttons.answer_key) then
          validated.call_buttons.answer_key = config.call_buttons.answer_key:upper()
        else
          print('[WARNING] Invalid answer key "' .. tostring(config.call_buttons.answer_key) .. '", using default: E')
          validated.call_buttons.answer_key = 'E'
        end

        if self:isValidKey(config.call_buttons.reject_key) then
          validated.call_buttons.reject_key = config.call_buttons.reject_key:upper()
        else
          print('[WARNING] Invalid reject key "' .. tostring(config.call_buttons.reject_key) .. '", using default: R')
          validated.call_buttons.reject_key = 'R'
        end

        -- Prevent duplicate keys
        if validated.call_buttons.answer_key == validated.call_buttons.reject_key then
          print('[WARNING] Answer and reject keys cannot be the same, using defaults')
          validated.call_buttons.answer_key = 'E'
          validated.call_buttons.reject_key = 'R'
        end

        -- Copy callbacks
        validated.call_buttons.answer_callback = config.call_buttons.answer_callback
        validated.call_buttons.reject_callback = config.call_buttons.reject_callback
      end

      -- Validate elevenlabs settings if present
      if config.elevenlabs then
        validated.elevenlabs = validated.elevenlabs or {}
        validated.elevenlabs.voice_id = config.elevenlabs.voice_id or self.defaults.elevenlabs and self.defaults.elevenlabs.voice_id
        validated.elevenlabs.model_id = config.elevenlabs.model_id or self.defaults.elevenlabs and self.defaults.elevenlabs.model_id
        validated.elevenlabs.stability = math.max(0, math.min(1, tonumber(config.elevenlabs.stability) or 0.55))
        validated.elevenlabs.similarity = math.max(0, math.min(1, tonumber(config.elevenlabs.similarity) or 0.7))
        validated.elevenlabs.style = math.max(0, math.min(1, tonumber(config.elevenlabs.style) or 0.15))
        validated.elevenlabs.speaker_boost = config.elevenlabs.speaker_boost == true
      end
    end

    return validated
  end,

  -- Get current validated configuration
  getConfig = function(self)
    return CFG or self:load()
  end,

  -- Runtime configuration update with validation
  updateConfig = function(self, newConfig)
    local validated = self:validate(newConfig)

    -- Apply to global CFG
    for k, v in pairs(validated) do
      CFG[k] = v
    end

    if validated.debug then
      print('[ConfigManager] Configuration updated and validated')
    end

    return CFG
  end,

  isValidKey = function(self, keyLetter)
    return keyLetter and self.keyMap[string.upper(keyLetter)] ~= nil
  end,

  getControlId = function(self, keyLetter)
    if not keyLetter or keyLetter == '' then return nil end
    return self.keyMap[string.upper(keyLetter)]
  end,

  load = function(self)
    local config = {}

    -- Merge configurations in priority order
    self:merge(config, self.defaults)
    self:merge(config, RizoSpeechConfig or {})

    -- Validate final configuration
    return self:validate(config)
  end,

  merge = function(self, target, source)
    for key, value in pairs(source) do
      if type(value) == 'table' and type(target[key]) == 'table' then
        self:merge(target[key], value)
      else
        target[key] = value
      end
    end
  end
}

-- Call State Manager
local CallState = {
  current = nil,

  create = function(self, data)
    local callData = self:validateData(data)

    return {
      id = self:generateId(),
      config = callData,
      startTime = GetGameTimer(),
      status = 'ringing',
      timers = {},
      eventHandlers = {}
    }
  end,

  validateData = function(self, data)
    return {
      avatar = data.avatar or 'assets/judy.webp',
      name = data.name or 'Unknown',
      subtitle = data.subtitle or '',
      duration = math.max(1000, tonumber(data.duration) or 8000),
      sound = data.sound,
      volume = math.max(0, math.min(1, tonumber(data.volume) or getConfig().default_volume)),
      voice_id = data.voice_id,
      model_id = data.model_id,
      precallMs = tonumber(data.precallMs),
      precallLoop = data.precallLoop,
      precallVolume = tonumber(data.precallVolume),
      autoTimeout = tonumber(data.autoTimeout)
    }
  end,

  generateId = function(self)
    currentCallId = currentCallId + 1
    return currentCallId
  end,

  setCurrent = function(self, call)
    self.current = call
    if call then
      debugPrint("Call state set:", call.id, "status:", call.status)
    else
      debugPrint("Call state cleared")
    end
  end,

  getCurrent = function(self)
    return self.current
  end,

  cleanup = function(self)
    if self.current then
      debugPrint('Cleaning up call state for call ID:', self.current.id)
      self.current = nil
    end
  end
}

-- UI Manager for NUI operations with centralized state synchronization
local UIManager = {
  -- Synchronize current state between Lua and NUI
  syncState = function(self)
    local currentState = CallState:getCurrent()
    local config = ConfigManager:getConfig()

    SendNUIMessage({
      action = 'state:sync',
      payload = {
        callActive = currentState and currentState.active or false,
        callId = currentState and currentState.id or nil,
        debug = config.debug,
        config = {
          answerKey = config.call_buttons.answer_key,
          rejectKey = config.call_buttons.reject_key,
          showHints = config.call_buttons.show_key_hints,
          autoTimeout = config.call_buttons.auto_timeout,
          mode = config.mode
        }
      }
    })
  end,

  show = function(self, call)
    local config = call.config
    local callId = call.id

    -- Sync state before showing
    self:syncState()

    SendNUIMessage({
      action = 'show',
      payload = {
        avatar = config.avatar,
        name = config.name,
        subtitle = config.subtitle,
        precallMs = (getConfig().precall.enabled and (config.precallMs or getConfig().precall.ms)) or 0,
        precallLoop = (config.precallLoop ~= nil) and config.precallLoop or getConfig().precall.loop,
        precallVolume = config.precallVolume or getConfig().precall.volume,
        autoTimeout = (getConfig().call_buttons.enabled and (config.autoTimeout or getConfig().call_buttons.auto_timeout)) or 0,
        answerKey = getConfig().call_buttons.answer_key or 'E',
        rejectKey = getConfig().call_buttons.reject_key or 'R',
        showHints = getConfig().call_buttons.show_key_hints ~= false,
        callId = callId,
        debug = getConfig().debug
      }
    })

    SetNuiFocus(false, false)
    debugPrint("UI shown for call ID:", callId)
  end,

  hide = function(self)
    SendNUIMessage({ action = 'hide' })
    debugPrint("UI hidden")
  end,

  updateSubtitle = function(self, name, text)
    SendNUIMessage({
      action = 'subtitle:update',
      payload = { name = name or 'Unknown', text = text or '' }
    })
  end,

  playLocal = function(self, src, volume)
    SendNUIMessage({
      action = 'voice:playFile',
      payload = { src = src, volume = volume or getConfig().default_volume, syncSubtitle = true }
    })
  end,

  cancelTimeout = function(self)
    SendNUIMessage({ action = 'cancelTimeout' })
  end,

  notifyCallAccepted = function(self)
    SendNUIMessage({ action = 'callAccepted' })
  end,

  stopLocal = function(self)
    SendNUIMessage({ action = 'voice:stop' })
  end
}

-- ===== INITIALIZATION =====
-- Initialize configuration early with safe getter
local CFG = nil

-- Safe configuration getter (global)
function getConfig()
  if not CFG then
    CFG = ConfigManager:load()
  end
  return CFG
end

-- Update debug function to use loaded config
debugPrint = function(...)
  local config = getConfig()
  if config and config.debug then
    print("[DEBUG]", ...)
  end
end

-- Updated function references (global)
function getControlId(keyLetter)
  return ConfigManager:getControlId(keyLetter)
end

-- Functions moved to top of file

handleCallAction = function(action, callId)
  callId = callId or currentCallId -- Use current call ID if not provided
  debugPrint("handleCallAction called with:", action, "for Call ID:", callId, "callActive:", callActive, "[Current Call ID:", currentCallId, "]")

  -- Validate this action is for the current call
  if callId ~= currentCallId then
    debugPrint("Action for old call [ID:", callId, "], ignoring (current:", currentCallId, ")")
    return
  end

  if not callActive then
    debugPrint("Call not active, ignoring action [Call ID:", callId, "]")
    return
  end

  debugPrint("Processing call action:", action, "[Call ID:", callId, "]")
  keyControlsEnabled = false

  -- Notify NUI to cancel its timeout
  SendNUIMessage({ action = 'cancelTimeout' })

  if action == 'accept' then
    -- Keep callActive = true for accepted calls until they finish
    debugPrint("Call accepted [Call ID:", currentCallId, "]")

    -- Clear the auto-hide timer since call was answered
    if hideTimer then
      debugPrint("Clearing hideTimer since call was answered [Call ID:", currentCallId, "]")
      ClearTimeout(hideTimer)
      hideTimer = nil
    end

    -- Call accept callback if configured
    if getConfig().call_buttons.answer_callback and type(getConfig().call_buttons.answer_callback) == 'function' then
      getConfig().call_buttons.answer_callback()
    end

    -- Notify NUI that call was accepted
    SendNUIMessage({ action = 'callAccepted' })

    -- Trigger event for other resources to handle
    TriggerEvent('rizo-cyberpunkcall:callAnswered')

    -- Play the first line now that call is answered
    if _G['__rizoCallFirstLine'] then
      _G['__rizoCallFirstLine']()
      _G['__rizoCallFirstLine'] = nil
    end

    -- Set a new timer to hide the call after it completes (use remaining duration)
    -- Since we need access to the original duration, we'll store it globally
    if _G['__rizoCallDuration'] then
      local remainingDuration = _G['__rizoCallDuration']
      debugPrint("Setting new hideTimer for answered call, duration:", remainingDuration, "ms [Call ID:", currentCallId, "]")

      local acceptedCallId = currentCallId -- Capture current call ID
      local durationTimer = SetTimeout(remainingDuration, function()
        if currentCallId == acceptedCallId and callActive then
          debugPrint("Call duration ended, hiding call [Call ID:", acceptedCallId, "]")
          exports['rizo-cyberpunkcall']:HideCallNotification()
        else
          debugPrint("Call duration timer ignored [Call ID:", acceptedCallId, "] - currentCallId:", currentCallId, "callActive:", callActive)
        end
      end)

      -- Register timer with ResourceManager
      ResourceManager:addTimer("durationTimer", durationTimer, acceptedCallId)
    end

  elseif action == 'reject' then
    callActive = false -- Deactivate call for rejection
    debugPrint("Call rejected")
    -- Call reject callback if configured
    if getConfig().call_buttons.reject_callback and type(getConfig().call_buttons.reject_callback) == 'function' then
      getConfig().call_buttons.reject_callback()
    end

    -- Clean up stored first line function
    _G['__rizoCallFirstLine'] = nil

    -- Trigger event for other resources to handle
    TriggerEvent('rizo-cyberpunkcall:callRejected')

    -- Hide call notification immediately
    exports['rizo-cyberpunkcall']:HideCallNotification()

  elseif action == 'timeout' then
    callActive = false -- Deactivate call for timeout
    debugPrint("Call timeout")
    -- Clean up stored first line function
    _G['__rizoCallFirstLine'] = nil

    -- Handle auto-timeout (treat as miss)
    TriggerEvent('rizo-cyberpunkcall:callTimeout')

    -- Hide call notification
    exports['rizo-cyberpunkcall']:HideCallNotification()
  end
end

RegisterNetEvent('rizo-speech:client:config')
AddEventHandler('rizo-speech:client:config', function(newcfg)
  if type(newcfg) == 'table' then
    for k,v in pairs(newcfg) do getConfig()[k] = v end
  end
end)

-- ===== TTS De-duplication (prevents repeated speech in short intervals) =====
local lastTTSText = nil
local lastTTSTime = 0
local DEDUP_WINDOW_MS = 1500 -- 1.5s

local function shouldSpeak(text)
  if not text or text == '' then return false end
  local now = GetGameTimer()
  if lastTTSText == text and (now - lastTTSTime) < DEDUP_WINDOW_MS then
    return false
  end
  lastTTSText = text
  lastTTSTime = now
  return true
end

-- ===== NUI Bridge =====
local function nuiShow(payload)
  SendNUIMessage({ action = 'show', payload = payload })
end
local function nuiHideAll()
  SendNUIMessage({ action = 'hide' })
end
local function nuiSubUpdate(name, text)
  SendNUIMessage({ action = 'subtitle:update', payload = { name = name or 'Unknown', text = text or '' } })
end
local function nuiPlayLocal(src, volume)
  SendNUIMessage({ action = 'voice:playFile', payload = { src = src, volume = volume or getConfig().default_volume, syncSubtitle = true } })
end
local function nuiStopLocal()
  SendNUIMessage({ action = 'voice:stop' })
end
local function nuiUnlockOverlay()
  SendNUIMessage({ action = 'tts:showUnlock' })
end

-- ===== TTS (via server) =====
local function playTTS(text, opts)
  if not shouldSpeak(text) then return end
  TriggerServerEvent('rizo-speech:server:tts', text, opts or {})
end

RegisterNetEvent('rizo-speech:client:ttsResult')
AddEventHandler('rizo-speech:client:ttsResult', function(ok, payload)
  if not ok then
    -- print(('[rizo-speech] TTS failed: %s'):format(tostring(payload)))
    return
  end
  SendNUIMessage({
    action = 'tts:play',
    payload = { base64 = payload.base64, mime = payload.mime }
  })
end)

-- ===== PUBLIC API (exports) =====

--- Shows panel + (optional) initial speech
--- data = {
---   avatar, name, subtitle, duration, keepSubtitle,
---   -- IA:
---   voice_id, model_id,
---   -- LOCAL:
---   sound, volume,
---   -- Precall:
---   precallMs, precallLoop, precallVolume
--- }
---@class CallNotificationData
---@field avatar string? Caminho para imagem do avatar (padrão: 'assets/judy.webp')
---@field name string? Nome do personagem (padrão: 'Unknown')
---@field subtitle string? Texto da mensagem (padrão: '')
---@field duration number? Duração da chamada em ms (padrão: 8000)
---@field sound string? Arquivo de áudio local (modo local)
---@field voice_id string? ID da voz ElevenLabs (modo AI)
---@field model_id string? ID do modelo ElevenLabs (modo AI)
---@field volume number? Volume do áudio (0.0-1.0)
---@field precallMs number? Duração do precall em ms
---@field precallLoop boolean? Loop do som de precall
---@field precallVolume number? Volume do precall (0.0-1.0)
---@field autoTimeout number? Timeout automático em ms

---Exibe notificação de chamada com áudio opcional
---@param data CallNotificationData Dados da chamada
---@return boolean success Se a chamada foi iniciada com sucesso
exports('ShowCallNotification', function(data)
  -- Validate input data
  if not data or type(data) ~= 'table' then
    debugPrint("Invalid call data provided")
    return false
  end

  -- Use ResourceManager to cleanup previous call
  ResourceManager:cleanupAll()

  -- Create new call using CallState manager
  local call = CallState:create(data)
  CallState:setCurrent(call)

  debugPrint("ShowCallNotification called [ID:", call.id, "] current callActive:", callActive, "keyControlsEnabled:", keyControlsEnabled)

  -- Store duration globally for use after call is answered
  _G['__rizoCallDuration'] = call.config.duration

  -- Reset state completely first
  callActive = false
  keyControlsEnabled = false
  _G['__rizoCallFirstLine'] = nil
  _G['__rizoCallDuration'] = nil

  -- Force NUI reset
  UIManager:hide()

  debugPrint("State reset completely, enabling new call [ID:", call.id, "]")

  -- Enable call state and key controls
  callActive = true
  if getConfig().call_buttons.enabled then
    enableKeyControls()
    debugPrint("Key controls enabled for new call [ID:", call.id, "]")
  end

  -- Show UI using UIManager
  UIManager:show(call)

  -- Set hide timer using ResourceManager
  debugPrint("Setting hideTimer for", call.config.duration, "ms [ID:", call.id, "]")
  local hideTimer = SetTimeout(call.config.duration, function()
    -- Only execute if this is still the current call AND call is still active
    if currentCallId == call.id and callActive then
      debugPrint("hideTimer expired for valid call [ID:", call.id, "], hiding call")
      UIManager:hide()

      -- Reset call state when timer expires
      callActive = false
      keyControlsEnabled = false
      _G['__rizoCallFirstLine'] = nil
    else
      debugPrint("hideTimer expired but ignoring [ID:", call.id, "] - currentCallId:", currentCallId, "callActive:", callActive)
    end
  end)

  -- Register timer with ResourceManager
  ResourceManager:addTimer("hideTimer", hideTimer, call.id)

  -- Store data for when call is answered
  local storedCallData = {
    name = data.name or 'Unknown',
    subtitle = data.subtitle or '',
    sound = data.sound,
    volume = data.volume,
    voice_id = data.voice_id,
    model_id = data.model_id
  }

  -- Function to play first line (only when call is answered)
  local function kickOffFirstLine()
    if not storedCallData.subtitle or storedCallData.subtitle == '' then return end

    -- always notify NUI of name+text (subtitle will appear on audio play)
    nuiSubUpdate(storedCallData.name, storedCallData.subtitle)

    if getConfig().mode == 'local' then
      if storedCallData.sound and storedCallData.sound ~= '' then
        nuiPlayLocal(storedCallData.sound, storedCallData.volume or getConfig().default_volume)
      elseif getConfig().allow_tts_fallback_when_local then
        playTTS(storedCallData.subtitle, { voice_id = storedCallData.voice_id, model_id = storedCallData.model_id })
      end
    else -- elevenlabs
      playTTS(storedCallData.subtitle, { voice_id = storedCallData.voice_id, model_id = storedCallData.model_id })
    end
  end

  -- Store the function to be called when call is answered
  _G['__rizoCallFirstLine'] = kickOffFirstLine
end)

--- Updates only subtitle and (optional) plays speech (local/AI)
--- name, text, [sound], [volume], [opts]  -- opts { voice_id, model_id }
exports('UpdateCallSubtitle', function(name, text, sound, volume, opts)
  nuiSubUpdate(name, text)

  if not text or text == '' then return end

  if getConfig().mode == 'local' then
    if sound and sound ~= '' then
      nuiPlayLocal(sound, volume or getConfig().default_volume)
    elseif getConfig().allow_tts_fallback_when_local then
      playTTS(text, opts or {})
    end
  else
    playTTS(text, opts or {})
  end
end)

--- Hides everything immediately
exports('HideCallNotification', function()
  debugPrint("HideCallNotification called")

  -- Use ResourceManager for complete cleanup
  ResourceManager:cleanupCall(currentCallId)

  -- Disable call state and key controls
  callActive = false
  disableKeyControls()

  -- Clean up stored functions and variables
  _G['__rizoCallFirstLine'] = nil
  _G['__rizoCallDuration'] = nil

  nuiHideAll()
  nuiStopLocal()
  debugPrint("Call notification hidden completely")
end)

-- ===== Useful commands =====
RegisterCommand('nui-unlock', function()
  SetNuiFocus(true, false)
  nuiUnlockOverlay()
  SetTimeout(8000, function()
    SetNuiFocus(false, false)
  end)
end)

-- Test command for ElevenLabs TTS mode
RegisterCommand('voicetest1', function()
  debugPrint("Starting ElevenLabs TTS test call")

  -- Temporarily set mode to elevenlabs for this test
  local originalMode = getConfig().mode
  getConfig().mode = 'elevenlabs'

  exports['rizo-cyberpunkcall']:ShowCallNotification({
    avatar = 'assets/judy.webp',
    name = 'ELEVENLABS TEST',
    subtitle = 'Testing AI voice generation with ElevenLabs API',
    duration = 8000,
    voice_id = 'JBFqnCBsd6RMkjVDRZzb', -- Default voice from config
    volume = 1.0
  })

  -- Clean event handler for this test
  local testHandler = nil

  local function onTestCallAnswered()
    if testHandler then RemoveEventHandler(testHandler) end
    debugPrint("ElevenLabs test call answered - playing AI voice")

    -- Restore original mode after test
    getConfig().mode = originalMode
  end

  testHandler = AddEventHandler('rizo-cyberpunkcall:callAnswered', onTestCallAnswered)
end)

-- Test command for Local files mode
RegisterCommand('voicetest2', function()
  debugPrint("Starting local files test call")

  -- Temporarily set mode to local for this test
  local originalMode = getConfig().mode
  getConfig().mode = 'local'

  -- Start with the first message
  exports['rizo-cyberpunkcall']:ShowCallNotification({
    avatar = 'assets/judy.webp',
    name = 'JUDY ALVAREZ',
    subtitle = 'Hey V, you got a minute?',
    duration = 15000, -- Extended duration for 3 messages
    sound = 'assets/localtestvoice', -- Same sound file for all messages
    volume = 1.0
  })

  -- Clean event handler for this test
  local testHandler = nil
  local timeoutHandler1 = nil
  local timeoutHandler2 = nil

  local function onTestCallAnswered()
    if testHandler then RemoveEventHandler(testHandler) end
    debugPrint("Local files test call answered - starting conversation sequence")

    -- First message (plays immediately when answered)
    debugPrint("Playing first message: Hey V, you got a minute?")

    -- Second message after 3 seconds
    timeoutHandler1 = SetTimeout(3000, function()
      debugPrint("Playing second message")
      exports['rizo-cyberpunkcall']:UpdateCallSubtitle(
        'JUDY ALVAREZ',
        'I found something interesting about the relic.',
        'assets/localtestvoice', -- Same sound file
        1.0
      )
    end)

    -- Third message after 6 seconds
    timeoutHandler2 = SetTimeout(6000, function()
      debugPrint("Playing third message")
      exports['rizo-cyberpunkcall']:UpdateCallSubtitle(
        'JUDY ALVAREZ',
        'Meet me at the workshop when you can.',
        'assets/localtestvoice', -- Same sound file
        1.0
      )
    end)

    -- Clean up and restore mode after all messages
    SetTimeout(10000, function()
      if timeoutHandler1 then ClearTimeout(timeoutHandler1) end
      if timeoutHandler2 then ClearTimeout(timeoutHandler2) end
      getConfig().mode = originalMode
      debugPrint("voicetest2 sequence completed")
    end)
  end

  local function onTestCallRejected()
    if testHandler then RemoveEventHandler(testHandler) end
    if timeoutHandler1 then ClearTimeout(timeoutHandler1) end
    if timeoutHandler2 then ClearTimeout(timeoutHandler2) end
    getConfig().mode = originalMode
    debugPrint("voicetest2 call rejected - cleaning up")
  end

  testHandler = AddEventHandler('rizo-cyberpunkcall:callAnswered', onTestCallAnswered)
  AddEventHandler('rizo-cyberpunkcall:callRejected', onTestCallRejected)
  AddEventHandler('rizo-cyberpunkcall:callTimeout', onTestCallRejected)
end)

RegisterNUICallback('unlock-done', function(_, cb)
  SetNuiFocus(false, false)
  if cb then cb({ ok = true }) end
end)

-- Optimized Key Control System

-- Validate configured keys on startup
local answerKey = getConfig().call_buttons.answer_key
local rejectKey = getConfig().call_buttons.reject_key

if not getControlId(answerKey) then
  print("[WARNING] Invalid answer key configured:", answerKey)
end
if not getControlId(rejectKey) then
  print("[WARNING] Invalid reject key configured:", rejectKey)
end

debugPrint("Configured keys - Answer:", answerKey, "Reject:", rejectKey)

-- Function moved to top of file

-- NUI Callback for timeout actions from JavaScript
RegisterNUICallback('callAction', function(data, cb)
  local action = data and data.action
  local callId = data and data.callId or currentCallId
  debugPrint("NUI callback received action:", action, "for Call ID:", callId)
  if action == 'timeout' then
    handleCallAction('timeout', callId)
  end
  if cb then cb({ ok = true }) end
end)

-- ===== Demo (works in both modes) =====
-- In "local" mode, fill "sound" with files in assets/*.ogg
-- In "elevenlabs" mode, you can omit "sound" and optionally set "voice_id"/"model_id"
RegisterCommand('rizo-test', function()
  local dialog = {
    {
      avatar   = 'assets/judy.webp',
      name     = 'JUDY ALVAREZ',
      subtitle = "No, I'm tryin' to get you. Know someone at Clouds who'll take our side.",
      sound    = 'assets/localtestvoice',  -- used in local mode
      volume   = 1.0,
      duration = 4000
    },
    {
      name     = 'JUDY',
      subtitle = "Meet me at Lizzie's. Come alone.",
      sound    = 'assets/localtestvoice',
      volume   = 1.0,
      duration = 5000
    },
    {
      name     = 'JUDY',
      subtitle = "Hurry up, it's important.",
      sound    = 'assets/localtestvoice',
      volume   = 1.0,
      duration = 4000
    }
  }

  -- total sum
  local totalDuration = 0
  for i = 1, #dialog do
    totalDuration = totalDuration + (dialog[i].duration or 0)
  end
  if getConfig().precall.enabled then totalDuration = totalDuration + (getConfig().precall.ms or 0) end

  -- first speech opens the panel
  local first = dialog[1]
  exports['rizo-cyberpunkcall']:ShowCallNotification({
    avatar   = first.avatar,
    name     = first.name,
    subtitle = first.subtitle,
    duration = totalDuration,
    sound    = first.sound,  -- will be ignored in AI mode
    volume   = first.volume,
    precallMs = getConfig().precall.ms
  })

  -- Only play dialog if call is answered
  local function playDialog(idx)
    local line = dialog[idx]
    if not line then return end
    if idx > 1 then
      exports['rizo-cyberpunkcall']:UpdateCallSubtitle(
        line.name, line.subtitle, line.sound, line.volume, nil
      )
    end
    SetTimeout(line.duration, function()
      playDialog(idx + 1)
    end)
  end

  -- Event handler references for cleanup
  local answeredHandler = nil
  local rejectedHandler = nil
  local timeoutHandler = nil

  -- Listen for call answered event to start dialog
  local function onCallAnswered()
    -- Remove all event handlers
    if answeredHandler then RemoveEventHandler(answeredHandler) end
    if rejectedHandler then RemoveEventHandler(rejectedHandler) end
    if timeoutHandler then RemoveEventHandler(timeoutHandler) end

    playDialog(1)

    -- fail-safe cleanup after total duration
    SetTimeout(totalDuration, function()
      SendNUIMessage({ action = 'hide' })
      SendNUIMessage({ action = 'voice:stop' })
    end)
  end

  -- Cleanup if call is rejected or times out
  local function onCallNotAnswered()
    -- Remove all event handlers
    if answeredHandler then RemoveEventHandler(answeredHandler) end
    if rejectedHandler then RemoveEventHandler(rejectedHandler) end
    if timeoutHandler then RemoveEventHandler(timeoutHandler) end
  end

  -- Register event handlers and store references
  answeredHandler = AddEventHandler('rizo-cyberpunkcall:callAnswered', onCallAnswered)
  rejectedHandler = AddEventHandler('rizo-cyberpunkcall:callRejected', onCallNotAnswered)
  timeoutHandler = AddEventHandler('rizo-cyberpunkcall:callTimeout', onCallNotAnswered)
end)

-- ===== EXPORTED FUNCTIONS =====
-- Original implementations are used (lines 753, 857, etc.)

-- Export functions to resource interface
-- Note: ShowCallNotification already exported at line 753
-- exports('UpdateCallSubtitle', UpdateCallSubtitle) - Will be added if needed
-- exports('HideCallNotification', HideCallNotification) - Will be added if needed
