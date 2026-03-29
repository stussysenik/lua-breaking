--- Section 2.5: Force Vector Field
--- ★ Flagship visualization — inspired by the electric field simulator.
--- Contact points (feet, hands on ground) act as force sources.
--- A grid of arrows shows force distribution, gravity overlaid.
--- Drag contact points to see forces redistribute in real-time.
---
--- Research bridge: experiments/components/contact_light.py
--- Physics: F = G * m1 * m2 / r² (gravitational analogy for body forces)

local Theme = require("shell.theme")
local Draw = require("lib.draw")
local Widgets = require("lib.widgets")
local Vec = require("lib.vector")

local Section = {}
Section.__index = Section

Section.meta = {
    id = "2.5",
    title = "Force Vector Field",
    layer = "physics",
    description = "Contact points as force sources - drag to redistribute forces. Like electric fields, but for the body.",
    research_mapping = "experiments/components/contact_light.py",
    data_bridge = true,
    prerequisites = {"1.1", "1.2"},
}

--- Contact point (force source)
local ContactPoint = {}
ContactPoint.__index = ContactPoint

function ContactPoint.new(x, y, strength, name, color)
    return setmetatable({
        x = x,
        y = y,
        strength = strength,  -- positive = push out, negative = pull in
        name = name,
        color = color or {0.490, 0.827, 0.988},
        radius = 14,
        hovered = false,
    }, ContactPoint)
end

--- State
local contacts = {}
local field_w, field_h = 0, 0
local field_x, field_y = 0, 0
local grid_spacing = 28
local dragging_contact = nil
local show_equipotential = false
local show_magnitude = true
local show_field_lines = false
local gravity_strength = 0.3
local selected_contact = nil
local field_strength_display = 0
local force_between_display = 0

--- Canvas cache for expensive field rendering
local field_canvas = nil
local cache_dirty = true

--- Compute the force field at a point from all contacts
local function fieldAt(px, py)
    local fx, fy = 0, gravity_strength  -- gravity pulls down

    for _, c in ipairs(contacts) do
        local dx = px - c.x
        local dy = py - c.y
        local dist2 = dx * dx + dy * dy
        local dist = math.sqrt(dist2)

        if dist > 5 then  -- avoid singularity
            -- Coulomb-like: F = k * q / r²
            local k = 5000
            local force = k * c.strength / dist2
            fx = fx + force * (dx / dist)
            fy = fy + force * (dy / dist)
        end
    end

    return fx, fy
end

--- Compute force magnitude between two contacts
local function forceBetween(c1, c2)
    local dx = c2.x - c1.x
    local dy = c2.y - c1.y
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 1 then return 0, dist end
    local k = 5000
    local force = k * math.abs(c1.strength * c2.strength) / (dist * dist)
    return force, dist
end

function Section:load()
    local sw, sh = love.graphics.getDimensions()

    -- Field area (left portion of screen)
    field_x = 20
    field_y = 70
    field_w = sw * 0.65 - 40
    field_h = sh - 100

    -- Initialize contact points (bboy in a freeze position)
    local cx, cy = field_x + field_w / 2, field_y + field_h / 2
    contacts = {
        -- Right hand (main support)
        ContactPoint.new(cx - 60, cy + 80, 1.5, "R.Hand",
            {0.984, 0.443, 0.522}),  -- rose
        -- Left hand
        ContactPoint.new(cx + 40, cy + 60, 0.8, "L.Hand",
            {0.984, 0.749, 0.141}),  -- amber
        -- Right foot (in the air, weaker)
        ContactPoint.new(cx + 100, cy - 120, -0.5, "R.Foot",
            {0.655, 0.545, 0.980}),  -- violet
        -- Head (for headspins - negative = pulling)
        ContactPoint.new(cx - 30, cy - 80, -0.3, "Head",
            {0.204, 0.827, 0.600}),  -- emerald
    }

    selected_contact = nil
    dragging_contact = nil
    show_equipotential = false
    show_magnitude = true
    show_field_lines = false
    gravity_strength = 0.3
    cache_dirty = true
end

function Section:update(dt)
    if not contacts then return end

    local mx, my = love.mouse.getPosition()

    -- Update contact hover states
    for i, c in ipairs(contacts) do
        local dx, dy = mx - c.x, my - c.y
        c.hovered = (dx * dx + dy * dy) < (c.radius + 8) ^ 2
    end

    -- Drag contact
    if dragging_contact then
        if love.mouse.isDown(1) then
            contacts[dragging_contact].x = math.max(field_x + 10, math.min(field_x + field_w - 10, mx))
            contacts[dragging_contact].y = math.max(field_y + 10, math.min(field_y + field_h - 10, my))
            cache_dirty = true
        else
            dragging_contact = nil
        end
    end

    -- Update field strength at mouse position
    local fx, fy = fieldAt(mx, my)
    field_strength_display = math.sqrt(fx * fx + fy * fy)

    -- Update force between first two contacts
    if #contacts >= 2 then
        force_between_display, _ = forceBetween(contacts[1], contacts[2])
    end
end

function Section:draw()
    local sw, sh = love.graphics.getDimensions()

    -- Background
    love.graphics.setColor(unpack(Theme.colors.bg))
    love.graphics.rectangle("fill", 0, 0, sw, sh)

    -- Title bar
    Draw.titleBar(Section.meta.title, Section.meta.layer, Section.meta.id)

    -- Field area background
    love.graphics.setColor(unpack(Theme.colors.bg))
    Theme.roundRect("fill", field_x, field_y, field_w, field_h, Theme.radius.lg)
    love.graphics.setColor(unpack(Theme.colors.border))
    Theme.roundRect("line", field_x, field_y, field_w, field_h, Theme.radius.lg)

    -- Dot grid inside field
    Draw.dotGrid(field_x, field_y, field_w, field_h, grid_spacing, 0.5, Theme.colors.grid_dot)

    -- Render expensive field computations to a cached Canvas
    if cache_dirty or not field_canvas then
        local cw = math.floor(field_w)
        local ch = math.floor(field_h)
        if not field_canvas or field_canvas:getWidth() ~= cw or field_canvas:getHeight() ~= ch then
            field_canvas = love.graphics.newCanvas(cw, ch)
        end

        love.graphics.setCanvas(field_canvas)
        love.graphics.clear(0, 0, 0, 0)
        love.graphics.push()
        love.graphics.translate(-field_x, -field_y)

        if show_equipotential then self:drawEquipotential() end
        if show_magnitude then self:drawMagnitudeField() end
        self:drawVectorField()
        if show_field_lines then self:drawFieldLines() end

        love.graphics.pop()
        love.graphics.setCanvas()
        cache_dirty = false
    end

    -- Draw cached field
    love.graphics.setColor(unpack(Theme.colors.text))
    love.graphics.draw(field_canvas, field_x, field_y)

    -- Draw contact points
    self:drawContacts()

    -- Field info overlay (top-left of field)
    love.graphics.setColor(unpack(Theme.colors.text_dim))
    love.graphics.setFont(Theme.fonts().mono)
    love.graphics.print(
        string.format("Field strength: %.4f N/C", field_strength_display),
        field_x + 10, field_y + 8
    )
    if #contacts >= 2 then
        love.graphics.print(
            string.format("F12: %.2f N", force_between_display),
            field_x + 10, field_y + 24
        )
    end

    -- Sidebar
    self:drawSidebar(sw, sh)

    -- Bottom formula
    Draw.formula(
        "F = k |q1 * q2| / d²    (Coulomb analogy for body contact forces)",
        field_x, sh - 40
    )
end

function Section:drawVectorField()
    for gx = field_x + grid_spacing, field_x + field_w - grid_spacing, grid_spacing do
        for gy = field_y + grid_spacing, field_y + field_h - grid_spacing, grid_spacing do
            local fx, fy = fieldAt(gx, gy)
            local mag = math.sqrt(fx * fx + fy * fy)

            if mag > 0.005 then
                -- Color by magnitude
                local t = math.min(mag / 3, 1)
                local r = 0.2 + t * 0.4
                local g = 0.3 + t * 0.4
                local b = 0.7 + t * 0.2
                local a = 0.15 + t * 0.55

                love.graphics.setColor(r, g, b, a)

                -- Normalize and scale arrow
                local arrow_len = math.min(grid_spacing * 0.7, mag * 15)
                local nx, ny = fx / mag, fy / mag

                Draw.arrow(
                    gx - nx * arrow_len * 0.3,
                    gy - ny * arrow_len * 0.3,
                    gx + nx * arrow_len * 0.7,
                    gy + ny * arrow_len * 0.7,
                    5, 1.2
                )
            end
        end
    end
end

function Section:drawMagnitudeField()
    -- Low-res magnitude heatmap
    local step = 8
    for gx = field_x, field_x + field_w, step do
        for gy = field_y, field_y + field_h, step do
            local fx, fy = fieldAt(gx, gy)
            local mag = math.sqrt(fx * fx + fy * fy)
            local t = math.min(mag / 5, 1)
            if t > 0.02 then
                love.graphics.setColor(0.3, 0.3, 0.8, t * 0.06)
                love.graphics.rectangle("fill", gx, gy, step, step)
            end
        end
    end
end

function Section:drawEquipotential()
    -- Simplified equipotential via contour hints
    for _, c in ipairs(contacts) do
        local col = c.color
        for r = 30, 200, 30 do
            love.graphics.setColor(col[1], col[2], col[3], 0.06)
            love.graphics.circle("line", c.x, c.y, r)
        end
    end
end

function Section:drawFieldLines()
    -- Trace field lines from positive contacts outward
    for _, c in ipairs(contacts) do
        if c.strength > 0 then
            local col = c.color
            for angle = 0, math.pi * 2, math.pi / 6 do
                love.graphics.setColor(col[1], col[2], col[3], 0.15)
                local px, py = c.x + math.cos(angle) * 20, c.y + math.sin(angle) * 20
                local points = {px, py}

                for step = 1, 80 do
                    local fx, fy = fieldAt(px, py)
                    local mag = math.sqrt(fx * fx + fy * fy)
                    if mag < 0.001 then break end

                    local ds = 4  -- step size
                    px = px + (fx / mag) * ds
                    py = py + (fy / mag) * ds

                    -- Bounds check
                    if px < field_x or px > field_x + field_w or
                       py < field_y or py > field_y + field_h then
                        break
                    end

                    table.insert(points, px)
                    table.insert(points, py)
                end

                if #points >= 4 then
                    love.graphics.setLineWidth(1)
                    love.graphics.line(points)
                end
            end
        end
    end
end

function Section:drawContacts()
    for i, c in ipairs(contacts) do
        local is_selected = (i == selected_contact)

        -- Glow
        if c.hovered or is_selected then
            love.graphics.setColor(c.color[1], c.color[2], c.color[3], 0.15)
            love.graphics.circle("fill", c.x, c.y, c.radius + 12)
        end

        -- Outer ring
        love.graphics.setColor(c.color[1], c.color[2], c.color[3], 0.3)
        love.graphics.circle("line", c.x, c.y, c.radius + 4)

        -- Fill
        local alpha = (c.hovered or is_selected) and 0.9 or 0.7
        love.graphics.setColor(c.color[1], c.color[2], c.color[3], alpha)
        love.graphics.circle("fill", c.x, c.y, c.radius)

        -- Charge sign
        love.graphics.setColor(0, 0, 0, 0.8)
        love.graphics.setFont(Theme.fonts().heading)
        local sign = c.strength > 0 and "+" or "-"
        local tw = Theme.fonts().heading:getWidth(sign)
        local th = Theme.fonts().heading:getHeight()
        love.graphics.print(sign, c.x - tw / 2, c.y - th / 2)

        -- Label
        love.graphics.setColor(c.color[1], c.color[2], c.color[3], 0.8)
        love.graphics.setFont(Theme.fonts().small)
        love.graphics.print(c.name, c.x - Theme.fonts().small:getWidth(c.name) / 2, c.y + c.radius + 6)
    end
end

function Section:drawSidebar(sw, sh)
    local sidebar_x = sw * 0.67
    local sidebar_w = sw * 0.30
    local y = 80

    -- Contact panels
    for i, c in ipairs(contacts) do
        -- Contact card
        love.graphics.setColor(unpack(Theme.colors.panel_bg))
        Theme.roundRect("fill", sidebar_x, y, sidebar_w, 70, Theme.radius.md)
        love.graphics.setColor(c.color[1], c.color[2], c.color[3], 0.15)
        Theme.roundRect("line", sidebar_x, y, sidebar_w, 70, Theme.radius.md)

        -- Color bar
        love.graphics.setColor(c.color[1], c.color[2], c.color[3], 0.6)
        love.graphics.rectangle("fill", sidebar_x, y + 8, 3, 54, 1, 1)

        -- Name & position
        love.graphics.setColor(unpack(Theme.colors.text))
        love.graphics.setFont(Theme.fonts().body)
        love.graphics.print(c.name, sidebar_x + 14, y + 8)

        love.graphics.setColor(unpack(Theme.colors.text_muted))
        love.graphics.setFont(Theme.fonts().small)
        love.graphics.print(
            string.format("Position: (%.0f, %.0f)", c.x, c.y),
            sidebar_x + sidebar_w - 130, y + 10
        )

        -- Strength slider
        local new_str, changed = Widgets.slider(
            sidebar_x + 14, y + 34, sidebar_w - 80, c.strength,
            nil,
            {min = -2, max = 2, format = "%.1f", color = c.color}
        )
        if changed then
            c.strength = new_str
            cache_dirty = true
        end

        -- Unit label
        love.graphics.setColor(unpack(Theme.colors.text_muted))
        love.graphics.setFont(Theme.fonts().small)
        love.graphics.print("C", sidebar_x + sidebar_w - 20, y + 42)

        y = y + 80
    end

    -- Controls
    y = y + 10

    -- Add/Remove buttons
    Widgets.button(sidebar_x, y, "Add Contact",
        {w = sidebar_w / 2 - 4, color = Theme.colors.accent})

    Widgets.button(sidebar_x + sidebar_w / 2 + 4, y, "Remove Contact",
        {w = sidebar_w / 2 - 4, color = Theme.colors.text_dim})
    y = y + 44

    -- Gravity slider
    local new_g, g_changed = Widgets.slider(
        sidebar_x, y, sidebar_w, gravity_strength,
        "Gravity",
        {min = 0, max = 2, format = "%.2f"}
    )
    if g_changed then
        gravity_strength = new_g
        cache_dirty = true
    end
    y = y + 48

    -- Grid spacing slider
    local new_gs, gs_changed = Widgets.slider(
        sidebar_x, y, sidebar_w, grid_spacing,
        "Grid Spacing",
        {min = 15, max = 60, format = "%.0f px"}
    )
    if gs_changed then
        grid_spacing = math.floor(new_gs)
        cache_dirty = true
    end
    y = y + 58

    -- Toggle buttons
    local toggles_y = y
    Widgets.button(sidebar_x, y, show_equipotential and "Hide Equipotential" or "Show Equipotential",
        {w = sidebar_w, color = Theme.colors.signal})
    y = y + 36
    Widgets.button(sidebar_x, y, show_field_lines and "Hide Field Lines" or "Show Field Lines",
        {w = sidebar_w, color = Theme.colors.signal})
    y = y + 36
    Widgets.button(sidebar_x, y, show_magnitude and "Hide Magnitude" or "Show Magnitude",
        {w = sidebar_w, color = Theme.colors.signal})
    y = y + 50

    -- Force calculations
    if #contacts >= 2 then
        local c1, c2 = contacts[1], contacts[2]
        local force, dist = forceBetween(c1, c2)

        love.graphics.setColor(unpack(Theme.colors.border))
        Theme.roundRect("fill", sidebar_x, y, sidebar_w, 180, Theme.radius.lg)

        love.graphics.setColor(unpack(Theme.colors.text))
        love.graphics.setFont(Theme.fonts().heading)
        love.graphics.print("Force Calculations", sidebar_x + 14, y + 12)

        love.graphics.setFont(Theme.fonts().small)
        love.graphics.setColor(unpack(Theme.colors.text_dim))

        local cy_text = y + 40
        love.graphics.print(string.format("%s ↔ %s:", c1.name, c2.name), sidebar_x + 14, cy_text)
        love.graphics.setColor(unpack(Theme.colors.text))
        love.graphics.setFont(Theme.fonts().mono)
        love.graphics.print(string.format("%.2e N", force), sidebar_x + 120, cy_text)
        love.graphics.print(string.format("(%.1f px)", dist), sidebar_x + sidebar_w - 80, cy_text)

        cy_text = cy_text + 24
        love.graphics.setColor(unpack(Theme.colors.text_muted))
        love.graphics.setFont(Theme.fonts().small)
        love.graphics.print(string.format("q1: %.1f C", c1.strength), sidebar_x + 14, cy_text)
        love.graphics.print(string.format("q2: %.1f C", c2.strength), sidebar_x + 120, cy_text)

        cy_text = cy_text + 20
        love.graphics.print(
            string.format("(x1,y1): (%.0f, %.0f)", c1.x, c1.y),
            sidebar_x + 14, cy_text
        )
        love.graphics.print(
            string.format("(x2,y2): (%.0f, %.0f)", c2.x, c2.y),
            sidebar_x + 120, cy_text
        )

        -- Formula
        cy_text = cy_text + 24
        love.graphics.setColor(unpack(Theme.colors.text_dim))
        love.graphics.setFont(Theme.fonts().mono)
        love.graphics.print("F = k|q1 * q2| / d²", sidebar_x + 14, cy_text)
    end
end

function Section:mousepressed(x, y, button)
    if button ~= 1 then return end

    local sw, sh = love.graphics.getDimensions()
    local sidebar_x = sw * 0.67
    local sidebar_w = sw * 0.30

    -- Check contact hit in field
    for i, c in ipairs(contacts) do
        local dx, dy = x - c.x, y - c.y
        if dx * dx + dy * dy < (c.radius + 8) ^ 2 then
            dragging_contact = i
            selected_contact = i
            return
        end
    end

    -- Check sidebar buttons
    local btn_y = 80 + #contacts * 80 + 10

    -- Add contact
    if Widgets.buttonClicked(sidebar_x, btn_y, sidebar_w / 2 - 4, 32, x, y) then
        if #contacts < 6 then
            local names = {"L.Foot", "R.Knee", "Elbow"}
            local colors = {
                {0.490, 0.827, 0.988},
                {0.984, 0.749, 0.141},
                {0.655, 0.545, 0.980},
            }
            local idx = (#contacts - 3) % 3 + 1
            table.insert(contacts, ContactPoint.new(
                field_x + field_w / 2 + math.random(-100, 100),
                field_y + field_h / 2 + math.random(-100, 100),
                0.5,
                names[idx] or "Point",
                colors[idx] or {0.8, 0.8, 0.8}
            ))
            cache_dirty = true
        end
        return
    end

    -- Remove contact
    if Widgets.buttonClicked(sidebar_x + sidebar_w / 2 + 4, btn_y, sidebar_w / 2 - 4, 32, x, y) then
        if #contacts > 2 then
            table.remove(contacts)
            if selected_contact and selected_contact > #contacts then
                selected_contact = nil
            end
            cache_dirty = true
        end
        return
    end

    -- Toggle buttons
    local toggle_y = btn_y + 44 + 48 + 48 + 58
    if Widgets.buttonClicked(sidebar_x, toggle_y, sidebar_w, 32, x, y) then
        show_equipotential = not show_equipotential
        return
    end
    toggle_y = toggle_y + 36
    if Widgets.buttonClicked(sidebar_x, toggle_y, sidebar_w, 32, x, y) then
        show_field_lines = not show_field_lines
        return
    end
    toggle_y = toggle_y + 36
    if Widgets.buttonClicked(sidebar_x, toggle_y, sidebar_w, 32, x, y) then
        show_magnitude = not show_magnitude
        return
    end

    -- Deselect
    selected_contact = nil
end

function Section:mousereleased(x, y, button)
    if button == 1 then
        dragging_contact = nil
    end
end

function Section:mousemoved(x, y, dx, dy)
    -- handled in update
end

function Section:keypressed(key)
    if key == "e" then
        show_equipotential = not show_equipotential
    elseif key == "f" then
        show_field_lines = not show_field_lines
    elseif key == "m" then
        show_magnitude = not show_magnitude
    end
end

function Section:unload()
    contacts = {}
    dragging_contact = nil
    selected_contact = nil
end

return Section
