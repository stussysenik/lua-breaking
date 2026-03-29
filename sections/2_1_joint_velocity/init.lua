--- Section 2.1: Joint Velocity Vectors
--- Skeleton with per-joint velocity arrows. Color-coded by speed.
--- Timeline scrubber to see velocity evolve over time.
--- Data bridge: frames[t].velocity from exported JSON.
---
--- Research bridge: experiments/world_state.py:per_joint_velocity()

local Theme = require("shell.theme")
local Draw = require("lib.draw")
local Skeleton = require("lib.skeleton")
local Widgets = require("lib.widgets")
local Vec = require("lib.vector")

local Section = {}
Section.__index = Section

Section.meta = {
    id = "2.1",
    title = "Joint Velocity Vectors",
    layer = "physics",
    description = "Per-joint velocity arrows showing speed and direction. Scrub the timeline to see motion evolve.",
    research_mapping = "experiments/world_state.py:per_joint_velocity()",
    data_bridge = true,
    prerequisites = {"1.1"},
}

local skel
local time = 0
local playing = true
local playback_speed = 1.0
local velocity_scale = 80
local show_trails = true
local trail_length = 10

--- Generate simulated motion data (a bboy doing toprock)
--- In real use, this would come from the data bridge
local frames = {}
local total_frames = 120
local fps = 30

local function generateDemoMotion()
    frames = {}
    -- Simulate a simple toprock motion: weight shift side to side
    for f = 0, total_frames - 1 do
        local t = f / fps
        local frame = {joints = {}, velocities = {}}

        for j = 1, 24 do
            -- Base position from default pose
            local bx = ({
                0.50, 0.46, 0.54, 0.50, 0.44, 0.56, 0.50, 0.43, 0.57,
                0.50, 0.43, 0.57, 0.50, 0.46, 0.54, 0.50, 0.40, 0.60,
                0.34, 0.66, 0.30, 0.70, 0.29, 0.71
            })[j]
            local by = ({
                0.45, 0.48, 0.48, 0.38, 0.60, 0.60, 0.32, 0.74, 0.74,
                0.26, 0.78, 0.78, 0.20, 0.23, 0.23, 0.14, 0.24, 0.24,
                0.34, 0.34, 0.44, 0.44, 0.46, 0.46
            })[j]

            -- Apply toprock motion (lateral sway + arm swing)
            local sway = math.sin(t * 3.5) * 0.04
            local arm_swing = math.sin(t * 3.5 + math.pi * 0.3) * 0.06
            local bounce = math.sin(t * 7) * 0.01

            local part = skel and skel:bodyPartOf(j) or "torso"
            local dx, dy = 0, 0

            if part == "torso" then
                dx = sway
                dy = bounce
            elseif part == "left_arm" then
                dx = sway + arm_swing * 0.8
                dy = bounce - arm_swing * 0.3
            elseif part == "right_arm" then
                dx = sway - arm_swing * 0.8
                dy = bounce + arm_swing * 0.3
            elseif part == "left_leg" then
                dx = sway * 0.5
                dy = bounce * 0.5 + math.sin(t * 3.5 + 0.5) * 0.02
            elseif part == "right_leg" then
                dx = sway * 0.5
                dy = bounce * 0.5 - math.sin(t * 3.5 + 0.5) * 0.02
            end

            frame.joints[j] = Vec.new(bx + dx, by + dy)
        end

        -- Compute velocities from finite differences
        if f > 0 then
            local prev = frames[f]  -- previous frame (1-indexed, so frames[f] is frame f-1)
            for j = 1, 24 do
                local vx = (frame.joints[j].x - prev.joints[j].x) * fps
                local vy = (frame.joints[j].y - prev.joints[j].y) * fps
                frame.velocities[j] = Vec.new(vx, vy)
            end
        else
            for j = 1, 24 do
                frame.velocities[j] = Vec.new(0, 0)
            end
        end

        frames[f + 1] = frame
    end
end

--- Position trails
local trails = {}

function Section:load()
    local sw, sh = love.graphics.getDimensions()
    local area_w = sw * 0.65
    local area_h = sh - 140
    local scale = math.min(area_w, area_h) * 0.85
    local ox = (area_w - scale) / 2
    local oy = 80

    skel = Skeleton.new(scale, ox, oy)
    skel.show_labels = false
    skel.joint_radius = 5

    generateDemoMotion()

    time = 0
    playing = true
    trails = {}
    for j = 1, 24 do trails[j] = {} end
end

function Section:update(dt)
    if not skel or #frames == 0 then return end

    -- Advance time
    if playing then
        time = time + dt * playback_speed
        if time >= total_frames / fps then
            time = 0
            for j = 1, 24 do trails[j] = {} end
        end
    end

    -- Get current frame
    local frame_idx = math.floor(time * fps) + 1
    frame_idx = math.max(1, math.min(#frames, frame_idx))
    local frame = frames[frame_idx]

    -- Update skeleton positions
    skel:setJoints(frame.joints)

    -- Update trails
    if show_trails then
        for j = 1, 24 do
            local pos = frame.joints[j]
            local sx, sy = skel:toScreen(pos)
            table.insert(trails[j], {x = sx, y = sy})
            while #trails[j] > trail_length do
                table.remove(trails[j], 1)
            end
        end
    end

    -- Color joints by velocity magnitude
    skel.joint_colors = {}
    local max_speed = 0
    for j = 1, 24 do
        local v = frame.velocities[j]
        local speed = v:len()
        if speed > max_speed then max_speed = speed end
    end

    for j = 1, 24 do
        local v = frame.velocities[j]
        local speed = v:len()
        local t = max_speed > 0 and (speed / max_speed) or 0
        local r, g, b = Draw.speedColor(t)
        skel.joint_colors[j] = {r, g, b, 0.9}
    end
end

function Section:draw()
    local sw, sh = love.graphics.getDimensions()

    love.graphics.setColor(unpack(Theme.colors.bg))
    love.graphics.rectangle("fill", 0, 0, sw, sh)
    Draw.dotGrid(0, 0, sw, sh, 30, 1, {1, 1, 1, 0.02})

    Draw.titleBar(Section.meta.title, Section.meta.layer, Section.meta.id)

    -- Draw trails
    if show_trails then
        for j = 1, 24 do
            local trail = trails[j]
            if #trail >= 2 then
                for i = 2, #trail do
                    local alpha = (i / #trail) * 0.15
                    local col = skel.joint_colors[j] or {1, 1, 1}
                    love.graphics.setColor(col[1], col[2], col[3], alpha)
                    love.graphics.line(trail[i-1].x, trail[i-1].y, trail[i].x, trail[i].y)
                end
            end
        end
    end

    -- Draw skeleton
    skel:draw()

    -- Draw velocity arrows
    local frame_idx = math.floor(time * fps) + 1
    frame_idx = math.max(1, math.min(#frames, frame_idx))
    local frame = frames[frame_idx]

    local max_speed = 0
    for j = 1, 24 do
        local speed = frame.velocities[j]:len()
        if speed > max_speed then max_speed = speed end
    end

    for j = 1, 24 do
        local pos = frame.joints[j]
        local vel = frame.velocities[j]
        local jx, jy = skel:toScreen(pos)
        local speed = vel:len()

        if speed > 0.01 then
            local t = max_speed > 0 and (speed / max_speed) or 0
            local r, g, b = Draw.speedColor(t)
            love.graphics.setColor(r, g, b, 0.7)
            Draw.vector(jx, jy, vel.x * velocity_scale, vel.y * velocity_scale, 1, 50)
        end
    end

    -- Timeline bar
    self:drawTimeline(sw, sh)

    -- Sidebar
    self:drawSidebar(sw, sh)

    -- Color ramp legend
    Draw.colorRamp(20, sh - 60, 150, 8, Draw.speedColor, "Still", "Fast")

    -- Formula
    Draw.formula("v_j(t) = (p_j(t) - p_j(t-1)) * fps", 200, sh - 40)
end

function Section:drawTimeline(sw, sh)
    local bar_x = 20
    local bar_y = sh - 85
    local bar_w = sw * 0.63
    local bar_h = 20

    -- Background
    love.graphics.setColor(0.06, 0.06, 0.09, 0.9)
    Theme.roundRect("fill", bar_x, bar_y - 4, bar_w, bar_h + 8, Theme.radius.sm)

    -- Progress
    local progress = time / (total_frames / fps)
    love.graphics.setColor(0.984, 0.749, 0.141, 0.3)
    love.graphics.rectangle("fill", bar_x + 2, bar_y, (bar_w - 4) * progress, bar_h, 2, 2)

    -- Playhead
    local px = bar_x + 2 + (bar_w - 4) * progress
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.rectangle("fill", px - 1, bar_y - 4, 3, bar_h + 8, 1, 1)

    -- Time label
    love.graphics.setColor(1, 1, 1, 0.5)
    love.graphics.setFont(Theme.fonts().mono)
    love.graphics.print(
        string.format("%.2fs / %.2fs  [%s]", time, total_frames / fps, playing and "playing" or "paused"),
        bar_x + bar_w + 10, bar_y
    )
end

function Section:drawSidebar(sw, sh)
    local sidebar_x = sw * 0.67
    local sidebar_w = sw * 0.30
    local y = 80

    -- Kinetic energy display
    local frame_idx = math.floor(time * fps) + 1
    frame_idx = math.max(1, math.min(#frames, frame_idx))
    local frame = frames[frame_idx]

    local total_ke = 0
    for j = 1, 24 do
        local speed = frame.velocities[j]:len()
        total_ke = total_ke + speed * speed
    end

    Draw.infoPanel(sidebar_x, y, sidebar_w, {
        {"Frame", frame_idx},
        {"Time", string.format("%.2f s", time)},
        {"K(t)", string.format("%.2f", total_ke)},
        {"Max Joint Speed", string.format("%.3f", math.sqrt(total_ke / 24))},
    })
    y = y + 130

    -- Controls
    y = y + 10
    local new_speed, speed_changed = Widgets.slider(
        sidebar_x, y, sidebar_w, playback_speed,
        "Playback Speed",
        {min = 0.1, max = 3, format = "%.1fx"}
    )
    if speed_changed then playback_speed = new_speed end
    y = y + 48

    local new_vscale, vs_changed = Widgets.slider(
        sidebar_x, y, sidebar_w, velocity_scale,
        "Arrow Scale",
        {min = 20, max = 200, format = "%.0f"}
    )
    if vs_changed then velocity_scale = new_vscale end
    y = y + 48

    local new_trail, trail_changed = Widgets.slider(
        sidebar_x, y, sidebar_w, trail_length,
        "Trail Length",
        {min = 0, max = 60, format = "%.0f frames"}
    )
    if trail_changed then trail_length = math.floor(new_trail) end
    y = y + 58

    -- Play/Pause button
    Widgets.button(sidebar_x, y, playing and "Pause" or "Play",
        {w = sidebar_w / 2 - 4, color = Theme.colors.physics})
    Widgets.button(sidebar_x + sidebar_w / 2 + 4, y, "Reset",
        {w = sidebar_w / 2 - 4, color = Theme.colors.text_dim})

    -- Teaching note
    y = sh - 140
    love.graphics.setColor(1, 1, 1, 0.15)
    love.graphics.setFont(Theme.fonts().small)
    love.graphics.printf(
        "Joint velocity is the foundation of all motion analysis in bboy-analytics. " ..
        "Each arrow shows the speed and direction of a joint. The color ramp goes from " ..
        "blue (still) through yellow to red (fastest). Kinetic energy K(t) is the sum " ..
        "of all squared velocities — it measures total movement intensity.",
        sidebar_x, y, sidebar_w, "left"
    )
end

function Section:mousepressed(x, y, button)
    if button ~= 1 then return end

    local sw, sh = love.graphics.getDimensions()
    local sidebar_x = sw * 0.67
    local sidebar_w = sw * 0.30

    -- Timeline click
    local bar_x, bar_y, bar_w = 20, sh - 85, sw * 0.63
    if x >= bar_x and x <= bar_x + bar_w and y >= bar_y - 10 and y <= bar_y + 30 then
        local progress = (x - bar_x) / bar_w
        time = progress * (total_frames / fps)
        return
    end

    -- Play/Pause button
    local btn_y = 80 + 130 + 10 + 48 * 2 + 58
    if Widgets.buttonClicked(sidebar_x, btn_y, sidebar_w / 2 - 4, 32, x, y) then
        playing = not playing
        return
    end
    -- Reset button
    if Widgets.buttonClicked(sidebar_x + sidebar_w / 2 + 4, btn_y, sidebar_w / 2 - 4, 32, x, y) then
        time = 0
        for j = 1, 24 do trails[j] = {} end
        return
    end
end

function Section:mousereleased(x, y, button) end
function Section:mousemoved(x, y, dx, dy) end

function Section:keypressed(key)
    if key == "space" then
        playing = not playing
    elseif key == "r" then
        time = 0
        for j = 1, 24 do trails[j] = {} end
    elseif key == "t" then
        show_trails = not show_trails
    end
end

function Section:unload()
    skel = nil
    frames = {}
    trails = {}
end

return Section
