package.path = './?.lua;./?/init.lua;' .. package.path

_G.GetCurrentResourceName = function() return 'tomic_querybuilder' end
_G.GetResourceMetadata = function() return 'test' end
_G.CreateThread = function(fn) fn() end
_G.json = {
    encode = function(tbl)
        local parts = {}
        for k, v in pairs(tbl) do
            parts[#parts + 1] = ('"%s":"%s"'):format(tostring(k), tostring(v))
        end
        table.sort(parts)
        return '{' .. table.concat(parts, ',') .. '}'
    end
}

local function makeClass()
    return function(_name)
        local cls = {}
        cls.__index = cls
        function cls:constructor(...) return self end
        setmetatable(cls, {
            __call = function(_, ...)
                local obj = setmetatable({}, cls)
                if obj.constructor then obj:constructor(...) end
                return obj
            end
        })
        return cls
    end
end

_G.lib = { class = makeClass() }

local recorded = { query = {}, single = {}, scalar = {}, insert = {}, update = {} }
local function recordCall(bucket, sql, params)
    recorded[bucket][#recorded[bucket] + 1] = { sql = sql, params = params }
end

_G.MySQL = {
    query = { await = function(sql, params) recordCall('query', sql, params) return {} end },
    single = { await = function(sql, params) recordCall('single', sql, params) return nil end },
    scalar = { await = function(sql, params) recordCall('scalar', sql, params) return 0 end },
    insert = { await = function(sql, params) recordCall('insert', sql, params) return 1 end },
    update = { await = function(sql, params) recordCall('update', sql, params) return 1 end },
}

local logs = {}
local originalPrint = _G.print
_G.print = function(...)
    local parts = {}
    for i = 1, select('#', ...) do
        parts[#parts + 1] = tostring(select(i, ...))
    end
    logs[#logs + 1] = table.concat(parts, ' ')
end

local DB = require 'src.classes.DB'

local failures = 0
local function assertEq(actual, expected, label)
    if actual ~= expected then
        failures = failures + 1
        originalPrint(('FAIL %s\n  expected: %s\n  actual:   %s'):format(label, tostring(expected), tostring(actual)))
    else
        originalPrint('PASS ' .. label)
    end
end

local function assertTableEq(actual, expected, label)
    if #actual ~= #expected then
        failures = failures + 1
        originalPrint(('FAIL %s\n  expected len: %d\n  actual len:   %d'):format(label, #expected, #actual))
        return
    end

    for i = 1, #expected do
        if actual[i] ~= expected[i] then
            failures = failures + 1
            originalPrint(('FAIL %s index %d\n  expected: %s\n  actual:   %s'):format(label, i, tostring(expected[i]), tostring(actual[i])))
            return
        end
    end

    originalPrint('PASS ' .. label)
end

local function assertContains(haystack, needle, label)
    if not tostring(haystack):find(needle, 1, true) then
        failures = failures + 1
        originalPrint(('FAIL %s\n  expected to contain: %s\n  actual: %s'):format(label, needle, tostring(haystack)))
    else
        originalPrint('PASS ' .. label)
    end
end

-- select + where + dotted identifiers
local q1, p1 = DB:table('users', 'u')
    :select('u.id', 'u.username')
    :where('u.status', 'active')
    :orWhere('u.age', '>', 18)
    :buildQuery()
assertEq(q1, 'SELECT `u`.`id`, `u`.`username` FROM `users` AS `u` WHERE `u`.`status` = ? OR `u`.`age` > ?', 'compile select+where')
assertTableEq(p1, { 'active', 18 }, 'compile select+where bindings')


-- join with where
local qJoin1, pJoin1 = DB:table('users', 'u')
    :join('characters', 'characters.identifier', '=', 'u.identifier')
    :where('u.group', 'admin')
    :buildQuery()
assertEq(qJoin1, 'SELECT * FROM `users` AS `u` INNER JOIN `characters` ON `characters`.`identifier` = `u`.`identifier` WHERE `u`.`group` = ?', 'compile join with where')
assertTableEq(pJoin1, { 'admin' }, 'compile join with where bindings')

-- join with multiple ON conditions and ON bindings
local qJoin2, pJoin2 = DB:table('users', 'u')
    :leftJoin('characters', function(j)
        j:on('characters.identifier', '=', 'u.identifier')
         :onRaw('characters.slot = ?', 2)
         :orOnRaw('characters.owner = ?', 'char1:abc')
    end)
    :where('u.active', 1)
    :buildQuery()
assertEq(qJoin2, 'SELECT * FROM `users` AS `u` LEFT JOIN `characters` ON `characters`.`identifier` = `u`.`identifier` AND characters.slot = ? OR characters.owner = ? WHERE `u`.`active` = ?', 'compile join with multiple on conditions')
assertTableEq(pJoin2, { 2, 'char1:abc', 1 }, 'compile join with multiple on conditions bindings')

-- toSql/getBindings helpers
local qb2 = DB:table('users'):where('id', 9)
assertEq(qb2:toSql(), 'SELECT * FROM `users` WHERE `id` = ?', 'toSql returns compiled sql')
assertTableEq(qb2:getBindings(), { 9 }, 'getBindings returns compiled params')

-- dump helper
logs = {}
qb2:dump()
assertEq(#logs, 1, 'dump emits one log line')
assertContains(logs[1], 'SQL: SELECT * FROM `users` WHERE `id` = ?', 'dump includes sql')
assertContains(logs[1], 'bindings:', 'dump includes bindings')

-- default logging disabled
logs = {}
DB:table('users'):where('id', 1):get()
assertEq(#logs, 0, 'query logging disabled by default')

-- logging enabled flag
logs = {}
DB:table('users'):setLoggingEnabled(true)
DB:table('users'):where('id', 2):get()
assertEq(#logs, 1, 'query logging enabled emits line')
assertContains(logs[1], 'SQL: SELECT * FROM `users` WHERE `id` = ?', 'enabled logging contains sql')
DB:table('users'):setLoggingEnabled(false)

-- update
local q3, p3 = DB:table('users')
    :where('identifier', 'char1:1')
    :buildUpdateQuery({ group = 'admin', firstname = 'Tom' })
assertEq(q3, 'UPDATE `users` SET `firstname` = ?, `group` = ? WHERE `identifier` = ?', 'compile update')
assertTableEq(p3, { 'Tom', 'admin', 'char1:1' }, 'compile update bindings')

-- delete
local q4, p4 = DB:table('users'):where('id', 7):buildDeleteQuery()
assertEq(q4, 'DELETE FROM `users` WHERE `id` = ?', 'compile delete')
assertTableEq(p4, { 7 }, 'compile delete bindings')

-- strict identifier validation (complex expression should fail in non-raw)
local ok = pcall(function()
    DB:table('users'):select('COUNT(*)'):buildQuery()
end)
assertEq(ok, false, 'complex expression requires raw method')

_G.print = originalPrint

if failures > 0 then
    print(('\n%d test(s) failed'):format(failures))
    os.exit(1)
end

print('\nAll compiler tests passed')
