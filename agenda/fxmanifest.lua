fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'agenda'
author 'Anthony'
description 'AGENDA - Systeme de reservation universel (multi-telephone, multi-framework)'
version '0.1.0'

ui_page 'html/index.html'

files {
  'html/index.html',
  'html/app.js',
  'html/style.css'
}

shared_script 'config.lua'
client_scripts { 'bridge/*.lua', 'client/*.lua' }
server_scripts { '@oxmysql/lib/MySQL.lua', 'bridge/*.lua', 'server/*.lua' }

-- IMPORTANT : la NUI n'est pas (encore) protegee par l'escrow.
escrow_ignore { 'html/**', 'config.lua' }

dependencies { 'oxmysql' }

-- npwd est optionnel : l'agenda fonctionne sans lui (fallback standalone)
-- Pour activer : installer npwd et le lancer AVANT agenda dans server.cfg
