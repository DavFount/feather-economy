EconomyJournal = {}

local function Text(value, maximum)
    return type(value) == 'string' and value ~= '' and #value <= maximum and value or nil
end

local function IsUuid(value)
    return type(value) == 'string' and value:match(
        '^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$') ~= nil
end

local function RequestId(value)
    local maximum = Config.Limits.maximumIdempotencyKeyLength
    return Text(value, maximum) and value:match('^[A-Za-z0-9][A-Za-z0-9._:%-]*$') and value or nil
end

local function Fingerprint(operation, request)
    return table.concat({ operation, request.fromAccountId, request.toAccountId,
        request.currency, tostring(request.amount), request.reasonCode,
        request.referenceType or '', request.referenceId or '' }, '|')
end

local function Failure(code, message, details)
    return EconomyResults.Err(code, message, details)
end

local function Post(operation, request, context)
    request, context = type(request) == 'table' and request or {},
        type(context) == 'table' and context or {}
    local resource = context.resource
    local trusted = operation == 'reversal' and Config.Access.trustedReversers
        or operation == 'transfer' and Config.Access.trustedTransactors
        or Config.Access.trustedSuppliers
    if type(resource) ~= 'string' or not trusted[resource] then
        return Failure('authorization_denied',
            'Calling resource is not authorized to transfer currency.')
    end
    local amount = tonumber(request.amount)
    local idempotencyKey = RequestId(request.idempotencyKey)
    local reasonCode = Text(request.reasonCode, Config.Limits.maximumReasonLength)
    local referenceType = request.referenceType == nil and nil
        or Text(request.referenceType, 48)
    local referenceId = request.referenceId == nil and nil
        or Text(request.referenceId, Config.Limits.maximumReferenceLength)
    if not IsUuid(request.fromAccountId) or not IsUuid(request.toAccountId)
        or request.fromAccountId == request.toAccountId
        or type(amount) ~= 'number' or amount < 1
        or amount > Config.Limits.maximumTransferAmount or amount ~= math.floor(amount)
        or type(request.currency) ~= 'string' or not idempotencyKey or not reasonCode
        or (request.referenceType ~= nil and not referenceType)
        or (request.referenceId ~= nil and not referenceId) then
        return Failure('invalid_input', 'Transfer request is invalid.')
    end
    local fingerprint = Fingerprint(operation, {
        fromAccountId = request.fromAccountId, toAccountId = request.toAccountId,
        currency = request.currency, amount = amount, reasonCode = reasonCode,
        referenceType = referenceType, referenceId = referenceId
    })
    local bodyResult, bodyError
    local called, committed = pcall(MySQL.startTransaction, function(query)
        local ok, result = pcall(function()
            if operation == 'reversal' then
                local originals = query([[SELECT * FROM `economy_transactions`
                    WHERE `transaction_id`=? FOR UPDATE]], { referenceId }) or {}
                local original = originals[1]
                if not original or original.source_resource ~= resource
                    or original.operation_type ~= 'transfer' or original.status ~= 'committed'
                    or original.reason_code ~= 'shop.purchase' or original.reference_type ~= 'shop_order' then
                    return Failure('reversal_not_allowed', 'Only this caller\'s committed shop payment can be reversed.')
                end
                local entries = query([[SELECT `account_id`,`amount` FROM `economy_entries`
                    WHERE `transaction_id`=?]], { referenceId }) or {}
                local valid = #entries == 2
                local debit, credit = false, false
                for _, entry in ipairs(entries) do
                    debit = debit or (entry.account_id == request.toAccountId and tonumber(entry.amount) == -amount)
                    credit = credit or (entry.account_id == request.fromAccountId and tonumber(entry.amount) == amount)
                end
                if not valid or not debit or not credit or original.currency_code ~= request.currency then
                    return Failure('internal_error', 'Original payment entries do not match the reversal.')
                end
            end
            query([[
                INSERT IGNORE INTO `economy_transactions`
                    (`transaction_id`,`operation_type`,`status`,`currency_code`,`reason_code`,
                     `reference_type`,`reference_id`,`source_resource`,`actor_account_id`,
                     `actor_character_id`,`correlation_id`,`idempotency_key`,`request_fingerprint`)
                VALUES (UUID(),?,'pending',?,?,?,?,?,?,?,?,?,?)
            ]], { operation, request.currency, reasonCode, referenceType, referenceId, resource,
                context.actorAccountId, context.actorCharacterId,
                Text(context.correlationId, 128), idempotencyKey, fingerprint })
            local transactionRows = query([[
                SELECT * FROM `economy_transactions`
                WHERE `source_resource`=? AND `operation_type`=?
                  AND `idempotency_key`=? FOR UPDATE
            ]], { resource, operation, idempotencyKey }) or {}
            local transaction = transactionRows[1]
            if not transaction then return Failure('internal_error', 'Transfer request could not be reserved.') end
            if transaction.request_fingerprint ~= fingerprint then
                return Failure('idempotency_conflict',
                    'Idempotency key was already used for a different transfer.')
            end
            if transaction.status == 'committed' and transaction.result_json then
                local decoded, value = pcall(json.decode, transaction.result_json)
                if decoded and type(value) == 'table' then
                    value.replayed = true
                    return EconomyResults.Ok(value)
                end
                return Failure('internal_error', 'Stored transfer result is invalid.')
            end

            local first, second = request.fromAccountId, request.toAccountId
            if second < first then first, second = second, first end
            local accountRows = query([[
                SELECT a.`account_id`,a.`owner_type`,a.`account_type`,a.`currency_code`,a.`status`,
                       b.`posted_amount`,b.`revision`
                FROM `economy_accounts` a INNER JOIN `economy_balances` b
                  ON b.`account_id`=a.`account_id`
                WHERE a.`account_id` IN (?,?) ORDER BY a.`account_id` FOR UPDATE
            ]], { first, second }) or {}
            local accounts = {}
            for _, row in ipairs(accountRows) do accounts[row.account_id] = row end
            local from, to = accounts[request.fromAccountId], accounts[request.toAccountId]
            if not from or not to then return Failure('account_not_found', 'Transfer account was not found.') end
            if from.status ~= 'open' or to.status ~= 'open' then
                return Failure('account_closed', 'Transfer account is closed.')
            end
            if from.currency_code ~= request.currency or to.currency_code ~= request.currency then
                return Failure('currency_mismatch', 'Transfer accounts do not use the requested currency.')
            end
            local typesAllowed = operation == 'transfer' and from.account_type == 'wallet'
                and (to.account_type == 'wallet' or to.account_type == 'system_sink')
                or operation == 'issue' and from.account_type == 'system_source'
                    and to.account_type == 'wallet'
                or operation == 'destroy' and from.account_type == 'wallet'
                    and to.account_type == 'system_sink'
                or operation == 'reversal' and from.account_type == 'system_sink'
                    and to.account_type == 'wallet'
            if not typesAllowed then
                return Failure('authorization_denied', 'These account types cannot use a normal transfer.')
            end
            local fromBalance, toBalance = tonumber(from.posted_amount), tonumber(to.posted_amount)
            if not fromBalance or not toBalance then
                return Failure('internal_error', 'Transfer balance is invalid.')
            end
            if operation ~= 'issue' and fromBalance < amount then
                return Failure('insufficient_funds', 'Available balance is insufficient.', {
                    available = fromBalance, required = amount
                })
            end
            local nextFrom, nextTo = fromBalance - amount, toBalance + amount
            if nextTo > Config.Limits.maximumBalance
                or nextFrom < -Config.Limits.maximumBalance then
                return Failure('transaction_conflict', 'Destination balance limit would be exceeded.')
            end
            query('UPDATE `economy_balances` SET `posted_amount`=?,`revision`=`revision`+1 WHERE `account_id`=?',
                { nextFrom, request.fromAccountId })
            query('UPDATE `economy_balances` SET `posted_amount`=?,`revision`=`revision`+1 WHERE `account_id`=?',
                { nextTo, request.toAccountId })
            if Config.DevMode and resource == 'feather-economy'
                and context.failureInjection == 'after_balance_update' then
                return Failure('transaction_conflict',
                    'Injected failure after balance update.')
            end
            query([[
                INSERT INTO `economy_entries`
                    (`entry_id`,`transaction_id`,`account_id`,`amount`,`resulting_balance`)
                VALUES (UUID(),?,?,?,?),(UUID(),?,?,?,?)
            ]], { transaction.transaction_id, request.fromAccountId, -amount, nextFrom,
                transaction.transaction_id, request.toAccountId, amount, nextTo })
            local value = {
                transactionId = transaction.transaction_id, currency = request.currency,
                amount = amount, fromAccountId = request.fromAccountId,
                toAccountId = request.toAccountId, fromBalance = nextFrom,
                toBalance = nextTo, operation = operation, reasonCode = reasonCode,
                referenceType = referenceType, referenceId = referenceId,
                sourceResource = resource, correlationId = Text(context.correlationId, 128),
                replayed = false
            }
            local encoded = json.encode(value)
            query([[
                UPDATE `economy_transactions` SET `status`='committed',`result_json`=?,
                    `posted_at`=CURRENT_TIMESTAMP WHERE `transaction_id`=?
            ]], { encoded, transaction.transaction_id })
            query([[
                INSERT INTO `economy_outbox`
                    (`event_id`,`event_type`,`aggregate_id`,`payload_json`)
                VALUES (UUID(),'economy.transaction.posted.v1',?,?)
            ]], { transaction.transaction_id, encoded })
            return EconomyResults.Ok(value)
        end)
        if not ok then bodyError = tostring(result) return false end
        bodyResult = result
        return EconomyResults.Is(result) and result.ok
    end)
    if not called then
        return Failure('internal_error', 'Economy transfer transaction could not start.', {
            reason = tostring(committed)
        })
    end
    if committed ~= true then
        if EconomyResults.Is(bodyResult) then return bodyResult end
        return Failure('internal_error', 'Economy transfer transaction failed.', { reason = bodyError })
    end
    return bodyResult
end

function EconomyJournal.Transfer(request, context)
    return Post('transfer', request, context)
end

function EconomyJournal.ReversePayment(request, context)
    if type(context) ~= 'table' or not Config.Access.trustedReversers
        or Config.Access.trustedReversers[context.resource or ''] ~= true then
        return Failure('authorization_denied', 'Payment reversal caller is not trusted.')
    end
    if type(request) ~= 'table' or not IsUuid(request.transactionId) then
        return Failure('invalid_input', 'Original payment transaction UUID required.')
    end
    for key in pairs(request) do
        if key ~= 'transactionId' then return Failure('invalid_input', 'Unexpected reversal field.') end
    end
    local original = MySQL.single.await([[SELECT * FROM `economy_transactions`
        WHERE `transaction_id`=?]], { request.transactionId })
    if not original or original.source_resource ~= context.resource
        or original.operation_type ~= 'transfer' or original.status ~= 'committed'
        or original.reason_code ~= 'shop.purchase' or original.reference_type ~= 'shop_order' then
        return Failure('reversal_not_allowed', 'Only this caller\'s committed shop payment can be reversed.')
    end
    local decoded, value = pcall(json.decode, original.result_json or '')
    if not decoded or type(value) ~= 'table' then
        return Failure('internal_error', 'Original payment receipt is invalid.')
    end
    -- The original UUID supplies the only reversal key. Callers cannot obtain
    -- multiple refunds by choosing new request IDs or arbitrary amounts/accounts.
    return Post('reversal', {
        fromAccountId = value.toAccountId, toAccountId = value.fromAccountId,
        amount = value.amount, currency = value.currency,
        reasonCode = 'shop.payment_reversal', referenceType = 'economy_transaction',
        referenceId = original.transaction_id,
        idempotencyKey = 'reversal:' .. original.transaction_id
    }, context)
end

local function Supply(operation, request, context)
    request = type(request) == 'table' and request or {}
    local system = EconomyAccounts.FindByOwner('system', Config.SystemOwnerId)
    if not system.ok then return system end
    local systemType = operation == 'issue' and 'system_source' or 'system_sink'
    local systemAccount
    for _, account in ipairs(system.value) do
        if account.currency == request.currency and account.accountType == systemType then
            systemAccount = account
        end
    end
    if not systemAccount then
        return Failure('account_not_found', 'System supply account was not found.')
    end
    local post = {}
    for key, value in pairs(request) do post[key] = value end
    if operation == 'issue' then
        post.fromAccountId, post.toAccountId = systemAccount.accountId, request.accountId
    else
        post.fromAccountId, post.toAccountId = request.accountId, systemAccount.accountId
    end
    return Post(operation, post, context)
end

function EconomyJournal.Issue(request, context) return Supply('issue', request, context) end
function EconomyJournal.Destroy(request, context) return Supply('destroy', request, context) end
