--- lib/draw.lua
--- Common drawing utilities: arrows, vector fields, grids, labels, formulas.
--- Used across all sections for consistent visual style.

local Vec = require("lib.vector")
local Theme = require("shell.theme")

local Draw = {}

--- Draw an arrow from (x1,y1) to (x2,y2)
--- @param x1 number Start x
--- @param y1 number Start y
--- @param x2 number End x
--- @param y2 number End y
--- @param head_size number? Arrow head size (default 8)
--- @param line_width number? Line width (default 2)
function Draw.arrow(x1, y1, x2, y2, head_size, line_width)
    head_size = head_size or 8
    line_width = line_width or 2

    local dx, dy = x2 - x1, y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1 then return end

    local nx, ny = dx / len, dy / len

    love.graphics.setLineWidth(line_width)
    love.graphics.line(x1, y1, x2, y2)

    -- Arrow head
    local px, py = -ny, nx  -- perpendicular
    local hx, hy = x2 - nx * head_size, y2 - ny * head_size
    love.graphics.polygon("fill",
        x2, y2,
        hx + px * head_size * 0.4, hy + py * head_size * 0.4,
        hx - px * head_size * 0.4, hy - py * head_size * 0.4
    )
    love.graphics.setLineWidth(1)
end

--- Draw a velocity/force vector at a point
--- @param x number Origin x
--- @param y number Origin y
--- @param vx number Vector x component
--- @param vy number Vector y component
--- @param scale number? Visual scale factor (default 1)
--- @param max_len number? Maximum pixel length (default 60)
function Draw.vector(x, y, vx, vy, scale, max_len)
    scale = scale or 1
    max_len = max_len or 60

    local svx, svy = vx * scale, vy * scale
    local len = math.sqrt(svx * svx + svy * svy)
    if len < 0.5 then return end

    -- Clamp length
    if len > max_len then
        local f = max_len / len
        svx, svy = svx * f, svy * f
    end

    Draw.arrow(x, y, x + svx, y + svy, 6, 1.5)
end

--- Draw a grid of vector arrows (like the electric field visualization)
--- @param field function(gx, gy) → vx, vy  Returns vector at grid point
--- @param x number Grid origin x
--- @param y number Grid origin y
--- @param w number Grid width
--- @param h number Grid height
--- @param spacing number Grid spacing in pixels
--- @param color_fn function(magnitude) → r,g,b,a  Color by magnitude
function Draw.vectorField(field, x, y, w, h, spacing, color_fn)
    spacing = spacing or 30
    color_fn = color_fn or function(mag)
        local t = math.min(mag / 2, 1)
        return 0.3 + t * 0.5, 0.5 + t * 0.3, 0.9, 0.4 + t * 0.4
    end

    for gx = x, x + w, spacing do
        for gy = y, y + h, spacing do
            local vx, vy = field(gx, gy)
            local mag = math.sqrt(vx * vx + vy * vy)
            if mag > 0.01 then
                local r, g, b, a = color_fn(mag)
                love.graphics.setColor(r, g, b, a)
                Draw.vector(gx, gy, vx, vy, 1, spacing * 0.8)
            end
        end
    end
end

--- Draw a dot grid background
function Draw.dotGrid(x, y, w, h, spacing, dot_r, color)
    spacing = spacing or 40
    dot_r = dot_r or 1
    color = color or {1, 1, 1, 0.04}
    love.graphics.setColor(unpack(color))
    for gx = x, x + w, spacing do
        for gy = y, y + h, spacing do
            love.graphics.circle("fill", gx, gy, dot_r)
        end
    end
end

--- Draw axis lines at origin
function Draw.axes(ox, oy, length, show_labels)
    length = length or 100

    -- X axis (red)
    love.graphics.setColor(0.9, 0.3, 0.3, 0.6)
    Draw.arrow(ox, oy, ox + length, oy, 6, 1.5)
    if show_labels then
        love.graphics.print("X", ox + length + 4, oy - 6)
    end

    -- Y axis (green, pointing up in screen = down in world)
    love.graphics.setColor(0.3, 0.9, 0.3, 0.6)
    Draw.arrow(ox, oy, ox, oy - length, 6, 1.5)
    if show_labels then
        love.graphics.print("Y", ox + 4, oy - length - 14)
    end
end

--- Draw a formula/equation in monospace
--- @param text string Formula text (e.g., "K(t) = Σ ||v_j(t)||²")
--- @param x number Position x
--- @param y number Position y
--- @param font love.Font? Font to use
function Draw.formula(text, x, y, font)
    font = font or Theme.fonts().mono
    local prev_font = love.graphics.getFont()
    love.graphics.setFont(font)

    -- Background pill
    local tw = font:getWidth(text)
    local th = font:getHeight()
    local pad = 8
    love.graphics.setColor(0.06, 0.06, 0.10, 0.9)
    Theme.roundRect("fill", x - pad, y - pad/2, tw + pad*2, th + pad, Theme.radius.sm)
    love.graphics.setColor(1, 1, 1, 0.08)
    Theme.roundRect("line", x - pad, y - pad/2, tw + pad*2, th + pad, Theme.radius.sm)

    -- Text
    love.graphics.setColor(0.75, 0.85, 0.95, 0.9)
    love.graphics.print(text, x, y)

    love.graphics.setFont(prev_font)
end

--- Draw a label badge (like layer indicator)
--- @param text string Label text
--- @param x number Position x
--- @param y number Position y
--- @param color table? {r,g,b,a}
function Draw.badge(text, x, y, color)
    color = color or Theme.colors.accent
    local font = Theme.fonts().small
    local prev_font = love.graphics.getFont()
    love.graphics.setFont(font)

    local tw = font:getWidth(text)
    local th = font:getHeight()
    local pad_x, pad_y = 8, 3

    -- Background
    love.graphics.setColor(color[1], color[2], color[3], 0.15)
    Theme.roundRect("fill", x, y, tw + pad_x*2, th + pad_y*2, Theme.radius.sm)

    -- Text
    love.graphics.setColor(color[1], color[2], color[3], 1)
    love.graphics.print(text, x + pad_x, y + pad_y)

    love.graphics.setFont(prev_font)
    return tw + pad_x * 2  -- return width for layout
end

--- Draw a section title bar
--- @param title string Section title
--- @param layer string Layer name (for color)
--- @param section_id string Section ID (e.g., "2.5")
function Draw.titleBar(title, layer, section_id)
    local w = love.graphics.getWidth()
    local h = 52

    -- Background
    love.graphics.setColor(0.05, 0.05, 0.08, 0.95)
    love.graphics.rectangle("fill", 0, 0, w, h)
    love.graphics.setColor(1, 1, 1, 0.06)
    love.graphics.line(0, h, w, h)

    -- Layer badge
    local layer_color = Theme.layerColor(layer)
    local badge_w = Draw.badge(string.upper(layer), 16, 14, layer_color)

    -- Section ID
    love.graphics.setColor(1, 1, 1, 0.4)
    love.graphics.setFont(Theme.fonts().body)
    love.graphics.print(section_id, 16 + badge_w + 12, 17)

    -- Title
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.setFont(Theme.fonts().heading)
    local id_w = Theme.fonts().body:getWidth(section_id)
    love.graphics.print(title, 16 + badge_w + 12 + id_w + 12, 15)

    -- Back hint
    love.graphics.setColor(1, 1, 1, 0.3)
    love.graphics.setFont(Theme.fonts().small)
    love.graphics.print("ESC  back to graph", w - 130, 20)

    return h
end

--- Draw an info panel (sidebar-style)
--- @param x number Panel x
--- @param y number Panel y
--- @param w number Panel width
--- @param items table Array of {label, value} pairs
function Draw.infoPanel(x, y, w, items)
    local pad = 16
    local line_h = 24
    local h = pad * 2 + #items * line_h

    -- Background
    love.graphics.setColor(0.06, 0.06, 0.09, 0.95)
    Theme.roundRect("fill", x, y, w, h, Theme.radius.lg)
    love.graphics.setColor(1, 1, 1, 0.06)
    Theme.roundRect("line", x, y, w, h, Theme.radius.lg)

    for i, item in ipairs(items) do
        local iy = y + pad + (i - 1) * line_h

        -- Label
        love.graphics.setColor(1, 1, 1, 0.4)
        love.graphics.setFont(Theme.fonts().small)
        love.graphics.print(item[1], x + pad, iy)

        -- Value
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.setFont(Theme.fonts().body)
        local val_str = tostring(item[2])
        local val_w = Theme.fonts().body:getWidth(val_str)
        love.graphics.print(val_str, x + w - pad - val_w, iy)
    end

    return h
end

--- Draw a horizontal color ramp (for legends)
--- @param x number Position x
--- @param y number Position y
--- @param w number Width
--- @param h number Height
--- @param color_fn function(t) → r,g,b  where t is 0-1
--- @param label_low string? Label for low end
--- @param label_high string? Label for high end
function Draw.colorRamp(x, y, w, h, color_fn, label_low, label_high)
    for px = 0, w - 1 do
        local t = px / w
        local r, g, b = color_fn(t)
        love.graphics.setColor(r, g, b, 1)
        love.graphics.rectangle("fill", x + px, y, 1, h)
    end

    if label_low then
        love.graphics.setColor(1, 1, 1, 0.5)
        love.graphics.setFont(Theme.fonts().small)
        love.graphics.print(label_low, x, y + h + 2)
    end
    if label_high then
        love.graphics.setColor(1, 1, 1, 0.5)
        local lw = Theme.fonts().small:getWidth(label_high)
        love.graphics.print(label_high, x + w - lw, y + h + 2)
    end
end

--- Speed color ramp: blue → yellow → red
function Draw.speedColor(t)
    t = math.max(0, math.min(1, t))
    if t < 0.5 then
        local s = t * 2
        return 0.2 + s * 0.8, 0.3 + s * 0.7, 0.9 - s * 0.4
    else
        local s = (t - 0.5) * 2
        return 1.0, 1.0 - s * 0.6, 0.5 - s * 0.4
    end
end

return Draw
