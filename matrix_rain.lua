local LEFT = 8
local TOP = 22
local WIDTH_CELL = 16
local HEIGHT_CELL = 16
local ROWS = 14
local COLS = 17
local DEFAULT_VALUE = " "
local DEFAULT_FONT = "10x20"
local DEFAULT_FONT_SIZE = 1
local BG_COLOR = display.color565(0, 0, 0)
local ACTIVATE_TIME_MS = 300
local DEACTIVATE_TIME_MS = 300
local REFRESH_TIME_MS = 100
local ANSI_SYMBOLS = "!\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`0123456789{|}~"
local HEX_SYMBOLS = "0123456789ABCDEF"
local BINARY_SYMBOLS = "01"

local ValueState = {
    DEFAULT = 0,
    ACTIVE = 1,
    IDLE = 2,
    INACTIVE = 3
}

local ValueColor = {
    [ValueState.DEFAULT] = display.color565(0, 0, 0),
    [ValueState.ACTIVE] = display.color565(0, 255, 0),
    [ValueState.IDLE] = display.color565(0, 150, 0),
    [ValueState.INACTIVE] = display.color565(0, 50, 0)
}

local Timer = {}
Timer.__index = Timer
function Timer.new(limit_ms)
    return setmetatable({
        t = 0,
        limit = limit_ms
    }, Timer)
end
function Timer:is_over(delta_ms)
    self.t = self.t + delta_ms
    if self.t >= self.limit then
        self.t = self.t - self.limit
        return true
    end
    return false
end

local SymbolManager = {}
SymbolManager.__index = SymbolManager
function SymbolManager.new()
    return setmetatable({
        _map = {},
        _keys = {},
        _current = nil,
        _cur_size = 0
    }, SymbolManager)
end
function SymbolManager:put(key, symbols)
    if self._map[key] == nil then
        table.insert(self._keys, key)
    end
    self._map[key] = symbols
    if not self._current then
        self:_change(key)
    end
end
function SymbolManager:_change(key)
    self._current = key
    self._cur_size = #self._map[key]
end
function SymbolManager:get_random_symbol()
    local r = math.random(self._cur_size) + 1
    return self._map[self._current]:sub(r, r)
end
function SymbolManager:_get_current_index()
    for i, key in ipairs(self._keys) do
        if key == self._current then
            return i
        end
    end
    return nil
end
function SymbolManager:next()
    local index = self:_get_current_index()
    if index and index < #self._keys then
        self:_change(self._keys[index + 1])
    end
end
function SymbolManager:prev()
    local index = self:_get_current_index()
    if index and index > 1 then
        self:_change(self._keys[index - 1])
    end
end

local MatrixRain = {}
MatrixRain.__index = MatrixRain
function MatrixRain._create_matrix(rows, cols, value, state)
    local m = {}
    for row = 1, rows do
        m[row] = {}
        for col = 1, cols do
            m[row][col] = {
                value = value,
                state = state
            }
        end
    end
    return m
end
function MatrixRain.new(cfg)
    cfg = cfg or {}
    local self = setmetatable({
        _rows = cfg.rows or 1,
        _cols = cfg.cols or 1,
        _default_value = cfg.default_value or " ",
        _default_state = cfg.default_state or 0,
        _symbolManager = cfg.symbolManager or {}
    }, MatrixRain)

    self._cells = MatrixRain._create_matrix(self._rows, self._cols, self._default_value, self._default_state)

    return self
end
function MatrixRain:each_cell(state, callback)
    for row = 1, self._rows do
        for col = 1, self._cols do
            local cell = self._cells[row][col]
            if cell.state == state then
                callback(cell.value, row, col)
            end
        end
    end
end
function MatrixRain:get_random_value()
    return self._symbolManager:get_random_symbol()
end
function MatrixRain:mark_random_active(use_top_row)
    local row = use_top_row and 1 or math.random(self._rows) + 1
    local col = math.random(self._cols) + 1
    self._cells[row][col].value = self:get_random_value()
    self._cells[row][col].state = ValueState.ACTIVE
end
function MatrixRain:mark_random_inactive(use_top_row)
    local row = use_top_row and 1 or math.random(self._rows) + 1
    local col = math.random(self._cols) + 1
    self._cells[row][col].value = self._default_value
    self._cells[row][col].state = ValueState.INACTIVE
end
function MatrixRain:refresh()
    local cells = self._cells
    for row = self._rows, 1, -1 do
        for col = self._cols, 1, -1 do
            local cell = cells[row][col]
            if cell.state == ValueState.ACTIVE then
                cell.state = ValueState.IDLE
                if row < self._rows then
                    local next_cell_in_col = cells[row + 1][col]
                    next_cell_in_col.value = self:get_random_value()
                    next_cell_in_col.state = ValueState.ACTIVE
                end
            elseif cell.state == ValueState.INACTIVE then
                cell.state = ValueState.DEFAULT
                cell.value = self._default_value
                if row < self._rows then
                    local next_cell_in_col = cells[row + 1][col]
                    next_cell_in_col.state = ValueState.INACTIVE
                end
            end
        end
    end
end

local activate_timer = Timer.new(ACTIVATE_TIME_MS)
local deactivate_timer = Timer.new(DEACTIVATE_TIME_MS)
local refresh_timer = Timer.new(REFRESH_TIME_MS)

local symbolManager = SymbolManager.new()
symbolManager:put("ansi", ANSI_SYMBOLS)
symbolManager:put("hex", HEX_SYMBOLS)
symbolManager:put("binary", BINARY_SYMBOLS)

local matrix = MatrixRain.new({
    rows = ROWS,
    cols = COLS,
    default_value = DEFAULT_VALUE,
    default_state = ValueState.DEFAULT,
    symbolManager = symbolManager
})

function lilka.init()
    display.set_font(DEFAULT_FONT)
    display.set_text_size(DEFAULT_FONT_SIZE)
end

function lilka.update(delta)
    local state = controller.get_state()
    if state.a.just_pressed then
        util.exit()
    end
    if state.up.just_pressed then
        symbolManager:next()
    elseif state.down.just_pressed then
        symbolManager:prev()
    end
    local delta_ms = math.floor(delta * 1000)
    if refresh_timer:is_over(delta_ms) then
        matrix:refresh()
    end
    if activate_timer:is_over(delta_ms) then
        matrix:mark_random_active(true)
        matrix:mark_random_active(false)
    end
    if deactivate_timer:is_over(delta_ms) then
        matrix:mark_random_inactive(true)
        matrix:mark_random_inactive(false)
    end
end

function draw_cell(value, row, col)
    local x = LEFT + (col - 1) * WIDTH_CELL
    local y = TOP + (row - 1) * HEIGHT_CELL
    display.set_cursor(x, y)
    display.print(value)
end

function draw_cells_by_state(state)
    local color = ValueColor[state] or display.color565(255, 0, 0)
    display.set_text_color(ValueColor[state], BG_COLOR)
    matrix:each_cell(state, draw_cell)
end

function lilka.draw()
    display.fill_screen(BG_COLOR)
    for _, state in pairs(ValueState) do
        draw_cells_by_state(state)
    end
end
