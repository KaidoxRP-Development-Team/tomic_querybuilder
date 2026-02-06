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
    return function(name)
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

local DB = require 'src.classes.DB'

local failures = 0
local function assertEq(actual, expected, label)
    if actual ~= expected then
        failures = failures + 1
        print(('FAIL %s\n  expected: %s\n  actual:   %s'):format(label, tostring(expected), tostring(actual)))
    else
        print('PASS ' .. label)
    end
end

local function assertTableEq(actual, expected, label)
    if #actual ~= #expected then
        failures = failures + 1
        print(('FAIL %s\n  expected len: %d\n  actual len:   %d'):format(label, #expected, #actual))
        return
    end

    for i = 1, #expected do
        if actual[i] ~= expected[i] then
            failures = failures + 1
            print(('FAIL %s index %d\n  expected: %s\n  actual:   %s'):format(label, i, tostring(expected[i]), tostring(actual[i])))
            return
        end
    end

    print('PASS ' .. label)
end

-- select + where + dotted identifiers
local q1, p1 = DB:table('users', 'u')
    :select('u.id', 'u.username')
    :where('u.status', 'active')
    :orWhere('u.age', '>', 18)
    :buildQuery()
assertEq(q1, 'SELECT `u`.`id`, `u`.`username` FROM `users` AS `u` WHERE `u`.`status` = ? OR `u`.`age` > ?', 'compile select+where')
assertTableEq(p1, { 'active', 18 }, 'compile select+where bindings')

-- update
local q2, p2 = DB:table('users')
    :where('identifier', 'char1:1')
    :buildUpdateQuery({ group = 'admin', firstname = 'Tom' })
assertEq(q2, 'UPDATE `users` SET `firstname` = ?, `group` = ? WHERE `identifier` = ?', 'compile update')
assertTableEq(p2, { 'Tom', 'admin', 'char1:1' }, 'compile update bindings')

-- delete
local q3, p3 = DB:table('users'):where('id', 7):buildDeleteQuery()
assertEq(q3, 'DELETE FROM `users` WHERE `id` = ?', 'compile delete')
assertTableEq(p3, { 7 }, 'compile delete bindings')

-- strict identifier validation (complex expression should fail in non-raw)
local ok = pcall(function()
    DB:table('users'):select('COUNT(*)'):buildQuery()
end)
assertEq(ok, false, 'complex expression requires raw method')

if failures > 0 then
    print(('\n%d test(s) failed'):format(failures))
    os.exit(1)
end

print('\nAll compiler tests passed')
