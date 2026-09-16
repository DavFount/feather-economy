if not Config.DevMode then return end
RegisterCommand('EconomyShopFundingTest', function(source, args)
    if source ~= 0 then return end
    local target, requestId = tonumber(args[1]), args[2]
    if not target or type(requestId) ~= 'string' or #requestId > 100
        or not requestId:match('^[A-Za-z0-9][A-Za-z0-9._:%-]*$') then
        print('[EconomyShopFundingTest] usage: EconomyShopFundingTest <active source> <stable requestId>'); return
    end
    local session = exports['feather-core']:GetSessionContext(target)
    if type(session) ~= 'table' or not session.ok then
        print('[EconomyShopFundingTest] FAIL active session required'); return
    end
    local wallets = EconomyAccounts.EnsureCharacterWallets(session.value.characterId)
    local wallet
    for _, account in ipairs(wallets.ok and wallets.value or {}) do
        if account.currency == 'dollars' then wallet = account; break end
    end
    if not wallet then print('[EconomyShopFundingTest] FAIL wallet missing'); return end
    if not exports['feather-core']:IsSessionCurrent(target, session.value.sessionId, session.value.characterId) then
        print('[EconomyShopFundingTest] FAIL session changed'); return
    end
    local issued = EconomyAPI.Issue({ accountId = wallet.accountId, currency = 'dollars', amount = 200,
        reasonCode = 'smoke.shop_funding', referenceType = 'smoke', referenceId = requestId,
        idempotencyKey = 'shop-funding:' .. requestId }, { resource = 'feather-economy', actorSource = target,
        actorCharacterId = session.value.characterId, correlationId = requestId }, 'feather-economy')
    local after = EconomyAccounts.Get(wallet.accountId)
    local passed = issued.ok and after.ok
        and after.value.balance == wallet.balance + (issued.value.replayed and 0 or 200)
    print(('[EconomyShopFundingTest] %s issued=200 replayed=%s balance=%s'):format(
        passed and 'PASS' or 'FAIL', tostring(issued.ok and issued.value.replayed),
        tostring(after.ok and after.value.balance)))
end, true)
RegisterCommand('EconomyPaymentReversalContractSmokeTest', function(source)
    if source ~= 0 then return end
    local uuid = '00000000-0000-4000-8000-000000000001'
    local untrusted = EconomyAPI.ReversePayment({ transactionId = uuid }, {}, 'untrusted-test')
    local incomplete = EconomyAPI.ReversePayment({}, {}, 'feather-shops')
    local tampered = EconomyAPI.ReversePayment({ transactionId = uuid, amount = 1 }, {}, 'feather-shops')
    local missing = EconomyAPI.ReversePayment({ transactionId = uuid }, {}, 'feather-shops')
    local tests = {
        { 'trusted caller configured', Config.Access.trustedReversers['feather-shops'] == true },
        { 'untrusted caller rejected', not untrusted.ok and untrusted.code == 'authorization_denied' },
        { 'incomplete request rejected', not incomplete.ok and incomplete.code == 'invalid_input' },
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
