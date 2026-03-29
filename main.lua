--- main.lua
--- lua-breaking: Interactive Explorable Explanations for Breakdancing Physics
--- Entry point — loads graph navigation shell and all section modules.

local Theme = require("shell.theme")
local Graph = require("shell.graph")
local Widgets = require("lib.widgets")

local graph

--- Scan sections/ directory and load all init.lua modules
local function loadSections()
    local sections_dir = "sections"
    local items = love.filesystem.getDirectoryItems(sections_dir)

    -- Sort for consistent ordering
    table.sort(items)

    local loaded = 0
    for _, dir_name in ipairs(items) do
        local path = sections_dir .. "/" .. dir_name .. "/init.lua"
        if love.filesystem.getInfo(path) then
            local ok, section = pcall(require, sections_dir .. "." .. dir_name .. ".init")
            if ok and section and section.meta then
                graph:registerSection(section)
                loaded = loaded + 1
            elseif not ok then
                print("[lua-breaking] Failed to load section: " .. dir_name)
                print("  " .. tostring(section))
            end
        end
    end

    print(string.format("[lua-breaking] Loaded %d sections", loaded))
end

function love.load()
    -- Set default filter for crisp pixel text
    love.graphics.setDefaultFilter("linear", "linear")

    -- Background color
    love.graphics.setBackgroundColor(unpack(Theme.colors.bg))

    -- Create graph
    graph = Graph.new()

    -- Load all sections
    loadSections()

    -- Layout graph nodes
    graph:layout()

    print("[lua-breaking] Ready. Click a node to explore.")
end

function love.update(dt)
    Widgets.beginFrame()

    if graph.active_section then
        -- Update active section
        if graph.active_section.update then
            graph.active_section:update(dt)
        end
    else
        -- Update graph view
        graph:update(dt)
    end
end

function love.draw()
    if graph.active_section then
        -- Draw active section
        love.graphics.setColor(unpack(Theme.colors.bg))
        love.graphics.rectangle("fill", 0, 0, love.graphics.getDimensions())

        if graph.active_section.draw then
            graph.active_section:draw()
        end
    else
        -- Draw graph view
        graph:draw()
    end
end

function love.mousepressed(x, y, button)
    if graph.active_section then
        if graph.active_section.mousepressed then
            graph.active_section:mousepressed(x, y, button)
        end
    else
        graph:mousepressed(x, y, button)
    end
end

function love.mousereleased(x, y, button)
    if graph.active_section then
        if graph.active_section.mousereleased then
            graph.active_section:mousereleased(x, y, button)
        end
    else
        graph:mousereleased(x, y, button)
    end
end

function love.mousemoved(x, y, dx, dy)
    if graph.active_section then
        if graph.active_section.mousemoved then
            graph.active_section:mousemoved(x, y, dx, dy)
        end
    else
        graph:mousemoved(x, y, dx, dy)
    end
end

function love.wheelmoved(x, y)
    if graph.active_section then
        if graph.active_section.wheelmoved then
            graph.active_section:wheelmoved(x, y)
        end
    else
        graph:wheelmoved(x, y)
    end
end

function love.keypressed(key)
    -- ESC always goes back to graph
    if key == "escape" and graph.active_section then
        graph:exitSection()
        return
    end

    -- Pass to active section or graph
    if graph.active_section then
        if graph.active_section.keypressed then
            graph.active_section:keypressed(key)
        end
    else
        graph:keypressed(key)
    end
end

function love.resize(w, h)
    if graph.active_section and graph.active_section.resize then
        graph.active_section:resize(w, h)
    end
end
