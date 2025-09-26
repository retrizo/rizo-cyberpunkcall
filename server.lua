local RES_NAME = GetCurrentResourceName()

-- === util: base64 (pura Lua) ===
local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local function toBase64(data)
  return ((data:gsub('.', function(x)
      local r,bits='',x:byte()
      for i=8,1,-1 do r=r..((bits % 2^i - bits % 2^(i-1) > 0) and '1' or '0') end
      return r
    end)..'0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
      if #x < 6 then return '' end
      local c=0
      for i=1,6 do c = c + (x:sub(i,i)=='1' and 2^(6-i) or 0) end
      return b:sub(c+1,c+1)
    end)..({ '', '==', '=' })[#data%3+1])
end

-- ====== Lê convars e mescla com o config.lua ======
local function readServerConfig()
  local cfg = RizoSpeechConfig or {}

  local mode = GetConvar('rizo:mode', cfg.mode or 'elevenlabs')
  mode = (mode == 'local') and 'local' or 'elevenlabs'

  local precall = cfg.precall or { enabled = true, ms = 2000, loop = false, volume = 0.6 }

  local el = cfg.elevenlabs or {}
  local api_key = GetConvar('elevenlabs:api_key', '')
  local voice_id = GetConvar('elevenlabs:voice_id', el.voice_id or 'JBFqnCBsd6RMkjVDRZzb')
  local model_id = GetConvar('elevenlabs:model_id', el.model_id or 'eleven_multilingual_v2')
  local format   = GetConvar('elevenlabs:format',   el.format   or 'mp3_44100_128')
  local stability= tonumber(GetConvar('elevenlabs:stability', tostring(el.stability or 0.55))) or 0.55
  local simil    = tonumber(GetConvar('elevenlabs:similarity_boost', tostring(el.similarity or 0.7))) or 0.7
  local style    = tonumber(GetConvar('elevenlabs:style', tostring(el.style or 0.15))) or 0.15
  local sboost   = GetConvar('elevenlabs:speaker_boost', (el.speaker_boost and 'true' or 'false')) == 'true'

  return {
    mode = mode,
    allow_tts_fallback_when_local = (cfg.allow_tts_fallback_when_local == true),
    precall = precall,
    default_volume = cfg.default_volume or 1.0,
    elevenlabs = {
      api_key = api_key,
      voice_id = voice_id,
      model_id = model_id,
      format   = format,
      stability = stability,
      similarity = simil,
      style = style,
      speaker_boost = sboost,
    }
  }
end

local CURRENT = readServerConfig()

local function broadcastConfig(target)
  local who = target or -1
  TriggerClientEvent('rizo-speech:client:config', who, {
    mode = CURRENT.mode,
    precall = CURRENT.precall,
    default_volume = CURRENT.default_volume,
    allow_tts_fallback_when_local = CURRENT.allow_tts_fallback_when_local
  })
end

AddEventHandler('onResourceStart', function(res)
  if res ~= RES_NAME then return end
  CURRENT = readServerConfig()
  broadcastConfig()
end)

AddEventHandler('playerJoining', function()
  broadcastConfig(source)
end)

-- ====== ElevenLabs TTS ======
local function httpRequest(method, url, headers, body, cb)
  PerformHttpRequest(url, function(status, data, responseHeaders)
    cb(status, data, responseHeaders)
  end, method, body, headers)
end

-- Security and Rate Limiting System
local playerLastTTS = {}
local playerRequestCount = {}
local RATE_LIMIT_WINDOW = 60000 -- 1 minute window
local MAX_REQUESTS_PER_WINDOW = 20
local MAX_TEXT_LENGTH = 1000
local MIN_REQUEST_INTERVAL = 2000 -- 2 seconds between requests

-- Security validation function
local function validateTTSRequest(src, text, opts)
  -- Basic text validation
  if not text or type(text) ~= 'string' then
    return false, 'Texto inválido ou ausente'
  end

  if #text == 0 then
    return false, 'Texto vazio'
  end

  if #text > MAX_TEXT_LENGTH then
    return false, string.format('Texto muito longo (máximo %d caracteres)', MAX_TEXT_LENGTH)
  end

  -- Security: Check for potentially malicious content
  if text:match('[<>{}]') or text:match('script') or text:match('javascript:') then
    return false, 'Caracteres não permitidos no texto'
  end

  -- Rate limiting - minimum interval between requests
  local lastRequest = playerLastTTS[src] or 0
  local now = GetGameTimer()
  if (now - lastRequest) < MIN_REQUEST_INTERVAL then
    return false, 'Rate limit: aguarde antes de fazer nova solicitação'
  end

  -- Rate limiting - requests per window
  local currentWindow = math.floor(now / RATE_LIMIT_WINDOW)
  local playerKey = string.format('%s_%d', src, currentWindow)

  playerRequestCount[playerKey] = (playerRequestCount[playerKey] or 0) + 1

  if playerRequestCount[playerKey] > MAX_REQUESTS_PER_WINDOW then
    return false, 'Rate limit: muitas solicitações por minuto'
  end

  -- Validate options
  if opts and type(opts) ~= 'table' then
    return false, 'Opções inválidas'
  end

  -- Update last request time
  playerLastTTS[src] = now

  return true, nil
end

-- Cleanup old rate limit data
Citizen.CreateThread(function()
  while true do
    Citizen.Wait(RATE_LIMIT_WINDOW)

    local now = GetGameTimer()
    local currentWindow = math.floor(now / RATE_LIMIT_WINDOW)

    -- Clean old request counts
    for key, _ in pairs(playerRequestCount) do
      local keyWindow = tonumber(key:match('_(%d+)$'))
      if keyWindow and keyWindow < currentWindow - 1 then
        playerRequestCount[key] = nil
      end
    end

    -- Clean old last request times (older than 5 minutes)
    for src, time in pairs(playerLastTTS) do
      if (now - time) > 300000 then
        playerLastTTS[src] = nil
      end
    end
  end
end)

RegisterNetEvent('rizo-speech:server:tts')
AddEventHandler('rizo-speech:server:tts', function(text, opts)
  local src = source
  local cfg = CURRENT

  -- Security validation first
  local valid, errorMsg = validateTTSRequest(src, text, opts)
  if not valid then
    TriggerClientEvent('rizo-speech:client:ttsResult', src, false, errorMsg)
    print(string.format('[SECURITY] TTS request blocked from player %d: %s', src, errorMsg))
    return
  end

  if cfg.mode == 'local' and not cfg.allow_tts_fallback_when_local then
    TriggerClientEvent('rizo-speech:client:ttsResult', src, false, 'TTS desabilitado (modo local)')
    return
  end

  if (not cfg.elevenlabs.api_key or cfg.elevenlabs.api_key == '') then
    TriggerClientEvent('rizo-speech:client:ttsResult', src, false, 'API key ElevenLabs ausente')
    return
  end

  opts = opts or {}
  local voice_id = opts.voice_id or cfg.elevenlabs.voice_id
  local model_id = opts.model_id or cfg.elevenlabs.model_id

  local url = ("https://api.elevenlabs.io/v1/text-to-speech/%s"):format(voice_id)
  local bodyTbl = {
    text = text,
    model_id = model_id,
    voice_settings = {
      stability = opts.stability or cfg.elevenlabs.stability,
      similarity_boost = opts.similarity or cfg.elevenlabs.similarity,
      style = opts.style or cfg.elevenlabs.style,
      use_speaker_boost = (opts.speaker_boost == nil) and cfg.elevenlabs.speaker_boost or opts.speaker_boost
    }
  }
  local headers = {
    ['Content-Type'] = 'application/json',
    ['xi-api-key']   = cfg.elevenlabs.api_key,
    ['Accept']       = 'audio/mpeg'
  }

  httpRequest('POST', url, headers, json.encode(bodyTbl), function(status, data, _)
    if status ~= 200 or not data or data == '' then
      print(("[rizo-speech] ElevenLabs error %s"):format(status))
      TriggerClientEvent('rizo-speech:client:ttsResult', src, false, status)
      return
    end
    
    local b64 = toBase64(data)
    TriggerClientEvent('rizo-speech:client:ttsResult', src, true, { base64 = b64, mime = 'audio/mpeg' })
  end)
end)
