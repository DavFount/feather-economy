Config = {
    Contract = 1,
    RequiredCoreContract = 1,
    -- Registers the data-changing console tests and the migration fault switch.
    -- Development servers only; keep false for production.
    DevMode = false,
    SystemOwnerId = '00000000-0000-0000-0000-000000000001',
    -- Resources allowed to call each group of exports (README "Access groups").
    -- Add a resource to every group it needs, then restart feather-economy.
    Access = {
        trustedTreasuryProvisioners = {
            ['feather-economy'] = true,
            ['feather-shops'] = true,
            ['feather-admin'] = true,
        },
        -- Operated accounts (README "Operated accounts"). May provision character
        -- bank accounts (EnsureCharacterBankAccounts).
        trustedBankProvisioners = {
            ['feather-economy'] = true,
        },
        -- May register reason codes whose shapes move character bank accounts.
        -- They must also be in trustedTransactors.
        trustedBankTransactors = {
            ['feather-economy'] = true,
        },
        -- May bind organization treasuries (EnsureOperatedTreasury) and register
        -- reason codes whose shapes move them. They must also be in trustedTransactors.
        trustedTreasuryOperators = {
        },
        -- May read the journal history of any account (ListAccountEntries). Other
        -- trusted readers see only accounts they serve: bank transactors read bank
        -- accounts, treasury operators read the treasury bound to them.
        privilegedHistoryReaders = {
            ['feather-economy'] = true,
            ['feather-admin'] = true,
        },
        trustedReaders = {
            ['feather-economy'] = true,
            ['feather-admin'] = true,
            ['feather-hud'] = true,
            ['feather-shops'] = true,
        },
        trustedProvisioners = {
            ['feather-economy'] = true,
            ['feather-character'] = true,
            ['feather-shops'] = true,
            ['feather-admin'] = true,
        },
        trustedTransactors = {
            ['feather-economy'] = true,
            ['feather-shops'] = true,
        },
        trustedReversers = {
            ['feather-economy'] = true,
            ['feather-shops'] = true,
        },
        -- Issue and Destroy; each also needs the Core policy grant (Authorization).
        trustedSuppliers = {
            ['feather-economy'] = true,
            ['feather-admin'] = true,
        },
    },
    -- Reason codes an operator may create currency with (issue_to_bank and
    -- issue_to_operated shapes), per resource, exact match only. Each issue still
    -- needs a Core policy grant (economy.currency.issue) for the resource.
    -- Example:
    --   ['my-bank'] = {
    --       ['bank.reserve.funding'] = true
    --   },
    OperatorSupply = {
    },
    -- Issue and Destroy need an explicit Core policy grant (issueAction or
    -- destroyAction) for the calling resource. Keep enabled for production;
    -- trust lists alone never allow creating or destroying currency.
    Authorization = {
        enabled = true,
        issueAction = 'economy.currency.issue',
        destroyAction = 'economy.currency.destroy'
    },
    Outbox = {
        pollIntervalMs = 1000,
        retryDelaySeconds = 5,
        batchSize = 25
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
        maximumIdempotencyKeyLength = 128,
        maximumTransferAmount = 1000000000000,
        maximumBalance = 9000000000000000
    }
}