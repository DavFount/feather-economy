EconomyAccounts = {}

local function IsUuid(value)
    return type(value) == 'string' and value:match(
        '^[0-9a-fA-F]+%-[0-9a-fA-F]+%-[0-9a-fA-F]+%-[0-9a-fA-F]+%-[0-9a-fA-F]+$') ~= nil
        and #value == 36
end

local function Copy(value)
    if type(value) ~= 'table' then return value end
    local output = {}
    for key, child in pairs(value) do output[key] = Copy(child) end
    return output
end

local function Normalize(row)
    if type(row) ~= 'table' then return nil end
    return {
        accountId = row.account_id,
        ownerType = row.owner_type,
        ownerId = row.owner_id,
        accountType = row.account_type,
        currency = row.currency_code,
        status = row.status,
        label = row.label,
        revision = tonumber(row.account_revision),
        balance = tonumber(row.posted_amount),
        balanceRevision = tonumber(row.balance_revision),
        createdAt = row.created_at,
        closedAt = row.closed_at,
        updatedAt = row.updated_at
    }
end

local function RunTransaction(body)
    local bodyResult, bodyError
    local called, committed = pcall(MySQL.startTransaction, function(query)
        local ok, result = pcall(body, query)
        if not ok then bodyError = tostring(result) return false end
        bodyResult = result
        return EconomyResults.Is(result) and result.ok
    end)
    if not called then
        return EconomyResults.Err('internal_error',
            'Economy account transaction could not start.', { reason = tostring(committed) })
    end
    if committed ~= true then
        if EconomyResults.Is(bodyResult) then return bodyResult end
        return EconomyResults.Err('internal_error',
            'Economy account transaction failed.', { reason = bodyError })
    end
    return Copy(bodyResult)
end

local function Ensure(ownerType, ownerId, accountTypes)
    if (ownerType ~= 'character' and ownerType ~= 'system' and ownerType ~= 'organization') or not IsUuid(ownerId) then
        return EconomyResults.Err('invalid_input', 'A valid account owner is required.')
    end
    local currencies = EconomyCurrencies.List()
    if not currencies.ok then return currencies end

    return RunTransaction(function(query)
        local accounts = {}
        for _, currency in ipairs(currencies.value) do
            for _, accountType in ipairs(accountTypes) do
                query([[
                    INSERT IGNORE INTO `economy_accounts`
                        (`account_id`,`owner_type`,`owner_id`,`account_type`,`currency_code`,`status`,`label`)
                    VALUES (UUID(),?,?,?,?, 'open', ?)
                ]], {
                    ownerType, ownerId, accountType, currency.code,
                    ('%s %s'):format(currency.label, accountType:gsub('_', ' '))
                })
                local rows = query([[
                    SELECT `account_id`,`owner_type`,`owner_id`,`account_type`,`currency_code`,
                           `status`,`label`,`revision` AS `account_revision`,`created_at`,`closed_at`
                    FROM `economy_accounts`
                    WHERE `owner_type`=? AND `owner_id`=? AND `account_type`=?
                      AND `currency_code`=? FOR UPDATE
                ]], { ownerType, ownerId, accountType, currency.code }) or {}
                local account = rows[1]
                if not account or account.status ~= 'open' then
                    return EconomyResults.Err('account_closed',
                        'An Economy account is unavailable.', {
                            ownerType = ownerType, ownerId = ownerId,
                            accountType = accountType, currency = currency.code
                        })
                end
                query([[
                    INSERT IGNORE INTO `economy_balances`
                        (`account_id`,`posted_amount`,`revision`) VALUES (?,0,1)
                ]], { account.account_id })
                local balanceRows = query([[
                    SELECT `posted_amount`,`revision` AS `balance_revision`,`updated_at`
                    FROM `economy_balances` WHERE `account_id`=? FOR UPDATE
                ]], { account.account_id }) or {}
                local balance = balanceRows[1]
                if not balance then
                    return EconomyResults.Err('internal_error',
                        'An Economy balance could not be provisioned.')
                end
                for key, value in pairs(balance) do account[key] = value end
                accounts[#accounts + 1] = Normalize(account)
            end
        end
        table.sort(accounts, function(left, right)
            if left.currency == right.currency then return left.accountType < right.accountType end
            return left.currency < right.currency
        end)
        return EconomyResults.Ok(accounts)
    end)
end

function EconomyAccounts.Start()
    if not IsUuid(Config and Config.SystemOwnerId) then
        return EconomyResults.Err('invalid_config', 'Config.SystemOwnerId must be a UUID.')
    end
    local ensured = Ensure('system', Config.SystemOwnerId,
        { 'system_source', 'system_sink' })
    if not ensured.ok then return ensured end
    return EconomyResults.Ok({ systemAccounts = #ensured.value })
end

function EconomyAccounts.EnsureCharacterWallets(characterId)
    return Ensure('character', characterId, { 'wallet' })
end

function EconomyAccounts.EnsureOrganizationTreasuries(organizationId)
    return Ensure('organization', organizationId, { 'treasury' })
end

function EconomyAccounts.Get(accountId)
    if not IsUuid(accountId) then
        return EconomyResults.Err('invalid_input', 'accountId must be a UUID.')
    end
    local rows = MySQL.query.await([[
        SELECT a.`account_id`,a.`owner_type`,a.`owner_id`,a.`account_type`,a.`currency_code`,
               a.`status`,a.`label`,a.`revision` AS `account_revision`,a.`created_at`,a.`closed_at`,
               b.`posted_amount`,b.`revision` AS `balance_revision`,b.`updated_at`
        FROM `economy_accounts` a
        INNER JOIN `economy_balances` b ON b.`account_id`=a.`account_id`
        WHERE a.`account_id`=? LIMIT 1
    ]], { accountId }) or {}
    if not rows[1] then
        return EconomyResults.Err('account_not_found', 'Economy account was not found.')
    end
    return EconomyResults.Ok(Normalize(rows[1]))
end

function EconomyAccounts.FindByOwner(ownerType, ownerId)
    if (ownerType ~= 'character' and ownerType ~= 'system' and ownerType ~= 'organization') or not IsUuid(ownerId) then
        return EconomyResults.Err('invalid_input', 'A valid account owner is required.')
    end
    local rows = MySQL.query.await([[
        SELECT a.`account_id`,a.`owner_type`,a.`owner_id`,a.`account_type`,a.`currency_code`,
               a.`status`,a.`label`,a.`revision` AS `account_revision`,a.`created_at`,a.`closed_at`,
               b.`posted_amount`,b.`revision` AS `balance_revision`,b.`updated_at`
        FROM `economy_accounts` a
        INNER JOIN `economy_balances` b ON b.`account_id`=a.`account_id`
        WHERE a.`owner_type`=? AND a.`owner_id`=?
        ORDER BY a.`currency_code`,a.`account_type`
        LIMIT ?
    ]], { ownerType, ownerId, Config.Limits.maximumPageSize }) or {}
    local accounts = {}
    for _, row in ipairs(rows) do accounts[#accounts + 1] = Normalize(row) end
    return EconomyResults.Ok(accounts)
end
