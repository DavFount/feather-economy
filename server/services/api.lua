EconomyAPI = {}

function EconomyAPI.GetCapabilities()
    return EconomyFoundation.GetCapabilities()
end

function EconomyAPI.GetHealth()
    return EconomyResults.Ok(EconomyFoundation.GetHealth())
end

function EconomyAPI.AwaitReady(timeoutMs)
    return EconomyFoundation.AwaitReady(timeoutMs)
end

function EconomyAPI.GetCurrency(code)
    return EconomyCurrencies.Get(code)
end

function EconomyAPI.ListCurrencies()
    return EconomyCurrencies.List()
end

local function Authorize(resource, group)
    if type(resource) ~= 'string' or resource == ''
        or type(Config.Access[group]) ~= 'table'
        or Config.Access[group][resource] ~= true then
        return EconomyResults.Err('authorization_denied',
            'Calling resource is not authorized for this Economy operation.')
    end
    return EconomyResults.Ok(true)
end

function EconomyAPI.GetAccount(request, resource)
    local allowed = Authorize(resource, 'trustedReaders')
    if not allowed.ok then return allowed end
    request = type(request) == 'table' and request or {}
    return EconomyAccounts.Get(request.accountId)
end

function EconomyAPI.FindAccountsByOwner(request, resource)
    local allowed = Authorize(resource, 'trustedReaders')
    if not allowed.ok then return allowed end
    request = type(request) == 'table' and request or {}
    return EconomyAccounts.FindByOwner(request.ownerType, request.ownerId)
end

function EconomyAPI.EnsureCharacterWallets(request, resource)
    local allowed = Authorize(resource, 'trustedProvisioners')
    if not allowed.ok then return allowed end
    request = type(request) == 'table' and request or {}
    return EconomyAccounts.EnsureCharacterWallets(request.characterId)
end

function EconomyAPI.Transfer(request, context, resource)
    context = type(context) == 'table' and context or {}
    context.resource = resource
    return EconomyJournal.Transfer(request, context)
end

local function Supply(operation, request, context, resource)
    context = type(context) == 'table' and context or {}
    context.resource = resource
    if Config.Authorization.enabled == true then
        local action = operation == 'issue' and Config.Authorization.issueAction
            or Config.Authorization.destroyAction
        local decision = exports['feather-core']:Authorize(action, {
            source = context.actorSource,
            correlationId = context.correlationId,
            subject = { operation = operation, accountId = request and request.accountId,
                currency = request and request.currency, amount = request and request.amount }
        })
        if type(decision) ~= 'table' or not decision.ok
            or type(decision.value) ~= 'table' or decision.value.allowed ~= true then
            return EconomyResults.Err('authorization_denied',
                'Currency supply operation is not authorized.')
        end
    end
    return operation == 'issue' and EconomyJournal.Issue(request, context)
        or EconomyJournal.Destroy(request, context)
end

function EconomyAPI.Issue(request, context, resource)
    return Supply('issue', request, context, resource)
end

function EconomyAPI.Destroy(request, context, resource)
    return Supply('destroy', request, context, resource)
end

exports('GetCapabilities', EconomyAPI.GetCapabilities)
exports('GetHealth', EconomyAPI.GetHealth)
exports('AwaitReady', EconomyAPI.AwaitReady)
exports('GetCurrency', EconomyAPI.GetCurrency)
exports('ListCurrencies', EconomyAPI.ListCurrencies)
exports('GetAccount', function(request)
    return EconomyAPI.GetAccount(request, GetInvokingResource())
end)
exports('FindAccountsByOwner', function(request)
    return EconomyAPI.FindAccountsByOwner(request, GetInvokingResource())
end)
exports('EnsureCharacterWallets', function(request)
    return EconomyAPI.EnsureCharacterWallets(request, GetInvokingResource())
end)
exports('Transfer', function(request, context)
    return EconomyAPI.Transfer(request, context, GetInvokingResource())
end)
exports('Issue', function(request, context)
    return EconomyAPI.Issue(request, context, GetInvokingResource())
end)
exports('Destroy', function(request, context)
    return EconomyAPI.Destroy(request, context, GetInvokingResource())
end)

exports('initiate', function()
    return {
        GetCapabilities = EconomyAPI.GetCapabilities,
        GetHealth = EconomyAPI.GetHealth,
        AwaitReady = EconomyAPI.AwaitReady,
        Currencies = {
            Get = EconomyAPI.GetCurrency,
            List = EconomyAPI.ListCurrencies
        }
    }
end)
