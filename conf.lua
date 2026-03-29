function love.conf(t)
    t.identity = "lua-breaking"
    t.version = "11.4"

    t.window.title = "lua-breaking — Breakdancing Physics Explorable Explanations"
    t.window.width = 1440
    t.window.height = 900
    t.window.minwidth = 1024
    t.window.minheight = 640
    t.window.resizable = true
    t.window.vsync = 1
    t.window.msaa = 4
    t.window.highdpi = true

    t.modules.physics = true
    t.modules.audio = true
    t.modules.sound = true

    t.console = false
end
