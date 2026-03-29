--- Section 3.2: 8D Audio Signature
--- Comprehensive visualization of the 8 psychoacoustic dimensions used in
--- bboy-analytics to characterize music for dance musicality analysis.
---
--- The 8D signature is a feature vector that captures the perceptual qualities
--- of a music track most relevant to breakdancing: bass energy, percussive
--- strength, vocal presence, beat stability, spectral flux, rhythm complexity,
--- harmonic richness, and dynamic range. Together they form the input to the
--- H(t) audio heat signal that drives the musicality score mu.
---
--- Research bridge: 8D psychoacoustic features -> H(t) computation pipeline

local Theme = require("shell.theme")
local Draw  = require("lib.draw")
local Widgets = require("lib.widgets")

local Section = {}
Section.__index = Section

Section.meta = {
    id = "3.2",
    title = "8D Audio Signature",
    layer = "signal",
    description = "8 psychoacoustic dimensions that characterize music for dance analysis",
    research_mapping = "8D psychoacoustic features",
    data_bridge = true,
    prerequisites = {"3.1"},
}

-- ─────────────────────────────────────────────
-- The 8 Psychoacoustic Dimensions
-- ─────────────────────────────────────────────
-- Each dimension is a normalized [0, 1] scalar extracted from the audio signal.
-- Together they form an 8D feature vector that characterizes the "dance-ability
-- profile" of a track. The radar chart maps these onto a regular octagon.

local DIMENSIONS = {
    {
        name  = "Bass Energy",
        key   = "bass",
        short = "Low-frequency power (20-250Hz)",
        desc  = "RMS power in the 20-250Hz band. Strong bass grounds footwork timing.",
        formula = "RMS(FFT[20..250Hz])",
    },
    {
        name  = "Percussive Strength",
        key   = "percussive",
        short = "Transient-to-sustain ratio",
        desc  = "Ratio of transient energy to sustained energy from onset detection.",
        formula = "E_transient / E_sustain",
    },
    {
        name  = "Vocal Presence",
        key   = "vocal",
        short = "Mid-frequency formant energy",
        desc  = "Energy in 300Hz-3kHz formant band. Vocals create call-and-response.",
        formula = "RMS(FFT[300..3000Hz])",
    },
    {
        name  = "Beat Stability",
        key   = "stability",
        short = "Inter-beat interval consistency",
        desc  = "How metronomic vs. swung the beat is. Affects anticipatory movement.",
        formula = "1 - std(IBI)/mean(IBI)",
    },
    {
        name  = "Spectral Flux",
        key   = "flux",
        short = "Rate of spectral change",
        desc  = "L2 norm of frame-to-frame spectral difference. Musical activity level.",
        formula = "||S(t) - S(t-1)||_2",
    },
    {
        name  = "Rhythm Complexity",
        key   = "complexity",
        short = "Syncopation and polyrhythm degree",
        desc  = "Beat salience entropy. High = complex off-beat patterns (funk, Afrobeat).",
        formula = "H(beat_salience)",
    },
    {
        name  = "Harmonic Richness",
        key   = "harmonic",
        short = "Overtone density and chord depth",
        desc  = "Inverse spectral flatness. Rich chords vs. simple bass lines.",
        formula = "1 / spectral_flatness",
    },
    {
        name  = "Dynamic Range",
        key   = "dynamic",
        short = "Loudness variance over time",
        desc  = "Peak-to-trough loudness in dB across windows. Build-up and release.",
        formula = "max(dB) - min(dB)",
    },
}

local N_DIM = #DIMENSIONS

-- ─────────────────────────────────────────────
-- Preset signatures
-- ─────────────────────────────────────────────
-- Each preset is a representative 8D vector for a genre archetype.
-- Values are normalized [0, 1] and ordered to match DIMENSIONS.

local PRESETS = {
    {
        name = "Funky Breaks",
        --         bass  perc  vocal stab  flux  cmplx harm  dyn
        values = { 0.88, 0.85, 0.50, 0.35, 0.82, 0.80, 0.55, 0.78 },
        desc = "James Brown, The Meters. High bass and percussion with complex syncopation.",
    },
    {
        name = "Boom Bap",
        values = { 0.85, 0.82, 0.78, 0.55, 0.50, 0.52, 0.30, 0.55 },
        desc = "DJ Premier, Pete Rock. Hard-hitting drums, prominent vocals, steady groove.",
    },
    {
        name = "Electronic",
        values = { 0.60, 0.55, 0.18, 0.92, 0.75, 0.25, 0.20, 0.30 },
        desc = "Four-on-the-floor. Metronomic stability, low vocal presence, compressed.",
    },
    {
        name = "Jazz Fusion",
        values = { 0.30, 0.28, 0.50, 0.25, 0.55, 0.85, 0.90, 0.80 },
        desc = "Herbie Hancock, Weather Report. Rich harmony, complex rhythm, wide dynamics.",
    },
}

-- ─────────────────────────────────────────────
-- State
-- ─────────────────────────────────────────────

local values = {}          -- current 8D values [1..8], each in [0, 1]
local anim_time = 0        -- global animation clock
local active_preset = nil  -- index of last-selected preset, or nil

-- Animated values for smooth transitions
local anim_values = {}     -- the values being rendered (lerp toward target)
local LERP_SPEED = 6       -- speed of interpolation (higher = snappier)

-- Layout state (computed in :load)
local radar_cx, radar_cy, radar_r
local sidebar_x, sidebar_y, sidebar_w
local panel_x, panel_y, panel_w, panel_h
local preset_x, preset_y

-- Scroll state for educational panel
local edu_scroll = 0

-- ─────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────

--- Linear interpolation
local function lerp(a, b, t)
    return a + (b - a) * t
end

--- Clamp a value to [lo, hi]
local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

--- Get the angle for dimension index i (1-based), with dimension 1 at top
--- The radar chart is a regular octagon with the first axis pointing straight up.
--- @param i number  Dimension index (1..N_DIM)
--- @return number   Angle in radians
local function dimAngle(i)
    -- Start at -pi/2 (top) and go clockwise
    return -math.pi / 2 + (i - 1) * (2 * math.pi / N_DIM)
end

--- Convert a dimension index and value (0..1) to screen coordinates on the radar.
--- @param i number Dimension index
--- @param v number Value 0..1
--- @return number x, number y  Screen position
local function radarPoint(i, v)
    local angle = dimAngle(i)
    local r = v * radar_r
    return radar_cx + math.cos(angle) * r,
           radar_cy + math.sin(angle) * r
end

--- Build a flat array of polygon vertices from the 8 animated values.
--- @param vals table  Array of 8 values
--- @return table      Flat array {x1,y1, x2,y2, ...}
local function radarPolygon(vals)
    local pts = {}
    for i = 1, N_DIM do
        local x, y = radarPoint(i, vals[i])
        pts[#pts + 1] = x
        pts[#pts + 1] = y
    end
    return pts
end

-- ─────────────────────────────────────────────
-- Section lifecycle
-- ─────────────────────────────────────────────

function Section:load()
    local sw, sh = love.graphics.getDimensions()

    -- Initialize with the first preset so there is something interesting to see
    local init = PRESETS[1].values
    for i = 1, N_DIM do
        values[i] = init[i]
        anim_values[i] = init[i]
    end
    active_preset = 1

    -- Layout: radar chart center-left, sidebar on the right
    -- The radar chart occupies roughly the left 58% of the screen
    local chart_area_w = math.floor(sw * 0.58)
    radar_r = math.min(chart_area_w, sh - 180) * 0.34
    radar_r = math.max(radar_r, 100)  -- minimum useful size
    radar_cx = chart_area_w * 0.50
    radar_cy = 64 + (sh - 64 - 200) * 0.45  -- vertically centered in available space

    -- Sidebar (sliders and presets)
    sidebar_x = chart_area_w + 12
    sidebar_y = 64
    sidebar_w = sw - sidebar_x - 16

    -- Preset buttons below sliders
    preset_x = sidebar_x
    preset_y = 0  -- computed dynamically in draw

    -- Educational panel at bottom
    panel_w = sw - 32
    panel_x = 16
    panel_h = 180
    panel_y = sh - panel_h - 8

    anim_time = 0
    edu_scroll = 0
end

function Section:update(dt)
    anim_time = anim_time + dt

    -- Smoothly interpolate animated values toward target values
    local factor = 1 - math.exp(-LERP_SPEED * dt)
    for i = 1, N_DIM do
        anim_values[i] = lerp(anim_values[i], values[i], factor)
    end
end

function Section:draw()
    local sw, sh = love.graphics.getDimensions()
    local fonts = Theme.fonts()

    -- Background
    love.graphics.setColor(unpack(Theme.colors.bg))
    love.graphics.rectangle("fill", 0, 0, sw, sh)
    Draw.dotGrid(0, 0, sw, sh, 30, 1, Theme.colors.grid_dot)

    -- Title bar
    Draw.titleBar(Section.meta.title, Section.meta.layer, Section.meta.id)

    -- Radar chart
    self:drawRadarChart()

    -- Sidebar: sliders and presets
    self:drawSidebar(sw, sh)

    -- Educational panel at the bottom
    self:drawEducationalPanel(sw, sh)

    -- Formula bar
    Draw.formula(
        "8D Signature: S = [bass, perc, vocal, stab, flux, cmplx, harm, dyn]  |  S -> H(t) audio heat",
        20, sh - 36
    )
end

-- ─────────────────────────────────────────────
-- Radar / Spider Chart
-- ─────────────────────────────────────────────
--- The radar chart is the hero visualization. It draws:
---   1. Concentric octagonal guide rings at 25%, 50%, 75%, 100%
---   2. Axis lines from center to each dimension tip
---   3. Dimension labels at the tips
---   4. A filled polygon showing the current (animated) values
---   5. Value dots on each axis with subtle glow
---   6. Current numeric value next to each dot

function Section:drawRadarChart()
    local fonts = Theme.fonts()
    local layer_color = Theme.layerColor("signal")

    -- ── 1. Concentric guide rings ──
    -- We draw 4 octagonal rings at 25%, 50%, 75%, 100% of radar_r.
    -- These give the viewer a sense of scale.
    for _, frac in ipairs({0.25, 0.50, 0.75, 1.00}) do
        local ring_pts = {}
        for i = 1, N_DIM do
            local angle = dimAngle(i)
            ring_pts[#ring_pts + 1] = radar_cx + math.cos(angle) * radar_r * frac
            ring_pts[#ring_pts + 1] = radar_cy + math.sin(angle) * radar_r * frac
        end
        -- Close the polygon by repeating the first point
        ring_pts[#ring_pts + 1] = ring_pts[1]
        ring_pts[#ring_pts + 1] = ring_pts[2]

        love.graphics.setLineWidth(1)
        if frac == 1.0 then
            love.graphics.setColor(Theme.colors.text_muted[1], Theme.colors.text_muted[2], Theme.colors.text_muted[3], 0.25)
        else
            love.graphics.setColor(Theme.colors.text_muted[1], Theme.colors.text_muted[2], Theme.colors.text_muted[3], 0.10)
        end
        love.graphics.line(ring_pts)

        -- Tick label on the first axis (straight up) for scale reference
        if frac > 0 then
            local tick_val = string.format("%.0f%%", frac * 100)
            local tx, ty = radarPoint(1, frac)
            love.graphics.setFont(fonts.small)
            love.graphics.setColor(Theme.colors.text_muted[1], Theme.colors.text_muted[2], Theme.colors.text_muted[3], 0.35)
            love.graphics.print(tick_val, tx + 4, ty - 4)
        end
    end

    -- ── 2. Axis lines from center to each tip ──
    love.graphics.setLineWidth(1)
    for i = 1, N_DIM do
        local tx, ty = radarPoint(i, 1.0)
        love.graphics.setColor(Theme.colors.text_muted[1], Theme.colors.text_muted[2], Theme.colors.text_muted[3], 0.12)
        love.graphics.line(radar_cx, radar_cy, tx, ty)
    end

    -- ── 3. Filled polygon (the signature shape) ──
    local poly = radarPolygon(anim_values)
    if #poly >= 6 then  -- need at least 3 points (6 coords)
        -- Semi-transparent fill with layer color
        love.graphics.setColor(layer_color[1], layer_color[2], layer_color[3], 0.12)
        -- Love2D polygon fill requires convex or uses triangulation.
        -- Our radar polygon for 8 axes can be non-convex if values vary wildly,
        -- so we triangulate from center to draw the fill reliably.
        for i = 1, N_DIM do
            local next_i = (i % N_DIM) + 1
            local x1, y1 = radarPoint(i, anim_values[i])
            local x2, y2 = radarPoint(next_i, anim_values[next_i])
            love.graphics.polygon("fill", radar_cx, radar_cy, x1, y1, x2, y2)
        end

        -- A second, brighter fill closer to center for depth
        for i = 1, N_DIM do
            local next_i = (i % N_DIM) + 1
            local inner = 0.5
            local x1, y1 = radarPoint(i, anim_values[i] * inner)
            local x2, y2 = radarPoint(next_i, anim_values[next_i] * inner)
            love.graphics.setColor(layer_color[1], layer_color[2], layer_color[3], 0.06)
            love.graphics.polygon("fill", radar_cx, radar_cy, x1, y1, x2, y2)
        end

        -- Outline stroke
        -- Close the polygon for the outline by appending the first point
        poly[#poly + 1] = poly[1]
        poly[#poly + 1] = poly[2]
        love.graphics.setLineWidth(2)
        love.graphics.setColor(layer_color[1], layer_color[2], layer_color[3], 0.7)
        love.graphics.line(poly)
        love.graphics.setLineWidth(1)
    end

    -- ── 4. Value dots on each axis with glow ──
    for i = 1, N_DIM do
        local v = anim_values[i]
        local dx, dy = radarPoint(i, v)

        -- Outer glow (pulses subtly)
        local pulse = 0.15 + 0.08 * math.sin(anim_time * 2.0 + i * 0.7)
        love.graphics.setColor(layer_color[1], layer_color[2], layer_color[3], pulse)
        love.graphics.circle("fill", dx, dy, 8)

        -- Inner dot
        love.graphics.setColor(layer_color[1], layer_color[2], layer_color[3], 0.9)
        love.graphics.circle("fill", dx, dy, 4)

        -- Bright center
        love.graphics.setColor(unpack(Theme.colors.text_dim))
        love.graphics.circle("fill", dx, dy, 1.5)
    end

    -- ── 5. Dimension labels at the tips ──
    love.graphics.setFont(fonts.small)
    for i = 1, N_DIM do
        local angle = dimAngle(i)
        local label_r = radar_r + 18
        local lx = radar_cx + math.cos(angle) * label_r
        local ly = radar_cy + math.sin(angle) * label_r

        local text = DIMENSIONS[i].name
        local tw = fonts.small:getWidth(text)
        local th = fonts.small:getHeight()

        -- Position label relative to the axis direction so it doesn't overlap the chart
        -- For axes pointing right, left-align; for left, right-align; center for top/bottom
        local nx = math.cos(angle)  -- normalized direction
        local ny = math.sin(angle)

        local draw_x = lx
        local draw_y = ly - th / 2

        if nx < -0.3 then
            -- Axis points left: right-align label
            draw_x = lx - tw
        elseif nx > 0.3 then
            -- Axis points right: left-align
            draw_x = lx
        else
            -- Near-vertical: center
            draw_x = lx - tw / 2
        end

        if ny < -0.3 then
            draw_y = ly - th - 2
        elseif ny > 0.3 then
            draw_y = ly + 2
        end

        -- Value annotation
        local val_str = string.format("%.0f%%", anim_values[i] * 100)
        local val_w = fonts.small:getWidth(val_str)

        -- Draw label text
        love.graphics.setColor(Theme.colors.text[1], Theme.colors.text[2], Theme.colors.text[3], 0.85)
        love.graphics.print(text, draw_x, draw_y)

        -- Draw value below/beside the label
        love.graphics.setColor(layer_color[1], layer_color[2], layer_color[3], 0.7)
        if ny > 0.3 then
            -- Below the chart: value on next line
            love.graphics.print(val_str, draw_x + (tw - val_w) / 2, draw_y + th + 1)
        elseif ny < -0.3 then
            -- Above the chart: value on previous line
            love.graphics.print(val_str, draw_x + (tw - val_w) / 2, draw_y - th - 1)
        else
            -- Sides: value after name
            love.graphics.print(val_str, draw_x, draw_y + th + 1)
        end
    end

    -- Center dot
    love.graphics.setColor(Theme.colors.text_muted[1], Theme.colors.text_muted[2], Theme.colors.text_muted[3], 0.3)
    love.graphics.circle("fill", radar_cx, radar_cy, 3)
end

-- ─────────────────────────────────────────────
-- Sidebar: Sliders + Presets
-- ─────────────────────────────────────────────

function Section:drawSidebar(sw, sh)
    local fonts = Theme.fonts()
    local layer_color = Theme.layerColor("signal")
    local y = sidebar_y + 4

    -- Section description
    love.graphics.setFont(fonts.small)
    love.graphics.setColor(unpack(Theme.colors.text_dim))
    love.graphics.printf(
        "Each dimension captures a psychoacoustic feature relevant to dance musicality. " ..
        "Drag the sliders to explore how different audio profiles shape the signature.",
        sidebar_x, y, sidebar_w, "left"
    )
    y = y + 36

    -- ── Dimension sliders ──
    -- Each slider has: name, value readout, and a brief description
    local slider_spacing = 54
    for i = 1, N_DIM do
        local dim = DIMENSIONS[i]

        -- Slider
        local new_val, changed = Widgets.slider(
            sidebar_x, y, sidebar_w, values[i],
            dim.name,
            {
                min = 0, max = 1,
                format = "%.2f",
                color = layer_color,
            }
        )
        if changed then
            values[i] = new_val
            active_preset = nil  -- user tweaked a slider, no longer on a preset
        end

        -- Brief description below the slider track
        love.graphics.setFont(fonts.small)
        love.graphics.setColor(Theme.colors.text_muted[1], Theme.colors.text_muted[2], Theme.colors.text_muted[3], 0.7)
        love.graphics.print(dim.short, sidebar_x + 2, y + 32)

        y = y + slider_spacing
    end

    y = y + 8

    -- ── Presets ──
    love.graphics.setFont(fonts.body)
    love.graphics.setColor(unpack(Theme.colors.text_dim))
    love.graphics.print("Presets", sidebar_x, y)
    y = y + 22

    preset_x = sidebar_x
    preset_y = y

    for idx, preset in ipairs(PRESETS) do
        local is_active = (active_preset == idx)
        local btn_color = is_active and layer_color or Theme.colors.text_dim

        Widgets.button(sidebar_x, y, preset.name, {
            w = sidebar_w,
            color = btn_color,
        })

        -- Active indicator: small colored bar on the left edge
        if is_active then
            love.graphics.setColor(layer_color[1], layer_color[2], layer_color[3], 0.8)
            love.graphics.rectangle("fill", sidebar_x, y + 4, 3, 24, 1, 1)
        end

        y = y + 38
    end
end

-- ─────────────────────────────────────────────
-- Educational Panel
-- ─────────────────────────────────────────────
--- The bottom panel provides deep educational content about the 8D signature,
--- its role in the bboy-analytics pipeline, and the signal processing concepts
--- underlying each dimension.

function Section:drawEducationalPanel(sw, sh)
    local fonts = Theme.fonts()
    local layer_color = Theme.layerColor("signal")

    -- Recompute panel position in case window resized
    panel_w = sw - 32
    panel_x = 16
    panel_h = 180
    panel_y = sh - panel_h - 42

    -- Panel background
    love.graphics.setColor(unpack(Theme.colors.panel_bg))
    Theme.roundRect("fill", panel_x, panel_y, panel_w, panel_h, Theme.radius.lg)
    love.graphics.setColor(unpack(Theme.colors.panel_border))
    Theme.roundRect("line", panel_x, panel_y, panel_w, panel_h, Theme.radius.lg)

    -- Subtle top accent bar
    love.graphics.setColor(layer_color[1], layer_color[2], layer_color[3], 0.15)
    love.graphics.rectangle("fill", panel_x, panel_y, panel_w, 3, Theme.radius.lg, Theme.radius.lg)

    -- Title
    love.graphics.setFont(fonts.heading)
    love.graphics.setColor(unpack(Theme.colors.text))
    love.graphics.print("Understanding the 8D Audio Signature", panel_x + 16, panel_y + 12)

    -- Content area: three columns of educational text
    local col_w = math.floor((panel_w - 64) / 3)
    local text_y = panel_y + 36
    local text_h = panel_h - 48
    local col_gap = 16

    -- Column 1: What the 8D signature means
    local col1_x = panel_x + 16
    love.graphics.setFont(fonts.small)
    love.graphics.setColor(layer_color[1], layer_color[2], layer_color[3], 0.8)
    love.graphics.print("What is the 8D Signature?", col1_x, text_y)
    love.graphics.setColor(Theme.colors.text_dim[1], Theme.colors.text_dim[2], Theme.colors.text_dim[3], 0.9)
    love.graphics.printf(
        "The 8D audio signature is a compact vector S = [s1..s8] that captures " ..
        "the perceptual qualities of music most relevant to dance. Each dimension " ..
        "is a normalized scalar extracted from the audio signal via standard DSP: " ..
        "FFT band power, onset detection, beat tracking, and spectral analysis. " ..
        "The signature tells us what kind of movement a track naturally invites " ..
        "-- heavy footwork (high bass, high percussion) vs. intricate musicality " ..
        "(high complexity, high harmonic richness).",
        col1_x, text_y + 16, col_w, "left"
    )

    -- Column 2: How it drives H(t)
    local col2_x = col1_x + col_w + col_gap
    love.graphics.setColor(layer_color[1], layer_color[2], layer_color[3], 0.8)
    love.graphics.print("From Signature to H(t)", col2_x, text_y)
    love.graphics.setColor(Theme.colors.text_dim[1], Theme.colors.text_dim[2], Theme.colors.text_dim[3], 0.9)
    love.graphics.printf(
        "bboy-analytics computes the audio heat signal H(t) as a weighted sum: " ..
        "H(t) = w . S(t), where w is a learned weight vector and S(t) is the " ..
        "time-varying 8D signature. Dimensions like bass energy and percussive " ..
        "strength contribute most to beat-aligned peaks in H(t), while spectral " ..
        "flux and dynamic range modulate the signal's envelope. The musicality " ..
        "score mu = max_tau corr(M(t), H(t-tau)) then measures how well a " ..
        "dancer's movement energy M(t) aligns with this perceptual heat map.",
        col2_x, text_y + 16, col_w, "left"
    )

    -- Column 3: Why these 8 dimensions?
    local col3_x = col2_x + col_w + col_gap
    love.graphics.setColor(layer_color[1], layer_color[2], layer_color[3], 0.8)
    love.graphics.print("Why These 8 Dimensions?", col3_x, text_y)
    love.graphics.setColor(Theme.colors.text_dim[1], Theme.colors.text_dim[2], Theme.colors.text_dim[3], 0.9)
    love.graphics.printf(
        "These 8 features were selected because they capture orthogonal axes of " ..
        "psychoacoustic perception that map to distinct movement patterns. Bass " ..
        "and percussion drive the body's rhythmic grounding. Vocal presence " ..
        "triggers interpretive expression. Beat stability vs. complexity creates " ..
        "the tension between predictability and surprise that expert dancers " ..
        "navigate. Harmonic richness adds emotional color. Dynamic range provides " ..
        "natural choreographic arcs. Together they span the space of " ..
        "'what makes music danceable' for breakdancing.",
        col3_x, text_y + 16, col_w, "left"
    )

    -- Active preset description (if any)
    if active_preset and PRESETS[active_preset] then
        local preset = PRESETS[active_preset]
        love.graphics.setFont(fonts.small)
        love.graphics.setColor(layer_color[1], layer_color[2], layer_color[3], 0.6)
        local desc_text = "Active: " .. preset.name .. " -- " .. preset.desc
        love.graphics.printf(desc_text, panel_x + 16, panel_y + panel_h - 20, panel_w - 32, "left")
    end
end

-- ─────────────────────────────────────────────
-- Input handlers
-- ─────────────────────────────────────────────

function Section:mousepressed(x, y, button)
    if button ~= 1 then return end

    -- Check preset buttons
    local btn_y = preset_y
    for idx, preset in ipairs(PRESETS) do
        if Widgets.buttonClicked(sidebar_x, btn_y, sidebar_w, 32, x, y) then
            -- Load preset values
            for i = 1, N_DIM do
                values[i] = preset.values[i]
            end
            active_preset = idx
            return
        end
        btn_y = btn_y + 38
    end
end

function Section:mousereleased(x, y, button)
    -- Slider release handled internally by Widgets
end

function Section:mousemoved(x, y, dx, dy)
    -- Hover states handled by Widgets in draw
end

function Section:keypressed(key)
    -- Number keys 1-4 load presets
    local num = tonumber(key)
    if num and num >= 1 and num <= #PRESETS then
        local preset = PRESETS[num]
        for i = 1, N_DIM do
            values[i] = preset.values[i]
        end
        active_preset = num
    elseif key == "r" then
        -- Reset to first preset
        local preset = PRESETS[1]
        for i = 1, N_DIM do
            values[i] = preset.values[i]
        end
        active_preset = 1
    elseif key == "space" then
        -- Randomize all values (for exploration)
        for i = 1, N_DIM do
            values[i] = 0.1 + math.random() * 0.8
        end
        active_preset = nil
    end
end

function Section:wheelmoved(x, y)
    -- Could be used for educational panel scrolling in future
end

function Section:unload()
    values = {}
    anim_values = {}
    anim_time = 0
    active_preset = nil
    edu_scroll = 0
end

return Section
