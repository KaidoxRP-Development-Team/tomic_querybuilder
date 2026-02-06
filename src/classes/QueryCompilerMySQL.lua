---@class Input
local Input = require 'src.classes.Input'

---@class Utilities
local Utilities = require 'src.classes.Utilities'

---@class QueryCompilerMySQL
local QueryCompilerMySQL = lib.class('QueryCompilerMySQL')

---@param from { name: string, alias: string|nil }
---@return string
local function compileFrom(from)
    local fromSql = Utilities.ensureBackticks(from.name)
    if from.alias then
        fromSql = fromSql .. ' AS ' .. Utilities.ensureBackticks(from.alias)
    end

    return fromSql
end

---@param selects table
---@return string
function QueryCompilerMySQL:compileSelectList(selects)
    if #selects == 0 then
        return '*'
    end

    local compiled = {}

    for _, s in ipairs(selects) do
        if s._raw then
            compiled[#compiled + 1] = s.expr
        else
            compiled[#compiled + 1] = Utilities.ensureBackticks(s.col)
        end
    end

    return table.concat(compiled, ', ')
end

---@param wheres table
---@param params table
---@return string
function QueryCompilerMySQL:compileWhereClause(wheres, params)
    local parts = {}

    for i, w in ipairs(wheres) do
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
            local nestedClause = self:compileWhereClause(w.group.wheres, nestedParams)
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

---@param state QueryBuilder
---@return string, table
function QueryCompilerMySQL:compileSelect(state)
    local query = {
        ('SELECT %s FROM %s'):format(self:compileSelectList(state.selects), compileFrom(state.from))
    }
    local params = {}

    if #state.wheres > 0 then
        query[#query + 1] = 'WHERE ' .. self:compileWhereClause(state.wheres, params)
    end

    if #state.groupBys > 0 then
        query[#query + 1] = 'GROUP BY ' .. table.concat(Utilities.map(state.groupBys, Utilities.ensureBackticks), ', ')
    end

    if #state.orderBys > 0 then
        local clauses = {}
        for _, orderBy in ipairs(state.orderBys) do
            clauses[#clauses + 1] = ('%s %s'):format(Utilities.ensureBackticks(orderBy.column), orderBy.direction)
        end
        query[#query + 1] = 'ORDER BY ' .. table.concat(clauses, ', ')
    end

    if state._limit then
        query[#query + 1] = 'LIMIT ' .. state._limit
    end

    if state._offset then
        query[#query + 1] = 'OFFSET ' .. state._offset
    end

    return table.concat(query, ' '), params
end

---@param state QueryBuilder
---@return string, table
function QueryCompilerMySQL:compileCount(state)
    local fromSql = compileFrom(state.from)
    local params = {}

    if #state.groupBys == 0 then
        local q = { ('SELECT COUNT(*) FROM %s'):format(fromSql) }
        if #state.wheres > 0 then
            q[#q + 1] = 'WHERE ' .. self:compileWhereClause(state.wheres, params)
        end
        return table.concat(q, ' '), params
    end

    local inner = { ('SELECT 1 FROM %s'):format(fromSql) }
    if #state.wheres > 0 then
        inner[#inner + 1] = 'WHERE ' .. self:compileWhereClause(state.wheres, params)
    end
    inner[#inner + 1] = 'GROUP BY ' .. table.concat(Utilities.map(state.groupBys, Utilities.ensureBackticks), ', ')

    local innerSql = table.concat(inner, ' ')
    return ('SELECT COUNT(*) FROM (%s) AS %s'):format(innerSql, Utilities.ensureBackticks('qb_count')), params
end

---@param state QueryBuilder
---@param data table
---@return string, table
function QueryCompilerMySQL:compileInsert(state, data)
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

    return ('INSERT INTO %s (%s) VALUES (%s)'):format(
        Utilities.ensureBackticks(state.from.name),
        table.concat(columns, ', '),
        table.concat(values, ', ')
    ), params
end

---@param state QueryBuilder
---@param data table
---@return string, table
function QueryCompilerMySQL:compileUpdate(state, data)
    if #state.wheres == 0 and not state._allowNoWhere then
        error(('[%s]: Refusing to UPDATE without WHERE. Call :allowAll() to override.'):format(Utilities.CURRENT_RESOURCE_NAME))
    end

    local sets = {}
    local params = {}

    for _, column in ipairs(Utilities.getSorted(data)) do
        sets[#sets + 1] = Utilities.ensureBackticks(column) .. ' = ?'
        local v = data[column]
        if type(v) == 'table' then
            params[#params + 1] = json.encode(v)
        else
            params[#params + 1] = Input:sanitize(v)
        end
    end

    local query = { ('UPDATE %s SET %s'):format(Utilities.ensureBackticks(state.from.name), table.concat(sets, ', ')) }
    if #state.wheres > 0 then
        query[#query + 1] = 'WHERE ' .. self:compileWhereClause(state.wheres, params)
    end

    return table.concat(query, ' '), params
end

---@param state QueryBuilder
---@return string, table
function QueryCompilerMySQL:compileDelete(state)
    if #state.wheres == 0 and not state._allowNoWhere then
        error(('[%s]: Refusing to DELETE without WHERE. Call :allowAll() to override.'):format(Utilities.CURRENT_RESOURCE_NAME))
    end

    local params = {}
    local query = { ('DELETE FROM %s'):format(Utilities.ensureBackticks(state.from.name)) }

    if #state.wheres > 0 then
        query[#query + 1] = 'WHERE ' .. self:compileWhereClause(state.wheres, params)
    end

    return table.concat(query, ' '), params
end

return QueryCompilerMySQL
