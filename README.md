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

Atomic wallet transfers, balanced journal entries, payload-bound idempotency,
transactional outbox records, and policy-gated currency issuance/destruction
are available.

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

local paid = exports['feather-economy']:Transfer({
    fromAccountId = buyerWalletId,
    toAccountId = recipientWalletId,
    currency = 'dollars',
    amount = 2500,
    reasonCode = 'shop.purchase',
    referenceType = 'order',
    referenceId = orderId,
    idempotencyKey = requestId
}, context)
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
EconomyTransferContractSmokeTest <connected source>
EconomySupplyTest <connected source> <fresh requestId>
EconomyJournalAuditSmokeTest
EconomyTransferLiveTest <sender source> <recipient source> <fresh requestId>
```

The account contract is read-only and should pass `7/7`. The wallet test
creates the active character's two zero-balance wallets and verifies that a
retry returns the same account IDs.
The transfer contract test moves no funds and should pass `7/7`.
The supply test issues 100.00 dollars, replays the request, rejects mismatched
payload reuse, verifies balanced entries, and destroys the test amount so the
wallet finishes at its original balance.
The journal audit is read-only. The two-character transfer test funds the
sender, transfers 40.00 dollars with idempotent replay, and destroys the test
funds from both wallets so both finish at their original balances.
