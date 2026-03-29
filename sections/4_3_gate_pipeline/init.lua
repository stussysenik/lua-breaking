--- Section 4.3: Validation Gate Pipeline
--- Frames flow through 5 validation gates used in bboy-analytics to determine
--- if 3D pose reconstruction is trustworthy.
--- Each gate filters out frames that fail a specific quality check.
--- Particles (representing video frames) animate left-to-right through the pipeline;
--- rejected frames turn red and fall away.
--- Research bridge: experiments/evaluate_powermove_gates.py

local Theme = require("shell.theme")
local Draw  = require("lib.draw")
local Widgets = require("lib.widgets")

local Section = {}
Section.__index = Section

Section.meta = {
    id = "4.3",
    title = "Validation Gate Pipeline",
    layer = "cv",
    description = "Frames flow through 5 validation gates: application \226\134\146 extraction \226\134\146 placement \226\134\146 pose \226\134\146 viability",
    research_mapping = "experiments/evaluate_powermove_gates.py",
    data_bridge = true,
    prerequisites = {"1.1"},
}

-------------------------------------------------------------------------------
-- Gate definitions
-------------------------------------------------------------------------------

local GATES = {
    {
        name       = "APPLICATION",
        short      = "APP",
        question   = "Was the model actually run on this frame?",
        check      = "Output file exists for frame",
        thresholds = {"output_path exists", "file size > 0 bytes"},
        logic      = "os.path.exists(output_npy)",
        pass_rate  = 0.96,  -- simulated base pass rate
        color_pass = {0.204, 0.827, 0.600},  -- green
        color_fail = {0.984, 0.443, 0.522},  -- red
    },
    {
        name       = "EXTRACTION",
        short      = "EXT",
        question   = "Did the pipeline extract valid joint data?",
        check      = "joints.npy has valid numbers",
        thresholds = {"no NaN values", "no Inf values", "shape == (J, 3)"},
        logic      = "~np.isnan(joints).any() and joints.shape == (24, 3)",
        pass_rate  = 0.89,
        color_pass = {0.204, 0.827, 0.600},
        color_fail = {0.984, 0.443, 0.522},
    },
    {
        name       = "PLACEMENT",
        short      = "PLC",
        question   = "Is the skeleton placed correctly in world space?",
        check      = "Root height > 0, not underground",
        thresholds = {"root_y > 0.0", "root_y < 3.0 meters", "feet near ground"},
        logic      = "0 < root_height < 3.0 and min(foot_y) > -0.1",
        pass_rate  = 0.82,
        color_pass = {0.204, 0.827, 0.600},
        color_fail = {0.984, 0.443, 0.522},
    },
    {
        name       = "POSE",
        short      = "PSE",
        question   = "Are joint angles physically plausible?",
        check      = "Bone lengths consistent, no self-intersection",
        thresholds = {"bone_len_std < 0.15", "no self-intersection", "angle limits respected"},
        logic      = "bone_length_variance < threshold and no_collision(joints)",
        pass_rate  = 0.78,
        color_pass = {0.204, 0.827, 0.600},
        color_fail = {0.984, 0.443, 0.522},
    },
    {
        name       = "VIABILITY",
        short      = "VIA",
        question   = "Is the reconstruction usable for analysis?",
        check      = "Confidence > threshold, motion smooth",
        thresholds = {"confidence > 0.6", "jerk < 500 m/s\194\179", "temporal consistency"},
        logic      = "confidence > 0.6 and jerk(traj) < 500",
        pass_rate  = 0.72,
        color_pass = {0.204, 0.827, 0.600},
        color_fail = {0.984, 0.443, 0.522},
    },
}

-------------------------------------------------------------------------------
-- Particle system for frame flow
-------------------------------------------------------------------------------

-- Each particle: {x, y, vx, vy, stage, alive, rejected, reject_gate, alpha,
--                 trail, birth_time, radius, color}
-- stage: which gate the particle is currently approaching (1-5), 6 = passed all
-- trail: array of {x, y, alpha} for afterimage effect

local particles = {}
local spawn_timer = 0
local spawn_interval = 0.18  -- seconds between new particles
local time_elapsed = 0

-- Gate layout computed in load()
local gate_rects = {}   -- {x, y, w, h} for each gate
local pipeline_y = 0
local pipeline_x_start = 0
local pipeline_x_end = 0
local gate_w = 0
local gate_h = 0
local gate_spacing = 0

-- Counters
local gate_pass_counts = {0, 0, 0, 0, 0}
local gate_fail_counts = {0, 0, 0, 0, 0}
local total_spawned = 0

-- Interaction
local expanded_gate = nil   -- index of gate currently expanded (clicked)
local hovered_gate = nil
local speed_mult = 1.0
local show_research = false
local particle_speed = 160  -- pixels per second base speed

-- Glow animation phase per gate
local gate_glow_phase = {0, 0, 0, 0, 0}

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

--- Ease-out cubic
local function ease_out(t)
    t = t - 1
    return t * t * t + 1
end

--- Create a new particle at the left edge of the pipeline
local function spawn_particle()
    local p = {
        x          = pipeline_x_start - 20,
        y          = pipeline_y + gate_h / 2,
        vx         = particle_speed * (0.9 + math.random() * 0.2),
        vy         = 0,
        stage      = 1,            -- approaching gate 1
        alive      = true,
        rejected   = false,
        reject_gate = 0,
        alpha      = 1.0,
        trail      = {},
        birth_time = time_elapsed,
        radius     = 3 + math.random() * 1.5,
        color      = {0.490, 0.827, 0.988},  -- sky blue (neutral frame)
        decided    = {},           -- {[gate_index] = true} means decision made
    }
    -- Pre-roll pass/fail decisions for each gate using the gate's pass rate
    -- But only if the particle reaches that gate (cumulative)
    p.will_pass = {}
    local still_alive = true
    for i = 1, 5 do
        if still_alive then
            local r = math.random()
            p.will_pass[i] = (r < GATES[i].pass_rate)
            if not p.will_pass[i] then
                still_alive = false
            end
        else
            p.will_pass[i] = false
        end
    end
    return p
end

--- Get the x-position of the "decision line" for a gate (center of gate box)
local function gate_decision_x(gate_idx)
    local rect = gate_rects[gate_idx]
    if not rect then return 0 end
    return rect.x + rect.w / 2
end

--- Get the x-position just past a gate (exit side)
local function gate_exit_x(gate_idx)
    local rect = gate_rects[gate_idx]
    if not rect then return 0 end
    return rect.x + rect.w + 4
end

-------------------------------------------------------------------------------
-- Section interface
-------------------------------------------------------------------------------

function Section:load()
    local sw, sh = love.graphics.getDimensions()

    -- Layout the pipeline horizontally, leaving room for title and bottom bar
    local margin_x = 60
    local title_h = 60
    pipeline_y = title_h + 80
    gate_h = 100
    local usable_w = sw - margin_x * 2
    gate_spacing = 24
    gate_w = (usable_w - gate_spacing * 4) / 5
    pipeline_x_start = margin_x
    pipeline_x_end = sw - margin_x

    gate_rects = {}
    for i = 1, 5 do
        gate_rects[i] = {
            x = margin_x + (i - 1) * (gate_w + gate_spacing),
            y = pipeline_y,
            w = gate_w,
            h = gate_h,
        }
    end

    -- Reset state
    particles = {}
    spawn_timer = 0
    time_elapsed = 0
    gate_pass_counts = {0, 0, 0, 0, 0}
    gate_fail_counts = {0, 0, 0, 0, 0}
    total_spawned = 0
    expanded_gate = nil
    hovered_gate = nil
    speed_mult = 1.0
    show_research = false
    gate_glow_phase = {0, 0, 0, 0, 0}
end

function Section:update(dt)
    local adt = dt * speed_mult  -- adjusted delta time
    time_elapsed = time_elapsed + adt

    -- Update glow phases
    for i = 1, 5 do
        gate_glow_phase[i] = gate_glow_phase[i] + dt * (1.5 + i * 0.2)
    end

    -- Spawn new particles
    spawn_timer = spawn_timer + adt
    if spawn_timer >= spawn_interval then
        spawn_timer = spawn_timer - spawn_interval
        local p = spawn_particle()
        particles[#particles + 1] = p
        total_spawned = total_spawned + 1
    end

    -- Update particles
    local sw, sh = love.graphics.getDimensions()
    local removal = {}

    for idx, p in ipairs(particles) do
        if p.alive then
            -- Record trail position (before movement)
            if #p.trail == 0 or
               (p.trail[#p.trail] and
                math.abs(p.x - p.trail[#p.trail].x) > 3) then
                p.trail[#p.trail + 1] = {x = p.x, y = p.y, alpha = 0.6}
                -- Cap trail length
                if #p.trail > 14 then
                    table.remove(p.trail, 1)
                end
            end

            if p.rejected then
                -- Rejected particle: fall down and fade
                p.vy = p.vy + 320 * adt  -- gravity
                p.x = p.x + p.vx * 0.3 * adt
                p.y = p.y + p.vy * adt
                p.alpha = p.alpha - 1.2 * adt
                if p.alpha <= 0 or p.y > sh + 20 then
                    p.alive = false
                end
            else
                -- Moving forward through the pipeline
                p.x = p.x + p.vx * adt

                -- Check if particle has reached the decision point of its current gate
                if p.stage >= 1 and p.stage <= 5 then
                    local dx = gate_decision_x(p.stage)
                    if p.x >= dx and not p.decided[p.stage] then
                        p.decided[p.stage] = true
                        if p.will_pass[p.stage] then
                            -- Pass: count it, advance stage
                            gate_pass_counts[p.stage] = gate_pass_counts[p.stage] + 1
                            p.color = GATES[p.stage].color_pass
                        else
                            -- Fail: reject the particle
                            gate_fail_counts[p.stage] = gate_fail_counts[p.stage] + 1
                            p.rejected = true
                            p.reject_gate = p.stage
                            p.color = GATES[p.stage].color_fail
                            p.vy = -40 - math.random() * 30  -- slight upward pop
                            p.vx = p.vx * 0.4
                        end
                    end
                    -- Advance stage once past the gate exit
                    if not p.rejected and p.x >= gate_exit_x(p.stage) and p.decided[p.stage] then
                        p.stage = p.stage + 1
                    end
                end

                -- Particle has cleared all gates
                if p.stage > 5 then
                    -- Fade out on the right
                    if p.x > pipeline_x_end + 40 then
                        p.alpha = p.alpha - 2.0 * adt
                        if p.alpha <= 0 then
                            p.alive = false
                        end
                    end
                end
            end

            -- Fade trail
            for ti = #p.trail, 1, -1 do
                p.trail[ti].alpha = p.trail[ti].alpha - 1.8 * adt
                if p.trail[ti].alpha <= 0 then
                    table.remove(p.trail, ti)
                end
            end
        else
            removal[#removal + 1] = idx
        end
    end

    -- Remove dead particles (iterate backwards)
    for i = #removal, 1, -1 do
        table.remove(particles, removal[i])
    end

    -- Determine hovered gate
    local mx, my = love.mouse.getPosition()
    hovered_gate = nil
    for i = 1, 5 do
        local r = gate_rects[i]
        if mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h then
            hovered_gate = i
            break
        end
    end
end

function Section:draw()
    local sw, sh = love.graphics.getDimensions()

    -- Background
    love.graphics.setColor(unpack(Theme.colors.bg))
    love.graphics.rectangle("fill", 0, 0, sw, sh)
    Draw.dotGrid(0, 0, sw, sh, 30, 1, {1, 1, 1, 0.02})

    -- Title bar
    Draw.titleBar(Section.meta.title, Section.meta.layer, Section.meta.id)

    -- Pipeline connector line (behind gates)
    self:drawPipelineConnector(sw, sh)

    -- Draw particle trails and particles (behind gates so gates overlay)
    self:drawParticles()

    -- Draw gates
    for i = 1, 5 do
        self:drawGate(i)
    end

    -- Draw counters below gates
    self:drawCounters()

    -- Draw expanded gate detail panel
    if expanded_gate then
        self:drawExpandedGate(expanded_gate, sw, sh)
    end

    -- Draw sidebar / bottom info
    self:drawBottomBar(sw, sh)

    -- Speed slider
    local slider_x = sw - 240
    local slider_y = 68
    speed_mult = Widgets.slider(slider_x, slider_y, 180, speed_mult, "Speed", {
        min = 0.2, max = 3.0, format = "%.1fx",
        color = Theme.colors.cv,
    })

    -- Research mapping toggle
    local btn_x = 20
    local btn_y = sh - 80
    Widgets.button(btn_x, btn_y, show_research and "Hide Research Mapping" or "Show Research Mapping", {
        w = 200,
        color = Theme.colors.cv,
    })

    if show_research then
        self:drawResearchMapping(sw, sh)
    end

    -- Formula
    Draw.formula(
        "viable_frames = frames[app & ext & plc & pse & via]  -- cumulative gate filter",
        20, sh - 40
    )
end

-------------------------------------------------------------------------------
-- Drawing sub-routines
-------------------------------------------------------------------------------

function Section:drawPipelineConnector(sw, sh)
    local cy = pipeline_y + gate_h / 2

    -- Main connector line
    love.graphics.setLineWidth(2)
    love.graphics.setColor(unpack(Theme.colors.border))
    love.graphics.line(pipeline_x_start - 30, cy, pipeline_x_end + 30, cy)

    -- Arrow heads between gates
    for i = 1, 4 do
        local x1 = gate_rects[i].x + gate_rects[i].w
        local x2 = gate_rects[i + 1].x
        local mx = (x1 + x2) / 2

        love.graphics.setColor(unpack(Theme.colors.border))
        -- Small chevron
        love.graphics.line(mx - 4, cy - 5, mx + 4, cy, mx - 4, cy + 5)
    end

    -- Entry arrow on left
    love.graphics.setColor(unpack(Theme.colors.text_muted))
    love.graphics.setFont(Theme.fonts().small)
    love.graphics.print("FRAMES IN", pipeline_x_start - 30, cy - 22)
    Draw.arrow(pipeline_x_start - 30, cy, pipeline_x_start - 8, cy, 5, 1.5)

    -- Exit arrow on right
    love.graphics.setColor(Theme.colors.success[1], Theme.colors.success[2], Theme.colors.success[3], 0.3)
    love.graphics.print("VIABLE", pipeline_x_end + 8, cy - 22)
    Draw.arrow(pipeline_x_end + 8, cy, pipeline_x_end + 30, cy, 5, 1.5)

    love.graphics.setLineWidth(1)
end

function Section:drawGate(i)
    local gate = GATES[i]
    local r = gate_rects[i]
    local is_hovered = (hovered_gate == i)
    local is_expanded = (expanded_gate == i)

    -- Compute aggregate pass rate for this gate from counters
    local total = gate_pass_counts[i] + gate_fail_counts[i]
    local pass_pct = total > 0 and (gate_pass_counts[i] / total) or gate.pass_rate
    local is_healthy = pass_pct > 0.5

    -- Gate glow effect (subtle pulsing border)
    local glow_alpha = 0.04 + 0.03 * math.sin(gate_glow_phase[i])
    local glow_color = is_healthy and gate.color_pass or gate.color_fail

    -- Outer glow (expanded radius)
    if is_hovered or is_expanded then
        love.graphics.setColor(glow_color[1], glow_color[2], glow_color[3], glow_alpha * 2.5)
        Theme.roundRect("fill", r.x - 4, r.y - 4, r.w + 8, r.h + 8, Theme.radius.lg + 2)
    end

    -- Gate background
    local bg_alpha = is_expanded and 0.18 or (is_hovered and 0.12 or 0.08)
    love.graphics.setColor(glow_color[1], glow_color[2], glow_color[3], bg_alpha)
    Theme.roundRect("fill", r.x, r.y, r.w, r.h, Theme.radius.lg)

    -- Gate border with glow
    local border_alpha = is_expanded and 0.5 or (is_hovered and 0.35 or 0.15)
    love.graphics.setColor(glow_color[1], glow_color[2], glow_color[3],
        border_alpha + glow_alpha)
    love.graphics.setLineWidth(is_expanded and 2 or 1)
    Theme.roundRect("line", r.x, r.y, r.w, r.h, Theme.radius.lg)
    love.graphics.setLineWidth(1)

    -- Gate number badge
    local badge_x = r.x + 8
    local badge_y = r.y + 8
    love.graphics.setColor(glow_color[1], glow_color[2], glow_color[3], 0.25)
    love.graphics.circle("fill", badge_x + 10, badge_y + 10, 12)
    love.graphics.setColor(unpack(Theme.colors.text))
    love.graphics.setFont(Theme.fonts().body)
    local num_str = tostring(i)
    local nw = Theme.fonts().body:getWidth(num_str)
    love.graphics.print(num_str, badge_x + 10 - nw / 2, badge_y + 3)

    -- Gate name
    love.graphics.setColor(unpack(Theme.colors.text))
    love.graphics.setFont(Theme.fonts().heading)
    local name_w = Theme.fonts().heading:getWidth(gate.name)
    love.graphics.print(gate.name, r.x + (r.w - name_w) / 2, r.y + 30)

    -- Short question
    love.graphics.setColor(unpack(Theme.colors.text_dim))
    love.graphics.setFont(Theme.fonts().small)
    love.graphics.printf(gate.check, r.x + 8, r.y + 52, r.w - 16, "center")

    -- Pass rate indicator bar at bottom
    local bar_h = 4
    local bar_y = r.y + r.h - bar_h - 6
    local bar_x = r.x + 8
    local bar_w = r.w - 16

    -- Background bar
    love.graphics.setColor(unpack(Theme.colors.border))
    love.graphics.rectangle("fill", bar_x, bar_y, bar_w, bar_h, 2, 2)

    -- Fill bar
    local fill_w = bar_w * pass_pct
    love.graphics.setColor(glow_color[1], glow_color[2], glow_color[3], 0.6)
    love.graphics.rectangle("fill", bar_x, bar_y, fill_w, bar_h, 2, 2)

    -- Pass rate text
    love.graphics.setColor(unpack(Theme.colors.text_dim))
    love.graphics.setFont(Theme.fonts().small)
    local pct_str = string.format("%.0f%%", pass_pct * 100)
    local pct_w = Theme.fonts().small:getWidth(pct_str)
    love.graphics.print(pct_str, r.x + r.w - pct_w - 8, r.y + 8)
end

function Section:drawCounters()
    love.graphics.setFont(Theme.fonts().small)
    for i = 1, 5 do
        local r = gate_rects[i]
        local cy = r.y + r.h + 12

        -- Pass count
        love.graphics.setColor(Theme.colors.success[1], Theme.colors.success[2],
            Theme.colors.success[3], 0.7)
        local pass_str = string.format("pass: %d", gate_pass_counts[i])
        love.graphics.print(pass_str, r.x + 4, cy)

        -- Fail count
        love.graphics.setColor(Theme.colors.error[1], Theme.colors.error[2],
            Theme.colors.error[3], 0.7)
        local fail_str = string.format("fail: %d", gate_fail_counts[i])
        local fw = Theme.fonts().small:getWidth(fail_str)
        love.graphics.print(fail_str, r.x + r.w - fw - 4, cy)

        -- Rejection arrow (small downward indicator)
        if gate_fail_counts[i] > 0 then
            local arrow_x = r.x + r.w / 2
            local arrow_y = r.y + r.h + 4
            love.graphics.setColor(Theme.colors.error[1], Theme.colors.error[2],
                Theme.colors.error[3], 0.25)
            love.graphics.line(arrow_x, arrow_y, arrow_x, arrow_y + 6)
            love.graphics.polygon("fill",
                arrow_x - 3, arrow_y + 6,
                arrow_x + 3, arrow_y + 6,
                arrow_x, arrow_y + 10)
        end
    end
end

function Section:drawParticles()
    -- Draw trails first (behind particles)
    for _, p in ipairs(particles) do
        if p.alive and #p.trail > 1 then
            for ti, t in ipairs(p.trail) do
                local frac = ti / #p.trail
                local tr = p.rejected and p.color[1] or p.color[1]
                local tg = p.rejected and p.color[2] or p.color[2]
                local tb = p.rejected and p.color[3] or p.color[3]
                local ta = t.alpha * frac * p.alpha * 0.5
                love.graphics.setColor(tr, tg, tb, ta)
                local trail_r = p.radius * frac * 0.7
                love.graphics.circle("fill", t.x, t.y, trail_r)
            end
        end
    end

    -- Draw particles
    for _, p in ipairs(particles) do
        if p.alive then
            local r, g, b = p.color[1], p.color[2], p.color[3]

            -- Outer glow
            love.graphics.setColor(r, g, b, p.alpha * 0.15)
            love.graphics.circle("fill", p.x, p.y, p.radius * 2.5)

            -- Inner glow
            love.graphics.setColor(r, g, b, p.alpha * 0.35)
            love.graphics.circle("fill", p.x, p.y, p.radius * 1.6)

            -- Core
            love.graphics.setColor(r, g, b, p.alpha * 0.9)
            love.graphics.circle("fill", p.x, p.y, p.radius)

            -- Bright center
            love.graphics.setColor(unpack(Theme.colors.text_dim))
            love.graphics.circle("fill", p.x, p.y, p.radius * 0.4)
        end
    end
end

function Section:drawExpandedGate(idx, sw, sh)
    local gate = GATES[idx]
    local r = gate_rects[idx]

    -- Panel below the gate
    local panel_w = math.min(320, sw * 0.3)
    local panel_x = clamp(r.x + r.w / 2 - panel_w / 2, 16, sw - panel_w - 16)
    local panel_y = r.y + r.h + 40
    local line_h = 22
    local pad = 16
    local num_lines = 3 + #gate.thresholds  -- question + check + logic + thresholds
    local panel_h = pad * 2 + num_lines * line_h + 30

    -- Connection line from gate to panel
    love.graphics.setColor(unpack(Theme.colors.border))
    love.graphics.line(r.x + r.w / 2, r.y + r.h, panel_x + panel_w / 2, panel_y)

    -- Panel background
    love.graphics.setColor(0.06, 0.06, 0.09, 0.96)
    Theme.roundRect("fill", panel_x, panel_y, panel_w, panel_h, Theme.radius.lg)

    -- Panel border with gate color
    local gc = gate.color_pass
    love.graphics.setColor(gc[1], gc[2], gc[3], 0.2)
    Theme.roundRect("line", panel_x, panel_y, panel_w, panel_h, Theme.radius.lg)

    local tx = panel_x + pad
    local ty = panel_y + pad

    -- Gate title
    love.graphics.setColor(gc[1], gc[2], gc[3], 0.9)
    love.graphics.setFont(Theme.fonts().heading)
    love.graphics.print("Gate " .. idx .. ": " .. gate.name, tx, ty)
    ty = ty + line_h + 4

    -- Question
    love.graphics.setColor(unpack(Theme.colors.text))
    love.graphics.setFont(Theme.fonts().body)
    love.graphics.printf(gate.question, tx, ty, panel_w - pad * 2, "left")
    ty = ty + line_h + 6

    -- Thresholds header
    love.graphics.setColor(unpack(Theme.colors.text_dim))
    love.graphics.setFont(Theme.fonts().small)
    love.graphics.print("THRESHOLDS:", tx, ty)
    ty = ty + line_h - 4

    -- Threshold items
    love.graphics.setFont(Theme.fonts().mono)
    for _, thresh in ipairs(gate.thresholds) do
        love.graphics.setColor(gc[1], gc[2], gc[3], 0.5)
        love.graphics.print("\226\128\162", tx, ty)  -- bullet
        love.graphics.setColor(unpack(Theme.colors.text_dim))
        love.graphics.print(thresh, tx + 14, ty)
        ty = ty + line_h - 4
    end

    ty = ty + 6

    -- Logic
    love.graphics.setColor(unpack(Theme.colors.text_muted))
    love.graphics.setFont(Theme.fonts().small)
    love.graphics.print("LOGIC:", tx, ty)
    ty = ty + 14
    love.graphics.setColor(0.75, 0.85, 0.95, 0.7)
    love.graphics.setFont(Theme.fonts().mono)
    love.graphics.printf(gate.logic, tx, ty, panel_w - pad * 2, "left")
end

function Section:drawBottomBar(sw, sh)
    -- Total stats
    local total_passed = 0
    if total_spawned > 0 then
        -- Count particles that passed all gates
        local all_pass = total_spawned
        for i = 1, 5 do
            all_pass = all_pass - gate_fail_counts[i]
        end
        total_passed = math.max(0, all_pass)
    end

    local stats_y = pipeline_y + gate_h + 36
    local stats_x = pipeline_x_start

    love.graphics.setFont(Theme.fonts().body)
    love.graphics.setColor(unpack(Theme.colors.text_dim))
    love.graphics.print(
        string.format("Total frames: %d", total_spawned),
        stats_x, stats_y + 20
    )

    love.graphics.setColor(Theme.colors.success[1], Theme.colors.success[2],
        Theme.colors.success[3], 0.8)
    love.graphics.print(
        string.format("Viable: %d", total_passed),
        stats_x + 160, stats_y + 20
    )

    if total_spawned > 0 then
        local overall_pct = total_passed / total_spawned * 100
        love.graphics.setColor(unpack(Theme.colors.text_dim))
        love.graphics.print(
            string.format("(%.1f%% yield)", overall_pct),
            stats_x + 260, stats_y + 20
        )
    end

    -- Teaching note in lower left
    local note_y = sh - 130
    local note_w = sw * 0.55
    love.graphics.setColor(unpack(Theme.colors.text_muted))
    love.graphics.setFont(Theme.fonts().small)
    love.graphics.printf(
        "Each frame of video passes through all 5 validation gates sequentially. " ..
        "A frame must clear every gate to be considered viable for bboy move analysis. " ..
        "The cumulative filtering is strict by design: we prefer fewer high-quality " ..
        "reconstructions over many noisy ones. Click a gate to inspect its checks.",
        20, note_y, note_w, "left"
    )
end

function Section:drawResearchMapping(sw, sh)
    local panel_w = 360
    local panel_h = 180
    local panel_x = sw / 2 - panel_w / 2
    local panel_y = sh / 2 - panel_h / 2

    -- Dim overlay
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", 0, 0, sw, sh)

    -- Panel
    love.graphics.setColor(0.06, 0.06, 0.09, 0.98)
    Theme.roundRect("fill", panel_x, panel_y, panel_w, panel_h, Theme.radius.xl)
    love.graphics.setColor(Theme.colors.cv[1], Theme.colors.cv[2], Theme.colors.cv[3], 0.2)
    Theme.roundRect("line", panel_x, panel_y, panel_w, panel_h, Theme.radius.xl)

    local tx = panel_x + 20
    local ty = panel_y + 20

    love.graphics.setColor(Theme.colors.cv[1], Theme.colors.cv[2], Theme.colors.cv[3], 0.9)
    love.graphics.setFont(Theme.fonts().heading)
    love.graphics.print("Research Mapping", tx, ty)
    ty = ty + 28

    love.graphics.setColor(unpack(Theme.colors.text_dim))
    love.graphics.setFont(Theme.fonts().body)
    love.graphics.printf(
        "This visualization maps to evaluate_powermove_gates.py in the " ..
        "bboy-analytics research pipeline. That script implements the same " ..
        "5-gate sequential filter on real 3D pose reconstruction output from " ..
        "GVHMR/JOSH models.",
        tx, ty, panel_w - 40, "left"
    )
    ty = ty + 68

    love.graphics.setColor(unpack(Theme.colors.text_dim))
    love.graphics.setFont(Theme.fonts().mono)
    love.graphics.print("experiments/evaluate_powermove_gates.py", tx, ty)
    ty = ty + 20

    love.graphics.setColor(unpack(Theme.colors.text_muted))
    love.graphics.setFont(Theme.fonts().small)
    love.graphics.print("Click anywhere or press R to close", tx, ty)
end

-------------------------------------------------------------------------------
-- Input handlers
-------------------------------------------------------------------------------

function Section:mousepressed(x, y, button)
    if button ~= 1 then return end

    local sw, sh = love.graphics.getDimensions()

    -- If research overlay is open, close it
    if show_research then
        show_research = false
        return
    end

    -- Check research button
    local btn_x = 20
    local btn_y = sh - 80
    if Widgets.buttonClicked(btn_x, btn_y, 200, 32, x, y) then
        show_research = not show_research
        return
    end

    -- Check gate clicks
    for i = 1, 5 do
        local r = gate_rects[i]
        if x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h then
            if expanded_gate == i then
                expanded_gate = nil  -- toggle off
            else
                expanded_gate = i
            end
            return
        end
    end

    -- Click elsewhere closes expanded gate
    if expanded_gate then
        expanded_gate = nil
    end
end

function Section:mousereleased(x, y, button)
    -- No special handling needed; widget releases handled internally
end

function Section:mousemoved(x, y, dx, dy)
    -- Hover handled in update()
end

function Section:keypressed(key)
    if key == "r" then
        if show_research then
            show_research = false
        else
            show_research = true
        end
    elseif key == "c" then
        -- Clear / reset counters and particles
        particles = {}
        gate_pass_counts = {0, 0, 0, 0, 0}
        gate_fail_counts = {0, 0, 0, 0, 0}
        total_spawned = 0
        spawn_timer = 0
    elseif key == "1" or key == "2" or key == "3" or key == "4" or key == "5" then
        local idx = tonumber(key)
        if expanded_gate == idx then
            expanded_gate = nil
        else
            expanded_gate = idx
        end
    elseif key == "escape" then
        if expanded_gate then
            expanded_gate = nil
        end
    end
end

function Section:unload()
    particles = {}
    gate_rects = {}
    expanded_gate = nil
    hovered_gate = nil
    show_research = false
end

return Section
