--- Section 2.6: Center of Mass Tracker
--- COM dot with trajectory trail. Support polygon from contact points.
--- COM inside polygon = stable (green), outside = falling (red).
---
--- Research bridge: experiments/components/com_tracker.py

local Theme = require("shell.theme")
local Draw = require("lib.draw")
local Skeleton = require("lib.skeleton")
local Widgets = require("lib.widgets")
local Vec = require("lib.vector")
local Physics = require("lib.physics")

local Section = {}
Section.__index = Section

Section.meta = {
    id = "2.6",
    title = "Center of Mass & Stability",
    layer = "physics",
    description = "Track the center of mass through movement. Support polygon shows stability.",
    research_mapping = "experiments/components/com_tracker.py",
    data_bridge = true,
    prerequisites = {"1.1", "2.5"},
}

local skel
local com_trail = {}
local trail_max = 80
local contact_points = {}  -- active contact positions
local support_poly = {}
local com = nil
local stability = 0
local dragging_joint = nil
local show_support = true
local show_trail = true
local show_stability_meter = true

--- Which joints are currently in contact with ground
local active_contacts = {
    [8] = true,   -- l_ankle
    [9] = true,   -- r_ankle
    [11] = true,  -- l_foot
    [12] = true,  -- r_foot
}

function Section:load()
    local sw, sh = love.graphics.getDimensions()
    local area_w = sw * 0.62
    local area_h = sh - 100
    local scale = math.min(area_w, area_h) * 0.85
    local ox = (area_w - scale) / 2 + 20
    local oy = 70

    skel = Skeleton.new(scale, ox, oy)
    skel.show_labels = false
    skel.joint_radius = 6

    com_trail = {}
    self:updatePhysics()
end

function Section:updatePhysics()
    if not skel then return end

    -- Get 2D joint positions in screen coords
    local positions = {}
    for i = 1, 24 do
        local jx, jy = skel:toScreen(skel.joints[i])
        positions[i] = Vec.new(jx, jy)
    end

    -- Compute COM
    com = Physics.centerOfMass(positions)

    -- Gather active contact positions
    contact_points = {}
    for idx in pairs(active_contacts) do
        table.insert(contact_points, positions[idx])
    end

    -- Compute support polygon
    if #contact_points >= 2 then
        support_poly = Physics.supportPolygon(contact_points)
    else
        support_poly = contact_points
    end

    -- Compute stability
    if #support_poly >= 3 then
        stability = Physics.stabilityMargin(com, support_poly)
    else
        stability = -1
    end

    -- Add to trail
    if com then
        table.insert(com_trail, {x = com.x, y = com.y})
        while #com_trail > trail_max do
            table.remove(com_trail, 1)
        end
    end

    -- Color joints by contact state
    skel.joint_colors = {}
    for idx in pairs(active_contacts) do
        skel.joint_colors[idx] = {0.204, 0.827, 0.600, 1}  -- emerald for contacts
    end
end

function Section:update(dt)
    if not skel then return end

    local mx, my = love.mouse.getPosition()

    if not dragging_joint then
        skel.hovered_joint = skel:hitTest(mx, my, 18)
    end

    if dragging_joint then
        if love.mouse.isDown(1) then
            skel.joints[dragging_joint] = skel:fromScreen(mx, my)
            self:updatePhysics()
        else
            dragging_joint = nil
        end
    end
end

function Section:draw()
    local sw, sh = love.graphics.getDimensions()

    love.graphics.setColor(unpack(Theme.colors.bg))
    love.graphics.rectangle("fill", 0, 0, sw, sh)
    Draw.dotGrid(0, 0, sw, sh, 30, 1, {1, 1, 1, 0.02})

    Draw.titleBar(Section.meta.title, Section.meta.layer, Section.meta.id)

    -- Ground line
    local ground_y = skel.offset_y + skel.scale * 0.82
    love.graphics.setColor(unpack(Theme.colors.border))
    love.graphics.setLineWidth(1)
    love.graphics.line(20, ground_y, sw * 0.62, ground_y)

    -- Support polygon
    if show_support and #support_poly >= 3 then
        -- Fill
        local is_stable = stability > 0
        if is_stable then
            love.graphics.setColor(0.204, 0.827, 0.600, 0.08)
        else
            love.graphics.setColor(0.984, 0.443, 0.522, 0.08)
        end

        -- Draw as triangle fan from first vertex
        for i = 2, #support_poly - 1 do
            love.graphics.polygon("fill",
                support_poly[1].x, support_poly[1].y,
                support_poly[i].x, support_poly[i].y,
                support_poly[i + 1].x, support_poly[i + 1].y
            )
        end

        -- Outline
        if is_stable then
            love.graphics.setColor(0.204, 0.827, 0.600, 0.4)
        else
            love.graphics.setColor(0.984, 0.443, 0.522, 0.4)
        end
        love.graphics.setLineWidth(2)
        for i = 1, #support_poly do
            local j = (i % #support_poly) + 1
            love.graphics.line(
                support_poly[i].x, support_poly[i].y,
                support_poly[j].x, support_poly[j].y
            )
        end
    end

    -- COM trail
    if show_trail and #com_trail >= 2 then
        for i = 2, #com_trail do
            local alpha = (i / #com_trail) * 0.4
            love.graphics.setColor(0.984, 0.749, 0.141, alpha)
            love.graphics.setLineWidth(2)
            love.graphics.line(com_trail[i-1].x, com_trail[i-1].y, com_trail[i].x, com_trail[i].y)
        end
    end

    -- Draw skeleton
    skel:draw()

    -- Draw COM dot
    if com then
        local is_stable = stability > 0
        -- Glow
        if is_stable then
            love.graphics.setColor(0.204, 0.827, 0.600, 0.2)
        else
            love.graphics.setColor(0.984, 0.443, 0.522, 0.2)
        end
        love.graphics.circle("fill", com.x, com.y, 16)

        -- Dot
        if is_stable then
            love.graphics.setColor(0.204, 0.827, 0.600, 0.9)
        else
            love.graphics.setColor(0.984, 0.443, 0.522, 0.9)
        end
        love.graphics.circle("fill", com.x, com.y, 8)

        -- Label
        love.graphics.setColor(unpack(Theme.colors.text_dim))
        love.graphics.setFont(Theme.fonts().small)
        love.graphics.print("COM", com.x + 12, com.y - 6)
    end

    -- Contact point indicators
    for idx in pairs(active_contacts) do
        local jx, jy = skel:toScreen(skel.joints[idx])
        love.graphics.setColor(0.204, 0.827, 0.600, 0.3)
        love.graphics.circle("line", jx, jy, 14)
    end

    -- Sidebar
    self:drawSidebar(sw, sh)

    -- Stability meter
    if show_stability_meter then
        self:drawStabilityMeter(sw, sh)
    end

    Draw.formula("COM = (1/J) Σ_j p_j    Stable iff COM ∈ Support Polygon", 20, sh - 40)
end

function Section:drawStabilityMeter(sw, sh)
    local x = 20
    local y = sh - 100
    local w = sw * 0.55
    local h = 30

    love.graphics.setColor(unpack(Theme.colors.bg_surface))
    Theme.roundRect("fill", x, y, w, h, Theme.radius.sm)

    -- Stability bar
    local is_stable = stability > 0
    local bar_val = is_stable and math.min(stability / 50, 1) or 0

    if is_stable then
        love.graphics.setColor(0.204, 0.827, 0.600, 0.4)
    else
        love.graphics.setColor(0.984, 0.443, 0.522, 0.4)
    end
    love.graphics.rectangle("fill", x + 2, y + 2, (w - 4) * bar_val, h - 4, 2, 2)

    -- Label
    love.graphics.setColor(unpack(Theme.colors.text))
    love.graphics.setFont(Theme.fonts().mono)
    love.graphics.print(
        is_stable and string.format("STABLE  margin: %.1f px", stability) or "UNSTABLE — COM outside support polygon",
        x + 10, y + 8
    )
end

function Section:drawSidebar(sw, sh)
    local sidebar_x = sw * 0.65
    local sidebar_w = sw * 0.32
    local y = 80

    -- Info panel
    Draw.infoPanel(sidebar_x, y, sidebar_w, {
        {"COM X", com and string.format("%.1f", com.x) or "—"},
        {"COM Y", com and string.format("%.1f", com.y) or "—"},
        {"Contacts", tostring(#contact_points)},
        {"Stability", stability > 0 and string.format("%.1f px", stability) or "UNSTABLE"},
        {"Polygon Verts", tostring(#support_poly)},
    })
    y = y + 160

    -- Contact toggles
    love.graphics.setColor(unpack(Theme.colors.text))
    love.graphics.setFont(Theme.fonts().heading)
    love.graphics.print("Active Contacts", sidebar_x, y)
    y = y + 28

    local toggle_contacts = {
        {8, "L.Ankle"}, {9, "R.Ankle"},
        {11, "L.Foot"}, {12, "R.Foot"},
        {21, "L.Wrist"}, {22, "R.Wrist"},
        {16, "Head"},
    }

    for _, tc in ipairs(toggle_contacts) do
        local idx, name = tc[1], tc[2]
        local is_active = active_contacts[idx]
        local color = is_active and Theme.colors.success or Theme.colors.text_dim

        Widgets.button(sidebar_x, y, name,
            {w = sidebar_w / 2 - 4, color = color})
        y = y + 30
    end

    -- Teaching note
    y = sh - 160
    love.graphics.setColor(unpack(Theme.colors.text_muted))
    love.graphics.setFont(Theme.fonts().small)
    love.graphics.printf(
        "The center of mass (COM) must stay within the support polygon — " ..
        "the convex hull of all ground contact points — for the bboy to stay balanced. " ..
        "In a freeze, the support polygon is tiny (one hand), making balance hard. " ..
        "Drag joints to see how pose changes affect stability.",
        sidebar_x, y, sidebar_w, "left"
    )
end

function Section:mousepressed(x, y, button)
    if button ~= 1 then return end

    local sw = love.graphics.getWidth()
    local sidebar_x = sw * 0.65
    local sidebar_w = sw * 0.32

    -- Check contact toggle buttons
    local btn_y = 80 + 160 + 28
    local toggle_contacts = {8, 9, 11, 12, 21, 22, 16}
    for _, idx in ipairs(toggle_contacts) do
        if Widgets.buttonClicked(sidebar_x, btn_y, sidebar_w / 2 - 4, 28, x, y) then
            if active_contacts[idx] then
                active_contacts[idx] = nil
            else
                active_contacts[idx] = true
            end
            self:updatePhysics()
            return
        end
        btn_y = btn_y + 30
    end

    -- Check skeleton hit
    local hit = skel:hitTest(x, y, 18)
    if hit then
        dragging_joint = hit
        skel.selected_joint = hit
    end
end

function Section:mousereleased(x, y, button)
    if button == 1 then dragging_joint = nil end
end

function Section:mousemoved(x, y, dx, dy) end

function Section:keypressed(key)
    if key == "s" then show_support = not show_support
    elseif key == "t" then show_trail = not show_trail
    elseif key == "m" then show_stability_meter = not show_stability_meter
    elseif key == "c" then com_trail = {}
    end
end

function Section:unload()
    skel = nil
    com_trail = {}
end

return Section
