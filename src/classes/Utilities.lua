---@class Utilities
local Utilities = lib.class('Utilities')

local CURRENT_RESOURCE_NAME <const> = GetCurrentResourceName()
local CURRENT_ENVIRONMENT <const> = GetResourceMetadata(CURRENT_RESOURCE_NAME, 'environment', 0)
local PRODUCTION <const> = 'production'

---@type string
Utilities.CURRENT_RESOURCE_NAME = CURRENT_RESOURCE_NAME

---Check if the current environment is production
---@return boolean
function Utilities.isProduction()
    return CURRENT_ENVIRONMENT == PRODUCTION
end

---Map function for tables
---@param tbl table The table to map over
---@param fn function The function to apply to each element
---@return table
function Utilities.map(tbl, fn)
    local mapped = {}
    for i, v in ipairs(tbl) do
        mapped[i] = fn(v)
    end
    return mapped
end

---Helper function to ensure proper backtick escaping for identifiers
---@param identifier string
---@return string
function Utilities.ensureBackticks(identifier)
    if Utilities.isEmpty(identifier) then
        error(('[%s]: Empty identifier provided.'):format(Utilities.CURRENT_RESOURCE_NAME))
    end

    -- Allow "*" and "table.*" patterns.
    if identifier == '*' then
        return '*'
    end

    local parts = {}

    for part in tostring(identifier):gmatch('[^%.]+') do
        if part == '*' then
            parts[#parts + 1] = '*'
        else
            -- Strip surrounding backticks if developer provided them.
            local inner = part:match('^`(.+)`$') or part

            -- STRICT identifier validation:
            -- - blocks spaces, punctuation, SQL comment tokens, etc.
            -- - forces predictable quoting output
            if not inner:match('^[A-Za-z_][A-Za-z0-9_]*$') then
                error(('[%s]: Unsafe identifier: %s'):format(Utilities.CURRENT_RESOURCE_NAME, tostring(identifier)))
            end

            parts[#parts + 1] = '`' .. inner .. '`'
        end
    end

    -- Disallow "*" in the middle (e.g. "*.id")
    for i = 1, (#parts - 1) do
        if parts[i] == '*' then
            error(('[%s]: Invalid identifier: %s'):format(Utilities.CURRENT_RESOURCE_NAME, tostring(identifier)))
        end
    end

    return table.concat(parts, '.')
end

function Utilities.getSorted(tbl)
    local sortedKeys = {}

    for k in pairs(tbl) do
        table.insert(sortedKeys, k)
    end

    table.sort(sortedKeys)

    return sortedKeys
end

function Utilities.isEmpty(value)
    local trimmedValue = (value or ''):match('^%s*(.-)%s*$')
    return trimmedValue == nil or trimmedValue == ''
end

return Utilities
