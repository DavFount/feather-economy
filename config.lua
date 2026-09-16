Config = {
    Contract = 1,
    RequiredCoreContract = 1,
    DevMode = true,
    SystemOwnerId = '00000000-0000-0000-0000-000000000001',
    Access = {
        trustedReaders = {
            ['feather-economy'] = true,
            ['feather-admin'] = true,
            ['feather-hud'] = true,
            ['bcc-shops'] = true
        },
        trustedProvisioners = {
            ['feather-economy'] = true,
            ['feather-character'] = true,
            ['feather-admin'] = true
        }
    },
    Currencies = {
        dollars = {
            label = 'Dollars',
            precision = 2,
            enabled = true
        },
        gold = {
            label = 'Gold',
            precision = 2,
            enabled = true
        }
    },
    Limits = {
        readinessTimeoutMs = 30000,
        maximumPageSize = 100,
        maximumReasonLength = 64,
        maximumReferenceLength = 128,
        maximumIdempotencyKeyLength = 128
    }
}
