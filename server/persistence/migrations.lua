EconomyMigrationRunner = {}

local logger = EconomyLogging.Create('migrations')

local function Hash(value)
    local hash = 2166136261
    for index = 1, #value do hash = ((hash ~ value:byte(index)) * 16777619) & 0xffffffff end
    return ('fnv1a32:%08x'):format(hash)
end

local function EnsureLedger()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `economy_schema_migrations` (
          `id` VARCHAR(100) NOT NULL,
          `checksum` VARCHAR(64) NOT NULL,
          `applied_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
          PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])
end

function EconomyMigrationRunner.Run()
    local executed, result = xpcall(function()
        EnsureLedger()
        local rows = MySQL.query.await(
            'SELECT `id`, `checksum` FROM `economy_schema_migrations`') or {}
        local applied = {}
        for _, row in ipairs(rows) do applied[row.id] = row.checksum end

        local definitions = EconomyMigrationDefinitions or {}
        table.sort(definitions, function(left, right) return left.id < right.id end)
        local seen, appliedCount = {}, 0
        for _, migration in ipairs(definitions) do
            if type(migration.id) ~= 'string' or migration.id == ''
                or type(migration.statements) ~= 'table' or #migration.statements == 0
                or seen[migration.id] then
                return EconomyResults.Err('invalid_migration',
                    'An Economy migration definition is invalid.')
            end
            seen[migration.id] = true
            local checksum = Hash(table.concat(migration.statements,
                '\n-- next statement --\n'))
            if applied[migration.id] and applied[migration.id] ~= checksum then
                return EconomyResults.Err('migration_checksum_mismatch',
                    'An applied Economy migration has changed.', {
                        migrationId = migration.id
                    })
            end
            if not applied[migration.id] then
                logger.Info('migration.applying', { migrationId = migration.id })
                for _, statement in ipairs(migration.statements) do
                    MySQL.query.await(statement)
                end
                MySQL.insert.await([[
                    INSERT INTO `economy_schema_migrations` (`id`,`checksum`) VALUES (?,?)
                ]], { migration.id, checksum })
                appliedCount = appliedCount + 1
            end
        end
        return EconomyResults.Ok({ total = #definitions, applied = appliedCount })
    end, debug.traceback)

    if not executed then
        logger.Error('migration.failed', { reason = tostring(result) })
        return EconomyResults.Err('migration_failed',
            'An Economy database migration failed.', { reason = tostring(result) })
    end
    return result
end
