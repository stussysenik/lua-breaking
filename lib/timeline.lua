--- lib/timeline.lua
--- Playback timeline with scrubber, play/pause, and speed control.
--- Used by sections that display time-series data.

local Theme = require("shell.theme")
local Widgets = require("lib.widgets")

local Timeline = {}
Timeline.__index = Timeline

function Timeline.new(opts)
    opts = opts or {}
    local self = setmetatable({}, Timeline)
    self.duration = opts.duration or 4.0  -- seconds
    self.fps = opts.fps or 30
    self.time = 0
    self.playing = opts.playing ~= false
    self.speed = opts.speed or 1.0
    self.loop = opts.loop ~= false
    -- Layout
    self.x = opts.x or 20
    self.y = opts.y or 0
    self.w = opts.w or 400
    self.h = opts.h or 24
    self.color = opts.color or Theme.colors.accent
    -- Interaction
    self.scrubbing = false
    return self
end

function Timeline:update(dt)
    if self.playing and not self.scrubbing then
        self.time = self.time + dt * self.speed
        if self.time >= self.duration then
            if self.loop then
                self.time = self.time - self.duration
            else
                self.time = self.duration
                self.playing = false
            end
        end
    end
end

function Timeline:draw()
    local x, y, w, h = self.x, self.y, self.w, self.h

    -- Background
    love.graphics.setColor(0.06, 0.06, 0.09, 0.9)
    Theme.roundRect("fill", x, y, w, h, Theme.radius.sm)

    -- Progress fill
    local progress = self.duration > 0 and (self.time / self.duration) or 0
    love.graphics.setColor(self.color[1], self.color[2], self.color[3], 0.2)
    love.graphics.rectangle("fill", x + 2, y + 2, (w - 4) * progress, h - 4, 2, 2)

    -- Playhead
    local px = x + 2 + (w - 4) * progress
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.rectangle("fill", px - 1, y, 3, h, 1, 1)

    -- Time label
    love.graphics.setColor(1, 1, 1, 0.5)
    love.graphics.setFont(Theme.fonts().mono)
    local frame = math.floor(self.time * self.fps)
    love.graphics.print(
        string.format("%.2fs  F%d  %s",
            self.time, frame,
            self.playing and "▶" or "⏸"
        ),
        x + w + 10, y + 3
    )
end

function Timeline:mousepressed(mx, my, button)
    if button ~= 1 then return false end
    if mx >= self.x and mx <= self.x + self.w and
       my >= self.y - 5 and my <= self.y + self.h + 5 then
        self.scrubbing = true
        self:scrubTo(mx)
        return true
    end
    return false
end

function Timeline:mousereleased(mx, my, button)
    if button == 1 and self.scrubbing then
        self.scrubbing = false
        return true
    end
    return false
end

function Timeline:mousemoved(mx, my, dx, dy)
    if self.scrubbing then
        self:scrubTo(mx)
        return true
    end
    return false
end

function Timeline:scrubTo(mx)
    local progress = (mx - self.x) / self.w
    progress = math.max(0, math.min(1, progress))
    self.time = progress * self.duration
end

function Timeline:togglePlay()
    self.playing = not self.playing
end

function Timeline:reset()
    self.time = 0
end

function Timeline:currentFrame()
    return math.floor(self.time * self.fps)
end

return Timeline
