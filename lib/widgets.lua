--- lib/widgets.lua
--- Interactive UI widgets: sliders, toggles, buttons, panels.
--- Immediate-mode style — call in draw/update, returns interaction state.

local Theme = require("shell.theme")

local Widgets = {}

--- Internal state for active widget tracking
local _active_id = nil
local _hover_id = nil

--- Generate a unique widget ID from position
local function wid(x, y, label)
    return string.format("%s_%d_%d", label or "w", math.floor(x), math.floor(y))
end

--- Horizontal slider
--- @param x number Position x
--- @param y number Position y
--- @param w number Width
--- @param value number Current value (0-1)
--- @param label string? Label text
--- @param opts table? {min, max, format, color}
--- @return number new_value, boolean changed
function Widgets.slider(x, y, w, value, label, opts)
    opts = opts or {}
    local min_val = opts.min or 0
    local max_val = opts.max or 1
    local format = opts.format or "%.2f"
    local color = opts.color or Theme.colors.accent
    local id = wid(x, y, label)

    local h = 32
    local track_y = y + 20
    local track_h = 4
    local knob_r = 7

    -- Normalize value to 0-1
    local t = (value - min_val) / (max_val - min_val)
    t = math.max(0, math.min(1, t))

    local knob_x = x + t * w
    local mx, my = love.mouse.getPosition()
    local mouse_down = love.mouse.isDown(1)

    -- Hit test
    local hovering = mx >= x - 10 and mx <= x + w + 10 and my >= y and my <= y + h + 10
    if hovering then _hover_id = id end

    -- Drag
    local changed = false
    if _active_id == id then
        if mouse_down then
            local new_t = math.max(0, math.min(1, (mx - x) / w))
            local new_val = min_val + new_t * (max_val - min_val)
            if math.abs(new_val - value) > 0.0001 then
                value = new_val
                t = new_t
                knob_x = x + t * w
                changed = true
            end
        else
            _active_id = nil
        end
    elseif hovering and mouse_down and _active_id == nil then
        _active_id = id
    end

    -- Draw label
    if label then
        love.graphics.setColor(1, 1, 1, 0.6)
        love.graphics.setFont(Theme.fonts().small)
        love.graphics.print(label, x, y)
    end

    -- Draw value
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.setFont(Theme.fonts().mono)
    local val_str = string.format(format, value)
    local val_w = Theme.fonts().mono:getWidth(val_str)
    love.graphics.print(val_str, x + w - val_w, y)

    -- Track background
    love.graphics.setColor(1, 1, 1, 0.08)
    love.graphics.rectangle("fill", x, track_y, w, track_h, 2, 2)

    -- Track fill
    love.graphics.setColor(color[1], color[2], color[3], 0.6)
    love.graphics.rectangle("fill", x, track_y, knob_x - x, track_h, 2, 2)

    -- Knob
    local knob_alpha = (_active_id == id) and 1 or (hovering and 0.9 or 0.7)
    love.graphics.setColor(color[1], color[2], color[3], knob_alpha)
    love.graphics.circle("fill", knob_x, track_y + track_h / 2, knob_r)

    if _active_id == id or _hover_id == id then
        love.graphics.setColor(color[1], color[2], color[3], 0.2)
        love.graphics.circle("fill", knob_x, track_y + track_h / 2, knob_r + 4)
    end

    return value, changed
end

--- Toggle button
--- @param x number Position x
--- @param y number Position y
--- @param value boolean Current state
--- @param label string Label text
--- @param color table? Active color
--- @return boolean new_value, boolean changed
function Widgets.toggle(x, y, value, label, color)
    color = color or Theme.colors.accent
    local id = wid(x, y, label)
    local w, h = 36, 20
    local r = h / 2

    local mx, my = love.mouse.getPosition()
    local hovering = mx >= x and mx <= x + w and my >= y and my <= y + h

    -- Draw track
    if value then
        love.graphics.setColor(color[1], color[2], color[3], 0.4)
    else
        love.graphics.setColor(1, 1, 1, 0.1)
    end
    love.graphics.rectangle("fill", x, y, w, h, r, r)

    -- Draw knob
    local knob_x = value and (x + w - r) or (x + r)
    love.graphics.setColor(1, 1, 1, value and 0.95 or 0.4)
    love.graphics.circle("fill", knob_x, y + r, r - 3)

    -- Label
    if label then
        love.graphics.setColor(1, 1, 1, 0.6)
        love.graphics.setFont(Theme.fonts().small)
        love.graphics.print(label, x + w + 8, y + 3)
    end

    -- Click detection is handled externally via Widgets.clicked
    return value, false
end

--- Track toggle clicks (call from mousepressed)
function Widgets.toggleClicked(x, y, w, h, mx, my)
    w = w or 36
    h = h or 20
    return mx >= x and mx <= x + w and my >= y and my <= y + h
end

--- Simple button
--- @param x number Position x
--- @param y number Position y
--- @param text string Button text
--- @param opts table? {w, h, color, disabled}
--- @return boolean hovered
function Widgets.button(x, y, text, opts)
    opts = opts or {}
    local font = Theme.fonts().body
    local tw = font:getWidth(text)
    local w = opts.w or (tw + 32)
    local h = opts.h or 32
    local color = opts.color or Theme.colors.accent
    local disabled = opts.disabled or false

    local mx, my = love.mouse.getPosition()
    local hovering = not disabled and mx >= x and mx <= x + w and my >= y and my <= y + h

    -- Background
    if disabled then
        love.graphics.setColor(1, 1, 1, 0.04)
    elseif hovering then
        love.graphics.setColor(color[1], color[2], color[3], 0.15)
    else
        love.graphics.setColor(1, 1, 1, 0.06)
    end
    Theme.roundRect("fill", x, y, w, h, Theme.radius.sm)

    -- Border
    if hovering then
        love.graphics.setColor(color[1], color[2], color[3], 0.3)
    else
        love.graphics.setColor(1, 1, 1, 0.08)
    end
    Theme.roundRect("line", x, y, w, h, Theme.radius.sm)

    -- Text
    if disabled then
        love.graphics.setColor(1, 1, 1, 0.2)
    else
        love.graphics.setColor(1, 1, 1, hovering and 0.9 or 0.6)
    end
    love.graphics.setFont(font)
    love.graphics.print(text, x + (w - tw) / 2, y + (h - font:getHeight()) / 2)

    return hovering
end

--- Check if a button was clicked (call from mousepressed)
function Widgets.buttonClicked(x, y, w, h, mx, my)
    return mx >= x and mx <= x + w and my >= y and my <= y + h
end

--- Reset active widget state (call at start of frame)
function Widgets.beginFrame()
    _hover_id = nil
end

--- Check if any widget is active (being dragged)
function Widgets.isActive()
    return _active_id ~= nil
end

return Widgets
