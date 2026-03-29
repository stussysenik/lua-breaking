--- Section 3.3: Musicality — Cross-Correlation (mu)
--- Hero section visualizing how movement energy syncs to audio beats.
--- Computes real cross-correlation between M(t) and time-shifted H(t-tau),
--- letting the learner drag tau to discover optimal alignment.
--- Research bridge: core mu metric — the musicality score.

local Theme = require("shell.theme")
local Draw  = require("lib.draw")
local Widgets = require("lib.widgets")

local Section = {}
Section.__index = Section

Section.meta = {
    id = "3.3",
    title = "Musicality — Cross-Correlation (\xCE\xBC)",
    layer = "signal",
    description = "How movement syncs to music: \xCE\xBC = max_\xCF\x84 corr(M(t), H(t-\xCF\x84))",
    research_mapping = "core \xCE\xBC metric",
    data_bridge = true,
    prerequisites = {"1.1"},
}

-- ─────────────────────────────────────────────
-- Signal generation
-- ─────────────────────────────────────────────
-- We generate two beat-like signals from layered sinusoids.
-- M(t) has peaks at slightly different phases so the learner
-- must find the right tau to align them with H(t).

local N_SAMPLES = 256            -- number of discrete samples
local DURATION  = 4.0            -- seconds of signal
local BPM       = 120            -- beats per minute for the underlying beat grid
local MAX_TAU   = 1.0            -- tau range: -MAX_TAU .. +MAX_TAU seconds

local mt_samples = {}            -- movement energy M(t)
local ht_samples = {}            -- audio heat H(t)
local corr_curve = {}            -- correlation as a function of tau
local tau_steps  = 201           -- resolution of the correlation curve

-- Interactive state
local tau_value      = 0.0       -- current tau chosen by the user
local optimal_tau    = 0.0       -- tau that maximizes correlation
local mu_value       = 0.0       -- current correlation at chosen tau
local mu_max         = 0.0       -- maximum correlation (the mu metric)
local anim_time      = 0.0       -- animation clock for subtle pulsing

-- Layout constants computed on load
local vis_x, vis_y, vis_w, vis_h
local sidebar_x, sidebar_w
local graph_top_y, graph_top_h
local graph_bot_y, graph_bot_h
local corr_graph_y, corr_graph_h

--- Build a realistic beat-aligned signal from sinusoidal harmonics.
--- @param phase_offset number  Phase offset in seconds (shifts beat alignment)
--- @param flavor number        1 = movement-like (sharper peaks), 2 = audio-like (warmer)
--- @return table samples       Array of N_SAMPLES values in roughly [0, 1]
local function generate_signal(phase_offset, flavor)
    local samples = {}
    local beat_freq = BPM / 60.0  -- Hz
    local dt = DURATION / N_SAMPLES

    for i = 1, N_SAMPLES do
        local t = (i - 1) * dt + phase_offset
        local v = 0

        -- Fundamental beat
        v = v + 0.45 * math.max(0, math.sin(2 * math.pi * beat_freq * t))

        -- Half-time accent (downbeat emphasis)
        v = v + 0.25 * math.max(0, math.sin(2 * math.pi * (beat_freq / 2) * t))

        if flavor == 1 then
            -- Movement: sharper transients, slight syncopation
            v = v + 0.15 * math.max(0, math.sin(2 * math.pi * beat_freq * 2 * t + 0.3))
            v = v + 0.10 * math.max(0, math.cos(2 * math.pi * beat_freq * 3 * t))
            -- Noise-like texture (deterministic pseudo-random via sin)
            v = v + 0.05 * math.abs(math.sin(t * 47.3 + i * 0.7))
        else
            -- Audio heat: fuller, smoother envelope
            v = v + 0.20 * math.max(0, math.sin(2 * math.pi * beat_freq * 2 * t))
            v = v + 0.08 * math.max(0, math.sin(2 * math.pi * beat_freq * 4 * t))
            v = v + 0.04 * math.abs(math.sin(t * 31.1 + i * 1.3))
        end

        samples[i] = v
    end

    -- Normalize to [0, 1]
    local lo, hi = math.huge, -math.huge
    for i = 1, #samples do
        if samples[i] < lo then lo = samples[i] end
        if samples[i] > hi then hi = samples[i] end
    end
    local range = hi - lo
    if range < 1e-8 then range = 1 end
    for i = 1, #samples do
        samples[i] = (samples[i] - lo) / range
    end

    return samples
end

--- Pearson correlation between two equal-length sample arrays.
--- @param a table  Signal A
--- @param b table  Signal B
--- @return number  Correlation in [-1, 1]
local function pearson(a, b)
    local n = math.min(#a, #b)
    if n < 2 then return 0 end

    local sum_a, sum_b = 0, 0
    for i = 1, n do
        sum_a = sum_a + a[i]
        sum_b = sum_b + b[i]
    end
    local mean_a = sum_a / n
    local mean_b = sum_b / n

    local cov, var_a, var_b = 0, 0, 0
    for i = 1, n do
        local da = a[i] - mean_a
        local db = b[i] - mean_b
        cov   = cov   + da * db
        var_a = var_a + da * da
        var_b = var_b + db * db
    end

    local denom = math.sqrt(var_a * var_b)
    if denom < 1e-12 then return 0 end
    return cov / denom
end

--- Shift signal B by a given number of samples (positive = shift right).
--- Uses zero-padding at boundaries.
--- @param sig table   Original signal
--- @param shift number Integer sample shift
--- @return table       Shifted signal (same length)
local function shift_signal(sig, shift)
    local n = #sig
    local out = {}
    for i = 1, n do
        local src = i - shift
        if src >= 1 and src <= n then
            out[i] = sig[src]
        else
            out[i] = 0
        end
    end
    return out
end

--- Build the full correlation curve and find the optimal tau.
local function build_correlation_curve()
    corr_curve = {}
    mu_max = -math.huge
    optimal_tau = 0

    local dt = DURATION / N_SAMPLES  -- seconds per sample

    for step = 1, tau_steps do
        local tau = -MAX_TAU + (step - 1) * (2 * MAX_TAU) / (tau_steps - 1)
        local sample_shift = math.floor(tau / dt + 0.5)
        local shifted = shift_signal(ht_samples, sample_shift)
        local r = pearson(mt_samples, shifted)

        corr_curve[step] = { tau = tau, r = r }

        if r > mu_max then
            mu_max = r
            optimal_tau = tau
        end
    end
end

--- Get the correlation for the current tau_value.
local function correlation_at_tau(tau)
    local dt = DURATION / N_SAMPLES
    local sample_shift = math.floor(tau / dt + 0.5)
    local shifted = shift_signal(ht_samples, sample_shift)
    return pearson(mt_samples, shifted)
end

--- Grade string based on mu value
local function grade_from_mu(mu)
    if mu >= 0.90 then return "S", {1.00, 0.84, 0.20}  -- gold
    elseif mu >= 0.75 then return "A", {0.20, 0.83, 0.60}  -- emerald
    elseif mu >= 0.55 then return "B", {0.49, 0.83, 0.99}  -- sky
    elseif mu >= 0.35 then return "C", {0.98, 0.75, 0.14}  -- amber
    else return "D", {0.98, 0.44, 0.52}  -- rose
    end
end

-- ─────────────────────────────────────────────
-- Section lifecycle
-- ─────────────────────────────────────────────

function Section:load()
    local sw, sh = love.graphics.getDimensions()

    -- Layout: visualization left 70%, sidebar right 30%
    vis_x = 20
    vis_y = 64
    vis_w = math.floor(sw * 0.68) - 40
    vis_h = sh - vis_y - 20

    sidebar_x = math.floor(sw * 0.70)
    sidebar_w = sw - sidebar_x - 16

    -- Divide visualization area into three vertical bands:
    --   1. Top graph: M(t)
    --   2. Bottom graph: H(t - tau)
    --   3. Correlation curve
    local usable_h = vis_h - 20  -- some bottom padding
    graph_top_y = vis_y + 10
    graph_top_h = math.floor(usable_h * 0.30)
    graph_bot_y = graph_top_y + graph_top_h + 16
    graph_bot_h = math.floor(usable_h * 0.30)
    corr_graph_y = graph_bot_y + graph_bot_h + 16
    corr_graph_h = usable_h - graph_top_h - graph_bot_h - 32

    -- Generate demo signals.
    -- The "true" offset between them simulates a dancer who is 0.15s behind the beat.
    local true_offset = 0.15
    mt_samples = generate_signal(true_offset, 1)
    ht_samples = generate_signal(0, 2)

    -- Compute full correlation curve
    build_correlation_curve()

    -- Start tau at zero so the learner sees a non-optimal state
    tau_value = 0
    mu_value = correlation_at_tau(tau_value)
    anim_time = 0
end

function Section:update(dt)
    anim_time = anim_time + dt

    -- Recalculate mu for current tau (lightweight: single pearson call)
    mu_value = correlation_at_tau(tau_value)
end

function Section:draw()
    local sw, sh = love.graphics.getDimensions()
    local fonts = Theme.fonts()

    -- Background
    love.graphics.setColor(unpack(Theme.colors.bg))
    love.graphics.rectangle("fill", 0, 0, sw, sh)
    Draw.dotGrid(0, 0, sw, sh, 30, 1, {1, 1, 1, 0.02})

    -- Title bar
    Draw.titleBar(Section.meta.title, Section.meta.layer, Section.meta.id)

    -- ── Draw the two signal graphs ──
    self:drawSignalGraph(
        "M(t) — Movement Energy", mt_samples, nil,
        vis_x, graph_top_y, vis_w, graph_top_h,
        {0.655, 0.545, 0.980},  -- violet (signal layer)
        false
    )

    -- For H(t), apply the current tau shift visually
    local dt_sample = DURATION / N_SAMPLES
    local sample_shift = math.floor(tau_value / dt_sample + 0.5)
    local ht_shifted = shift_signal(ht_samples, sample_shift)

    self:drawSignalGraph(
        string.format("H(t - \xCF\x84)  [\xCF\x84 = %.3fs]", tau_value), ht_shifted, ht_samples,
        vis_x, graph_bot_y, vis_w, graph_bot_h,
        {0.490, 0.827, 0.988},  -- sky
        true
    )

    -- ── Correlation curve ──
    self:drawCorrelationGraph(vis_x, corr_graph_y, vis_w, corr_graph_h)

    -- ── Tau slider ──
    local slider_y = corr_graph_y + corr_graph_h + 12
    love.graphics.setColor(unpack(Theme.colors.text))
    local new_tau, changed = Widgets.slider(
        vis_x, slider_y, vis_w, tau_value,
        "\xCF\x84 (tau) — time shift",
        {min = -MAX_TAU, max = MAX_TAU, format = "%+.3f s", color = Theme.colors.signal}
    )
    if changed then
        tau_value = new_tau
        mu_value = correlation_at_tau(tau_value)
    end

    -- ── Sidebar ──
    self:drawSidebar(sw, sh)

    -- ── Formula bar at bottom ──
    Draw.formula(
        "\xCE\xBC = max_\xCF\x84 corr(M(t), H(t-\xCF\x84))   |   \xCF\x84 \xE2\x88\x88 [-1.0, +1.0]s   |   N=" .. N_SAMPLES,
        20, sh - 40
    )
end

-- ─────────────────────────────────────────────
-- Signal graph renderer
-- ─────────────────────────────────────────────

--- Draw a single signal as a filled line graph inside a bordered box.
--- @param title string         Graph title
--- @param samples table        The sample array to draw
--- @param original table|nil   If non-nil, draw the original (un-shifted) as a ghost
--- @param gx number            Graph area x
--- @param gy number            Graph area y
--- @param gw number            Graph area width
--- @param gh number            Graph area height
--- @param color table          {r, g, b} primary color
--- @param show_ghost boolean   Whether to draw original as ghost line
function Section:drawSignalGraph(title, samples, original, gx, gy, gw, gh, color, show_ghost)
    local fonts = Theme.fonts()
    local n = #samples
    if n < 2 then return end

    -- Panel background
    love.graphics.setColor(color[1], color[2], color[3], 0.04)
    Theme.roundRect("fill", gx, gy, gw, gh, Theme.radius.md)
    love.graphics.setColor(color[1], color[2], color[3], 0.12)
    Theme.roundRect("line", gx, gy, gw, gh, Theme.radius.md)

    -- Title
    love.graphics.setFont(fonts.small)
    love.graphics.setColor(color[1], color[2], color[3], 0.8)
    love.graphics.print(title, gx + 10, gy + 4)

    -- Drawing area inside the panel (with padding)
    local pad = 8
    local dx = gx + pad
    local dy = gy + 20
    local dw = gw - pad * 2
    local dh = gh - 28

    -- Helper: sample index -> screen coords
    local function sampleToScreen(i, val)
        local sx = dx + (i - 1) / (n - 1) * dw
        local sy = dy + dh - val * dh
        return sx, sy
    end

    -- Ghost line (original un-shifted signal, dimmed)
    if show_ghost and original and #original == n then
        love.graphics.setColor(color[1], color[2], color[3], 0.10)
        love.graphics.setLineWidth(1)
        local pts = {}
        for i = 1, n do
            local sx, sy = sampleToScreen(i, original[i])
            pts[#pts + 1] = sx
            pts[#pts + 1] = sy
        end
        if #pts >= 4 then
            love.graphics.line(pts)
        end
    end

    -- Compute per-sample correlation similarity for color coding.
    -- Compare each sample of M(t) with the corresponding shifted H(t).
    -- We use a local window to decide "correlated" vs "uncorrelated".
    local sample_sim = {}
    local window = 8  -- half-window for local similarity
    for i = 1, n do
        -- Simple: absolute difference between M and shifted-H
        local m_val = mt_samples[i] or 0
        local h_val = samples[i] or 0  -- samples is already shifted H for the bottom graph
        local diff = math.abs(m_val - h_val)
        sample_sim[i] = math.max(0, 1 - diff * 1.5)
    end

    -- Filled area under curve with correlation-based glow
    for i = 1, n - 1 do
        local sx1, sy1 = sampleToScreen(i, samples[i])
        local sx2, sy2 = sampleToScreen(i + 1, samples[i + 1])
        local base_y = dy + dh

        -- Glow intensity based on local correlation
        local sim = (sample_sim[i] + sample_sim[i + 1]) / 2
        local glow_alpha = 0.03 + sim * 0.12
        love.graphics.setColor(color[1], color[2], color[3], glow_alpha)
        love.graphics.polygon("fill",
            sx1, sy1,
            sx2, sy2,
            sx2, base_y,
            sx1, base_y
        )
    end

    -- Main signal line with correlation-based brightness
    love.graphics.setLineWidth(1.5)
    for i = 1, n - 1 do
        local sx1, sy1 = sampleToScreen(i, samples[i])
        local sx2, sy2 = sampleToScreen(i + 1, samples[i + 1])
        local sim = (sample_sim[i] + sample_sim[i + 1]) / 2
        local alpha = 0.25 + sim * 0.65
        love.graphics.setColor(color[1], color[2], color[3], alpha)
        love.graphics.line(sx1, sy1, sx2, sy2)
    end
    love.graphics.setLineWidth(1)

    -- Zero line
    love.graphics.setColor(unpack(Theme.colors.border))
    love.graphics.line(dx, dy + dh, dx + dw, dy + dh)
end

-- ─────────────────────────────────────────────
-- Correlation curve renderer
-- ─────────────────────────────────────────────

function Section:drawCorrelationGraph(gx, gy, gw, gh)
    local fonts = Theme.fonts()
    local n = #corr_curve
    if n < 2 then return end

    -- Panel background
    love.graphics.setColor(0.08, 0.06, 0.12, 0.6)
    Theme.roundRect("fill", gx, gy, gw, gh, Theme.radius.md)
    love.graphics.setColor(0.655, 0.545, 0.980, 0.12)
    Theme.roundRect("line", gx, gy, gw, gh, Theme.radius.md)

    -- Title
    love.graphics.setFont(fonts.small)
    love.graphics.setColor(unpack(Theme.colors.text_dim))
    love.graphics.print("Cross-Correlation  corr(M, H(\xCF\x84))", gx + 10, gy + 4)

    -- Drawing area
    local pad = 8
    local dx = gx + pad
    local dy = gy + 20
    local dw = gw - pad * 2
    local dh = gh - 28

    -- Find range of correlation values for vertical scaling
    local r_min, r_max = math.huge, -math.huge
    for i = 1, n do
        if corr_curve[i].r < r_min then r_min = corr_curve[i].r end
        if corr_curve[i].r > r_max then r_max = corr_curve[i].r end
    end
    -- Ensure a minimum range so flat curves don't break
    if r_max - r_min < 0.01 then
        r_min = r_min - 0.1
        r_max = r_max + 0.1
    end

    -- Horizontal zero-correlation line
    local zero_y = dy + dh - (0 - r_min) / (r_max - r_min) * dh
    if zero_y >= dy and zero_y <= dy + dh then
        love.graphics.setColor(unpack(Theme.colors.border))
        love.graphics.line(dx, zero_y, dx + dw, zero_y)
    end

    -- Helper: tau index -> screen coords
    local function corrToScreen(i)
        local entry = corr_curve[i]
        local tx = dx + (entry.tau + MAX_TAU) / (2 * MAX_TAU) * dw
        local ty = dy + dh - (entry.r - r_min) / (r_max - r_min) * dh
        return tx, ty
    end

    -- Filled area under correlation curve
    local base_y = dy + dh
    for i = 1, n - 1 do
        local sx1, sy1 = corrToScreen(i)
        local sx2, sy2 = corrToScreen(i + 1)
        local r_avg = (corr_curve[i].r + corr_curve[i + 1].r) / 2
        local t = (r_avg - r_min) / (r_max - r_min)
        love.graphics.setColor(0.655, 0.545, 0.980, 0.02 + t * 0.08)
        love.graphics.polygon("fill",
            sx1, sy1,
            sx2, sy2,
            sx2, base_y,
            sx1, base_y
        )
    end

    -- Correlation curve line
    love.graphics.setLineWidth(2)
    local pts = {}
    for i = 1, n do
        local sx, sy = corrToScreen(i)
        pts[#pts + 1] = sx
        pts[#pts + 1] = sy
    end
    love.graphics.setColor(0.655, 0.545, 0.980, 0.7)
    if #pts >= 4 then
        love.graphics.line(pts)
    end
    love.graphics.setLineWidth(1)

    -- Optimal tau vertical line (green pulsing)
    local opt_sx = dx + (optimal_tau + MAX_TAU) / (2 * MAX_TAU) * dw
    local pulse = 0.5 + 0.3 * math.sin(anim_time * 2.5)
    love.graphics.setColor(0.20, 0.83, 0.60, pulse)
    love.graphics.setLineWidth(1.5)
    love.graphics.line(opt_sx, dy, opt_sx, dy + dh)
    love.graphics.setLineWidth(1)

    -- Label for optimal tau
    love.graphics.setFont(fonts.small)
    love.graphics.setColor(0.20, 0.83, 0.60, 0.8)
    local opt_label = string.format("\xCF\x84* = %.3fs", optimal_tau)
    local opt_lw = fonts.small:getWidth(opt_label)
    local opt_label_x = opt_sx - opt_lw / 2
    -- Keep label inside graph bounds
    opt_label_x = math.max(dx, math.min(dx + dw - opt_lw, opt_label_x))
    love.graphics.print(opt_label, opt_label_x, dy - 2)

    -- Current tau indicator (user-controlled, vertical dashed-style line)
    local cur_sx = dx + (tau_value + MAX_TAU) / (2 * MAX_TAU) * dw
    love.graphics.setColor(0.98, 0.75, 0.14, 0.7)
    love.graphics.setLineWidth(1)
    -- Draw a dashed line by drawing short segments
    local dash_len = 4
    local gap_len = 4
    local y_pos = dy
    while y_pos < dy + dh do
        local y_end = math.min(y_pos + dash_len, dy + dh)
        love.graphics.line(cur_sx, y_pos, cur_sx, y_end)
        y_pos = y_end + gap_len
    end

    -- Current correlation dot on the curve
    local cur_cy = dy + dh - (mu_value - r_min) / (r_max - r_min) * dh
    love.graphics.setColor(0.98, 0.75, 0.14, 1)
    love.graphics.circle("fill", cur_sx, cur_cy, 5)
    love.graphics.setColor(0.98, 0.75, 0.14, 0.3)
    love.graphics.circle("fill", cur_sx, cur_cy, 9)

    -- Axis labels
    love.graphics.setFont(fonts.small)
    love.graphics.setColor(unpack(Theme.colors.text_muted))
    love.graphics.print(string.format("%.1fs", -MAX_TAU), dx, dy + dh + 2)
    local right_label = string.format("+%.1fs", MAX_TAU)
    love.graphics.print(right_label, dx + dw - fonts.small:getWidth(right_label), dy + dh + 2)
    love.graphics.print(string.format("%.2f", r_max), dx + dw + 4, dy - 2)
    love.graphics.print(string.format("%.2f", r_min), dx + dw + 4, dy + dh - fonts.small:getHeight())
end

-- ─────────────────────────────────────────────
-- Sidebar
-- ─────────────────────────────────────────────

function Section:drawSidebar(sw, sh)
    local fonts = Theme.fonts()
    local y = vis_y + 4

    -- ── Mu display (large, prominent) ──
    local grade, grade_color = grade_from_mu(mu_value)

    -- Current correlation card
    love.graphics.setColor(0.06, 0.06, 0.09, 0.95)
    Theme.roundRect("fill", sidebar_x, y, sidebar_w, 80, Theme.radius.lg)
    love.graphics.setColor(grade_color[1], grade_color[2], grade_color[3], 0.15)
    Theme.roundRect("fill", sidebar_x, y, sidebar_w, 80, Theme.radius.lg)
    love.graphics.setColor(unpack(Theme.colors.border))
    Theme.roundRect("line", sidebar_x, y, sidebar_w, 80, Theme.radius.lg)

    -- Grade badge
    love.graphics.setFont(fonts.title)
    love.graphics.setColor(grade_color[1], grade_color[2], grade_color[3], 1)
    love.graphics.print(grade, sidebar_x + 14, y + 10)

    -- Mu value
    love.graphics.setFont(fonts.heading)
    love.graphics.setColor(unpack(Theme.colors.text))
    local mu_str = string.format("\xCE\xBC = %.4f", mu_value)
    love.graphics.print(mu_str, sidebar_x + 50, y + 12)

    -- Subtitle
    love.graphics.setFont(fonts.small)
    love.graphics.setColor(unpack(Theme.colors.text_dim))
    love.graphics.print("current cross-correlation", sidebar_x + 50, y + 34)

    -- Optimal mu
    love.graphics.setColor(0.20, 0.83, 0.60, 0.8)
    love.graphics.setFont(fonts.mono)
    local opt_str = string.format("optimal: \xCE\xBC* = %.4f  at \xCF\x84* = %.3fs", mu_max, optimal_tau)
    love.graphics.print(opt_str, sidebar_x + 14, y + 56)

    y = y + 96

    -- ── Grade scale ──
    Draw.infoPanel(sidebar_x, y, sidebar_w, {
        {"Grade Scale", ""},
        {"S  (>= 0.90)", "perfect sync"},
        {"A  (>= 0.75)", "strong sync"},
        {"B  (>= 0.55)", "moderate sync"},
        {"C  (>= 0.35)", "weak sync"},
        {"D  (< 0.35)",  "no sync"},
    })

    y = y + 172

    -- ── Parameters ──
    Draw.infoPanel(sidebar_x, y, sidebar_w, {
        {"\xCF\x84 (tau)", string.format("%+.3f s", tau_value)},
        {"Samples", tostring(N_SAMPLES)},
        {"Duration", string.format("%.1f s", DURATION)},
        {"BPM", tostring(BPM)},
        {"\xCF\x84 range", string.format("\xC2\xB1%.1f s", MAX_TAU)},
    })

    y = y + 152

    -- ── Controls ──
    Widgets.button(sidebar_x, y, "Reset \xCF\x84 to 0",
        {w = sidebar_w, color = Theme.colors.signal})
    y = y + 40
    Widgets.button(sidebar_x, y, "Snap to Optimal \xCF\x84*",
        {w = sidebar_w, color = Theme.colors.success})
    y = y + 40
    Widgets.button(sidebar_x, y, "Regenerate Signals",
        {w = sidebar_w, color = Theme.colors.warning})
    y = y + 60

    -- ── Educational explanation ──
    love.graphics.setColor(unpack(Theme.colors.border))
    Theme.roundRect("fill", sidebar_x, y, sidebar_w, sh - y - 56, Theme.radius.md)

    love.graphics.setFont(fonts.small)
    love.graphics.setColor(unpack(Theme.colors.text_muted))
    love.graphics.printf(
        "CROSS-CORRELATION\n\n" ..
        "Cross-correlation measures how similar two signals are as a " ..
        "function of a time lag applied to one of them.\n\n" ..
        "M(t) is the movement energy extracted from pose keypoints " ..
        "(joint velocities summed over the skeleton).\n\n" ..
        "H(t) is the audio beat energy (onset strength from the " ..
        "music waveform).\n\n" ..
        "\xCF\x84 (tau) shifts H in time. When peaks in M align with peaks " ..
        "in H, the correlation is high — the dancer is on beat.\n\n" ..
        "\xCE\xBC = max_\xCF\x84 corr(M, H(\xCF\x84)) captures the best possible " ..
        "alignment. A high \xCE\xBC means the dancer's energy peaks are " ..
        "tightly locked to the musical beats, regardless of a small " ..
        "constant latency.\n\n" ..
        "Drag the \xCF\x84 slider to see how shifting the audio curve " ..
        "changes the correlation value.",
        sidebar_x + 10, y + 10, sidebar_w - 20, "left"
    )
end

-- ─────────────────────────────────────────────
-- Input handlers
-- ─────────────────────────────────────────────

function Section:mousepressed(x, y, button)
    if button ~= 1 then return end

    local sw, sh = love.graphics.getDimensions()

    -- Check sidebar buttons
    local btn_y = vis_y + 4 + 96 + 172 + 152

    -- "Reset tau to 0" button
    if Widgets.buttonClicked(sidebar_x, btn_y, sidebar_w, 32, x, y) then
        tau_value = 0
        mu_value = correlation_at_tau(tau_value)
        return
    end

    btn_y = btn_y + 40
    -- "Snap to Optimal" button
    if Widgets.buttonClicked(sidebar_x, btn_y, sidebar_w, 32, x, y) then
        tau_value = optimal_tau
        mu_value = correlation_at_tau(tau_value)
        return
    end

    btn_y = btn_y + 40
    -- "Regenerate Signals" button
    if Widgets.buttonClicked(sidebar_x, btn_y, sidebar_w, 32, x, y) then
        -- Regenerate with a random offset so the optimal tau changes each time
        local offset = 0.05 + math.random() * 0.4
        -- Randomize sign
        if math.random() > 0.5 then offset = -offset end
        mt_samples = generate_signal(offset, 1)
        ht_samples = generate_signal(0, 2)
        build_correlation_curve()
        mu_value = correlation_at_tau(tau_value)
        return
    end
end

function Section:mousereleased(x, y, button)
    -- Slider release handled by Widgets internally
end

function Section:mousemoved(x, y, dx, dy)
    -- Hover states handled in draw via Widgets
end

function Section:keypressed(key)
    if key == "r" then
        -- Reset tau
        tau_value = 0
        mu_value = correlation_at_tau(tau_value)
    elseif key == "o" then
        -- Snap to optimal
        tau_value = optimal_tau
        mu_value = correlation_at_tau(tau_value)
    elseif key == "left" then
        -- Nudge tau left
        tau_value = math.max(-MAX_TAU, tau_value - 0.01)
        mu_value = correlation_at_tau(tau_value)
    elseif key == "right" then
        -- Nudge tau right
        tau_value = math.min(MAX_TAU, tau_value + 0.01)
        mu_value = correlation_at_tau(tau_value)
    elseif key == "g" then
        -- Regenerate signals
        local offset = 0.05 + math.random() * 0.4
        if math.random() > 0.5 then offset = -offset end
        mt_samples = generate_signal(offset, 1)
        ht_samples = generate_signal(0, 2)
        build_correlation_curve()
        mu_value = correlation_at_tau(tau_value)
    end
end

function Section:unload()
    mt_samples = {}
    ht_samples = {}
    corr_curve = {}
    tau_value = 0
    mu_value = 0
    mu_max = 0
    optimal_tau = 0
    anim_time = 0
end

return Section
