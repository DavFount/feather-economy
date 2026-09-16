local logger = EconomyLogging.Create('main')

local function Fail(result)
    local failure = type(result) == 'table' and result
        or EconomyResults.Err('internal_error', 'Economy startup returned an invalid result.')
    logger.Error('startup.aborted', {
        code = failure.code,
        message = failure.message,
        details = failure.details
    })
    error(failure.message or 'Feather Economy startup failed.')
end

CreateThread(function()
    local started = EconomyFoundation.BeginStartup()
    if not started.ok then return Fail(started) end

    local migrations = EconomyMigrationRunner.Run()
    if not migrations.ok then
        return Fail(EconomyFoundation.MarkFailed(
            migrations.code, migrations.message, migrations.details))
    end
    EconomyFoundation.MarkMigrationsComplete(migrations.value)

    local currencies = EconomyCurrencies.Start()
    if not currencies.ok then
        return Fail(EconomyFoundation.MarkFailed(
            currencies.code, currencies.message, currencies.details))
    end
    EconomyFoundation.MarkCatalogReady(currencies.value)

    local accounts = EconomyAccounts.Start()
    if not accounts.ok then
        return Fail(EconomyFoundation.MarkFailed(
            accounts.code, accounts.message, accounts.details))
    end
    EconomyFoundation.MarkAccountsReady(accounts.value)

    local ready = EconomyFoundation.MarkReady()
    logger.Info('startup.ready', {
        contract = 1,
        currencies = EconomyCurrencies.Count(),
        systemAccounts = accounts.value.systemAccounts,
        migrationsApplied = migrations.value.applied
    })
    local published = exports['feather-core']:PublishEvent('economy.ready.v1', {
        contract = 1,
        version = GetResourceMetadata(GetCurrentResourceName(), 'version', 0) or '0.0.0',
        currencies = EconomyCurrencies.Count()
    })
    if type(published) ~= 'table' or published.ok ~= true then
        logger.Warn('readiness.publish_failed', {
            code = type(published) == 'table' and published.code or 'invalid_result'
        })
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        logger.Info('lifecycle.stopped')
    end
end)

RegisterCommand('EconomyFoundationSmokeTest', function(source)
    if source ~= 0 then return end
    local capabilities = EconomyFoundation.GetCapabilities()
    local health = EconomyFoundation.GetHealth()
    local currencies = EconomyCurrencies.List()
    local dollars = EconomyCurrencies.Get('dollars')
    local gold = EconomyCurrencies.Get('gold')
    local unknown = EconomyCurrencies.Get('unknown')
    local tests = {
        { 'capabilities', capabilities.ok and capabilities.value.contract == 1
            and capabilities.value.features.currencyCatalog == 1 },
        { 'health', health.state == 'ready' and health.checks.core.ok
            and health.checks.events.ok
            and health.checks.migrations.ok and health.checks.currencies.ok
            and health.checks.accounts.ok },
        { 'currency catalog', currencies.ok and #currencies.value == 2 },
        { 'dollars definition', dollars.ok and dollars.value.precision == 2
            and dollars.value.enabled == true },
        { 'gold definition', gold.ok and gold.value.precision == 2
            and gold.value.enabled == true },
        { 'unknown rejected', not unknown.ok and unknown.code == 'currency_not_found' }
    }
    local passed = 0
    for _, test in ipairs(tests) do
        if test[2] then passed = passed + 1 end
        print(('[EconomyFoundationSmokeTest] %-22s %s')
            :format(test[1], test[2] and 'PASS' or 'FAIL'))
    end
    print(('[EconomyFoundationSmokeTest] done %d/%d passed'):format(passed, #tests))
end, true)

RegisterCommand('EconomyAccountContractSmokeTest', function(source)
    if source ~= 0 then return end
    local system = EconomyAccounts.FindByOwner('system', Config.SystemOwnerId)
    local invalidOwner = EconomyAccounts.FindByOwner('character', 'invalid')
    local missing = EconomyAccounts.Get('00000000-0000-0000-0000-000000000099')
    local unauthorizedRead = EconomyAPI.FindAccountsByOwner({
        ownerType = 'system', ownerId = Config.SystemOwnerId
    }, 'untrusted-smoke-resource')
    local unauthorizedProvision = EconomyAPI.EnsureCharacterWallets({
        characterId = Config.SystemOwnerId
    }, 'untrusted-smoke-resource')
    local distinct = {}
    for _, account in ipairs(system.ok and system.value or {}) do
        distinct[account.accountId] = true
    end
    local tests = {
        { 'system accounts', system.ok and #system.value == 4 },
        { 'unique identities', system.ok and (function()
            local count = 0
            for _ in pairs(distinct) do count = count + 1 end
            return count == 4
        end)() },
        { 'zero balances', system.ok and (function()
            for _, account in ipairs(system.value) do
                if account.balance ~= 0 or account.balanceRevision ~= 1 then return false end
            end
            return true
        end)() },
        { 'invalid owner rejected', not invalidOwner.ok and invalidOwner.code == 'invalid_input' },
        { 'missing account rejected', not missing.ok and missing.code == 'account_not_found' },
        { 'untrusted read rejected', not unauthorizedRead.ok
            and unauthorizedRead.code == 'authorization_denied' },
        { 'untrusted provision rejected', not unauthorizedProvision.ok
            and unauthorizedProvision.code == 'authorization_denied' }
    }
    local passed = 0
    for _, test in ipairs(tests) do
        if test[2] then passed = passed + 1 end
        print(('[EconomyAccountContractSmokeTest] %-28s %s')
            :format(test[1], test[2] and 'PASS' or 'FAIL'))
    end
    print(('[EconomyAccountContractSmokeTest] done %d/%d passed (read-only)')
        :format(passed, #tests))
end, true)

if Config.DevMode then
    RegisterCommand('EconomyWalletProvisionTest', function(source, args)
        if source ~= 0 then return end
        local target = tonumber(args and args[1])
        if not target then
            print('[EconomyWalletProvisionTest] usage: EconomyWalletProvisionTest <source>')
            return
        end
        local session = exports['feather-core']:GetSessionContext(target)
        if type(session) ~= 'table' or not session.ok then
            print('[EconomyWalletProvisionTest] FAIL active character session required')
            return
        end
        local first = EconomyAccounts.EnsureCharacterWallets(session.value.characterId)
        local second = EconomyAccounts.EnsureCharacterWallets(session.value.characterId)
        local same = first.ok and second.ok and #first.value == 2 and #second.value == 2
        if same then
            for index = 1, #first.value do
                same = same and first.value[index].accountId == second.value[index].accountId
                    and first.value[index].balance == 0 and second.value[index].balance == 0
            end
        end
        print(('[EconomyWalletProvisionTest] %s character=%s wallets=%s idempotent=%s'):format(
            same and 'PASS' or 'FAIL', tostring(session.value.characterId),
            tostring(first.ok and #first.value or 0), tostring(same)))
    end, true)
end
