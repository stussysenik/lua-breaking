--- lib/data_loader.lua
--- Loads exported motion data from bboy-analytics (JSON format).
--- Provides frame-by-frame access with interpolation.
---
--- Expected JSON format: see tools/export_motion.py for schema.
--- Falls back to nil if no data file exists — sections use simulated data instead.

local Vec = require("lib.vector")

local DataLoader = {}
DataLoader.__index = DataLoader

--- Simple JSON parser (subset — handles the export format)
--- For production, replace with a proper JSON library like lunajson
local function parseJSON(str)
    -- Use love.filesystem's json support if available, otherwise basic parse
    -- This is a minimal parser for the export format
    local ok, result = pcall(function()
        -- Replace JSON null with Lua nil-safe value
        str = str:gsub('"null"', '"nil"')

        -- Convert JSON to Lua table literal (simplified)
        local lua_str = str
            :gsub('%[', '{')
            :gsub('%]', '}')
            :gsub('"([%w_]+)"%s*:', '["%1"]=')
            :gsub('null', 'nil')
            :gsub('true', 'true')
            :gsub('false', 'false')

        local fn = load("return " .. lua_str)
        if fn then return fn() end
        return nil
    end)

    if ok then return result end
    return nil
end

--- Load motion data from a JSON file
--- @param filepath string Path relative to love.filesystem save directory or project
--- @return table|nil data Loaded data or nil if not found
function DataLoader.load(filepath)
    local content = love.filesystem.read(filepath)
    if not content then
        return nil
    end

    local data = parseJSON(content)
    if not data then
        print("[DataLoader] Failed to parse: " .. filepath)
        return nil
    end

    -- Convert frame joint arrays to Vec objects
    if data.frames then
        for _, frame in ipairs(data.frames) do
            if frame.joints_3d then
                local vecs = {}
                for _, j in ipairs(frame.joints_3d) do
                    table.insert(vecs, Vec.new(j[1], j[2], j[3]))
                end
                frame.joints_3d = vecs
            end
            if frame.velocity then
                local vecs = {}
                for _, v in ipairs(frame.velocity) do
                    table.insert(vecs, Vec.new(v[1], v[2], v[3]))
                end
                frame.velocity = vecs
            end
            if frame.com then
                frame.com = Vec.new(frame.com[1], frame.com[2], frame.com[3])
            end
        end
    end

    print(string.format("[DataLoader] Loaded %s: %d frames, %s model",
        filepath,
        data.frames and #data.frames or 0,
        data.model or "unknown"
    ))

    return setmetatable({data = data}, DataLoader)
end

--- Get frame at time t (with linear interpolation)
--- @param t number Time in seconds
--- @return table|nil frame
function DataLoader:frameAt(t)
    if not self.data or not self.data.frames then return nil end

    local fps = self.data.fps or 30
    local f = t * fps
    local f0 = math.floor(f) + 1  -- 1-indexed
    local f1 = f0 + 1
    local frac = f - math.floor(f)

    local frames = self.data.frames
    if f0 < 1 then return frames[1] end
    if f0 >= #frames then return frames[#frames] end
    if f1 > #frames then return frames[f0] end

    -- Interpolate
    local frame0 = frames[f0]
    local frame1 = frames[f1]

    local result = {
        t = t,
        segment = frame0.segment,
        kinetic_energy = frame0.kinetic_energy + frac * (frame1.kinetic_energy - frame0.kinetic_energy),
        compactness = frame0.compactness + frac * (frame1.compactness - frame0.compactness),
    }

    -- Interpolate joints
    if frame0.joints_3d and frame1.joints_3d then
        result.joints_3d = {}
        for j = 1, #frame0.joints_3d do
            result.joints_3d[j] = frame0.joints_3d[j]:lerp(frame1.joints_3d[j], frac)
        end
    end

    -- Interpolate velocities
    if frame0.velocity and frame1.velocity then
        result.velocity = {}
        for j = 1, #frame0.velocity do
            result.velocity[j] = frame0.velocity[j]:lerp(frame1.velocity[j], frac)
        end
    end

    -- Interpolate COM
    if frame0.com and frame1.com then
        result.com = frame0.com:lerp(frame1.com, frac)
    end

    return result
end

--- Get total duration in seconds
function DataLoader:duration()
    if not self.data or not self.data.frames then return 0 end
    return #self.data.frames / (self.data.fps or 30)
end

--- Get number of frames
function DataLoader:frameCount()
    if not self.data or not self.data.frames then return 0 end
    return #self.data.frames
end

--- Get audio data
function DataLoader:audio()
    return self.data and self.data.audio or nil
end

--- Get musicality data
function DataLoader:musicality()
    return self.data and self.data.musicality or nil
end

--- Get source info
function DataLoader:source()
    return self.data and self.data.source or "unknown"
end

--- Get model name
function DataLoader:model()
    return self.data and self.data.model or "unknown"
end

return DataLoader
