if not Config.DevMode then return end
RegisterCommand('EconomyShopFundingTest', function(source, args)
    if source ~= 0 then return end
    local target, requestId = tonumber(args[1]), args[2]
    local currency, amount = args[3] or 'dollars', args[4] == nil and 200 or tonumber(args[4])
    if not target or target % 1 ~= 0 or target < 1 or target > 65535
        or type(requestId) ~= 'string' or #requestId > 100
        or (currency ~= 'dollars' and currency ~= 'gold')
        or not amount or amount % 1 ~= 0 or amount < 1 or amount > 10000 or args[5] ~= nil
        or not requestId:match('^[A-Za-z0-9][A-Za-z0-9._:%-]*$') then
        print('[EconomyShopFundingTest] usage: EconomyShopFundingTest <active source> <stable requestId> [dollars|gold] [minor units 1-10000]'); return
    end
    local session = exports['feather-core']:GetSessionContext(target)
    if type(session) ~= 'table' or not session.ok then
        print('[EconomyShopFundingTest] FAIL active session required'); return
    end
    local wallets = EconomyAccounts.EnsureCharacterWallets(session.value.characterId)
    local wallet
    for _, account in ipairs(wallets.ok and wallets.value or {}) do
        if account.currency == currency then wallet = account; break end
    end
    if not wallet then print('[EconomyShopFundingTest] FAIL wallet missing'); return end
    if not exports['feather-core']:IsSessionCurrent(target, session.value.sessionId, session.value.characterId) then
        print('[EconomyShopFundingTest] FAIL session changed'); return
    end
    local issued = EconomyAPI.Issue({ accountId = wallet.accountId, currency = currency, amount = amount,
        reasonCode = 'smoke.shop_funding', referenceType = 'smoke', referenceId = requestId,
        idempotencyKey = 'shop-funding:' .. requestId }, { resource = 'feather-economy', actorSource = target,
        actorCharacterId = session.value.characterId, correlationId = requestId }, 'feather-economy')
    local after = EconomyAccounts.Get(wallet.accountId)
    local passed = issued.ok and after.ok
        and after.value.balance == wallet.balance + (issued.value.replayed and 0 or amount)
    print(('[EconomyShopFundingTest] %s currency=%s issued=%s replayed=%s balance=%s code=%s'):format(
        passed and 'PASS' or 'FAIL', currency, tostring(amount), tostring(issued.ok and issued.value.replayed),
        tostring(after.ok and after.value.balance), tostring(issued.code)))
end, true)
RegisterCommand('EconomyPaymentReversalContractSmokeTest', function(source)
    if source ~= 0 then return end
    local uuid = '00000000-0000-4000-8000-000000000001'
    local untrusted = EconomyAPI.ReversePayment({ transactionId = uuid }, {}, 'untrusted-test')
    local incomplete = EconomyAPI.ReversePayment({}, {}, 'feather-shops')
    local tampered = EconomyAPI.ReversePayment({ transactionId = uuid, amount = 1 }, {}, 'feather-shops')
    local missing = EconomyAPI.ReversePayment({ transactionId = uuid }, {}, 'feather-shops')
    local malformed = EconomyAPI.ReversePayment({ transactionId = '0000000-00000-4000-8000-000000000001' }, {}, 'feather-shops')
    local tests = {
        { 'trusted caller configured', Config.Access.trustedReversers['feather-shops'] == true },
        { 'untrusted caller rejected', not untrusted.ok and untrusted.code == 'authorization_denied' },
        { 'incomplete request rejected', not incomplete.ok and incomplete.code == 'invalid_input' },
        { 'malformed UUID rejected', not malformed.ok and malformed.code == 'invalid_input' },
        { 'amount tampering rejected', not tampered.ok and tampered.code == 'invalid_input' },
        { 'missing payment rejected', not missing.ok and missing.code == 'reversal_not_allowed' },
        { 'shops supply access absent', Config.Access.trustedSuppliers['feather-shops'] ~= true }
    }
    local passed = 0
    for _, test in ipairs(tests) do
        if test[2] then passed = passed + 1 end
        print(('[EconomyPaymentReversalContractSmokeTest] %-29s %s'):format(test[1], test[2] and 'PASS' or 'FAIL'))
    end
    print(('[EconomyPaymentReversalContractSmokeTest] done %d/%d passed (no funds moved)'):format(passed, #tests))
end, true)
