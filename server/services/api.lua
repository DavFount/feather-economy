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
