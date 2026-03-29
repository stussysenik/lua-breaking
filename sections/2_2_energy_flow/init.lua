--- Section 2.2: Kinetic Energy Flow
--- K(t) = (1/2) * m * Sigma ||v_j(t)||^2 visualized as flowing heat through skeleton.
--- High-energy limbs glow. Bar chart per body part. Energy timeline below.
---
--- Research bridge: experiments/components/energy_flow.py

local Theme = require("shell.theme")
local Draw = require("lib.draw")
local Skeleton = require("lib.skeleton")
local Widgets = require("lib.widgets")
local Vec = require("lib.vector")

local Section = {}
Section.__index = Section

Section.meta = {
    id = "2.2",
    title = "Kinetic Energy Flow",
    layer = "physics",
    description = "Energy flows through the skeleton like heat. Watch it transfer between body parts during movement.",
    research_mapping = "experiments/components/energy_flow.py",
    data_bridge = true,
    prerequisites = {"1.1", "2.1"},
}

local skel
local time = 0
local playing = true
local total_time = 4  -- seconds of simulation

--- Simulated energy per body part over time
local function bodyPartEnergy(part, t)
    -- Simulate a toprock-to-footwork transition
    -- Energy flows: arms → torso → legs → feet
    if part == "torso" then
        return 0.3 + 0.2 * math.sin(t * 2.5)
    elseif part == "left_arm" then
        return 0.5 + 0.4 * math.sin(t * 3.5 + 0.3)
    elseif part == "right_arm" then
        return 0.5 + 0.4 * math.sin(t * 3.5 + math.pi + 0.3)
    elseif part == "left_leg" then
        return 0.4 + 0.3 * math.sin(t * 2.5 + math.pi * 0.5)
    elseif part == "right_leg" then
        return 0.4 + 0.3 * math.sin(t * 2.5 + math.pi * 1.5)
    end
    return 0.2
end

local function totalEnergy(t)
    local sum = 0
    for _, part in ipairs({"torso", "left_arm", "right_arm", "left_leg", "right_leg"}) do
        sum = sum + bodyPartEnergy(part, t)
    end
    return sum
end

function Section:load()
    local sw, sh = love.graphics.getDimensions()
    local area_w = sw * 0.55
    local area_h = sh - 200
    local scale = math.min(area_w, area_h) * 0.85
    local ox = (area_w - scale) / 2 + 20
    local oy = 80

    skel = Skeleton.new(scale, ox, oy)
    skel.joint_radius = 8
    skel.bone_width = 5

    time = 0
    playing = true
end

function Section:update(dt)
    if not skel then return end

    if playing then
        time = time + dt
        if time >= total_time then time = time - total_time end
    end

    -- Color skeleton by energy
    skel.joint_colors = {}
    skel.bone_colors = {}

    for part, joints in pairs(Skeleton.BODY_PARTS) do
        local energy = bodyPartEnergy(part, time)
        local t = math.min(energy / 0.9, 1)

        -- Energy glow color: dark blue → orange → white
        local r, g, b
        if t < 0.5 then
            local s = t * 2
            r = 0.1 + s * 0.6
            g = 0.05 + s * 0.3
            b = 0.3 - s * 0.1
        else
            local s = (t - 0.5) * 2
            r = 0.7 + s * 0.3
            g = 0.35 + s * 0.55
            b = 0.2 + s * 0.3
        end

        for _, j in ipairs(joints) do
            skel.joint_colors[j] = {r, g, b, 0.6 + t * 0.4}
        end
    end
end

function Section:draw()
    local sw, sh = love.graphics.getDimensions()

    love.graphics.setColor(unpack(Theme.colors.bg))
    love.graphics.rectangle("fill", 0, 0, sw, sh)
    Draw.dotGrid(0, 0, sw, sh, 30, 1, {1, 1, 1, 0.02})

    Draw.titleBar(Section.meta.title, Section.meta.layer, Section.meta.id)

    -- Glow effect behind skeleton
    for j = 1, 24 do
        local col = skel.joint_colors[j]
        if col then
            local jx, jy = skel:toScreen(skel.joints[j])
            local energy = col[4] or 0.5
            love.graphics.setColor(col[1], col[2], col[3], energy * 0.1)
            love.graphics.circle("fill", jx, jy, 20 + energy * 15)
        end
    end

    -- Draw skeleton with thick glowing bones
    skel:draw()

    -- Energy timeline (bottom)
    self:drawEnergyTimeline(sw, sh)

    -- Sidebar: bar chart + controls
    self:drawSidebar(sw, sh)

    -- Formula
    Draw.formula("K(t) = (1/2) * m * Sigma ||v_j(t)||^2", 20, sh - 40)
end

function Section:drawEnergyTimeline(sw, sh)
    local x = 20
    local y = sh - 150
    local w = sw * 0.55 - 10
    local h = 80

    -- Background
    love.graphics.setColor(unpack(Theme.colors.bg_surface))
    Theme.roundRect("fill", x, y, w, h, Theme.radius.md)

    -- Draw energy curves for each body part
    local parts = {
        {"left_arm",  {0.984, 0.749, 0.141}},
        {"right_arm", {0.984, 0.443, 0.522}},
        {"torso",     {0.490, 0.827, 0.988}},
        {"left_leg",  {0.204, 0.827, 0.600}},
        {"right_leg", {0.655, 0.545, 0.980}},
    }

    for _, part_info in ipairs(parts) do
        local part_name, color = part_info[1], part_info[2]
        love.graphics.setColor(color[1], color[2], color[3], 0.5)

        local points = {}
        for px = 0, w - 8 do
            local t = (px / (w - 8)) * total_time
            local energy = bodyPartEnergy(part_name, t)
            table.insert(points, x + 4 + px)
            table.insert(points, y + h - 8 - energy * (h - 16))
        end
        if #points >= 4 then
            love.graphics.setLineWidth(1.5)
            love.graphics.line(points)
        end
    end

    -- Playhead
    local progress = time / total_time
    local px = x + 4 + (w - 8) * progress
    love.graphics.setColor(unpack(Theme.colors.text))
    love.graphics.line(px, y + 4, px, y + h - 4)

    -- Total energy
    love.graphics.setColor(unpack(Theme.colors.text_muted))
    love.graphics.setFont(Theme.fonts().small)
    love.graphics.print(
        string.format("K(t) = %.2f", totalEnergy(time)),
        x + 8, y + 4
    )

    love.graphics.setLineWidth(1)
end

function Section:drawSidebar(sw, sh)
    local sidebar_x = sw * 0.58
    local sidebar_w = sw * 0.40
    local y = 80

    -- Bar chart: energy per body part
    love.graphics.setColor(unpack(Theme.colors.text))
    love.graphics.setFont(Theme.fonts().heading)
    love.graphics.print("Energy by Body Part", sidebar_x, y)
    y = y + 30

    local parts = {
        {"Left Arm",  "left_arm",  {0.984, 0.749, 0.141}},
        {"Right Arm", "right_arm", {0.984, 0.443, 0.522}},
        {"Torso",     "torso",     {0.490, 0.827, 0.988}},
        {"Left Leg",  "left_leg",  {0.204, 0.827, 0.600}},
        {"Right Leg", "right_leg", {0.655, 0.545, 0.980}},
    }

    local bar_max_w = sidebar_w - 100
    local bar_h = 20

    for _, part_info in ipairs(parts) do
        local label, part_name, color = part_info[1], part_info[2], part_info[3]
        local energy = bodyPartEnergy(part_name, time)
        local bar_w = energy * bar_max_w

        -- Label
        love.graphics.setColor(unpack(Theme.colors.text_dim))
        love.graphics.setFont(Theme.fonts().small)
        love.graphics.print(label, sidebar_x, y + 3)

        -- Bar background
        love.graphics.setColor(unpack(Theme.colors.border))
        love.graphics.rectangle("fill", sidebar_x + 80, y, bar_max_w, bar_h, 3, 3)

        -- Bar fill
        love.graphics.setColor(color[1], color[2], color[3], 0.6)
        love.graphics.rectangle("fill", sidebar_x + 80, y, bar_w, bar_h, 3, 3)

        -- Value
        love.graphics.setColor(unpack(Theme.colors.text))
        love.graphics.setFont(Theme.fonts().mono)
        love.graphics.print(string.format("%.2f", energy), sidebar_x + 80 + bar_max_w + 8, y + 2)

        y = y + bar_h + 8
    end

    -- Total
    y = y + 8
    love.graphics.setColor(unpack(Theme.colors.text_muted))
    love.graphics.line(sidebar_x + 80, y, sidebar_x + 80 + bar_max_w, y)
    y = y + 8

    love.graphics.setColor(unpack(Theme.colors.text))
    love.graphics.setFont(Theme.fonts().body)
    love.graphics.print("Total K(t)", sidebar_x, y)
    love.graphics.setFont(Theme.fonts().mono)
    love.graphics.print(string.format("%.2f", totalEnergy(time)), sidebar_x + 80 + bar_max_w + 8, y)

    y = y + 50

    -- Play/Pause
    Widgets.button(sidebar_x, y, playing and "Pause" or "Play",
        {w = 100, color = Theme.colors.physics})

    -- Teaching
    y = sh - 200
    love.graphics.setColor(unpack(Theme.colors.text_muted))
    love.graphics.setFont(Theme.fonts().small)
    love.graphics.printf(
        "Kinetic energy K(t) is the sum of squared velocities across all joints. " ..
        "It measures total movement intensity at each moment. Watch how energy " ..
        "transfers between body parts during transitions — arms swing to generate " ..
        "momentum, then energy flows into the legs for footwork.",
        sidebar_x, y, sidebar_w, "left"
    )
end

function Section:mousepressed(x, y, button)
    if button ~= 1 then return end

    local sw, sh = love.graphics.getDimensions()
    local sidebar_x = sw * 0.58

    -- Timeline click
    local tl_x, tl_y, tl_w = 20, sh - 150, sw * 0.55 - 10
    if x >= tl_x and x <= tl_x + tl_w and y >= tl_y and y <= tl_y + 80 then
        local progress = (x - tl_x) / tl_w
        time = progress * total_time
        return
    end

    -- Play/pause button
    local btn_y = 80 + 30 + 5 * 28 + 8 + 8 + 50 + 8
    if Widgets.buttonClicked(sidebar_x, btn_y, 100, 32, x, y) then
        playing = not playing
    end
end

function Section:mousereleased(x, y, button) end
function Section:mousemoved(x, y, dx, dy) end

function Section:keypressed(key)
    if key == "space" then playing = not playing end
end

function Section:unload()
    skel = nil
end

return Section
