--- Section 3.1: Beat Detection
--- Interactive visualization of the beat detection pipeline:
---   Raw Waveform → Energy Envelope (RMS) → Onset Detection → Thresholding
---
--- Teaches the fundamental signal processing chain used in music analysis.
--- The same pipeline underlies BeatNet+ in the bboy-analytics system,
--- where detected beats are cross-correlated with movement energy (mu metric).
---
--- The learner can toggle each processing stage on/off, adjust the threshold
--- and window size, and watch how those parameters affect beat detection
--- accuracy in real time.
---
--- Research bridge: BeatNet+ integration (beat detection for mu metric)

local Theme   = require("shell.theme")
local Draw    = require("lib.draw")
local Widgets = require("lib.widgets")

local Section = {}
Section.__index = Section

Section.meta = {
    id = "3.1",
    title = "Beat Detection",
    layer = "signal",
    description = "How beats are detected in audio: energy, onsets, thresholds",
    research_mapping = "BeatNet+ integration",
    data_bridge = false,
    prerequisites = {},
}

-- ─────────────────────────────────────────────
-- Constants
-- ─────────────────────────────────────────────

local SAMPLE_RATE  = 800          -- samples for ~4 seconds of "audio" (enough resolution for smooth curves)
local DURATION     = 4.0          -- seconds of simulated audio
local BPM          = 120          -- beats per minute for ground truth
local BEAT_INTERVAL = 60 / BPM   -- seconds between true beats

-- ─────────────────────────────────────────────
-- State
-- ─────────────────────────────────────────────

-- Raw waveform samples (bipolar, like real audio)
local waveform = {}

-- Computed signals (populated in recompute())
local energy_envelope = {}   -- RMS energy in sliding windows
local onset_function  = {}   -- positive half-wave rectified derivative of energy
local detected_beats  = {}   -- indices where onset peaks exceed threshold
local true_beat_times = {}   -- ground truth beat times in seconds

-- Interactive parameters
local threshold    = 0.35    -- onset detection threshold (0..1 of max onset)
local window_size  = 32      -- RMS window size in samples (controls smoothing)

-- Toggle visibility of each processing stage
local show_energy    = true
local show_onset     = true
local show_threshold = true

-- Animation
local anim_time = 0

-- Layout (computed on load)
local vis_x, vis_y, vis_w
local waveform_y, waveform_h
local onset_y, onset_h
local sidebar_x, sidebar_w

-- ─────────────────────────────────────────────
-- Waveform generation
-- ─────────────────────────────────────────────
--- Generate a realistic-looking audio waveform from layered sinusoids and noise.
--- The waveform has clear rhythmic structure at the given BPM so beat detection
--- actually has something meaningful to find.
---
--- How it works:
---   1. A "kick" envelope pulses at each beat — a sharp attack/decay that simulates
---      a bass drum hit. This is the dominant energy source at beat positions.
---   2. An "off-beat" hi-hat pattern adds energy between beats at half-beat intervals.
---   3. Harmonic content (low/mid/high frequency sinusoids) fills out the waveform
---      so it looks like real audio rather than a click track.
---   4. Broadband noise gives it that raw, organic texture.
---
--- The result is bipolar (values roughly in [-1, 1]) just like a real PCM waveform.
local function generate_waveform()
    local samples = {}
    true_beat_times = {}
    local dt = DURATION / SAMPLE_RATE

    -- Pre-calculate true beat times for ground truth comparison
    local t_beat = 0
    while t_beat < DURATION do
        table.insert(true_beat_times, t_beat)
        t_beat = t_beat + BEAT_INTERVAL
    end

    for i = 1, SAMPLE_RATE do
        local t = (i - 1) * dt
        local v = 0

        -- 1. Kick drum envelope: sharp transient at each beat
        --    Uses an exponential decay from each beat onset.
        --    This creates the energy spikes that the detector should find.
        for _, bt in ipairs(true_beat_times) do
            local delta = t - bt
            if delta >= 0 and delta < 0.3 then
                -- Fast attack, medium decay
                local env = math.exp(-delta * 12)
                -- Low frequency thump (like a real kick ~60Hz)
                v = v + env * 0.7 * math.sin(2 * math.pi * 62 * delta)
                -- Click transient (higher frequency burst at onset)
                if delta < 0.02 then
                    v = v + env * 0.3 * math.sin(2 * math.pi * 800 * delta)
                end
            end
        end

        -- 2. Hi-hat pattern: off-beat energy at half-beat intervals
        for _, bt in ipairs(true_beat_times) do
            local half_beat = bt + BEAT_INTERVAL * 0.5
            local delta = t - half_beat
            if delta >= 0 and delta < 0.08 then
                local env = math.exp(-delta * 40)
                -- High-frequency noise-like content
                v = v + env * 0.15 * math.sin(2 * math.pi * 3200 * delta + delta * 1500)
            end
        end

        -- 3. Harmonic content (fills out the spectrum, makes it look like audio)
        -- Bass line (follows the beat, one octave below kick)
        v = v + 0.10 * math.sin(2 * math.pi * 31 * t)
        -- Mid-range melodic content
        v = v + 0.06 * math.sin(2 * math.pi * 220 * t + math.sin(t * 3) * 0.5)
        v = v + 0.04 * math.sin(2 * math.pi * 330 * t)
        -- High harmonic shimmer
        v = v + 0.02 * math.sin(2 * math.pi * 880 * t + t * 2)

        -- 4. Broadband noise (deterministic pseudo-random via layered sin)
        --    Real audio always has noise. This makes the waveform look authentic.
        v = v + 0.04 * math.sin(t * 1571.3 + i * 0.731)
        v = v + 0.03 * math.sin(t * 2719.7 + i * 1.137)
        v = v + 0.02 * math.sin(t * 4513.1 + i * 0.519)

        samples[i] = v
    end

    return samples
end

-- ─────────────────────────────────────────────
-- Signal processing pipeline
-- ─────────────────────────────────────────────
--- Compute the RMS (Root Mean Square) energy in a sliding window.
---
--- This is step 2 of the beat detection pipeline. Raw audio samples oscillate
--- wildly between positive and negative values — you can't detect beats from
--- individual samples. RMS squashes the waveform into a smooth power curve
--- where each value represents the energy in a local neighborhood.
---
--- Formula: E(t) = sqrt( (1/N) * sum( x[n]^2 ) )  for n in [t-N/2, t+N/2]
---
--- Larger windows = smoother envelope (less detail, fewer false positives)
--- Smaller windows = more responsive (more detail, but noisier)
---
--- @param samples table  Raw waveform (bipolar values)
--- @param win     number Window size in samples
--- @return table         Energy envelope (same length as input)
local function compute_energy_envelope(samples, win)
    local n = #samples
    local envelope = {}
    local half_win = math.floor(win / 2)

    for i = 1, n do
        local sum_sq = 0
        local count = 0
        -- Centered window: look half_win samples in each direction
        for j = math.max(1, i - half_win), math.min(n, i + half_win) do
            sum_sq = sum_sq + samples[j] * samples[j]
            count = count + 1
        end
        -- RMS = root of mean of squares
        envelope[i] = math.sqrt(sum_sq / count)
    end

    return envelope
end

--- Compute the onset detection function: half-wave rectified derivative of energy.
---
--- This is step 3 of the pipeline. The energy envelope shows loudness over time,
--- but beats are *changes* in loudness — specifically, sudden *increases*.
---
--- Taking the derivative (dE/dt) highlights transitions. Half-wave rectification
--- (keeping only positive values, zeroing negatives) isolates *increases only*.
--- A sudden jump in energy → large positive spike → likely a beat onset.
---
--- This is the "spectral flux" approach simplified to the time domain.
---
--- @param envelope table  Energy envelope from compute_energy_envelope()
--- @return table          Onset function (same length, non-negative values)
--- @return number         Maximum onset value (for normalizing threshold)
local function compute_onset_function(envelope)
    local n = #envelope
    local onsets = {}
    local max_onset = 0

    onsets[1] = 0  -- no derivative at the first sample
    for i = 2, n do
        -- First derivative (forward difference)
        local diff = envelope[i] - envelope[i - 1]
        -- Half-wave rectification: only keep positive (energy increases)
        -- Negative derivatives mean energy is decreasing — not a beat onset
        onsets[i] = math.max(0, diff)
        if onsets[i] > max_onset then
            max_onset = onsets[i]
        end
    end

    return onsets, max_onset
end

--- Detect beats by finding peaks in the onset function above a threshold.
---
--- This is step 4, the final stage. A peak is a local maximum where:
---   onset[i] > onset[i-1]  AND  onset[i] > onset[i+1]  AND  onset[i] > threshold
---
--- The threshold controls sensitivity:
---   Too low  → every tiny energy fluctuation is "a beat" (false positives)
---   Too high → only the loudest hits are detected (missed beats)
---
--- In real systems, adaptive thresholds track the running average of onset
--- strength. Here we use a fixed threshold for clarity.
---
--- @param onsets     table   Onset function
--- @param max_onset  number  Maximum onset value (from compute_onset_function)
--- @param thresh     number  Threshold as a fraction of max_onset (0..1)
--- @return table             Array of {index, is_true_positive} for each detected beat
local function detect_beats(onsets, max_onset, thresh)
    local n = #onsets
    local abs_thresh = thresh * max_onset
    local beats = {}
    local dt = DURATION / SAMPLE_RATE

    -- Minimum distance between detected beats (prevents double-triggers)
    -- A real beat can't happen faster than ~300 BPM = 0.2s apart
    local min_gap = math.floor(0.15 / dt)

    local last_beat_idx = -min_gap

    for i = 3, n - 1 do
        -- Peak detection: local maximum above threshold with minimum gap
        if onsets[i] > abs_thresh
            and onsets[i] >= onsets[i - 1]
            and onsets[i] >= onsets[i + 1]
            and (i - last_beat_idx) >= min_gap then

            -- Check if this detected beat matches a true beat
            local beat_time = (i - 1) * dt
            local is_tp = false
            -- A detection within 0.08s of a true beat = true positive
            for _, tb in ipairs(true_beat_times) do
                if math.abs(beat_time - tb) < 0.08 then
                    is_tp = true
                    break
                end
            end

            table.insert(beats, {index = i, is_true_positive = is_tp, time = beat_time})
            last_beat_idx = i
        end
    end

    return beats
end

--- Recompute the full pipeline from current parameters.
--- Called on load and whenever threshold or window_size changes.
local function recompute()
    energy_envelope = compute_energy_envelope(waveform, window_size)
    local max_onset
    onset_function, max_onset = compute_onset_function(energy_envelope)
    detected_beats = detect_beats(onset_function, max_onset, threshold)
end

-- ─────────────────────────────────────────────
-- Statistics
-- ─────────────────────────────────────────────
--- Count true positives, false positives, and estimate BPM from detected beats.
local function compute_stats()
    local tp, fp = 0, 0
    for _, b in ipairs(detected_beats) do
        if b.is_true_positive then
            tp = tp + 1
        else
            fp = fp + 1
        end
    end

    -- BPM estimate from average inter-beat interval
    local bpm_est = 0
    if #detected_beats >= 2 then
        local dt = DURATION / SAMPLE_RATE
        local intervals = {}
        for i = 2, #detected_beats do
            local gap = (detected_beats[i].index - detected_beats[i - 1].index) * dt
            if gap > 0.15 then -- ignore sub-beat gaps
                table.insert(intervals, gap)
            end
        end
        if #intervals > 0 then
            local avg = 0
            for _, v in ipairs(intervals) do avg = avg + v end
            avg = avg / #intervals
            bpm_est = 60 / avg
        end
    end

    return {
        total     = #detected_beats,
        tp        = tp,
        fp        = fp,
        bpm_est   = bpm_est,
        true_beats = #true_beat_times,
    }
end

-- ─────────────────────────────────────────────
-- Section lifecycle
-- ─────────────────────────────────────────────

function Section:load()
    local sw, sh = love.graphics.getDimensions()

    -- Layout: visualization left 65%, sidebar right 32%, 3% gap
    vis_x = 20
    vis_y = 64
    vis_w = math.floor(sw * 0.65) - 40

    sidebar_x = math.floor(sw * 0.68)
    sidebar_w = sw - sidebar_x - 16

    -- Vertical layout of visualization area
    -- Top: waveform + energy overlay (~55% of vis height)
    -- Bottom: onset function (~35% of vis height)
    -- Gap between them
    local total_vis_h = sh - vis_y - 20
    waveform_y = vis_y + 10
    waveform_h = math.floor(total_vis_h * 0.52)
    onset_y    = waveform_y + waveform_h + 16
    onset_h    = math.floor(total_vis_h * 0.35)

    -- Generate waveform and run initial pipeline
    waveform = generate_waveform()
    recompute()

    anim_time = 0
end

function Section:update(dt)
    anim_time = anim_time + dt
end

function Section:draw()
    local sw, sh = love.graphics.getDimensions()
    local fonts = Theme.fonts()
    local layer_color = Theme.layerColor("signal")

    -- Background
    love.graphics.setColor(unpack(Theme.colors.bg))
    love.graphics.rectangle("fill", 0, 0, sw, sh)
    Draw.dotGrid(0, 0, sw, sh, 30, 1, Theme.colors.grid_dot)

    -- Title bar
    Draw.titleBar(Section.meta.title, Section.meta.layer, Section.meta.id)

    Widgets.beginFrame()

    -- ── Waveform panel (top visualization area) ──
    self:drawWaveformPanel(layer_color)

    -- ── Onset function panel (bottom visualization area) ──
    if show_onset then
        self:drawOnsetPanel(layer_color)
    end

    -- ── Sidebar ──
    self:drawSidebar(sw, sh, layer_color)

    -- ── Formula bar ──
    Draw.formula(
        "E(t) = sqrt(1/N * sum(x[n]^2))   |   onset = max(0, dE/dt)   |   beat if onset > T",
        20, sh - 40
    )
end

-- ─────────────────────────────────────────────
-- Waveform + Energy panel
-- ─────────────────────────────────────────────
--- Draws the main waveform as a filled area chart with the energy envelope overlaid.
--- Beat markers (vertical lines) are drawn if the threshold stage is active.
--- This is the primary visualization that shows the raw audio and the first
--- processing step (RMS energy extraction).
function Section:drawWaveformPanel(layer_color)
    local fonts = Theme.fonts()
    local n = #waveform
    if n < 2 then return end

    local gx, gy, gw, gh = vis_x, waveform_y, vis_w, waveform_h

    -- Panel background
    love.graphics.setColor(unpack(Theme.colors.bg_surface))
    Theme.roundRect("fill", gx, gy, gw, gh, Theme.radius.md)
    love.graphics.setColor(layer_color[1], layer_color[2], layer_color[3], 0.12)
    Theme.roundRect("line", gx, gy, gw, gh, Theme.radius.md)

    -- Title
    love.graphics.setFont(fonts.small)
    love.graphics.setColor(unpack(Theme.colors.text_dim))
    love.graphics.print("RAW WAVEFORM", gx + 10, gy + 6)

    if show_energy then
        love.graphics.setColor(Theme.colors.warning[1], Theme.colors.warning[2], Theme.colors.warning[3], 0.7)
        love.graphics.print("+ ENERGY ENVELOPE (RMS)", gx + 120, gy + 6)
    end

    -- Drawing area (with padding)
    local pad = 10
    local dx = gx + pad
    local dy = gy + 22
    local dw = gw - pad * 2
    local dh = gh - 30

    -- The waveform is bipolar. Map [-peak, +peak] to [dy+dh, dy].
    -- Find peak amplitude for scaling
    local peak = 0
    for i = 1, n do
        local a = math.abs(waveform[i])
        if a > peak then peak = a end
    end
    if peak < 0.001 then peak = 1 end

    -- Center line (zero crossing)
    local center_y = dy + dh * 0.5
    love.graphics.setColor(unpack(Theme.colors.border))
    love.graphics.line(dx, center_y, dx + dw, center_y)

    -- Time axis labels
    love.graphics.setFont(fonts.small)
    love.graphics.setColor(unpack(Theme.colors.text_muted))
    for sec = 0, math.floor(DURATION) do
        local sx = dx + (sec / DURATION) * dw
        love.graphics.print(string.format("%ds", sec), sx, gy + gh - 14)
        love.graphics.setColor(unpack(Theme.colors.border))
        love.graphics.line(sx, dy, sx, dy + dh)
        love.graphics.setColor(unpack(Theme.colors.text_muted))
    end

    -- ── Beat markers (drawn behind waveform for layering) ──
    if show_threshold and #detected_beats > 0 then
        for _, beat in ipairs(detected_beats) do
            local bx = dx + (beat.index - 1) / (n - 1) * dw
            if beat.is_true_positive then
                -- True positive: green
                love.graphics.setColor(Theme.colors.success[1], Theme.colors.success[2], Theme.colors.success[3], 0.20)
            else
                -- False positive: red
                love.graphics.setColor(Theme.colors.error[1], Theme.colors.error[2], Theme.colors.error[3], 0.20)
            end
            love.graphics.rectangle("fill", bx - 1, dy, 3, dh)
        end
    end

    -- ── Waveform: filled area from center line ──
    -- Draw as vertical line segments for each sample (efficient, clean look)
    love.graphics.setColor(layer_color[1], layer_color[2], layer_color[3], 0.25)
    local step = math.max(1, math.floor(n / dw))
    for i = 1, n, step do
        local sx = dx + (i - 1) / (n - 1) * dw
        local sample = waveform[i] / peak
        local sy = center_y - sample * (dh * 0.45)
        -- Draw from center to sample point
        love.graphics.line(sx, center_y, sx, sy)
    end

    -- Waveform outline (top and bottom envelopes for a cleaner look)
    love.graphics.setColor(layer_color[1], layer_color[2], layer_color[3], 0.5)
    love.graphics.setLineWidth(1)
    local top_pts = {}
    local bot_pts = {}
    -- Downsample to one point per pixel for performance
    local px_step = math.max(1, math.floor(n / dw))
    for i = 1, n, px_step do
        local sx = dx + (i - 1) / (n - 1) * dw
        local sample = waveform[i] / peak
        local sy = center_y - sample * (dh * 0.45)
        top_pts[#top_pts + 1] = sx
        top_pts[#top_pts + 1] = math.min(sy, center_y)
        bot_pts[#bot_pts + 1] = sx
        bot_pts[#bot_pts + 1] = math.max(sy, center_y)
    end
    if #top_pts >= 4 then love.graphics.line(top_pts) end

    -- ── Energy envelope overlay ──
    if show_energy and #energy_envelope == n then
        -- Find peak energy for scaling
        local e_peak = 0
        for i = 1, n do
            if energy_envelope[i] > e_peak then e_peak = energy_envelope[i] end
        end
        if e_peak < 0.001 then e_peak = 1 end

        -- Draw as filled area from bottom
        local energy_color = Theme.colors.warning
        love.graphics.setColor(energy_color[1], energy_color[2], energy_color[3], 0.08)
        for i = 1, n - 1, px_step do
            local i2 = math.min(n, i + px_step)
            local sx1 = dx + (i - 1) / (n - 1) * dw
            local sx2 = dx + (i2 - 1) / (n - 1) * dw
            local e1 = energy_envelope[i] / e_peak
            local e2 = energy_envelope[i2] / e_peak
            local sy1 = dy + dh - e1 * dh * 0.9
            local sy2 = dy + dh - e2 * dh * 0.9
            love.graphics.polygon("fill", sx1, sy1, sx2, sy2, sx2, dy + dh, sx1, dy + dh)
        end

        -- Energy envelope line
        love.graphics.setColor(energy_color[1], energy_color[2], energy_color[3], 0.8)
        love.graphics.setLineWidth(2)
        local e_pts = {}
        for i = 1, n, px_step do
            local sx = dx + (i - 1) / (n - 1) * dw
            local e = energy_envelope[i] / e_peak
            local sy = dy + dh - e * dh * 0.9
            e_pts[#e_pts + 1] = sx
            e_pts[#e_pts + 1] = sy
        end
        if #e_pts >= 4 then love.graphics.line(e_pts) end
        love.graphics.setLineWidth(1)

        -- Label
        love.graphics.setFont(fonts.small)
        love.graphics.setColor(energy_color[1], energy_color[2], energy_color[3], 0.6)
        love.graphics.print("E(t)", dx + dw - 30, dy + 4)
    end

    -- ── Beat marker labels on top ──
    if show_threshold and #detected_beats > 0 then
        love.graphics.setFont(fonts.small)
        for _, beat in ipairs(detected_beats) do
            local bx = dx + (beat.index - 1) / (n - 1) * dw
            if beat.is_true_positive then
                love.graphics.setColor(Theme.colors.success[1], Theme.colors.success[2], Theme.colors.success[3], 0.9)
            else
                love.graphics.setColor(Theme.colors.error[1], Theme.colors.error[2], Theme.colors.error[3], 0.9)
            end
            -- Small triangle marker at top
            love.graphics.polygon("fill", bx, dy + 2, bx - 4, dy - 4, bx + 4, dy - 4)
        end
    end

    -- True beat indicators (subtle tick marks at bottom regardless of toggle)
    love.graphics.setFont(fonts.small)
    love.graphics.setColor(unpack(Theme.colors.text_muted))
    for _, bt in ipairs(true_beat_times) do
        local bx = dx + (bt / DURATION) * dw
        love.graphics.line(bx, dy + dh - 3, bx, dy + dh + 3)
    end
end

-- ─────────────────────────────────────────────
-- Onset detection function panel
-- ─────────────────────────────────────────────
--- Draws the onset detection function as a separate chart below the waveform.
--- The threshold line is overlaid so the learner can see exactly which peaks
--- exceed it and become detected beats.
function Section:drawOnsetPanel(layer_color)
    local fonts = Theme.fonts()
    local n = #onset_function
    if n < 2 then return end

    local gx, gy, gw, gh = vis_x, onset_y, vis_w, onset_h

    -- Panel background
    love.graphics.setColor(unpack(Theme.colors.bg_surface))
    Theme.roundRect("fill", gx, gy, gw, gh, Theme.radius.md)
    love.graphics.setColor(layer_color[1], layer_color[2], layer_color[3], 0.12)
    Theme.roundRect("line", gx, gy, gw, gh, Theme.radius.md)

    -- Title
    love.graphics.setFont(fonts.small)
    love.graphics.setColor(unpack(Theme.colors.text_dim))
    love.graphics.print("ONSET DETECTION FUNCTION  (dE/dt, half-wave rectified)", gx + 10, gy + 6)

    -- Drawing area
    local pad = 10
    local dx = gx + pad
    local dy = gy + 22
    local dw = gw - pad * 2
    local dh = gh - 30

    -- Find peak onset for scaling
    local o_peak = 0
    for i = 1, n do
        if onset_function[i] > o_peak then o_peak = onset_function[i] end
    end
    if o_peak < 0.0001 then o_peak = 1 end

    -- Zero line
    love.graphics.setColor(unpack(Theme.colors.border))
    love.graphics.line(dx, dy + dh, dx + dw, dy + dh)

    -- Time axis labels
    love.graphics.setFont(fonts.small)
    love.graphics.setColor(unpack(Theme.colors.text_muted))
    for sec = 0, math.floor(DURATION) do
        local sx = dx + (sec / DURATION) * dw
        love.graphics.print(string.format("%ds", sec), sx, gy + gh - 14)
        love.graphics.setColor(unpack(Theme.colors.border))
        love.graphics.line(sx, dy, sx, dy + dh)
        love.graphics.setColor(unpack(Theme.colors.text_muted))
    end

    -- ── Threshold line ──
    if show_threshold then
        local thresh_y = dy + dh - threshold * dh
        -- Threshold fill zone (everything above threshold is "detection zone")
        love.graphics.setColor(Theme.colors.accent[1], Theme.colors.accent[2], Theme.colors.accent[3], 0.04)
        love.graphics.rectangle("fill", dx, dy, dw, thresh_y - dy)

        -- Threshold line itself
        love.graphics.setColor(Theme.colors.accent[1], Theme.colors.accent[2], Theme.colors.accent[3], 0.6)
        love.graphics.setLineWidth(1)
        -- Dashed line
        local dash = 6
        local gap = 4
        local px = dx
        while px < dx + dw do
            local px_end = math.min(px + dash, dx + dw)
            love.graphics.line(px, thresh_y, px_end, thresh_y)
            px = px_end + gap
        end

        -- Label
        love.graphics.setFont(fonts.small)
        love.graphics.setColor(Theme.colors.accent[1], Theme.colors.accent[2], Theme.colors.accent[3], 0.8)
        love.graphics.print(string.format("T = %.0f%%", threshold * 100), dx + dw - 50, thresh_y - 14)
    end

    -- ── Onset function filled area ──
    local onset_color = {0.984, 0.443, 0.522} -- rose/red for onset spikes
    local px_step = math.max(1, math.floor(n / dw))

    love.graphics.setColor(onset_color[1], onset_color[2], onset_color[3], 0.12)
    for i = 1, n - 1, px_step do
        local i2 = math.min(n, i + px_step)
        local sx1 = dx + (i - 1) / (n - 1) * dw
        local sx2 = dx + (i2 - 1) / (n - 1) * dw
        local o1 = onset_function[i] / o_peak
        local o2 = onset_function[i2] / o_peak
        local sy1 = dy + dh - o1 * dh
        local sy2 = dy + dh - o2 * dh
        love.graphics.polygon("fill", sx1, sy1, sx2, sy2, sx2, dy + dh, sx1, dy + dh)
    end

    -- Onset function line
    love.graphics.setColor(onset_color[1], onset_color[2], onset_color[3], 0.8)
    love.graphics.setLineWidth(1.5)
    local o_pts = {}
    for i = 1, n, px_step do
        local sx = dx + (i - 1) / (n - 1) * dw
        local o = onset_function[i] / o_peak
        local sy = dy + dh - o * dh
        o_pts[#o_pts + 1] = sx
        o_pts[#o_pts + 1] = sy
    end
    if #o_pts >= 4 then love.graphics.line(o_pts) end
    love.graphics.setLineWidth(1)

    -- ── Detected beat markers in onset panel ──
    if show_threshold then
        for _, beat in ipairs(detected_beats) do
            local bx = dx + (beat.index - 1) / (n - 1) * dw
            local o_val = onset_function[beat.index] / o_peak
            local by = dy + dh - o_val * dh

            if beat.is_true_positive then
                love.graphics.setColor(Theme.colors.success[1], Theme.colors.success[2], Theme.colors.success[3], 0.9)
            else
                love.graphics.setColor(Theme.colors.error[1], Theme.colors.error[2], Theme.colors.error[3], 0.9)
            end
            -- Dot at the peak
            love.graphics.circle("fill", bx, by, 4)
            -- Vertical line down to baseline
            love.graphics.setColor(
                beat.is_true_positive and Theme.colors.success[1] or Theme.colors.error[1],
                beat.is_true_positive and Theme.colors.success[2] or Theme.colors.error[2],
                beat.is_true_positive and Theme.colors.success[3] or Theme.colors.error[3],
                0.25
            )
            love.graphics.line(bx, by, bx, dy + dh)
        end
    end
end

-- ─────────────────────────────────────────────
-- Sidebar
-- ─────────────────────────────────────────────

function Section:drawSidebar(sw, sh, layer_color)
    local fonts = Theme.fonts()
    local y = vis_y + 4

    -- ── Threshold slider ──
    love.graphics.setColor(unpack(Theme.colors.text_dim))
    love.graphics.setFont(fonts.small)
    love.graphics.print("DETECTION THRESHOLD", sidebar_x, y)
    y = y + 4
    local new_thresh, thresh_changed = Widgets.slider(
        sidebar_x, y, sidebar_w, threshold,
        nil,
        {min = 0.05, max = 0.95, format = "%.0f%%",
         color = Theme.colors.accent}
    )
    -- The slider format expects 0-1 but displays as percentage
    if thresh_changed then
        threshold = new_thresh
        recompute()
    end
    y = y + 44

    -- ── Window size slider ──
    love.graphics.setColor(unpack(Theme.colors.text_dim))
    love.graphics.setFont(fonts.small)
    love.graphics.print("RMS WINDOW SIZE", sidebar_x, y)
    y = y + 4
    local new_win, win_changed = Widgets.slider(
        sidebar_x, y, sidebar_w, window_size,
        nil,
        {min = 4, max = 120, format = "%d samples",
         color = Theme.colors.warning}
    )
    if win_changed then
        window_size = math.floor(new_win)
        if window_size < 4 then window_size = 4 end
        recompute()
    end
    y = y + 50

    -- ── Stats panel ──
    local stats = compute_stats()
    Draw.infoPanel(sidebar_x, y, sidebar_w, {
        {"Detected Beats", tostring(stats.total)},
        {"True Positives", tostring(stats.tp)},
        {"False Positives", tostring(stats.fp)},
        {"Missed Beats", tostring(math.max(0, stats.true_beats - stats.tp))},
        {"BPM Estimate", stats.bpm_est > 0 and string.format("%.1f", stats.bpm_est) or "--"},
        {"True BPM", tostring(BPM)},
    })
    y = y + 170

    -- ── Step toggles ──
    love.graphics.setColor(unpack(Theme.colors.text_dim))
    love.graphics.setFont(fonts.small)
    love.graphics.print("PROCESSING STAGES", sidebar_x, y)
    y = y + 20

    -- Raw Waveform (always on, shown as disabled toggle)
    Widgets.toggle(sidebar_x, y, true, "Raw Waveform", layer_color)
    y = y + 28

    -- Energy Envelope toggle
    Widgets.toggle(sidebar_x, y, show_energy, "Energy Envelope",
        Theme.colors.warning)
    y = y + 28

    -- Onset Function toggle
    Widgets.toggle(sidebar_x, y, show_onset, "Onset Function",
        {0.984, 0.443, 0.522, 1})
    y = y + 28

    -- Threshold + Beats toggle
    Widgets.toggle(sidebar_x, y, show_threshold, "Threshold + Beats",
        Theme.colors.accent)
    y = y + 40

    -- ── Regenerate button ──
    Widgets.button(sidebar_x, y, "Regenerate Waveform",
        {w = sidebar_w, color = layer_color})
    y = y + 44

    -- ── Educational text ──
    local edu_y = y
    local edu_h = sh - edu_y - 56

    love.graphics.setColor(unpack(Theme.colors.bg_surface))
    Theme.roundRect("fill", sidebar_x, edu_y, sidebar_w, edu_h, Theme.radius.md)
    love.graphics.setColor(unpack(Theme.colors.border))
    Theme.roundRect("line", sidebar_x, edu_y, sidebar_w, edu_h, Theme.radius.md)

    love.graphics.setFont(fonts.small)
    love.graphics.setColor(unpack(Theme.colors.text_muted))
    love.graphics.printf(
        "BEAT DETECTION PIPELINE\n\n" ..
        "1. WAVEFORM: Raw audio samples at 44.1kHz. \n" ..
        "   Each sample is air pressure at a moment in time.\n\n" ..
        "2. ENERGY: Compute RMS energy in sliding windows.\n" ..
        "   E(t) = sqrt(1/N * sum(x[n]^2)) for n in window.\n" ..
        "   Smooths out individual samples into a power curve.\n\n" ..
        "3. ONSET: Take the first derivative dE/dt.\n" ..
        "   Positive spikes = sudden energy increases = hits.\n" ..
        "   This is the \"onset detection function\".\n\n" ..
        "4. THRESHOLD: Peaks in the onset function above a \n" ..
        "   threshold are marked as beats. Too low = false \n" ..
        "   positives. Too high = missed beats.\n\n" ..
        "In bboy-analytics, BeatNet+ extends this with:\n" ..
        "- Downbeat detection (the \"1\" of each bar)\n" ..
        "- Tempo tracking (adaptive BPM estimation)  \n" ..
        "- Beat phase alignment for cross-correlation with motion",
        sidebar_x + 10, edu_y + 10, sidebar_w - 20, "left"
    )
end

-- ─────────────────────────────────────────────
-- Input handlers
-- ─────────────────────────────────────────────

function Section:mousepressed(x, y, button)
    if button ~= 1 then return end

    local sw, sh = love.graphics.getDimensions()

    -- Calculate toggle Y positions (must match drawSidebar layout exactly)
    local ty = vis_y + 4 + 4 + 44 + 4 + 50 + 170 + 20

    -- "Raw Waveform" toggle at ty — always on, no action
    ty = ty + 28

    -- "Energy Envelope" toggle
    if Widgets.toggleClicked(sidebar_x, ty, 36, 20, x, y) then
        show_energy = not show_energy
        return
    end
    ty = ty + 28

    -- "Onset Function" toggle
    if Widgets.toggleClicked(sidebar_x, ty, 36, 20, x, y) then
        show_onset = not show_onset
        return
    end
    ty = ty + 28

    -- "Threshold + Beats" toggle
    if Widgets.toggleClicked(sidebar_x, ty, 36, 20, x, y) then
        show_threshold = not show_threshold
        return
    end
    ty = ty + 40

    -- "Regenerate Waveform" button
    if Widgets.buttonClicked(sidebar_x, ty, sidebar_w, 32, x, y) then
        waveform = generate_waveform()
        recompute()
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
    if key == "1" then
        -- Waveform is always shown; toggle energy instead
        show_energy = not show_energy
    elseif key == "2" then
        show_onset = not show_onset
    elseif key == "3" then
        show_threshold = not show_threshold
    elseif key == "r" then
        waveform = generate_waveform()
        recompute()
    elseif key == "up" then
        threshold = math.min(0.95, threshold + 0.02)
        recompute()
    elseif key == "down" then
        threshold = math.max(0.05, threshold - 0.02)
        recompute()
    elseif key == "left" then
        window_size = math.max(4, window_size - 4)
        recompute()
    elseif key == "right" then
        window_size = math.min(120, window_size + 4)
        recompute()
    end
end

function Section:unload()
    waveform = {}
    energy_envelope = {}
    onset_function = {}
    detected_beats = {}
    true_beat_times = {}
    threshold = 0.35
    window_size = 32
    show_energy = true
    show_onset = true
    show_threshold = true
    anim_time = 0
end

return Section
