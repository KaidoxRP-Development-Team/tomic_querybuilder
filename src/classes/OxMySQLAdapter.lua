---@class OxMySQLAdapter
local OxMySQLAdapter = lib.class('OxMySQLAdapter')

---@param sql string
---@param params table
---@return table
function OxMySQLAdapter:query(sql, params)
    return MySQL.query.await(sql, params)
end

---@param sql string
---@param params table
---@return table|nil
function OxMySQLAdapter:single(sql, params)
    return MySQL.single.await(sql, params)
end

---@param sql string
---@param params table
---@return any
function OxMySQLAdapter:scalar(sql, params)
    return MySQL.scalar.await(sql, params)
end

---@param sql string
---@param params table
---@return number
function OxMySQLAdapter:insert(sql, params)
    return MySQL.insert.await(sql, params)
end

---@param sql string
---@param params table
---@return number
function OxMySQLAdapter:update(sql, params)
    return MySQL.update.await(sql, params)
end

return OxMySQLAdapter
