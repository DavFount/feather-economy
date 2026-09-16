# Feather Economy

Authoritative monetary accounting for the Feather Framework.

The current `0.1.0` foundation provides:

- Feather Contract 1 results, health, capabilities, and readiness;
- checksummed, idempotent database migrations;
- validated `dollars` and `gold` currency definitions;
- immutable persisted currency precision; and
- read-only currency catalog exports;
- atomic character and system account provisioning; and
- zero-balance account records with trusted server-only reads.

Transfers, balance mutation, the balanced journal, idempotency, and the
transactional outbox remain unavailable until their implementation phases land.

## Dependencies

```text
oxmysql
feather-core
```

Start Economy after both dependencies:

```text
ensure oxmysql
ensure feather-core
ensure feather-economy
```

## Contract

```lua
local ready = exports['feather-economy']:AwaitReady(30000)
local capabilities = exports['feather-economy']:GetCapabilities()
local currencies = exports['feather-economy']:ListCurrencies()
local dollars = exports['feather-economy']:GetCurrency('dollars')

local wallets = exports['feather-economy']:EnsureCharacterWallets({
    characterId = characterId
})
```

Account exports are server-only and restricted by `Config.Access`. Consumers
should use the named `GetAccount`, `FindAccountsByOwner`, and
`EnsureCharacterWallets` exports so Cfx can derive the invoking resource.

All operations use Core's flat result envelope:

```lua
{ ok = true, value = value, meta = optionalTable }
{ ok = false, code = 'stable_code', message = 'Safe summary', details = optionalTable }
```

## Validation

From the server console:

```text
EconomyFoundationSmokeTest
```

Expected result: `6/6 passed`.

After the foundation passes:

```text
EconomyAccountContractSmokeTest
EconomyWalletProvisionTest <connected source>
```

The account contract is read-only and should pass `7/7`. The wallet test
creates the active character's two zero-balance wallets and verifies that a
retry returns the same account IDs.
