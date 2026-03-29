--- shell/graph.lua
--- Graph-based navigation shell. Nodes represent sections, edges show prerequisites.
--- Click a node to enter a section. ESC to return. Zoom and pan with mouse.

local Theme = require("shell.theme")
local Draw = require("lib.draw")

local Graph = {}
Graph.__index = Graph

--- Section registry (populated by main.lua scanning sections/)
Graph.sections = {}

--- Node layout configuration
local LAYER_Y = {
    foundation = 0,
    physics    = 1,
    signal     = 1,
    cv         = 1,
    bboy       = 2,
    system     = 3,
}

local LAYER_X_OFFSET = {
    foundation = 0,
    physics    = -1.5,
    signal     = 0,
    cv         = 1.5,
    bboy       = 0,
    system     = 0,
}

local NODE_W = 200
local NODE_H = 60
local NODE_SPACING_X = 230
local NODE_SPACING_Y = 160

function Graph.new()
    local self = setmetatable({}, Graph)
    self.nodes = {}
    self.edges = {}
    self.camera_x = 0
    self.camera_y = 0
    self.camera_zoom = 1
    self.target_zoom = 1
    self.hovered_node = nil
    self.selected_node = nil
    self.visited = {}
    self.dragging = false
    self.drag_start_x = 0
    self.drag_start_y = 0
    self.cam_start_x = 0
    self.cam_start_y = 0
    self.transition_alpha = 0  -- for section enter/exit
    self.active_section = nil
    self.title_pulse = 0
    return self
end

--- Register a section (called by main.lua)
function Graph:registerSection(section_module)
    local meta = section_module.meta
    table.insert(self.sections, section_module)

    -- Create node
    local node = {
        section = section_module,
        id = meta.id,
        title = meta.title,
        layer = meta.layer,
        data_bridge = meta.data_bridge or false,
        prerequisites = meta.prerequisites or {},
        x = 0, y = 0,  -- computed in layout()
        w = NODE_W,
        h = NODE_H,
    }
    self.nodes[meta.id] = node

    return node
end

--- Compute node positions based on layer and section order
function Graph:layout()
    -- Group nodes by layer
    local layer_groups = {}
    for id, node in pairs(self.nodes) do
        local layer = node.layer
        if not layer_groups[layer] then layer_groups[layer] = {} end
        table.insert(layer_groups[layer], node)
    end

    -- Sort within each layer by id
    for layer, nodes in pairs(layer_groups) do
        table.sort(nodes, function(a, b) return a.id < b.id end)
    end

    -- Position nodes
    for layer, nodes in pairs(layer_groups) do
        local row = LAYER_Y[layer] or 0
        local x_off = LAYER_X_OFFSET[layer] or 0
        local count = #nodes
        local start_x = x_off * NODE_SPACING_X - (count - 1) * NODE_SPACING_X / 2

        for i, node in ipairs(nodes) do
            node.x = start_x + (i - 1) * NODE_SPACING_X
            node.y = row * NODE_SPACING_Y
        end
    end

    -- Build edges from prerequisites
    self.edges = {}
    for id, node in pairs(self.nodes) do
        for _, prereq_id in ipairs(node.prerequisites) do
            if self.nodes[prereq_id] then
                table.insert(self.edges, {
                    from = self.nodes[prereq_id],
                    to = node,
                })
            end
        end
    end

    -- Center camera on graph
    local min_x, max_x, min_y, max_y = math.huge, -math.huge, math.huge, -math.huge
    for _, node in pairs(self.nodes) do
        min_x = math.min(min_x, node.x)
        max_x = math.max(max_x, node.x + node.w)
        min_y = math.min(min_y, node.y)
        max_y = math.max(max_y, node.y + node.h)
    end
    local cx = (min_x + max_x) / 2
    local cy = (min_y + max_y) / 2
    local sw, sh = love.graphics.getDimensions()
    self.camera_x = cx - sw / 2
    self.camera_y = cy - sh / 2 + 40
end

--- Screen to world coordinates
function Graph:screenToWorld(sx, sy)
    return
        (sx - love.graphics.getWidth() / 2) / self.camera_zoom + self.camera_x + love.graphics.getWidth() / 2,
        (sy - love.graphics.getHeight() / 2) / self.camera_zoom + self.camera_y + love.graphics.getHeight() / 2
end

function Graph:update(dt)
    self.title_pulse = self.title_pulse + dt

    -- Smooth zoom
    self.camera_zoom = self.camera_zoom + (self.target_zoom - self.camera_zoom) * math.min(dt * 8, 1)

    -- Update hovered node
    local mx, my = love.mouse.getPosition()
    local wx, wy = self:screenToWorld(mx, my)
    self.hovered_node = nil

    for id, node in pairs(self.nodes) do
        if wx >= node.x and wx <= node.x + node.w and
           wy >= node.y and wy <= node.y + node.h then
            self.hovered_node = id
            break
        end
    end

    -- Transition animation
    if self.active_section then
        self.transition_alpha = math.min(1, self.transition_alpha + dt * 5)
    else
        self.transition_alpha = math.max(0, self.transition_alpha - dt * 5)
    end
end

function Graph:draw()
    local sw, sh = love.graphics.getDimensions()

    -- Background
    love.graphics.setColor(unpack(Theme.colors.bg))
    love.graphics.rectangle("fill", 0, 0, sw, sh)

    -- Dot grid
    Draw.dotGrid(0, 0, sw, sh, 30, 1, {1, 1, 1, 0.03})

    -- Apply camera transform
    love.graphics.push()
    love.graphics.translate(sw / 2, sh / 2)
    love.graphics.scale(self.camera_zoom)
    love.graphics.translate(-self.camera_x - sw / 2, -self.camera_y - sh / 2)

    -- Draw edges
    for _, edge in ipairs(self.edges) do
        local from, to = edge.from, edge.to
        local fx = from.x + from.w / 2
        local fy = from.y + from.h
        local tx = to.x + to.w / 2
        local ty = to.y

        love.graphics.setColor(1, 1, 1, 0.06)
        love.graphics.setLineWidth(1.5)

        -- Bezier curve
        local mid_y = (fy + ty) / 2
        local curve = love.math.newBezierCurve(fx, fy, fx, mid_y, tx, mid_y, tx, ty)
        love.graphics.line(curve:render())
    end

    -- Draw nodes
    for id, node in pairs(self.nodes) do
        local is_hovered = (id == self.hovered_node)
        local is_visited = self.visited[id]
        local layer_color = Theme.layerColor(node.layer)

        -- Node background
        if is_hovered then
            love.graphics.setColor(layer_color[1], layer_color[2], layer_color[3], 0.12)
        else
            love.graphics.setColor(0.06, 0.06, 0.09, 0.9)
        end
        Theme.roundRect("fill", node.x, node.y, node.w, node.h, Theme.radius.lg)

        -- Node border
        if is_hovered then
            love.graphics.setColor(layer_color[1], layer_color[2], layer_color[3], 0.4)
            love.graphics.setLineWidth(2)
        else
            love.graphics.setColor(layer_color[1], layer_color[2], layer_color[3], 0.15)
            love.graphics.setLineWidth(1)
        end
        Theme.roundRect("line", node.x, node.y, node.w, node.h, Theme.radius.lg)

        -- Layer color bar (left edge)
        love.graphics.setColor(layer_color[1], layer_color[2], layer_color[3], 0.6)
        love.graphics.rectangle("fill", node.x, node.y + 8, 3, node.h - 16, 1, 1)

        -- Section ID
        love.graphics.setColor(layer_color[1], layer_color[2], layer_color[3], 0.7)
        love.graphics.setFont(Theme.fonts().small)
        love.graphics.print(node.id, node.x + 14, node.y + 10)

        -- Title
        love.graphics.setColor(1, 1, 1, is_hovered and 0.95 or 0.75)
        love.graphics.setFont(Theme.fonts().body)
        -- Truncate title if too long (UTF-8 safe)
        local title = node.title
        local max_tw = node.w - 28
        local ok, tw = pcall(function() return Theme.fonts().body:getWidth(title) end)
        if ok and tw > max_tw then
            -- UTF-8 safe truncation: find valid codepoint boundaries
            local truncated = title
            while true do
                -- Remove last UTF-8 character (1-4 bytes)
                local len = #truncated
                if len <= 3 then break end
                local i = len
                while i > 1 and truncated:byte(i) >= 0x80 and truncated:byte(i) < 0xC0 do
                    i = i - 1
                end
                truncated = truncated:sub(1, i - 1)
                local tok, ttw = pcall(function() return Theme.fonts().body:getWidth(truncated .. "...") end)
                if tok and ttw <= max_tw then break end
            end
            title = truncated .. "..."
        end
        local pok = pcall(function() love.graphics.print(title, node.x + 14, node.y + 28) end)
        if not pok then
            love.graphics.print("...", node.x + 14, node.y + 28)
        end

        -- Data bridge indicator
        if node.data_bridge then
            love.graphics.setColor(0.655, 0.545, 0.980, 0.5)
            love.graphics.circle("fill", node.x + node.w - 18, node.y + 15, 4)
        end

        -- Visited checkmark
        if is_visited then
            love.graphics.setColor(0.204, 0.827, 0.600, 0.7)
            love.graphics.circle("fill", node.x + node.w - 18, node.y + node.h - 18, 6)
            love.graphics.setColor(0, 0, 0, 0.8)
            love.graphics.setFont(Theme.fonts().small)
            love.graphics.print("ok", node.x + node.w - 24, node.y + node.h - 24)
        end
    end

    love.graphics.pop()

    -- Title overlay
    self:drawTitle(sw, sh)

    -- Layer legend
    self:drawLegend(sw, sh)
end

function Graph:drawTitle(sw, sh)
    -- Title
    love.graphics.setFont(Theme.fonts().title)
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.print("lua-breaking", 24, 16)

    -- Subtitle
    love.graphics.setFont(Theme.fonts().body)
    love.graphics.setColor(1, 1, 1, 0.35)
    love.graphics.print("Breakdancing Physics — Explorable Explanations", 24, 46)

    -- Stats
    local section_count = 0
    local visited_count = 0
    for id in pairs(self.nodes) do
        section_count = section_count + 1
        if self.visited[id] then visited_count = visited_count + 1 end
    end

    love.graphics.setFont(Theme.fonts().small)
    love.graphics.setColor(1, 1, 1, 0.3)
    love.graphics.print(
        string.format("%d / %d sections explored", visited_count, section_count),
        sw - 200, 24
    )
end

function Graph:drawLegend(sw, sh)
    local layers = {"foundation", "physics", "signal", "cv", "bboy", "system"}
    local labels = {"Foundation", "Physics", "Signal", "CV", "Breakdancing", "System"}
    local legend_y = sh - 40
    local x = 24

    for i, layer in ipairs(layers) do
        local color = Theme.layerColor(layer)
        love.graphics.setColor(color[1], color[2], color[3], 0.7)
        love.graphics.circle("fill", x, legend_y, 5)

        love.graphics.setColor(1, 1, 1, 0.4)
        love.graphics.setFont(Theme.fonts().small)
        love.graphics.print(labels[i], x + 10, legend_y - 6)

        x = x + Theme.fonts().small:getWidth(labels[i]) + 30
    end
end

function Graph:mousepressed(x, y, button)
    if button == 1 then
        if self.hovered_node then
            -- Enter section
            self.selected_node = self.hovered_node
            local node = self.nodes[self.hovered_node]
            if node and node.section then
                self:enterSection(node.section)
            end
        else
            -- Start panning
            self.dragging = true
            self.drag_start_x = x
            self.drag_start_y = y
            self.cam_start_x = self.camera_x
            self.cam_start_y = self.camera_y
        end
    end
end

function Graph:mousereleased(x, y, button)
    if button == 1 then
        self.dragging = false
    end
end

function Graph:mousemoved(x, y, dx, dy)
    if self.dragging then
        self.camera_x = self.cam_start_x - (x - self.drag_start_x) / self.camera_zoom
        self.camera_y = self.cam_start_y - (y - self.drag_start_y) / self.camera_zoom
    end
end

function Graph:wheelmoved(x, y)
    local zoom_speed = 0.1
    self.target_zoom = math.max(0.3, math.min(2.5, self.target_zoom + y * zoom_speed))
end

function Graph:enterSection(section)
    self.active_section = section
    self.visited[section.meta.id] = true
    if section.load then
        section:load()
    end
end

function Graph:exitSection()
    if self.active_section and self.active_section.unload then
        self.active_section:unload()
    end
    self.active_section = nil
end

function Graph:keypressed(key)
    if key == "escape" then
        if self.active_section then
            self:exitSection()
            return true
        end
    end
    -- Pass to active section
    if self.active_section and self.active_section.keypressed then
        self.active_section:keypressed(key)
        return true
    end
    return false
end

return Graph
