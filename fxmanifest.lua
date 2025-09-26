fx_version 'cerulean'
game 'gta5'

ui_page 'web/index.html'

files {
  'web/index.html',
  'web/style.css',
  'web/script.js',
  'web/assets/*.webp',
  'web/assets/*.png',
  'web/assets/*.jpg',
  'web/assets/*.jpeg',
  'web/assets/*.mp3',
  'web/assets/*.ogg'
}

shared_script 'config.lua'

client_scripts {
  'client.lua'
}

server_scripts {
  'server.lua'
}
