---@class QueryBuilder
local QueryBuilder = require 'src.classes.QueryBuilder'

---@class DB
DB = lib.class('DB')

---Create a new QueryBuilder instance
---@param name string
---@param alias? string
---@return QueryBuilder
function DB:table(name, alias)
    return QueryBuilder:constructor(name, alias)
end

return DB
