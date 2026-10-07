fx_version 'cerulean'
game 'gta5'

name        'nova_medical'
description 'Système médical complet — Nova OMC'
version     '1.2.0'
author      'Nova Dev'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
    'client/examination.lua',
    'client/treatment.lua',
    'client/stretcher.lua',
    'client/bag.lua',
    'client/hud.lua',
    'client/monitoring.lua',
}

ui_page 'demo/index.html'

files {
    'demo/index.html',
    'imagerie/index.html',
    'chirurgie/index.html',
    'ui/index.html',
    'ui/style.css',
    'ui/script.js',
}

dependencies {
    'es_extended',
    'ox_lib',
    'ox_target',
    'oxmysql',
}
