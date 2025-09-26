RizoSpeechConfig = {
  -- Mode: "elevenlabs" (AI) or "local" (files)
  mode = "local",

  -- Debug mode: enables detailed logging for troubleshooting
  debug = false,

  -- If in "local" mode and 'sound' is missing from speech:
  --  false = no TTS, subtitle only
  --  true  = fallback to TTS (requires configured API key)
  allow_tts_fallback_when_local = false,

  -- Precall HUD (mini notification before main panel)
  precall = {
    enabled = true,
    ms = 2000,
    loop = false,
    volume = 0.6,
  },

  -- Call interaction settings
  call_buttons = {
    enabled = true,              -- Enable answer/reject controls
    auto_timeout = 5000,         -- Auto-hide after 5 seconds if no action (in ms)
    answer_key = 'E',            -- Key to answer call (A-Z supported)
    reject_key = 'F',            -- Key to reject call (A-Z supported)
    show_key_hints = true,       -- Show key hints on interface
    answer_callback = nil,       -- Custom callback for answer (function)
    reject_callback = nil,       -- Custom callback for reject (function)
    -- Supported keys: A, B, C, D, E, F, G, H, I, J, K, L, M, N, O, P, Q, R, S, T, U, V, W, X, Y, Z
  },

  -- Default speech volume
  default_volume = 1.0,

  -- Padrões para ElevenLabs (podem ser sobrescritos por convars no servidor)
  elevenlabs = {
    voice_id   = "JBFqnCBsd6RMkjVDRZzb",
    model_id   = "eleven_multilingual_v2", -- ex: "eleven_turbo_v2" ou "eleven_turbo_v2_5"
    format     = "mp3_44100_128",
    stability  = 0.55,
    similarity = 0.7,
    style      = 0.15,
    speaker_boost = true,
  }
}
