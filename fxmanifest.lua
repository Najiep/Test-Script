
fx_version 'cerulean'
game 'gta5'

name 'qbx_police'
description 'Police system (ESX Legacy + ox_lib/ox_inventory)'
repository 'https://github.com/Qbox-project/qbx_police'
version '1.0.0'

ox_lib 'locale'

dependencies {
    'ox_lib',
    'es_extended',
    'oxmysql',
    'ox_inventory'
}

shared_scripts {
    '@ox_lib/init.lua',
    'config/shared.lua',
}

client_scripts {
    'config/client.lua',
    'client/main.lua',
    'client/modules/*.lua',
    'client/*.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'config/server.lua',
    'server/*.lua',
}


lua54 'yes'
use_experimental_fxv2_oal 'yes'