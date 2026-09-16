EconomyFoundation = {}

local resourceName = GetCurrentResourceName()
local resourceVersion = GetResourceMetadata(resourceName, 'version', 0) or '0.0.0'
local logger = EconomyLogging.Create('foundation')
local health = {
    state = 'stopped',
    phase = 'not_started',
    contract = 1,
    version = resourceVersion,
    startedAt = os.time(),
    readyAt = nil,
    failure = nil,
    checks = {}
}

local function Copy(value)
    if type(value) ~= 'table' then return value end
    local output = {}
    for key, child in pairs(value) do output[key] = Copy(child) end
    return output
end

local function SetState(state, phase, failure)
    health.state = state
    health.phase = phase or state
    health.failure = failure and Copy(failure) or nil
    if state == 'ready' then health.readyAt = os.time() end
    logger.Info('lifecycle.changed', { state = state, phase = health.phase })
end

local function ValidateConfig()
    if tonumber(Config and Config.Contract) ~= 1 then
        return EconomyResults.Err('invalid_config', 'Config.Contract must equal 1.')
    end
    if tonumber(Config.RequiredCoreContract) ~= 1 then
        return EconomyResults.Err('invalid_config',
            'Config.RequiredCoreContract must equal 1.')
    end
    local limits = Config.Limits
    if type(limits) ~= 'table'
        or type(limits.readinessTimeoutMs) ~= 'number'
        or limits.readinessTimeoutMs < 0 or limits.readinessTimeoutMs > 60000
        or type(limits.maximumPageSize) ~= 'number'
        or limits.maximumPageSize < 1 or limits.maximumPageSize > 500
        or limits.maximumPageSize ~= math.floor(limits.maximumPageSize)
        or type(limits.maximumReasonLength) ~= 'number'
        or limits.maximumReasonLength < 1 or limits.maximumReasonLength > 128
        or type(limits.maximumReferenceLength) ~= 'number'
        or limits.maximumReferenceLength < 1 or limits.maximumReferenceLength > 256
        or type(limits.maximumIdempotencyKeyLength) ~= 'number'
        or limits.maximumIdempotencyKeyLength < 16
        or limits.maximumIdempotencyKeyLength > 256 then
        return EconomyResults.Err('invalid_config', 'Config.Limits is invalid.')
    end
    local access = Config.Access
    if type(access) ~= 'table' or type(access.trustedReaders) ~= 'table'
        or type(access.trustedProvisioners) ~= 'table'
        or access.trustedReaders['feather-economy'] ~= true
        or access.trustedProvisioners['feather-economy'] ~= true then
        return EconomyResults.Err('invalid_config', 'Config.Access is invalid.')
    end
    health.checks.configuration = { ok = true, checkedAt = os.time() }
    return EconomyResults.Ok(true)
end

function EconomyFoundation.BeginStartup()
    SetState('booting', 'validating_configuration')
    local configured = ValidateConfig()
    if not configured.ok then return EconomyFoundation.MarkFailed(
        configured.code, configured.message, configured.details) end

    SetState('waiting', 'waiting_for_core')
    local ready = exports['feather-core']:AwaitReady(Config.Limits.readinessTimeoutMs)
    if type(ready) ~= 'table' or ready.ok ~= true then
        return EconomyFoundation.MarkFailed('dependency_unavailable',
            'Feather Core did not become ready.', {
                dependency = 'feather-core',
                code = type(ready) == 'table' and ready.code or 'invalid_result'
            })
    end
    local capabilities = exports['feather-core']:GetCapabilities()
    local coreContract = type(capabilities) == 'table' and capabilities.ok == true
        and tonumber(capabilities.value and capabilities.value.contract) or 0
    if coreContract < tonumber(Config.RequiredCoreContract) then
        return EconomyFoundation.MarkFailed('dependency_unavailable',
            'Feather Core Contract 1 is required.')
    end
    health.checks.core = { ok = true, checkedAt = os.time(),
        contract = coreContract }
    local declared = exports['feather-core']:DeclareEvent('economy.ready.v1', {
        contract = 1, maxPayloadBytes = 2048, maxDepth = 5, maxNodes = 64
    })
    if type(declared) ~= 'table' or declared.ok ~= true then
        return EconomyFoundation.MarkFailed('dependency_unavailable',
            'Economy could not declare its readiness event.', {
                dependency = 'feather-core',
                code = type(declared) == 'table' and declared.code or 'invalid_result'
            })
    end
    health.checks.events = { ok = true, checkedAt = os.time() }
    SetState('migrating', 'database_migrations')
    return EconomyResults.Ok(true)
end

function EconomyFoundation.MarkMigrationsComplete(details)
    health.checks.migrations = { ok = true, checkedAt = os.time(), details = Copy(details or {}) }
    SetState('starting', 'loading_currency_catalog')
end

function EconomyFoundation.MarkCatalogReady(details)
    health.checks.currencies = { ok = true, checkedAt = os.time(), details = Copy(details or {}) }
end

function EconomyFoundation.MarkAccountsReady(details)
    health.checks.accounts = { ok = true, checkedAt = os.time(), details = Copy(details or {}) }
end

function EconomyFoundation.MarkReady()
    SetState('ready', 'ready')
    return EconomyResults.Ok(EconomyFoundation.GetHealth())
end

function EconomyFoundation.MarkFailed(code, message, details)
    local result = EconomyResults.Err(code, message, details)
    SetState('failed', 'startup_failed', result)
    logger.Error('startup.failed', result)
    return result
end

function EconomyFoundation.GetHealth() return Copy(health) end

function EconomyFoundation.GetCapabilities()
    return EconomyResults.Ok({
        resource = resourceName,
        contract = 1,
        version = resourceVersion,
        state = health.state,
        features = {
            lifecycle = 1,
            health = 1,
            migrations = 1,
            results = 1,
            currencyCatalog = 1,
            accounts = 1,
            transfers = 0,
            journal = 0,
            idempotency = 0,
            outbox = 0
        }
    })
end

function EconomyFoundation.AwaitReady(timeoutMs)
    timeoutMs = tonumber(timeoutMs) or 10000
    if timeoutMs < 0 or timeoutMs > 60000 then
        return EconomyResults.Err('invalid_input',
            'timeoutMs must be between 0 and 60000.')
    end
    local deadline = GetGameTimer() + timeoutMs
    while health.state ~= 'ready' and health.state ~= 'failed'
        and GetGameTimer() < deadline do Wait(0) end
    if health.state == 'ready' then
        return EconomyResults.Ok(EconomyFoundation.GetHealth())
    end
    if health.state == 'failed' then
        return EconomyResults.Err('not_ready', 'Feather Economy failed to start.', {
            health = EconomyFoundation.GetHealth()
        })
    end
    return EconomyResults.Err('timeout',
        'Timed out waiting for Feather Economy readiness.')
end
