---@class Input
local Input = require 'src.classes.Input'

---@class Utilities
local Utilities = require 'src.classes.Utilities'

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

---Creates a new QueryBuilder instance
---@param tableName string
---@param alias? string
---@return QueryBuilder
function QueryBuilder:constructor(tableName, alias)
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

    return self
end

---Allow UPDATE/DELETE without a WHERE clause (unsafe)
---@return QueryBuilder
function QueryBuilder:allowAll()
    self._allowNoWhere = true
    return self
end

---Add a raw select expression (e.g. "COUNT(*) AS total")
---@param expression string
---@return QueryBuilder
function QueryBuilder:selectRaw(expression)
    self.selects[#self.selects + 1] = { _raw = true, expr = expression }
    return self
end

---Select specific columns
---@param ... string
---@return QueryBuilder
function QueryBuilder:select(...)
    self.selects = {}
    for _, col in ipairs({ ... }) do
        self.selects[#self.selects + 1] = { col = col }
    end
    return self
end

---Select a column with alias (safe identifier alias)
---@param column string
---@param alias string
---@return QueryBuilder
function QueryBuilder:selectAs(column, alias)
    self.selects[#self.selects + 1] = {
        _raw = true,
        expr = ('%s AS %s'):format(Utilities.ensureBackticks(column), Utilities.ensureBackticks(alias))
    }
    return self
end

---Add a raw where clause
---@param expression string
---@param ... any
---@return QueryBuilder
function QueryBuilder:whereRaw(expression, ...)
    self.wheres[#self.wheres + 1] = {
        _raw = expression,
        params = Input:sanitizeTable({ ... }),
        boolean = 'AND'
    }
    return self
end

---Add an OR raw where clause
---@param expression string
---@param ... any
---@return QueryBuilder
function QueryBuilder:orWhereRaw(expression, ...)
    self.wheres[#self.wheres + 1] = {
        _raw = expression,
        params = Input:sanitizeTable({ ... }),
        boolean = 'OR'
    }
    return self
end

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

---Add a where clause
---@param column string
---@param operator string|any
---@param value any|nil
---@return QueryBuilder
function QueryBuilder:where(column, operator, value)
    if value == nil then
        value = operator
        operator = '='
    end

    -- Route table values to IN/NOT IN helpers when appropriate.
    if type(value) == 'table' then
        local opUpper = tostring(operator):upper()
        if opUpper == 'IN' then
            return self:whereIn(column, value)
        elseif opUpper == 'NOT IN' then
            return self:whereNotIn(column, value)
        else
            error(('[%s]: Table values require whereIn/whereNotIn/whereRaw.'):format(Utilities.CURRENT_RESOURCE_NAME))
        end
    end

    self.wheres[#self.wheres + 1] = {
        column = column,
        operator = normalizeOperator(operator),
        value = Input:sanitize(value),
        boolean = 'AND'
    }

    return self
end

---Add an OR where clause
---@param column string
---@param operator string|any
---@param value any|nil
---@return QueryBuilder
function QueryBuilder:orWhere(column, operator, value)
    if value == nil then
        value = operator
        operator = '='
    end

    if type(value) == 'table' then
        local opUpper = tostring(operator):upper()
        if opUpper == 'IN' then
            return self:orWhereIn(column, value)
        elseif opUpper == 'NOT IN' then
            return self:orWhereNotIn(column, value)
        else
            error(('[%s]: Table values require whereIn/whereNotIn/whereRaw.'):format(Utilities.CURRENT_RESOURCE_NAME))
        end
    end

    self.wheres[#self.wheres + 1] = {
        column = column,
        operator = normalizeOperator(operator),
        value = Input:sanitize(value),
        boolean = 'OR'
    }

    return self
end

---Add a WHERE IN clause
---@param column string
---@param values table
---@return QueryBuilder
function QueryBuilder:whereIn(column, values)
    self.wheres[#self.wheres + 1] = {
        _type = 'in',
        column = column,
        values = Input:sanitizeTable(values),
        notIn = false,
        boolean = 'AND'
    }

    return self
end

---Add an OR WHERE IN clause
---@param column string
---@param values table
---@return QueryBuilder
function QueryBuilder:orWhereIn(column, values)
    self.wheres[#self.wheres + 1] = {
        _type = 'in',
        column = column,
        values = Input:sanitizeTable(values),
        notIn = false,
        boolean = 'OR'
    }

    return self
end

---Add a WHERE NOT IN clause
---@param column string
---@param values table
---@return QueryBuilder
function QueryBuilder:whereNotIn(column, values)
    self.wheres[#self.wheres + 1] = {
        _type = 'in',
        column = column,
        values = Input:sanitizeTable(values),
        notIn = true,
        boolean = 'AND'
    }

    return self
end

---Add an OR WHERE NOT IN clause
---@param column string
---@param values table
---@return QueryBuilder
function QueryBuilder:orWhereNotIn(column, values)
    self.wheres[#self.wheres + 1] = {
        _type = 'in',
        column = column,
        values = Input:sanitizeTable(values),
        notIn = true,
        boolean = 'OR'
    }

    return self
end

---Add a grouped where clause: ( ... )
---@param cb fun(q: QueryBuilder)
---@return QueryBuilder
function QueryBuilder:whereGroup(cb)
    local nested = QueryBuilder:constructor(self.from.name, self.from.alias)
    cb(nested)
    self.wheres[#self.wheres + 1] = { _type = 'group', group = nested, boolean = 'AND' }
    return self
end

---Add an OR grouped where clause: OR ( ... )
---@param cb fun(q: QueryBuilder)
---@return QueryBuilder
function QueryBuilder:orWhereGroup(cb)
    local nested = QueryBuilder:constructor(self.from.name, self.from.alias)
    cb(nested)
    self.wheres[#self.wheres + 1] = { _type = 'group', group = nested, boolean = 'OR' }
    return self
end

---Add a WHERE column IS NULL
---@param column string
---@return QueryBuilder
function QueryBuilder:whereNull(column)
    self.wheres[#self.wheres + 1] = { _type = 'null', column = column, notNull = false, boolean = 'AND' }
    return self
end

---Add an OR WHERE column IS NULL
---@param column string
---@return QueryBuilder
function QueryBuilder:orWhereNull(column)
    self.wheres[#self.wheres + 1] = { _type = 'null', column = column, notNull = false, boolean = 'OR' }
    return self
end

---Add a WHERE column IS NOT NULL
---@param column string
---@return QueryBuilder
function QueryBuilder:whereNotNull(column)
    self.wheres[#self.wheres + 1] = { _type = 'null', column = column, notNull = true, boolean = 'AND' }
    return self
end

---Add an OR WHERE column IS NOT NULL
---@param column string
---@return QueryBuilder
function QueryBuilder:orWhereNotNull(column)
    self.wheres[#self.wheres + 1] = { _type = 'null', column = column, notNull = true, boolean = 'OR' }
    return self
end

---Add a GROUP BY clause
---@param column string
---@return QueryBuilder
function QueryBuilder:groupBy(column)
    self.groupBys[#self.groupBys + 1] = column
    return self
end

---Add an ORDER BY clause
---@param column string
---@param direction? string
---@return QueryBuilder
function QueryBuilder:orderBy(column, direction)
    local dir = tostring(direction or 'ASC'):upper()
    if dir ~= 'ASC' and dir ~= 'DESC' then
        error(('[%s]: Invalid direction provided.'):format(Utilities.CURRENT_RESOURCE_NAME))
    end

    self.orderBys[#self.orderBys + 1] = { column = column, direction = dir }
    return self
end

---Set LIMIT clause
---@param limit number
---@return QueryBuilder
function QueryBuilder:limit(limit)
    local n = tonumber(limit)
    if not n or n < 0 then
        error(('[%s]: Invalid LIMIT.'):format(Utilities.CURRENT_RESOURCE_NAME))
    end

    self._limit = math.floor(n)
    return self
end

---Set OFFSET clause
---@param offset number
---@return QueryBuilder
function QueryBuilder:offset(offset)
    local n = tonumber(offset)
    if not n or n < 0 then
        error(('[%s]: Invalid OFFSET.'):format(Utilities.CURRENT_RESOURCE_NAME))
    end

    self._offset = math.floor(n)
    return self
end

---Build the SQL query (compat: buildQuery(true) => count)
---@param isCount ?boolean
---@return string query, table params
function QueryBuilder:buildQuery(isCount)
    if isCount then
        return self:buildCountQuery()
    end

    return self:buildSelectQuery(false)
end

---Return the SQL string without executing
---@return string, table
function QueryBuilder:toSql()
    return self:buildQuery(false)
end

---Execute the query and get all results
---@return table
function QueryBuilder:get()
    local query, params = self:buildQuery(false)
    return MySQL.query.await(query, params)
end

---Execute and return the first row (or nil)
---@return table|nil
function QueryBuilder:first()
    local prev = self._limit
    self._limit = 1
    local query, params = self:buildQuery(false)
    self._limit = prev
    return MySQL.single.await(query, params)
end

---Return a single scalar value from the first row
---@param column string
---@return any
function QueryBuilder:value(column)
    local prevSelects = self.selects
    self.selects = { { col = column } }
    local prev = self._limit
    self._limit = 1
    local query, params = self:buildQuery(false)
    self._limit = prev
    self.selects = prevSelects
    return MySQL.scalar.await(query, params)
end

---Returns a number of found records
---@return number
function QueryBuilder:count()
    local query, params = self:buildCountQuery()
    return MySQL.scalar.await(query, params)
end

---Execute the query and return paginated results
---@param perPage number
---@param page number
---@return table
function QueryBuilder:paginate(perPage, page)
    local p = math.max(1, math.floor(tonumber(perPage) or 10))
    local cur = math.max(1, math.floor(tonumber(page) or 1))

    local total = self:count()
    local results = self:limit(p):offset((cur - 1) * p):get()

    return {
        data = results,
        totalCount = total,
        perPage = p,
        currentPage = cur,
        lastPage = math.max(1, math.ceil(total / p))
    }
end

---Insert data into the table
---@param data table
---@return number insertId
function QueryBuilder:insert(data)
    local query, params = self:buildInsertQuery(data)
    return MySQL.insert.await(query, params)
end

---Update data in the table
---@param data table
---@return number affectedRows
function QueryBuilder:update(data)
    local query, params = self:buildUpdateQuery(data)
    return MySQL.update.await(query, params)
end

---Delete records from the table
---@return number affectedRows
function QueryBuilder:delete()
    local query, params = self:buildDeleteQuery()
    return MySQL.update.await(query, params)
end

---Build select query
---@param _ignored ?boolean
---@return string query, table params
function QueryBuilder:buildSelectQuery(_ignored)
    local fromSql = Utilities.ensureBackticks(self.from.name)
    if self.from.alias then
        fromSql = fromSql .. ' AS ' .. Utilities.ensureBackticks(self.from.alias)
    end

    local selectSql
    if #self.selects == 0 then
        selectSql = '*'
    else
        local compiled = {}
        for _, s in ipairs(self.selects) do
            if s._raw then
                compiled[#compiled + 1] = s.expr
            else
                compiled[#compiled + 1] = Utilities.ensureBackticks(s.col)
            end
        end
        selectSql = table.concat(compiled, ', ')
    end

    local query = { ('SELECT %s FROM %s'):format(selectSql, fromSql) }
    local params = {}

    if #self.wheres > 0 then
        local whereClause = self:buildWhereClause(params)
        query[#query + 1] = 'WHERE ' .. whereClause
    end

    if #self.groupBys > 0 then
        query[#query + 1] = 'GROUP BY ' .. table.concat(Utilities.map(self.groupBys, Utilities.ensureBackticks), ', ')
    end

    if #self.orderBys > 0 then
        local clauses = {}
        for _, orderBy in ipairs(self.orderBys) do
            clauses[#clauses + 1] = ('%s %s'):format(Utilities.ensureBackticks(orderBy.column), orderBy.direction)
        end
        query[#query + 1] = 'ORDER BY ' .. table.concat(clauses, ', ')
    end

    if self._limit then
        query[#query + 1] = 'LIMIT ' .. self._limit
    end

    if self._offset then
        query[#query + 1] = 'OFFSET ' .. self._offset
    end

    return table.concat(query, ' '), params
end

---Build a COUNT query (handles GROUP BY safely by wrapping)
---@return string, table
function QueryBuilder:buildCountQuery()
    local fromSql = Utilities.ensureBackticks(self.from.name)
    if self.from.alias then
        fromSql = fromSql .. ' AS ' .. Utilities.ensureBackticks(self.from.alias)
    end

    local params = {}

    if #self.groupBys == 0 then
        local q = { ('SELECT COUNT(*) FROM %s'):format(fromSql) }
        if #self.wheres > 0 then
            q[#q + 1] = 'WHERE ' .. self:buildWhereClause(params)
        end
        return table.concat(q, ' '), params
    end

    -- GROUP BY: count rows returned by the grouped query
    local inner = { ('SELECT 1 FROM %s'):format(fromSql) }
    if #self.wheres > 0 then
        inner[#inner + 1] = 'WHERE ' .. self:buildWhereClause(params)
    end
    inner[#inner + 1] = 'GROUP BY ' .. table.concat(Utilities.map(self.groupBys, Utilities.ensureBackticks), ', ')

    local innerSql = table.concat(inner, ' ')
    local outerSql = ('SELECT COUNT(*) FROM (%s) AS %s'):format(innerSql, Utilities.ensureBackticks('qb_count'))
    return outerSql, params
end

---Build where clause (mutates params in-place)
---@param params table
---@return string clause
function QueryBuilder:buildWhereClause(params)
    local parts = {}

    for i, w in ipairs(self.wheres) do
        if i > 1 then
            parts[#parts + 1] = w.boolean or 'AND'
        end

        if w._raw then
            parts[#parts + 1] = w._raw
            if w.params then
                for _, v in ipairs(w.params) do
                    params[#params + 1] = v
                end
            end
        elseif w._type == 'in' then
            if not w.values or #w.values == 0 then
                -- Empty IN list: always false/true depending on NOT IN
                parts[#parts + 1] = w.notIn and '1=1' or '1=0'
            else
                local placeholders = {}
                for _, v in ipairs(w.values) do
                    placeholders[#placeholders + 1] = '?'
                    params[#params + 1] = v
                end
                parts[#parts + 1] = ('%s %sIN (%s)'):format(
                    Utilities.ensureBackticks(w.column),
                    w.notIn and 'NOT ' or '',
                    table.concat(placeholders, ', ')
                )
            end
        elseif w._type == 'null' then
            parts[#parts + 1] = ('%s IS %sNULL'):format(
                Utilities.ensureBackticks(w.column),
                w.notNull and 'NOT ' or ''
            )
        elseif w._type == 'group' then
            local nestedParams = {}
            local nestedClause = w.group:buildWhereClause(nestedParams)
            parts[#parts + 1] = '(' .. nestedClause .. ')'
            for _, v in ipairs(nestedParams) do
                params[#params + 1] = v
            end
        else
            parts[#parts + 1] = ('%s %s ?'):format(
                Utilities.ensureBackticks(w.column),
                w.operator
            )
            params[#params + 1] = w.value
        end
    end

    return table.concat(parts, ' ')
end

---Build insert query
---@param data table
---@return string query, table params
function QueryBuilder:buildInsertQuery(data)
    local columns = {}
    local values = {}
    local params = {}

    for _, column in ipairs(Utilities.getSorted(data)) do
        columns[#columns + 1] = Utilities.ensureBackticks(column)
        values[#values + 1] = '?'
        local v = data[column]
        if type(v) == 'table' then
            params[#params + 1] = json.encode(v)
        else
            params[#params + 1] = Input:sanitize(v)
        end
    end

    return
        ('INSERT INTO %s (%s) VALUES (%s)'):format(
            Utilities.ensureBackticks(self.from.name),
            table.concat(columns, ', '),
            table.concat(values, ', ')
        ),
        params
end

---Build update query
---@param data table
---@return string query, table params
function QueryBuilder:buildUpdateQuery(data)
    if #self.wheres == 0 and not self._allowNoWhere then
        error(('[%s]: Refusing to UPDATE without WHERE. Call :allowAll() to override.'):format(Utilities.CURRENT_RESOURCE_NAME))
    end

    local columns = {}
    local params = {}

    for _, column in ipairs(Utilities.getSorted(data)) do
        columns[#columns + 1] = Utilities.ensureBackticks(column) .. ' = ?'
        local v = data[column]
        if type(v) == 'table' then
            params[#params + 1] = json.encode(v)
        else
            params[#params + 1] = Input:sanitize(v)
        end
    end

    local query = { ('UPDATE %s SET %s'):format(Utilities.ensureBackticks(self.from.name), table.concat(columns, ', ')) }

    if #self.wheres > 0 then
        query[#query + 1] = 'WHERE ' .. self:buildWhereClause(params)
    end

    return table.concat(query, ' '), params
end

---Build delete query
---@return string query, table params
function QueryBuilder:buildDeleteQuery()
    if #self.wheres == 0 and not self._allowNoWhere then
        error(('[%s]: Refusing to DELETE without WHERE. Call :allowAll() to override.'):format(Utilities.CURRENT_RESOURCE_NAME))
    end

    local params = {}
    local query = { ('DELETE FROM %s'):format(Utilities.ensureBackticks(self.from.name)) }

    if #self.wheres > 0 then
        query[#query + 1] = 'WHERE ' .. self:buildWhereClause(params)
    end

    return table.concat(query, ' '), params
end

return QueryBuilder
