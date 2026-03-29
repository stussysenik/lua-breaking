--- lib/signal.lua
--- Signal processing utilities: cross-correlation, autocorrelation, windowing.
--- Used by the musicality (3.3) and cycle detection (3.4) sections.

local Signal = {}

--- Cross-correlation between two signals at a given lag
--- corr(x, y, tau) = Σ_t x(t) * y(t - tau) / (N * σx * σy)
--- @param x table Array of numbers
--- @param y table Array of numbers
--- @param tau number Lag (integer samples)
--- @return number Normalized correlation [-1, 1]
function Signal.crossCorrelation(x, y, tau)
    local n = math.min(#x, #y)
    if n == 0 then return 0 end

    -- Compute means
    local mx, my = 0, 0
    local count = 0
    for t = 1, n do
        local yt = t - tau
        if yt >= 1 and yt <= #y then
            mx = mx + x[t]
            my = my + y[yt]
            count = count + 1
        end
    end
    if count < 2 then return 0 end
    mx = mx / count
    my = my / count

    -- Compute correlation
    local sum_xy, sum_x2, sum_y2 = 0, 0, 0
    for t = 1, n do
        local yt = t - tau
        if yt >= 1 and yt <= #y then
            local dx = x[t] - mx
            local dy = y[yt] - my
            sum_xy = sum_xy + dx * dy
            sum_x2 = sum_x2 + dx * dx
            sum_y2 = sum_y2 + dy * dy
        end
    end

    local denom = math.sqrt(sum_x2 * sum_y2)
    if denom < 1e-10 then return 0 end
    return sum_xy / denom
end

--- Compute cross-correlation curve over a range of lags
--- @param x table Signal 1
--- @param y table Signal 2
--- @param min_lag number Minimum lag (can be negative)
--- @param max_lag number Maximum lag
--- @return table Array of {lag, correlation} pairs
--- @return number max_lag The lag with highest correlation
--- @return number max_corr The highest correlation value
function Signal.crossCorrelationCurve(x, y, min_lag, max_lag)
    min_lag = min_lag or 0
    max_lag = max_lag or math.floor(#x / 4)

    local curve = {}
    local best_lag, best_corr = 0, -math.huge

    for tau = min_lag, max_lag do
        local corr = Signal.crossCorrelation(x, y, tau)
        table.insert(curve, {lag = tau, corr = corr})
        if corr > best_corr then
            best_corr = corr
            best_lag = tau
        end
    end

    return curve, best_lag, best_corr
end

--- Autocorrelation of a signal (correlation with itself at lag tau)
--- @param x table Array of numbers
--- @param max_lag number Maximum lag to compute
--- @return table Array of correlation values indexed by lag
function Signal.autocorrelation(x, max_lag)
    max_lag = max_lag or math.floor(#x / 2)
    local result = {}
    for tau = 0, max_lag do
        result[tau] = Signal.crossCorrelation(x, x, tau)
    end
    return result
end

--- Generate a signal with peaks at specified times
--- @param duration number Duration in seconds
--- @param sample_rate number Samples per second
--- @param peaks table Array of peak times in seconds
--- @param width number Peak width in seconds
--- @return table Generated signal
function Signal.peakSignal(duration, sample_rate, peaks, width)
    width = width or 0.05
    local n = math.floor(duration * sample_rate)
    local signal = {}

    for i = 1, n do
        local t = (i - 1) / sample_rate
        local val = 0
        for _, peak_t in ipairs(peaks) do
            local dt = t - peak_t
            val = val + math.exp(-(dt * dt) / (2 * width * width))
        end
        signal[i] = val
    end

    return signal
end

--- Generate a beat-aligned signal (simulated audio energy)
--- @param duration number Duration in seconds
--- @param sample_rate number Samples per second
--- @param bpm number Beats per minute
--- @param offset number Phase offset in seconds
--- @return table Generated signal
--- @return table Beat times
function Signal.beatSignal(duration, sample_rate, bpm, offset)
    offset = offset or 0
    local beat_interval = 60 / bpm
    local beats = {}

    local t = offset
    while t < duration do
        if t >= 0 then table.insert(beats, t) end
        t = t + beat_interval
    end

    local signal = Signal.peakSignal(duration, sample_rate, beats, 0.04)

    -- Add some noise and sub-beats
    local n = #signal
    for i = 1, n do
        local t_sec = (i - 1) / sample_rate
        signal[i] = signal[i] + 0.15 * math.sin(t_sec * bpm / 60 * math.pi * 4)
        signal[i] = signal[i] + (math.random() - 0.5) * 0.05
        signal[i] = math.max(0, signal[i])
    end

    return signal, beats
end

--- Apply a Hann window to a signal
--- @param signal table Input signal
--- @param start number Start index (1-based)
--- @param length number Window length
--- @return table Windowed signal
function Signal.hannWindow(signal, start, length)
    local result = {}
    for i = 1, length do
        local idx = start + i - 1
        if idx >= 1 and idx <= #signal then
            local w = 0.5 * (1 - math.cos(2 * math.pi * (i - 1) / (length - 1)))
            result[i] = signal[idx] * w
        else
            result[i] = 0
        end
    end
    return result
end

--- Normalize a signal to [0, 1]
function Signal.normalize(signal)
    local min_val, max_val = math.huge, -math.huge
    for _, v in ipairs(signal) do
        if v < min_val then min_val = v end
        if v > max_val then max_val = v end
    end
    local range = max_val - min_val
    if range < 1e-10 then range = 1 end

    local result = {}
    for i, v in ipairs(signal) do
        result[i] = (v - min_val) / range
    end
    return result
end

return Signal
