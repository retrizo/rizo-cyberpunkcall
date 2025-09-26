# Cyberpunk-Style Call Notification System

A FiveM resource that displays cyberpunk-themed call notifications with text-to-speech functionality, inspired by the Cyberpunk 2077 game aesthetic.

## Features

- 🎮 Cyberpunk 2077-inspired call interface
- 🎤 Text-to-Speech (TTS) support via ElevenLabs API
- 🔊 Local audio file playback
- 📱 Real-time subtitle updates
- ⏰ Customizable call duration and timing
- 🔄 Anti-spam system with deduplication
- 🎵 Pre-call sound effects
- 📞 Keyboard controls for call interaction (E to answer, R to reject)
- ⏱️ Configurable auto-timeout functionality
- 🎯 Custom callback support for call actions
- 🎮 Customizable keybinds
- 💡 Visual key hints display
- 🌐 NUI-based interface

## Installation

1. Download or clone this resource to your FiveM server's `resources` folder
2. Add `ensure rizo-cyberpunkcall` to your `server.cfg`
3. **For ElevenLabs TTS mode**, add the following to your `server.cfg`:
   ```cfg
   ## Rizo Speech - AI Voice Configuration
   setr elevenlabs:api_key "your_elevenlabs_api_key_here"
   setr elevenlabs:voice_id "N2lVS1w4EtoT3dr4eOWO"
   setr elevenlabs:model_id "eleven_turbo_v2_5"
   setr elevenlabs:format "mp3_44100_128"
   setr elevenlabs:stability "0.55"
   setr elevenlabs:similarity_boost "0.7"
   setr elevenlabs:style "0.15"
   setr elevenlabs:speaker_boost "true"

   ## Rizo Speech - Mode Configuration (optional)
   setr rizo:mode "elevenlabs"  # or "local"
   ```
4. Replace `"your_elevenlabs_api_key_here"` with your actual ElevenLabs API key
5. Configure the resource according to your needs (see Configuration section)

> ⚠️ **Security Note**: Always keep your apikey in server.cfg to prevent dumpers who can access your files inside the server from seeing and using your key.

## Configuration

The resource supports two operation modes:

### Mode 1: ElevenLabs TTS (Default)
Uses ElevenLabs API for AI-generated speech.

```lua
CFG = {
  mode = 'elevenlabs',
  default_volume = 1.0,
  allow_tts_fallback_when_local = false,
  precall = {
    enabled = true,
    ms = 2000,      -- Pre-call duration in milliseconds
    loop = false,   -- Loop pre-call sound
    volume = 0.6    -- Pre-call volume
  },
  call_buttons = {
    enabled = true,         -- Enable Answer/Reject controls
    auto_timeout = 5000,    -- Auto-hide timeout in milliseconds (5 seconds)
    answer_key = 'E',       -- Key to answer calls (configurable)
    reject_key = 'R',       -- Key to reject calls (configurable)
    show_key_hints = true,  -- Show key hints on interface
    answer_callback = nil,  -- Custom callback for answer action
    reject_callback = nil   -- Custom callback for reject action
  }
}
```

### Mode 2: Local Audio Files
Uses pre-recorded audio files for playback.

```lua
CFG = {
  mode = 'local',
  default_volume = 1.0,
  allow_tts_fallback_when_local = true, -- Falls back to TTS if no local file
  precall = {
    enabled = true,
    ms = 2000,
    loop = false,
    volume = 0.6
  }
}
```

## Usage

### Basic Call Notification

```lua
exports['rizo-cyberpunkcall']:ShowCallNotification({
  avatar = 'assets/judy.webp',           -- Character avatar image
  name = 'JUDY ALVAREZ',                 -- Character name
  subtitle = "Meet me at Lizzie's bar",  -- Message text
  duration = 8000,                       -- Call duration in ms
  sound = 'assets/voice.ogg',            -- Local audio file (local mode)
  volume = 1.0,                          -- Audio volume
  voice_id = 'voice_id_here',            -- ElevenLabs voice ID
  model_id = 'model_id_here'             -- ElevenLabs model ID
})
```

### Update Call Subtitle

```lua
exports['rizo-cyberpunkcall']:UpdateCallSubtitle(
  'JUDY',                                -- Speaker name
  "I'll be waiting for you",            -- New message
  'assets/voice2.ogg',                   -- Audio file (optional)
  1.0,                                   -- Volume (optional)
  { voice_id = 'voice_id' }              -- TTS options (optional)
)
```

### Hide Call Notification

```lua
exports['rizo-cyberpunkcall']:HideCallNotification()
```

## Call Controls

When a call comes in, you have the following options:

- **Press E** - Answer the call (continues the call flow)
- **Press R** - Reject the call (immediately hides the call)
- **Do Nothing** - Call times out after configured time (default 5 seconds) and is treated as missed

The keys are displayed on the call interface and are fully configurable in `config.lua`.

## Export Usage Examples

### Using in Other Scripts

The `rizo-cyberpunkcall` resource exports functions that can be easily integrated into other FiveM scripts. Here are practical examples:

#### Basic Integration in Your Script

```lua
-- In your script's client.lua or any client-side file

-- Simple call notification
exports['rizo-cyberpunkcall']:ShowCallNotification({
    name = 'VINCENT',
    subtitle = 'The job is ready. You in?',
    duration = 6000,
    avatar = 'path/to/avatar.webp'
})
```

#### Phone System Integration

```lua
-- Example: Integration with a phone resource
RegisterNetEvent('phone:incomingCall')
AddEventHandler('phone:incomingCall', function(caller)
    exports['rizo-cyberpunkcall']:ShowCallNotification({
        avatar = caller.avatar or 'assets/default-avatar.webp',
        name = caller.name:upper(),
        subtitle = 'Incoming call...',
        duration = 15000, -- 15 seconds to answer
        sound = 'assets/ringtone.ogg', -- Custom ringtone
        volume = 0.8
    })

    -- Listen for call events
    local answerHandler = AddEventHandler('rizo-cyberpunkcall:callAnswered', function()
        TriggerServerEvent('phone:acceptCall', caller.id)
        RemoveEventHandler(answerHandler)
    end)

    local rejectHandler = AddEventHandler('rizo-cyberpunkcall:callRejected', function()
        TriggerServerEvent('phone:rejectCall', caller.id)
        RemoveEventHandler(rejectHandler)
    end)
end)
```

#### Mission/Quest System Integration

```lua
-- Example: Mission briefing system
function StartMissionBriefing(missionData)
    -- Initial briefing call
    exports['rizo-cyberpunkcall']:ShowCallNotification({
        avatar = missionData.contact.avatar,
        name = missionData.contact.name,
        subtitle = missionData.briefing.intro,
        duration = 8000,
        voice_id = missionData.contact.voice_id -- For TTS mode
    })

    -- Continue with mission updates
    Citizen.SetTimeout(9000, function()
        exports['rizo-cyberpunkcall']:UpdateCallSubtitle(
            missionData.contact.name,
            missionData.briefing.objective,
            nil, -- No audio file
            1.0,
            { voice_id = missionData.contact.voice_id }
        )
    end)
end

-- Usage
StartMissionBriefing({
    contact = {
        name = 'FIXER',
        avatar = 'assets/fixer.webp',
        voice_id = 'fixer_voice_id'
    },
    briefing = {
        intro = 'Got a job for you, samurai.',
        objective = 'Retrieve the data from Arasaka Tower. Payment: 50k eddies.'
    }
})
```

#### Notification System Integration

```lua
-- Example: Advanced notification system with different call types
local CallTypes = {
    MISSION = {
        avatar = 'assets/mission-contact.webp',
        duration = 10000,
        volume = 1.0
    },
    EMERGENCY = {
        avatar = 'assets/emergency.webp',
        duration = 15000,
        volume = 1.2,
        precallMs = 1000
    },
    FRIEND = {
        avatar = 'assets/friend.webp',
        duration = 8000,
        volume = 0.8,
        precallLoop = true
    }
}

function SendCustomCall(callType, name, message, audioFile)
    local config = CallTypes[callType]
    if not config then return false end

    exports['rizo-cyberpunkcall']:ShowCallNotification({
        avatar = config.avatar,
        name = name:upper(),
        subtitle = message,
        duration = config.duration,
        sound = audioFile,
        volume = config.volume,
        precallMs = config.precallMs,
        precallLoop = config.precallLoop
    })

    return true
end

-- Usage examples
SendCustomCall('MISSION', 'Wakako', 'New gig available in Japantown', 'audio/wakako_intro.ogg')
SendCustomCall('EMERGENCY', 'Trauma Team', 'Medical emergency detected', 'audio/trauma_alert.ogg')
SendCustomCall('FRIEND', 'Panam', 'Want to grab some tequila tonight?', 'audio/panam_casual.ogg')
```

#### Dynamic NPC Communication

```lua
-- Example: NPC calls based on player actions
RegisterNetEvent('npc:contactPlayer')
AddEventHandler('npc:contactPlayer', function(npcData, reason)
    local messages = {
        ['job_complete'] = 'Job well done. Payment transferred.',
        ['job_failed'] = 'What the hell happened out there?',
        ['new_opportunity'] = 'Got something that might interest you.',
        ['warning'] = 'You better watch your back, choom.'
    }

    exports['rizo-cyberpunkcall']:ShowCallNotification({
        avatar = npcData.avatar,
        name = npcData.name,
        subtitle = messages[reason] or 'Need to talk.',
        duration = 7000,
        voice_id = npcData.voice_profile -- For AI voice generation
    })
end)
```

#### Integration with Events System

```lua
-- Example: Complete event-driven integration
local CallSystem = {}

-- Initialize call system
function CallSystem:Init()
    -- Register event handlers
    AddEventHandler('rizo-cyberpunkcall:callAnswered', function()
        self:OnCallAnswered()
    end)

    AddEventHandler('rizo-cyberpunkcall:callRejected', function()
        self:OnCallRejected()
    end)

    AddEventHandler('rizo-cyberpunkcall:callTimeout', function()
        self:OnCallTimeout()
    end)
end

-- Handle call answer
function CallSystem:OnCallAnswered()
    if self.currentCall then
        -- Execute call answer logic
        if self.currentCall.onAnswer then
            self.currentCall.onAnswer()
        end
        self.currentCall = nil
    end
end

-- Make a call with callback
function CallSystem:MakeCall(data, callbacks)
    self.currentCall = {
        data = data,
        onAnswer = callbacks.onAnswer,
        onReject = callbacks.onReject,
        onTimeout = callbacks.onTimeout
    }

    exports['rizo-cyberpunkcall']:ShowCallNotification(data)
end

-- Usage
CallSystem:Init()

CallSystem:MakeCall({
    name = 'JUDY',
    subtitle = 'Meet me at the BD studio',
    duration = 8000,
    avatar = 'assets/judy.webp'
}, {
    onAnswer = function()
        print('Player answered Judy\'s call')
        -- Start conversation or mission
    end,
    onReject = function()
        print('Player rejected Judy\'s call')
        -- Maybe send a text message instead
    end,
    onTimeout = function()
        print('Player missed Judy\'s call')
        -- Add to missed calls
    end
})
```

#### Resource Dependencies

Add to your resource's `fxmanifest.lua`:

```lua
-- fxmanifest.lua
fx_version 'cerulean'
game 'gta5'

-- Add dependency
dependency 'rizo-cyberpunkcall'

-- Your script files
client_scripts {
    'client.lua'
}
```

#### Error Handling

```lua
-- Safe export usage with error handling
function SafeCallNotification(data)
    if GetResourceState('rizo-cyberpunkcall') ~= 'started' then
        print('Warning: rizo-cyberpunkcall resource not available')
        return false
    end

    local success, result = pcall(function()
        return exports['rizo-cyberpunkcall']:ShowCallNotification(data)
    end)

    if not success then
        print('Error calling ShowCallNotification:', result)
        return false
    end

    return result
end

-- Usage
SafeCallNotification({
    name = 'CONTACT',
    subtitle = 'Message here',
    duration = 5000
})
```

## Commands

### Testing Commands
- `/voicetest1` - Test ElevenLabs TTS mode with AI voice generation
- `/voicetest2` - Test local files mode with audio file playback
- `/rizo-test` - Complete demo conversation with multiple dialog lines

### Development Commands
- `/nui-unlock` - Unlock NUI overlay for development/debugging

### Debug Mode
Set `debug = true` in `config.lua` to enable detailed logging for troubleshooting. When enabled, all debug messages will be displayed in the console to help track call flow, timer events, and key presses.

## File Structure

```
rizo-cyberpunkcall/
├── client.lua          -- Main client-side logic
├── assets/             -- Audio files and images
│   ├── judy.webp       -- Default avatar
│   └── *.ogg/*.mp3     -- Audio files for local mode
└── html/               -- NUI interface files
```

## API Reference

### ShowCallNotification(data)

Shows a call notification with optional voice playback.

**Parameters:**
- `avatar` (string): Path to avatar image
- `name` (string): Character name
- `subtitle` (string): Message text
- `duration` (number): Call duration in milliseconds
- `keepSubtitle` (boolean): Keep subtitle visible after call ends
- `sound` (string): Local audio file path
- `volume` (number): Audio volume (0.0-1.0)
- `voice_id` (string): ElevenLabs voice ID
- `model_id` (string): ElevenLabs model ID
- `precallMs` (number): Pre-call duration override
- `precallLoop` (boolean): Loop pre-call sound
- `precallVolume` (number): Pre-call volume

### UpdateCallSubtitle(name, text, sound, volume, opts)

Updates the call subtitle with new text and optional audio.

**Parameters:**
- `name` (string): Speaker name
- `text` (string): New subtitle text
- `sound` (string, optional): Local audio file
- `volume` (number, optional): Audio volume
- `opts` (table, optional): TTS options `{voice_id, model_id}`

### HideCallNotification()

Immediately hides the call notification and stops any playing audio.

## Call Interaction Events

The resource triggers the following events based on user interaction with call buttons:

### Client Events

- `rizo-cyberpunkcall:callAnswered` - Triggered when user clicks Answer button
- `rizo-cyberpunkcall:callRejected` - Triggered when user clicks Reject button
- `rizo-cyberpunkcall:callTimeout` - Triggered when call times out without user interaction

### Event Usage Example

```lua
-- Listen for call events in your script
AddEventHandler('rizo-cyberpunkcall:callAnswered', function()
    print('Call was answered!')
    -- Handle call answer logic here
end)

AddEventHandler('rizo-cyberpunkcall:callRejected', function()
    print('Call was rejected!')
    -- Handle call rejection logic here
end)

AddEventHandler('rizo-cyberpunkcall:callTimeout', function()
    print('Call timed out!')
    -- Handle call timeout logic here
end)
```

## Advanced Configuration

### Anti-Spam System
The resource includes a built-in deduplication system that prevents the same text from being spoken within a 1.5-second window.

```lua
local DEDUP_WINDOW_MS = 1500 -- Configurable in client.lua
```

### Custom Configuration
You can override the default configuration by defining `RizoSpeechConfig` before the resource loads:

```lua
-- In another resource or server.cfg
RizoSpeechConfig = {
  mode = 'local',
  default_volume = 0.8,
  precall = {
    enabled = false
  }
}
```

## Requirements

- FiveM Server
- NUI-compatible framework
- (Optional) ElevenLabs API access for TTS functionality
- Server-side resource for TTS processing

## Contributing

Feel free to submit issues, feature requests, or pull requests to improve this resource.

## License

This project is open source. Please check the license file for more information.

## Credits

- Inspired by Cyberpunk 2077's communication system
- Built for FiveM community