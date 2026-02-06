---@class Input
local Input = require 'src.classes.Input'

---@class Utilities
local Utilities = require 'src.classes.Utilities'

---@class QueryCompilerMySQL
local QueryCompilerMySQL = require 'src.classes.QueryCompilerMySQL'

---@class OxMySQLAdapter
local OxMySQLAdapter = require 'src.classes.OxMySQLAdapter'

---@class QueryBuilderSelect
---@field _raw? boolean
---@field expr? string
---@field col? string

---@class QueryBuilderWhere
---@field _raw? string
---@field params? table
---@field _type? 'in'|'null'|'group'
---@field column? string
---@field operator? string
---@field value? any
---@field values? table
---@field notIn? boolean
---@field notNull? boolean
---@field boolean 'AND'|'OR'
---@field group? QueryBuilder

---@class QueryBuilder
---@field selects QueryBuilderSelect[]
---@field from { name: string, alias: string|nil }
---@field wheres QueryBuilderWhere[]
---@field groupBys string[]
---@field orderBys { column: string, direction: 'ASC'|'DESC' }[]
---@field _limit number|nil
---@field _offset number|nil
---@field _allowNoWhere boolean
---@field _compiler QueryCompilerMySQL
---@field _adapter OxMySQLAdapter
local QueryBuilder = lib.class('QueryBuilder')

local VALID_OPERATORS <const> = {
    ['='] = true,
    ['!='] = true,
    ['<>'] = true,
    ['>'] = true,
    ['>='] = true,
    ['<'] = true,
    ['<='] = true,
    ['LIKE'] = true,
    ['NOT LIKE'] = true,
}

local DEFAULT_COMPILER = QueryCompilerMySQL:constructor()
local DEFAULT_ADAPTER = OxMySQLAdapter:constructor()
local DEFAULT_CONFIG = { logQueries = false }

---@param op any
---@return string
local function normalizeOperator(op)
    if type(op) ~= 'string' then
        error(('[%s]: Invalid operator type.'):format(Utilities.CURRENT_RESOURCE_NAME))
    end

    local upper = op:upper()
    if not VALID_OPERATORS[upper] then
        error(('[%s]: Invalid operator: %s'):format(Utilities.CURRENT_RESOURCE_NAME, tostring(op)))
    end

    return upper
end

---Creates a new QueryBuilder instance
---@param tableName string
---@param alias? string
---@param compiler? QueryCompilerMySQL
---@param adapter? OxMySQLAdapter
---@return QueryBuilder
function QueryBuilder:constructor(tableName, alias, compiler, adapter)
    if Utilities.isEmpty(tableName) then
        error(('[%s]: Table name must be provided.'):format(Utilities.CURRENT_RESOURCE_NAME))
    end

    self.selects = {}
    self.from = { name = tableName, alias = alias }
    self.wheres = {}
    self.groupBys = {}
    self.orderBys = {}
    self._limit = nil
    self._offset = nil
    self._allowNoWhere = false
    self._compiler = compiler or DEFAULT_COMPILER
    self._adapter = adapter or DEFAULT_ADAPTER
    self._config = DEFAULT_CONFIG

    return self
end

---Enable/disable query logging globally for all QueryBuilder instances.
---@param enabled boolean
---@return QueryBuilder
function QueryBuilder:setLoggingEnabled(enabled)
    DEFAULT_CONFIG.logQueries = enabled == true
    return self
end

local function encodeBindings(bindings)
    if not json or type(json.encode) ~= 'function' then
        return tostring(bindings)
    end

    return json.encode(bindings)
end

---@return string, table
function QueryBuilder:_compileDebugQuery()
    return self:buildQuery(false)
end

function QueryBuilder:allowAll() self._allowNoWhere = true return self end

function QueryBuilder:selectRaw(expression)
    self.selects[#self.selects + 1] = { _raw = true, expr = expression }
    return self
end

function QueryBuilder:select(...)
    self.selects = {}
    for _, col in ipairs({ ... }) do
        self.selects[#self.selects + 1] = { col = col }
    end
    return self
end

function QueryBuilder:selectAs(column, alias)
    self.selects[#self.selects + 1] = {
        _raw = true,
        expr = ('%s AS %s'):format(Utilities.ensureBackticks(column), Utilities.ensureBackticks(alias))
    }
    return self
end

function QueryBuilder:whereRaw(expression, ...)
    self.wheres[#self.wheres + 1] = { _raw = expression, params = Input:sanitizeTable({ ... }), boolean = 'AND' }
    return self
end

function QueryBuilder:orWhereRaw(expression, ...)
    self.wheres[#self.wheres + 1] = { _raw = expression, params = Input:sanitizeTable({ ... }), boolean = 'OR' }
    return self
end

function QueryBuilder:where(column, operator, value)
    if value == nil then value = operator operator = '=' end

    if type(value) == 'table' then
        local opUpper = tostring(operator):upper()
        if opUpper == 'IN' then
            return self:whereIn(column, value)
        elseif opUpper == 'NOT IN' then
            return self:whereNotIn(column, value)
        end

        error(('[%s]: Table values require whereIn/whereNotIn/whereRaw.'):format(Utilities.CURRENT_RESOURCE_NAME))
    end

    self.wheres[#self.wheres + 1] = {
        column = column,
        operator = normalizeOperator(operator),
        value = Input:sanitize(value),
        boolean = 'AND'
    }

    return self
end

function QueryBuilder:orWhere(column, operator, value)
    if value == nil then value = operator operator = '=' end

    if type(value) == 'table' then
        local opUpper = tostring(operator):upper()
        if opUpper == 'IN' then
            return self:orWhereIn(column, value)
        elseif opUpper == 'NOT IN' then
            return self:orWhereNotIn(column, value)
        end

        error(('[%s]: Table values require whereIn/whereNotIn/whereRaw.'):format(Utilities.CURRENT_RESOURCE_NAME))
    end

    self.wheres[#self.wheres + 1] = {
        column = column,
        operator = normalizeOperator(operator),
        value = Input:sanitize(value),
        boolean = 'OR'
    }

    return self
end

function QueryBuilder:whereIn(column, values)
    self.wheres[#self.wheres + 1] = { _type = 'in', column = column, values = Input:sanitizeTable(values), notIn = false, boolean = 'AND' }
    return self
end

function QueryBuilder:orWhereIn(column, values)
    self.wheres[#self.wheres + 1] = { _type = 'in', column = column, values = Input:sanitizeTable(values), notIn = false, boolean = 'OR' }
    return self
end

function QueryBuilder:whereNotIn(column, values)
    self.wheres[#self.wheres + 1] = { _type = 'in', column = column, values = Input:sanitizeTable(values), notIn = true, boolean = 'AND' }
    return self
end

function QueryBuilder:orWhereNotIn(column, values)
    self.wheres[#self.wheres + 1] = { _type = 'in', column = column, values = Input:sanitizeTable(values), notIn = true, boolean = 'OR' }
    return self
end

function QueryBuilder:whereGroup(cb)
    local nested = QueryBuilder:constructor(self.from.name, self.from.alias, self._compiler, self._adapter)
    cb(nested)
    self.wheres[#self.wheres + 1] = { _type = 'group', group = nested, boolean = 'AND' }
    return self
end

function QueryBuilder:orWhereGroup(cb)
    local nested = QueryBuilder:constructor(self.from.name, self.from.alias, self._compiler, self._adapter)
    cb(nested)
    self.wheres[#self.wheres + 1] = { _type = 'group', group = nested, boolean = 'OR' }
    return self
end

function QueryBuilder:whereNull(column)
    self.wheres[#self.wheres + 1] = { _type = 'null', column = column, notNull = false, boolean = 'AND' }
    return self
end

function QueryBuilder:orWhereNull(column)
    self.wheres[#self.wheres + 1] = { _type = 'null', column = column, notNull = false, boolean = 'OR' }
    return self
end

function QueryBuilder:whereNotNull(column)
    self.wheres[#self.wheres + 1] = { _type = 'null', column = column, notNull = true, boolean = 'AND' }
    return self
end

function QueryBuilder:orWhereNotNull(column)
    self.wheres[#self.wheres + 1] = { _type = 'null', column = column, notNull = true, boolean = 'OR' }
    return self
end

function QueryBuilder:groupBy(column) self.groupBys[#self.groupBys + 1] = column return self end

function QueryBuilder:orderBy(column, direction)
    local dir = tostring(direction or 'ASC'):upper()
    if dir ~= 'ASC' and dir ~= 'DESC' then
        error(('[%s]: Invalid direction provided.'):format(Utilities.CURRENT_RESOURCE_NAME))
    end

    self.orderBys[#self.orderBys + 1] = { column = column, direction = dir }
    return self
end

function QueryBuilder:limit(limit)
    local n = tonumber(limit)
    if not n or n < 0 then
        error(('[%s]: Invalid LIMIT.'):format(Utilities.CURRENT_RESOURCE_NAME))
    end

    self._limit = math.floor(n)
    return self
end

function QueryBuilder:offset(offset)
    local n = tonumber(offset)
    if not n or n < 0 then
        error(('[%s]: Invalid OFFSET.'):format(Utilities.CURRENT_RESOURCE_NAME))
    end

    self._offset = math.floor(n)
    return self
end

function QueryBuilder:buildQuery(isCount)
    if isCount then return self:buildCountQuery() end
    return self:buildSelectQuery(false)
end

---Get only the compiled SQL string for the current SELECT query AST.
---@return string
function QueryBuilder:toSql()
    local query = self:_compileDebugQuery()
    return query
end

---Get only the compiled bindings array for the current SELECT query AST.
---@return table
function QueryBuilder:getBindings()
    local _, params = self:_compileDebugQuery()
    return params
end

---Print SQL + bindings for the current SELECT query AST.
---@return QueryBuilder
function QueryBuilder:dump()
    local query, params = self:_compileDebugQuery()
    print(('[%s]: SQL: %s | bindings: %s'):format(Utilities.CURRENT_RESOURCE_NAME, query, encodeBindings(params)))
    return self
end

function QueryBuilder:get()
    local query, params = self:buildQuery(false)
    if self._config.logQueries then
        print(('[%s]: SQL: %s | bindings: %s'):format(Utilities.CURRENT_RESOURCE_NAME, query, encodeBindings(params)))
    end
    return self._adapter:query(query, params)
end

function QueryBuilder:first()
    local prev = self._limit
    self._limit = 1
    local query, params = self:buildQuery(false)
    self._limit = prev
    if self._config.logQueries then
        print(('[%s]: SQL: %s | bindings: %s'):format(Utilities.CURRENT_RESOURCE_NAME, query, encodeBindings(params)))
    end
    return self._adapter:single(query, params)
end

function QueryBuilder:value(column)
    local prevSelects = self.selects
    self.selects = { { col = column } }
    local prev = self._limit
    self._limit = 1
    local query, params = self:buildQuery(false)
    self._limit = prev
    self.selects = prevSelects
    if self._config.logQueries then
        print(('[%s]: SQL: %s | bindings: %s'):format(Utilities.CURRENT_RESOURCE_NAME, query, encodeBindings(params)))
    end
    return self._adapter:scalar(query, params)
end

function QueryBuilder:count()
    local query, params = self:buildCountQuery()
    if self._config.logQueries then
        print(('[%s]: SQL: %s | bindings: %s'):format(Utilities.CURRENT_RESOURCE_NAME, query, encodeBindings(params)))
    end
    return self._adapter:scalar(query, params)
end

function QueryBuilder:paginate(perPage, page)
    local p = math.max(1, math.floor(tonumber(perPage) or 10))
    local cur = math.max(1, math.floor(tonumber(page) or 1))

    local total = self:count()
    local results = self:limit(p):offset((cur - 1) * p):get()

    return { data = results, totalCount = total, perPage = p, currentPage = cur, lastPage = math.max(1, math.ceil(total / p)) }
end

function QueryBuilder:insert(data)
    local query, params = self:buildInsertQuery(data)
    if self._config.logQueries then
        print(('[%s]: SQL: %s | bindings: %s'):format(Utilities.CURRENT_RESOURCE_NAME, query, encodeBindings(params)))
    end
    return self._adapter:insert(query, params)
end

function QueryBuilder:update(data)
    local query, params = self:buildUpdateQuery(data)
    if self._config.logQueries then
        print(('[%s]: SQL: %s | bindings: %s'):format(Utilities.CURRENT_RESOURCE_NAME, query, encodeBindings(params)))
    end
    return self._adapter:update(query, params)
end

function QueryBuilder:delete()
    local query, params = self:buildDeleteQuery()
    if self._config.logQueries then
        print(('[%s]: SQL: %s | bindings: %s'):format(Utilities.CURRENT_RESOURCE_NAME, query, encodeBindings(params)))
    end
    return self._adapter:update(query, params)
end

function QueryBuilder:buildSelectQuery(_ignored) return self._compiler:compileSelect(self) end
function QueryBuilder:buildCountQuery() return self._compiler:compileCount(self) end
function QueryBuilder:buildWhereClause(params) return self._compiler:compileWhereClause(self.wheres, params) end
function QueryBuilder:buildInsertQuery(data) return self._compiler:compileInsert(self, data) end
function QueryBuilder:buildUpdateQuery(data) return self._compiler:compileUpdate(self, data) end
function QueryBuilder:buildDeleteQuery() return self._compiler:compileDelete(self) end

return QueryBuilder
