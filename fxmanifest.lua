fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'

description 'Authoritative monetary accounting service for the Feather Framework'
author 'Feather Framework'
name 'feather-economy'
version '0.1.4'

shared_script 'shared/results.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'config.lua',
    'server/logging.lua',
    'server/migrations/001_economy_foundation.lua',
    'server/migrations/002_economy_accounts.lua',
    'server/migrations/003_economy_journal.lua',
    'server/migrations/004_organization_treasuries.lua',
    'server/persistence/migrations.lua',
    'server/repositories/currencies.lua',
    'server/repositories/accounts.lua',
    'server/services/journal.lua',
    'server/services/outbox.lua',
    'server/services/foundation.lua',
    'server/services/api.lua',
    'server/main.lua',
    'server/shop_tests.lua',
    'server/treasury_tests.lua'
}

dependencies {
    'oxmysql',
    'feather-core'
}
