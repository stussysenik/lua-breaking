--- Section 5.2: Powermove Physics
--- Interactive physics simulations for three iconic breakdancing powermoves:
--- Windmill (angular momentum conservation), Flare (centripetal force),
--- Headspin (gyroscopic precession). Each tab exposes the core physics
--- with real-time parameter control so the learner can feel the equations.
--- Research bridge: powermove failure analysis pipeline

local Theme = require("shell.theme")
local Draw  = require("lib.draw")
local Widgets = require("lib.widgets")

local Section = {}
Section.__index = Section

Section.meta = {
    id = "5.2",
    title = "Powermove Physics",
    layer = "bboy",
    description = "Physics of windmill, flare, and headspin: angular momentum, centripetal force, precession",
    research_mapping = "powermove failure analysis",
    data_bridge = true,
    prerequisites = {"1.1", "2.4"},
}

-- ─── Constants ──────────────────────────────────────────────────────────────

local TAB_NAMES = {"WINDMILL", "FLARE", "HEADSPIN"}
local TWO_PI = 2 * math.pi

-- ─── Module state ───────────────────────────────────────────────────────────

local active_tab       -- 1 = windmill, 2 = flare, 3 = headspin
local time             -- accumulated simulation time (s)

-- Windmill state
local wm = {}

-- Flare state
local fl = {}

-- Headspin state
local hs = {}

-- ─── Helpers ────────────────────────────────────────────────────────────────

--- Lerp between two values
local function lerp(a, b, t) return a + (b - a) * t end

--- Clamp a value to [lo, hi]
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

--- Draw a dashed circle (segments count = dashes * 2)
local function dashedCircle(cx, cy, r, dashes, line_width)
    dashes = dashes or 24
    love.graphics.setLineWidth(line_width or 1)
    local seg = TWO_PI / (dashes * 2)
    for i = 0, dashes - 1 do
        local a1 = i * 2 * seg
        local a2 = a1 + seg
        local steps = 8
        local pts = {}
        for s = 0, steps do
            local a = a1 + (a2 - a1) * s / steps
            pts[#pts + 1] = cx + math.cos(a) * r
            pts[#pts + 1] = cy + math.sin(a) * r
        end
        if #pts >= 4 then
            love.graphics.line(pts)
        end
    end
    love.graphics.setLineWidth(1)
end

--- Draw a curved arrow indicating rotation direction
local function rotationArrow(cx, cy, r, angle_start, angle_span, head, lw)
    head = head or 6
    lw = lw or 1.5
    love.graphics.setLineWidth(lw)
    local steps = 32
    local pts = {}
    for i = 0, steps do
        local a = angle_start + angle_span * (i / steps)
        pts[#pts + 1] = cx + math.cos(a) * r
        pts[#pts + 1] = cy + math.sin(a) * r
    end
    if #pts >= 4 then
        love.graphics.line(pts)
    end
    -- Arrowhead at the end
    local a_end = angle_start + angle_span
    local dir = angle_span > 0 and 1 or -1
    local tip_x = cx + math.cos(a_end) * r
    local tip_y = cy + math.sin(a_end) * r
    -- Tangent direction at tip
    local tx = -math.sin(a_end) * dir
    local ty =  math.cos(a_end) * dir
    -- Normal (outward)
    local nx =  math.cos(a_end)
    local ny =  math.sin(a_end)
    love.graphics.polygon("fill",
        tip_x, tip_y,
        tip_x - tx * head + nx * head * 0.35, tip_y - ty * head + ny * head * 0.35,
        tip_x - tx * head - nx * head * 0.35, tip_y - ty * head - ny * head * 0.35
    )
    love.graphics.setLineWidth(1)
end

--- Draw a simple stick figure limb (line with circle end)
local function drawLimb(x1, y1, x2, y2, thickness, joint_r)
    love.graphics.setLineWidth(thickness or 3)
    love.graphics.line(x1, y1, x2, y2)
    love.graphics.circle("fill", x2, y2, joint_r or 3)
    love.graphics.setLineWidth(1)
end

-- ─── WINDMILL simulation ────────────────────────────────────────────────────
-- Angular momentum conservation: L = I * omega
-- When the dancer tucks limbs, I decreases, omega increases.
-- We model a central torso disk + 4 limbs (arms + legs) as point masses.

local function wm_init()
    wm.tuck = 0.2            -- 0 = fully spread, 1 = fully tucked
    wm.angle = 0             -- current rotation angle (rad)
    wm.omega = 3.0           -- angular velocity (rad/s)

    -- Physical constants
    wm.torso_I = 2.0         -- torso moment of inertia (kg*m^2), constant
    wm.limb_mass = 3.0       -- total limb mass (kg) -- both arms + both legs
    wm.r_spread = 0.8        -- limb radius when fully spread (m)
    wm.r_tuck   = 0.15       -- limb radius when fully tucked (m)

    -- Compute initial angular momentum (conserved)
    local r0 = lerp(wm.r_spread, wm.r_tuck, wm.tuck)
    local I0 = wm.torso_I + wm.limb_mass * r0 * r0
    wm.L = I0 * wm.omega     -- conserved angular momentum

    wm.trail = {}             -- rotation trail for visual effect
    wm.trail_max = 60
end

local function wm_update(dt)
    -- Current limb radius based on tuck
    local r = lerp(wm.r_spread, wm.r_tuck, wm.tuck)
    -- Current moment of inertia
    local I = wm.torso_I + wm.limb_mass * r * r
    -- Angular velocity from conservation: omega = L / I
    wm.omega = wm.L / I
    -- Integrate angle
    wm.angle = wm.angle + wm.omega * dt

    -- Record trail
    wm.trail[#wm.trail + 1] = {angle = wm.angle, r = r}
    while #wm.trail > wm.trail_max do
        table.remove(wm.trail, 1)
    end
end

local function wm_draw(cx, cy, sim_r)
    local fonts = Theme.fonts()
    local r_limb = lerp(wm.r_spread, wm.r_tuck, wm.tuck)
    local I = wm.torso_I + wm.limb_mass * r_limb * r_limb
    local pixel_r = r_limb / wm.r_spread * sim_r * 0.85  -- limb pixel radius

    -- Draw trail (ghosted previous positions)
    for i, t in ipairs(wm.trail) do
        local alpha = (i / #wm.trail) * 0.12
        local tr = t.r / wm.r_spread * sim_r * 0.85
        love.graphics.setColor(Theme.colors.bboy[1], Theme.colors.bboy[2], Theme.colors.bboy[3], alpha)
        for limb = 0, 3 do
            local a = t.angle + limb * (math.pi / 2)
            local lx = cx + math.cos(a) * tr
            local ly = cy + math.sin(a) * tr
            love.graphics.circle("fill", lx, ly, 3)
        end
    end

    -- Ground contact arc (the back/shoulders rolling)
    love.graphics.setColor(unpack(Theme.colors.border))
    dashedCircle(cx, cy, sim_r * 0.25, 16, 1)

    -- Torso (central disk)
    local torso_r = sim_r * 0.22
    love.graphics.setColor(Theme.colors.bboy[1], Theme.colors.bboy[2], Theme.colors.bboy[3], 0.15)
    love.graphics.circle("fill", cx, cy, torso_r)
    love.graphics.setColor(Theme.colors.bboy[1], Theme.colors.bboy[2], Theme.colors.bboy[3], 0.5)
    love.graphics.circle("line", cx, cy, torso_r)

    -- Draw 4 limbs (2 arms + 2 legs, evenly spaced 90deg apart)
    local limb_colors = {
        {0.984, 0.749, 0.141},  -- arm 1 (amber)
        {0.204, 0.827, 0.600},  -- leg 1 (emerald)
        {0.490, 0.827, 0.988},  -- arm 2 (sky)
        {0.655, 0.545, 0.980},  -- leg 2 (violet)
    }
    local limb_labels = {"R.Arm", "R.Leg", "L.Arm", "L.Leg"}

    for i = 0, 3 do
        local a = wm.angle + i * (math.pi / 2)
        local lx = cx + math.cos(a) * pixel_r
        local ly = cy + math.sin(a) * pixel_r
        local c = limb_colors[i + 1]

        -- Limb line
        love.graphics.setColor(c[1], c[2], c[3], 0.7)
        drawLimb(cx, cy, lx, ly, 3, 5)

        -- Limb mass circle
        love.graphics.setColor(c[1], c[2], c[3], 0.3)
        love.graphics.circle("fill", lx, ly, 8)
        love.graphics.setColor(c[1], c[2], c[3], 0.8)
        love.graphics.circle("line", lx, ly, 8)

        -- Label
        love.graphics.setColor(c[1], c[2], c[3], 0.5)
        love.graphics.setFont(fonts.small)
        love.graphics.print(limb_labels[i + 1], lx + 10, ly - 6)
    end

    -- Rotation direction arrow
    local speed_t = clamp(math.abs(wm.omega) / 15, 0, 1)
    local sr, sg, sb = Draw.speedColor(speed_t)
    love.graphics.setColor(sr, sg, sb, 0.6)
    rotationArrow(cx, cy, pixel_r + 18, wm.angle, math.pi * 0.6, 8, 2)

    -- Center dot
    love.graphics.setColor(unpack(Theme.colors.text))
    love.graphics.circle("fill", cx, cy, 3)

    -- Radius line annotation
    love.graphics.setColor(unpack(Theme.colors.text_muted))
    love.graphics.setLineWidth(1)
    local ann_a = wm.angle + math.pi / 4  -- between first two limbs
    love.graphics.line(cx, cy, cx + math.cos(ann_a) * pixel_r, cy + math.sin(ann_a) * pixel_r)
    love.graphics.setColor(unpack(Theme.colors.text_dim))
    love.graphics.setFont(fonts.small)
    local mid_x = cx + math.cos(ann_a) * pixel_r * 0.5
    local mid_y = cy + math.sin(ann_a) * pixel_r * 0.5
    love.graphics.print(string.format("r=%.2fm", r_limb), mid_x + 6, mid_y - 10)

    -- Speed color bar at bottom of sim area
    local bar_x = cx - sim_r * 0.6
    local bar_y = cy + sim_r + 20
    Draw.colorRamp(bar_x, bar_y, sim_r * 1.2, 6, Draw.speedColor, "slow", "fast")
end

-- ─── FLARE simulation ───────────────────────────────────────────────────────
-- Legs sweep in circular arcs while body pivots on hands.
-- We model the legs as a rigid rod rotating around the pivot (hands on ground).
-- Centripetal force F_c = m*v^2/r = m*omega^2*r
-- Pendulum period T = 2*pi*sqrt(L/g) (small angle approx)

local function fl_init()
    fl.leg_spread = 0.6    -- 0 = legs together, 1 = full straddle
    fl.pivot_height = 0.5  -- 0 = low, 1 = high (normalized)
    fl.angle = 0           -- sweep angle (top-down)
    fl.omega = 4.5         -- angular velocity (rad/s)
    fl.leg_mass = 12       -- kg per leg
    fl.leg_length = 0.9    -- m
    fl.g = 9.81            -- gravity

    fl.trail_l = {}        -- left leg trail
    fl.trail_r = {}        -- right leg trail
    fl.trail_max = 80
end

local function fl_update(dt)
    -- Effective pendulum length from pivot height
    -- Higher pivot = longer effective pendulum = slower oscillation
    local L_pend = lerp(0.5, 1.2, fl.pivot_height)
    -- Natural angular frequency
    local omega_natural = math.sqrt(fl.g / L_pend)
    -- Driven angular velocity blends toward natural frequency
    fl.omega = lerp(fl.omega, omega_natural * 1.5, dt * 0.3)

    fl.angle = fl.angle + fl.omega * dt

    -- Effective radius depends on leg spread
    local r_eff = fl.leg_length * lerp(0.3, 1.0, fl.leg_spread)

    -- Trail: left leg and right leg positions (top-down)
    local spread_offset = lerp(0.1, math.pi * 0.45, fl.leg_spread)
    local la = fl.angle + spread_offset
    local ra = fl.angle - spread_offset
    fl.trail_l[#fl.trail_l + 1] = {a = la, r = r_eff}
    fl.trail_r[#fl.trail_r + 1] = {a = ra, r = r_eff}
    while #fl.trail_l > fl.trail_max do table.remove(fl.trail_l, 1) end
    while #fl.trail_r > fl.trail_max do table.remove(fl.trail_r, 1) end
end

local function fl_draw(cx, cy, sim_r)
    local fonts = Theme.fonts()
    local r_eff = fl.leg_length * lerp(0.3, 1.0, fl.leg_spread)
    local pixel_r = r_eff / fl.leg_length * sim_r * 0.75
    local spread_offset = lerp(0.1, math.pi * 0.45, fl.leg_spread)

    -- Orbit circle
    love.graphics.setColor(unpack(Theme.colors.border))
    dashedCircle(cx, cy, pixel_r, 32, 1)

    -- Trail: left leg (amber)
    for i, t in ipairs(fl.trail_l) do
        local alpha = (i / #fl.trail_l) * 0.15
        local pr = t.r / fl.leg_length * sim_r * 0.75
        love.graphics.setColor(0.984, 0.749, 0.141, alpha)
        love.graphics.circle("fill", cx + math.cos(t.a) * pr, cy + math.sin(t.a) * pr, 2.5)
    end
    -- Trail: right leg (violet)
    for i, t in ipairs(fl.trail_r) do
        local alpha = (i / #fl.trail_r) * 0.15
        local pr = t.r / fl.leg_length * sim_r * 0.75
        love.graphics.setColor(0.655, 0.545, 0.980, alpha)
        love.graphics.circle("fill", cx + math.cos(t.a) * pr, cy + math.sin(t.a) * pr, 2.5)
    end

    -- Pivot point (hands)
    love.graphics.setColor(unpack(Theme.colors.text_muted))
    love.graphics.circle("fill", cx, cy, 14)
    love.graphics.setColor(unpack(Theme.colors.text_dim))
    love.graphics.circle("line", cx, cy, 14)
    love.graphics.setFont(fonts.small)
    love.graphics.setColor(unpack(Theme.colors.text_dim))
    love.graphics.print("PIVOT", cx - 16, cy + 16)

    -- Torso line (from pivot toward "head" direction, opposite to average leg direction)
    local torso_a = fl.angle + math.pi
    local torso_len = sim_r * 0.2
    love.graphics.setColor(Theme.colors.bboy[1], Theme.colors.bboy[2], Theme.colors.bboy[3], 0.4)
    love.graphics.setLineWidth(4)
    love.graphics.line(cx, cy, cx + math.cos(torso_a) * torso_len, cy + math.sin(torso_a) * torso_len)
    love.graphics.setLineWidth(1)

    -- Left leg
    local la = fl.angle + spread_offset
    local lx = cx + math.cos(la) * pixel_r
    local ly = cy + math.sin(la) * pixel_r
    love.graphics.setColor(0.984, 0.749, 0.141, 0.8)
    drawLimb(cx, cy, lx, ly, 3, 6)
    love.graphics.setFont(fonts.small)
    love.graphics.print("L", lx + 8, ly - 5)

    -- Right leg
    local ra = fl.angle - spread_offset
    local rx = cx + math.cos(ra) * pixel_r
    local ry = cy + math.sin(ra) * pixel_r
    love.graphics.setColor(0.655, 0.545, 0.980, 0.8)
    drawLimb(cx, cy, rx, ry, 3, 6)
    love.graphics.setFont(fonts.small)
    love.graphics.print("R", rx + 8, ry - 5)

    -- Centripetal force vectors (pointing inward)
    local v = fl.omega * r_eff
    local Fc = fl.leg_mass * v * v / r_eff
    local force_scale = clamp(Fc / 200, 0.2, 1.0)
    local arrow_len = sim_r * 0.18 * force_scale

    -- Left leg force arrow
    local fc_lx = lx + math.cos(la + math.pi) * arrow_len
    local fc_ly = ly + math.sin(la + math.pi) * arrow_len
    love.graphics.setColor(0.984, 0.443, 0.522, 0.7)
    Draw.arrow(lx, ly, fc_lx, fc_ly, 7, 2)

    -- Right leg force arrow
    local fc_rx = rx + math.cos(ra + math.pi) * arrow_len
    local fc_ry = ry + math.sin(ra + math.pi) * arrow_len
    love.graphics.setColor(0.984, 0.443, 0.522, 0.7)
    Draw.arrow(rx, ry, fc_rx, fc_ry, 7, 2)

    -- Force label
    love.graphics.setColor(0.984, 0.443, 0.522, 0.5)
    love.graphics.setFont(fonts.small)
    love.graphics.print("Fc", (lx + fc_lx) / 2 + 4, (ly + fc_ly) / 2 - 10)

    -- Rotation arrow
    local speed_t = clamp(fl.omega / 10, 0, 1)
    local sr, sg, sb = Draw.speedColor(speed_t)
    love.graphics.setColor(sr, sg, sb, 0.5)
    rotationArrow(cx, cy, pixel_r + 16, fl.angle - 0.3, math.pi * 0.5, 7, 1.5)

    -- Radius annotation
    love.graphics.setColor(unpack(Theme.colors.text_muted))
    love.graphics.setLineWidth(1)
    local ann_a = fl.angle
    love.graphics.line(cx, cy, cx + math.cos(ann_a) * pixel_r, cy + math.sin(ann_a) * pixel_r)
    love.graphics.setColor(unpack(Theme.colors.text_muted))
    love.graphics.setFont(fonts.small)
    love.graphics.print(string.format("r=%.2fm", r_eff),
        cx + math.cos(ann_a) * pixel_r * 0.5 + 4,
        cy + math.sin(ann_a) * pixel_r * 0.5 - 12)
end

-- ─── HEADSPIN simulation ────────────────────────────────────────────────────
-- Gyroscopic precession: a spinning body tilted from vertical precesses.
-- Precession rate: Omega_p = (m*g*d) / (I_spin * omega_spin)
-- Friction gradually drains omega_spin; stability depends on spin speed.
-- Side view + precession cone visualization.

local function hs_init()
    hs.spin_speed = 8.0     -- initial spin angular velocity (rad/s)
    hs.tilt = 0.25          -- body tilt from vertical (0 = vertical, 1 = ~60 deg)
    hs.omega_spin = 8.0     -- current spin speed (rad/s)
    hs.precession_angle = 0 -- current precession angle (rad)
    hs.friction = 0.15      -- friction coefficient (spin decay rate)

    -- Physical parameters
    hs.body_mass = 70       -- kg
    hs.body_height = 1.7    -- m (used for display)
    hs.head_radius = 0.1    -- m
    hs.g = 9.81
    hs.I_spin = 3.5         -- moment of inertia about spin axis (kg*m^2)
    hs.com_distance = 0.5   -- distance from head contact to center of mass (m)

    hs.trail = {}
    hs.trail_max = 120
    hs.wobble_history = {}   -- for wobble visualization
    hs.wobble_max = 200
end

local function hs_update(dt)
    -- Apply friction to spin
    hs.omega_spin = hs.omega_spin * (1 - hs.friction * dt)
    if hs.omega_spin < 0.01 then hs.omega_spin = 0.01 end

    -- Tilt angle in radians (max ~60 degrees)
    local tilt_rad = hs.tilt * math.pi / 3

    -- Precession rate: Omega_p = (m*g*d*sin(tilt)) / (I_spin * omega_spin)
    -- For a tilted gyroscope
    local torque = hs.body_mass * hs.g * hs.com_distance * math.sin(tilt_rad)
    local omega_p = 0
    if hs.omega_spin > 0.05 then
        omega_p = torque / (hs.I_spin * hs.omega_spin)
    end

    hs.precession_angle = hs.precession_angle + omega_p * dt
    hs.current_precession_rate = omega_p

    -- Trail for precession cone
    hs.trail[#hs.trail + 1] = {
        pa = hs.precession_angle,
        tilt = tilt_rad,
        spin = hs.omega_spin,
    }
    while #hs.trail > hs.trail_max do table.remove(hs.trail, 1) end

    -- Wobble history (top of body traces a circle)
    local wobble_r = math.sin(tilt_rad) * hs.com_distance
    hs.wobble_history[#hs.wobble_history + 1] = {
        x = math.cos(hs.precession_angle) * wobble_r,
        z = math.sin(hs.precession_angle) * wobble_r,
        spin = hs.omega_spin,
    }
    while #hs.wobble_history > hs.wobble_max do table.remove(hs.wobble_history, 1) end
end

local function hs_draw(cx, cy, sim_r)
    local fonts = Theme.fonts()
    local tilt_rad = hs.tilt * math.pi / 3
    local body_pixel_h = sim_r * 0.85  -- full body height in pixels

    -- Ground line
    local ground_y = cy + sim_r * 0.35
    love.graphics.setColor(unpack(Theme.colors.border))
    love.graphics.setLineWidth(1)
    love.graphics.line(cx - sim_r, ground_y, cx + sim_r, ground_y)
    love.graphics.setColor(unpack(Theme.colors.border))
    love.graphics.rectangle("fill", cx - sim_r, ground_y, sim_r * 2, sim_r * 0.5)

    -- Head contact point
    local head_x = cx
    local head_y = ground_y

    -- Body tilts from head contact
    -- Side view: body extends upward and to the side based on tilt
    local body_top_x = head_x + math.sin(tilt_rad) * body_pixel_h
    local body_top_y = head_y - math.cos(tilt_rad) * body_pixel_h

    -- Precession cone: the body traces a cone as it precesses
    -- Draw faint cone outline
    local cone_base_r = math.sin(tilt_rad) * body_pixel_h
    if cone_base_r > 2 then
        -- Precession cone circle (top-down projected as ellipse in side view)
        love.graphics.setColor(Theme.colors.physics[1], Theme.colors.physics[2], Theme.colors.physics[3], 0.08)
        dashedCircle(head_x, head_y - body_pixel_h * 0.85, cone_base_r, 20, 1)

        -- Cone lines
        love.graphics.setColor(Theme.colors.physics[1], Theme.colors.physics[2], Theme.colors.physics[3], 0.06)
        love.graphics.line(head_x, head_y, head_x + cone_base_r, head_y - body_pixel_h * 0.85)
        love.graphics.line(head_x, head_y, head_x - cone_base_r, head_y - body_pixel_h * 0.85)
    end

    -- Wobble trail (trace of where the CoM moves)
    local trail_scale = body_pixel_h * 0.5
    for i, w in ipairs(hs.wobble_history) do
        local alpha = (i / #hs.wobble_history) * 0.2
        local st = clamp(w.spin / 12, 0, 1)
        local r, g, b = Draw.speedColor(st)
        love.graphics.setColor(r, g, b, alpha)
        -- Project 3D wobble onto 2D side view
        local wx = head_x + w.x * trail_scale / hs.com_distance
        local wy = head_y - body_pixel_h * 0.85 + w.z * trail_scale * 0.3 / hs.com_distance
        love.graphics.circle("fill", wx, wy, 1.5)
    end

    -- Vertical reference line (ideal axis)
    love.graphics.setColor(unpack(Theme.colors.text_muted))
    love.graphics.setLineWidth(1)
    local vert_top = head_y - body_pixel_h * 1.05
    love.graphics.line(head_x, head_y, head_x, vert_top)
    love.graphics.setFont(fonts.small)
    love.graphics.setColor(unpack(Theme.colors.text_muted))
    love.graphics.print("vertical", head_x + 4, vert_top)

    -- Tilt angle arc
    if tilt_rad > 0.02 then
        love.graphics.setColor(Theme.colors.physics[1], Theme.colors.physics[2], Theme.colors.physics[3], 0.3)
        local arc_r = body_pixel_h * 0.25
        local arc_pts = {}
        local arc_steps = 20
        for s = 0, arc_steps do
            local a = -math.pi / 2 + tilt_rad * (s / arc_steps)
            arc_pts[#arc_pts + 1] = head_x + math.cos(a) * arc_r
            arc_pts[#arc_pts + 1] = head_y + math.sin(a) * arc_r
        end
        if #arc_pts >= 4 then
            love.graphics.line(arc_pts)
        end
        -- Tilt label
        love.graphics.setFont(fonts.small)
        love.graphics.print(string.format("%.0f deg", math.deg(tilt_rad)),
            head_x + arc_r * 0.7 + 4, head_y - arc_r * 0.9)
    end

    -- Body (main line from head to feet, with segments)
    love.graphics.setColor(Theme.colors.bboy[1], Theme.colors.bboy[2], Theme.colors.bboy[3], 0.8)
    love.graphics.setLineWidth(4)
    love.graphics.line(head_x, head_y, body_top_x, body_top_y)
    love.graphics.setLineWidth(1)

    -- Head circle
    local head_pr = sim_r * 0.05
    love.graphics.setColor(Theme.colors.bboy[1], Theme.colors.bboy[2], Theme.colors.bboy[3], 0.4)
    love.graphics.circle("fill", head_x, head_y, head_pr)
    love.graphics.setColor(Theme.colors.bboy[1], Theme.colors.bboy[2], Theme.colors.bboy[3], 0.8)
    love.graphics.circle("line", head_x, head_y, head_pr)

    -- Body segments: shoulders, hips, feet
    local shoulder_t = 0.3
    local hip_t = 0.6
    local sx = lerp(head_x, body_top_x, shoulder_t)
    local sy = lerp(head_y, body_top_y, shoulder_t)
    local hx = lerp(head_x, body_top_x, hip_t)
    local hy = lerp(head_y, body_top_y, hip_t)

    -- Arms (spreading out from shoulders, spinning)
    local arm_len = sim_r * 0.2
    local spin_visual = time * hs.omega_spin * 0.3  -- visual spin modulation
    -- Normal to body axis
    local body_dx = body_top_x - head_x
    local body_dy = body_top_y - head_y
    local body_len = math.sqrt(body_dx * body_dx + body_dy * body_dy)
    local bnx, bny = 0, 0
    if body_len > 1 then
        bnx = -body_dy / body_len
        bny =  body_dx / body_len
    end
    -- Arms oscillate with spin (foreshortened view)
    local arm_spread = math.cos(spin_visual) * arm_len
    love.graphics.setColor(0.984, 0.749, 0.141, 0.6)
    drawLimb(sx, sy, sx + bnx * arm_spread, sy + bny * arm_spread, 2, 3)
    love.graphics.setColor(0.490, 0.827, 0.988, 0.6)
    drawLimb(sx, sy, sx - bnx * arm_spread, sy - bny * arm_spread, 2, 3)

    -- Legs (from hips to feet)
    local leg_spread = math.cos(spin_visual + math.pi / 3) * sim_r * 0.08
    love.graphics.setColor(0.655, 0.545, 0.980, 0.6)
    drawLimb(hx, hy, body_top_x + bnx * leg_spread, body_top_y + bny * leg_spread, 2, 3)
    love.graphics.setColor(0.204, 0.827, 0.600, 0.6)
    drawLimb(hx, hy, body_top_x - bnx * leg_spread, body_top_y - bny * leg_spread, 2, 3)

    -- Spin arrow around the body axis
    local spin_t = clamp(hs.omega_spin / 12, 0, 1)
    local sr, sg, sb = Draw.speedColor(spin_t)
    love.graphics.setColor(sr, sg, sb, 0.6)
    -- Draw spin arrow at shoulder level
    local spin_arrow_r = sim_r * 0.12
    rotationArrow(sx, sy, spin_arrow_r, spin_visual, math.pi * 0.7, 6, 2)

    -- Precession arrow (larger, around vertical axis)
    if hs.current_precession_rate and hs.current_precession_rate > 0.05 then
        love.graphics.setColor(Theme.colors.physics[1], Theme.colors.physics[2], Theme.colors.physics[3], 0.4)
        local prec_r = math.max(cone_base_r, sim_r * 0.15)
        rotationArrow(head_x, head_y - body_pixel_h * 0.5,
            prec_r,
            hs.precession_angle, math.pi * 0.5, 7, 1.5)
    end

    -- Angular velocity arrow along body axis
    local omega_arrow_len = clamp(hs.omega_spin / 10, 0.1, 1) * sim_r * 0.3
    local ax_dx = (body_top_x - head_x)
    local ax_dy = (body_top_y - head_y)
    local ax_len = math.sqrt(ax_dx * ax_dx + ax_dy * ax_dy)
    if ax_len > 1 then
        ax_dx, ax_dy = ax_dx / ax_len, ax_dy / ax_len
        love.graphics.setColor(sr, sg, sb, 0.7)
        local arrow_ox = (head_x + body_top_x) / 2
        local arrow_oy = (head_y + body_top_y) / 2
        Draw.arrow(arrow_ox, arrow_oy,
            arrow_ox + ax_dx * omega_arrow_len,
            arrow_oy + ax_dy * omega_arrow_len, 8, 2)
        love.graphics.setFont(fonts.small)
        love.graphics.print("omega",
            arrow_ox + ax_dx * omega_arrow_len + 6,
            arrow_oy + ax_dy * omega_arrow_len - 4)
    end

    -- Contact point indicator
    love.graphics.setColor(unpack(Theme.colors.text_dim))
    love.graphics.setFont(fonts.small)
    love.graphics.print("contact", head_x - 42, ground_y + 4)

    -- Speed ramp
    local bar_x = cx - sim_r * 0.6
    local bar_y = cy + sim_r + 20
    Draw.colorRamp(bar_x, bar_y, sim_r * 1.2, 6, Draw.speedColor, "slow", "fast")
end

-- ─── Tab drawing ────────────────────────────────────────────────────────────

local function drawTabs(x, y, w)
    local fonts = Theme.fonts()
    local tab_w = w / #TAB_NAMES
    local tab_h = 32

    for i, name in ipairs(TAB_NAMES) do
        local tx = x + (i - 1) * tab_w
        local is_active = (i == active_tab)

        -- Background
        if is_active then
            love.graphics.setColor(Theme.colors.bboy[1], Theme.colors.bboy[2], Theme.colors.bboy[3], 0.12)
        else
            love.graphics.setColor(unpack(Theme.colors.border))
        end
        Theme.roundRect("fill", tx + 2, y, tab_w - 4, tab_h, Theme.radius.sm)

        -- Border
        if is_active then
            love.graphics.setColor(Theme.colors.bboy[1], Theme.colors.bboy[2], Theme.colors.bboy[3], 0.4)
        else
            love.graphics.setColor(unpack(Theme.colors.border))
        end
        Theme.roundRect("line", tx + 2, y, tab_w - 4, tab_h, Theme.radius.sm)

        -- Label
        love.graphics.setFont(fonts.body)
        if is_active then
            love.graphics.setColor(Theme.colors.bboy[1], Theme.colors.bboy[2], Theme.colors.bboy[3], 1)
        else
            love.graphics.setColor(unpack(Theme.colors.text_dim))
        end
        local tw = fonts.body:getWidth(name)
        love.graphics.print(name, tx + (tab_w - tw) / 2, y + (tab_h - fonts.body:getHeight()) / 2)

        -- Keyboard hint
        love.graphics.setFont(fonts.small)
        love.graphics.setColor(unpack(Theme.colors.text_muted))
        love.graphics.print(tostring(i), tx + tab_w - 18, y + tab_h - 16)
    end

    return tab_h
end

-- ─── Sidebar: sliders + info ────────────────────────────────────────────────

local function drawSidebar(sw, sh)
    local fonts = Theme.fonts()
    local sidebar_x = sw * 0.65 + 16
    local sidebar_w = sw * 0.35 - 32
    local y = 100

    if active_tab == 1 then
        -- WINDMILL controls

        -- Formula
        love.graphics.setColor(unpack(Theme.colors.text))
        love.graphics.setFont(fonts.mono)
        love.graphics.print("L = I * omega", sidebar_x, y)
        y = y + 20
        love.graphics.setColor(unpack(Theme.colors.text_dim))
        love.graphics.setFont(fonts.small)
        love.graphics.print("Angular momentum is conserved.", sidebar_x, y)
        love.graphics.print("Tuck limbs -> I drops -> omega rises.", sidebar_x, y + 14)
        y = y + 44

        -- Tuck slider
        local new_tuck, tuck_changed = Widgets.slider(
            sidebar_x, y, sidebar_w, wm.tuck, "Limb Tuck",
            {min = 0, max = 1, format = "%.2f", color = Theme.colors.bboy})
        if tuck_changed then wm.tuck = new_tuck end
        y = y + 52

        -- Computed values panel
        local r = lerp(wm.r_spread, wm.r_tuck, wm.tuck)
        local I = wm.torso_I + wm.limb_mass * r * r
        Draw.infoPanel(sidebar_x, y, sidebar_w, {
            {"omega (rad/s)", string.format("%.2f", wm.omega)},
            {"I (kg*m^2)",    string.format("%.2f", I)},
            {"L (conserved)", string.format("%.2f", wm.L)},
            {"Limb r (m)",    string.format("%.2f", r)},
            {"RPM",           string.format("%.0f", wm.omega * 60 / TWO_PI)},
        })
        y = y + 160

        -- Educational text
        love.graphics.setColor(unpack(Theme.colors.text_muted))
        love.graphics.setFont(fonts.small)
        love.graphics.printf(
            "In a windmill, the bboy rolls on their back/shoulders while " ..
            "spinning legs and torso. By tucking the limbs closer to the " ..
            "spin axis, the moment of inertia (I) decreases. Since angular " ..
            "momentum L is conserved (no external torque), the spin rate " ..
            "omega must increase: omega = L / I. This is the same physics " ..
            "as an ice skater pulling in their arms.",
            sidebar_x, y, sidebar_w, "left")

    elseif active_tab == 2 then
        -- FLARE controls

        love.graphics.setColor(unpack(Theme.colors.text))
        love.graphics.setFont(fonts.mono)
        love.graphics.print("Fc = m*v^2/r", sidebar_x, y)
        y = y + 20
        love.graphics.setColor(unpack(Theme.colors.text_dim))
        love.graphics.setFont(fonts.small)
        love.graphics.print("Centripetal force keeps legs in orbit.", sidebar_x, y)
        love.graphics.print("Wider spread = larger r = more force.", sidebar_x, y + 14)
        y = y + 44

        -- Leg spread slider
        local new_spread, spread_changed = Widgets.slider(
            sidebar_x, y, sidebar_w, fl.leg_spread, "Leg Spread",
            {min = 0.1, max = 1, format = "%.2f", color = Theme.colors.bboy})
        if spread_changed then fl.leg_spread = new_spread end
        y = y + 52

        -- Pivot height slider
        local new_height, height_changed = Widgets.slider(
            sidebar_x, y, sidebar_w, fl.pivot_height, "Pivot Height",
            {min = 0.1, max = 1, format = "%.2f", color = Theme.colors.physics})
        if height_changed then fl.pivot_height = new_height end
        y = y + 52

        -- Computed values
        local r_eff = fl.leg_length * lerp(0.3, 1.0, fl.leg_spread)
        local v = fl.omega * r_eff
        local Fc = fl.leg_mass * v * v / r_eff
        local T = TWO_PI / fl.omega

        Draw.infoPanel(sidebar_x, y, sidebar_w, {
            {"omega (rad/s)", string.format("%.2f", fl.omega)},
            {"v (m/s)",       string.format("%.2f", v)},
            {"Fc (N)",        string.format("%.0f", Fc)},
            {"r_eff (m)",     string.format("%.2f", r_eff)},
            {"Period (s)",    string.format("%.2f", T)},
            {"RPM",           string.format("%.0f", fl.omega * 60 / TWO_PI)},
        })
        y = y + 180

        love.graphics.setColor(unpack(Theme.colors.text_muted))
        love.graphics.setFont(fonts.small)
        love.graphics.printf(
            "In a flare, the legs sweep in wide circles while the body " ..
            "pivots between the hands on the ground. The dancer must " ..
            "support huge centripetal forces through their arms. A wider " ..
            "straddle increases the effective radius, increasing the " ..
            "velocity and the centripetal force quadratically (Fc ~ v^2). " ..
            "The pendulum period depends on pivot height (effective length).",
            sidebar_x, y, sidebar_w, "left")

    elseif active_tab == 3 then
        -- HEADSPIN controls

        love.graphics.setColor(unpack(Theme.colors.text))
        love.graphics.setFont(fonts.mono)
        love.graphics.print("Omega_p = mgh/(I*omega)", sidebar_x, y)
        y = y + 20
        love.graphics.setColor(unpack(Theme.colors.text_dim))
        love.graphics.setFont(fonts.small)
        love.graphics.print("Precession trades tilt for wobble.", sidebar_x, y)
        love.graphics.print("Faster spin = slower precession = stability.", sidebar_x, y + 14)
        y = y + 44

        -- Spin speed slider (resets simulation speed)
        local new_spin, spin_changed = Widgets.slider(
            sidebar_x, y, sidebar_w, hs.spin_speed, "Initial Spin",
            {min = 1, max = 15, format = "%.1f rad/s", color = Theme.colors.bboy})
        if spin_changed then
            hs.spin_speed = new_spin
            hs.omega_spin = new_spin
            hs.wobble_history = {}
            hs.trail = {}
        end
        y = y + 52

        -- Tilt slider
        local new_tilt, tilt_changed = Widgets.slider(
            sidebar_x, y, sidebar_w, hs.tilt, "Body Tilt",
            {min = 0, max = 0.8, format = "%.2f", color = Theme.colors.physics})
        if tilt_changed then
            hs.tilt = new_tilt
            hs.wobble_history = {}
            hs.trail = {}
        end
        y = y + 52

        -- Computed values
        local tilt_rad = hs.tilt * math.pi / 3
        local torque = hs.body_mass * hs.g * hs.com_distance * math.sin(tilt_rad)
        local omega_p = 0
        if hs.omega_spin > 0.05 then
            omega_p = torque / (hs.I_spin * hs.omega_spin)
        end

        Draw.infoPanel(sidebar_x, y, sidebar_w, {
            {"omega_spin (rad/s)", string.format("%.2f", hs.omega_spin)},
            {"Omega_prec (rad/s)", string.format("%.2f", omega_p)},
            {"Tilt (deg)",         string.format("%.1f", math.deg(tilt_rad))},
            {"Torque (N*m)",       string.format("%.1f", torque)},
            {"Spin RPM",           string.format("%.0f", hs.omega_spin * 60 / TWO_PI)},
            {"Stability",          hs.omega_spin > 4 and "STABLE" or (hs.omega_spin > 1.5 and "WOBBLE" or "FALLING")},
        })
        y = y + 195

        love.graphics.setColor(unpack(Theme.colors.text_muted))
        love.graphics.setFont(fonts.small)
        love.graphics.printf(
            "A headspin works like a gyroscope. The spinning body resists " ..
            "tipping due to angular momentum. When tilted, gravity creates " ..
            "a torque that causes precession (wobble around the vertical) " ..
            "rather than toppling. Faster spin = stronger gyroscopic " ..
            "effect = slower precession = more stable. Friction gradually " ..
            "bleeds spin energy, eventually causing loss of stability.",
            sidebar_x, y, sidebar_w, "left")
    end
end

-- ─── Section interface ──────────────────────────────────────────────────────

function Section:load()
    active_tab = 1
    time = 0
    wm_init()
    fl_init()
    hs_init()
end

function Section:update(dt)
    time = time + dt

    if active_tab == 1 then
        wm_update(dt)
    elseif active_tab == 2 then
        fl_update(dt)
    elseif active_tab == 3 then
        hs_update(dt)
    end
end

function Section:draw()
    local sw, sh = love.graphics.getDimensions()

    -- Background
    love.graphics.setColor(unpack(Theme.colors.bg))
    love.graphics.rectangle("fill", 0, 0, sw, sh)
    Draw.dotGrid(0, 0, sw, sh, 30, 1, {1, 1, 1, 0.02})

    -- Title bar
    local title_h = Draw.titleBar(Section.meta.title, Section.meta.layer, Section.meta.id)

    -- Tabs (below title bar, spanning simulation area)
    local sim_area_w = sw * 0.65
    local tab_y = title_h + 8
    local tab_h = drawTabs(16, tab_y, sim_area_w - 16)

    -- Simulation area
    local sim_x = 16
    local sim_y = tab_y + tab_h + 16
    local sim_w = sim_area_w - 32
    local sim_h = sh - sim_y - 60

    -- Sim area background
    love.graphics.setColor(unpack(Theme.colors.border))
    Theme.roundRect("fill", sim_x, sim_y, sim_w, sim_h, Theme.radius.lg)
    love.graphics.setColor(unpack(Theme.colors.border))
    Theme.roundRect("line", sim_x, sim_y, sim_w, sim_h, Theme.radius.lg)

    -- Center of simulation area
    local cx = sim_x + sim_w / 2
    local cy = sim_y + sim_h / 2
    local sim_r = math.min(sim_w, sim_h) / 2 - 30

    -- Draw active simulation
    love.graphics.setScissor(sim_x, sim_y, sim_w, sim_h)
    if active_tab == 1 then
        wm_draw(cx, cy, sim_r)
    elseif active_tab == 2 then
        fl_draw(cx, cy, sim_r)
    elseif active_tab == 3 then
        hs_draw(cx, cy, sim_r)
    end
    love.graphics.setScissor()

    -- Sidebar: sliders + info panels
    drawSidebar(sw, sh)

    -- Bottom formula bar
    local formula_text
    if active_tab == 1 then
        formula_text = string.format(
            "L = I*omega  |  I = I_torso + m_limb*r^2  |  L = %.2f kg*m^2/s (conserved)",
            wm.L)
    elseif active_tab == 2 then
        local r_eff = fl.leg_length * lerp(0.3, 1.0, fl.leg_spread)
        local v = fl.omega * r_eff
        local Fc = fl.leg_mass * v * v / r_eff
        formula_text = string.format(
            "Fc = m*v^2/r = %.0f N  |  T = 2*pi/omega = %.2f s",
            Fc, TWO_PI / fl.omega)
    elseif active_tab == 3 then
        local tilt_rad = hs.tilt * math.pi / 3
        local omega_p = 0
        if hs.omega_spin > 0.05 then
            local torque = hs.body_mass * hs.g * hs.com_distance * math.sin(tilt_rad)
            omega_p = torque / (hs.I_spin * hs.omega_spin)
        end
        formula_text = string.format(
            "Omega_p = m*g*d*sin(tilt)/(I*omega) = %.2f rad/s  |  omega_spin = %.2f rad/s",
            omega_p, hs.omega_spin)
    end
    Draw.formula(formula_text, 20, sh - 40)
end

function Section:mousepressed(x, y, button)
    if button ~= 1 then return end

    local sw = love.graphics.getDimensions()
    local sim_area_w = sw * 0.65
    local title_h = 52

    -- Tab hit test
    local tab_y = title_h + 8
    local tab_h = 32
    local tab_w = (sim_area_w - 16) / #TAB_NAMES
    if y >= tab_y and y <= tab_y + tab_h and x >= 16 and x <= sim_area_w then
        local idx = math.floor((x - 16) / tab_w) + 1
        idx = clamp(idx, 1, #TAB_NAMES)
        if idx ~= active_tab then
            active_tab = idx
        end
    end
end

function Section:mousereleased(x, y, button)
    -- Widget release handled internally by Widgets
end

function Section:mousemoved(x, y, dx, dy)
    -- Hover states handled by Widgets in draw/update
end

function Section:keypressed(key)
    -- Tab switching with number keys
    if key == "1" then active_tab = 1
    elseif key == "2" then active_tab = 2
    elseif key == "3" then active_tab = 3
    -- Quick adjustments with arrow keys
    elseif key == "left" or key == "right" then
        local delta = (key == "right") and 0.05 or -0.05
        if active_tab == 1 then
            wm.tuck = clamp(wm.tuck + delta, 0, 1)
        elseif active_tab == 2 then
            fl.leg_spread = clamp(fl.leg_spread + delta, 0.1, 1)
        elseif active_tab == 3 then
            hs.tilt = clamp(hs.tilt + delta, 0, 0.8)
        end
    elseif key == "up" or key == "down" then
        local delta = (key == "up") and 0.05 or -0.05
        if active_tab == 2 then
            fl.pivot_height = clamp(fl.pivot_height + delta, 0.1, 1)
        elseif active_tab == 3 then
            hs.spin_speed = clamp(hs.spin_speed + delta * 20, 1, 15)
            hs.omega_spin = hs.spin_speed
            hs.wobble_history = {}
            hs.trail = {}
        end
    -- Reset current simulation
    elseif key == "r" then
        if active_tab == 1 then wm_init()
        elseif active_tab == 2 then fl_init()
        elseif active_tab == 3 then hs_init()
        end
    end
end

function Section:unload()
    wm = {}
    fl = {}
    hs = {}
    time = nil
    active_tab = nil
end

return Section
