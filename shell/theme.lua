--- shell/theme.lua
--- Design tokens for lua-breaking.
--- Supports light and dark mode (toggle with 'T' key).
--- Layer colors match the bboy-analytics visual companion palette.

local Theme = {}

Theme.mode = "light"  -- "light" or "dark"

--- Dark mode palette
local dark = {
    bg          = {0.04, 0.04, 0.06, 1},
    bg_surface  = {0.06, 0.06, 0.09, 1},
    bg_elevated = {0.09, 0.09, 0.12, 1},
    text        = {0.88, 0.88, 0.91, 1},
    text_dim    = {0.55, 0.55, 0.60, 1},
    text_muted  = {0.35, 0.35, 0.40, 1},
    border      = {1, 1, 1, 0.06},
    border_hover = {1, 1, 1, 0.12},
    accent      = {0.490, 0.827, 0.988, 1},
    node_bg     = {0.06, 0.06, 0.09, 0.9},
    node_hover  = 0.12,  -- alpha for layer color bg on hover
    grid_dot    = {1, 1, 1, 0.03},
    formula_bg  = {0.06, 0.06, 0.10, 0.9},
    formula_border = {1, 1, 1, 0.08},
    formula_text = {0.75, 0.85, 0.95, 0.9},
    panel_bg    = {0.06, 0.06, 0.09, 0.95},
    panel_border = {1, 1, 1, 0.06},
    bone        = {1, 1, 1, 0.25},
    bone_highlight = {1, 1, 1, 0.9},
    joint       = {1, 1, 1, 0.35},
    joint_hover = {1, 1, 1, 0.6},
    joint_selected = {0.490, 0.827, 0.988, 1},
}

--- Light mode palette
local light = {
    bg          = {0.965, 0.969, 0.976, 1},  -- #f6f7f9
    bg_surface  = {1, 1, 1, 1},
    bg_elevated = {1, 1, 1, 1},
    text        = {0.10, 0.10, 0.12, 1},
    text_dim    = {0.40, 0.40, 0.45, 1},
    text_muted  = {0.60, 0.60, 0.65, 1},
    border      = {0, 0, 0, 0.08},
    border_hover = {0, 0, 0, 0.15},
    accent      = {0.22, 0.47, 0.85, 1},     -- deeper blue
    node_bg     = {1, 1, 1, 0.95},
    node_hover  = 0.10,
    grid_dot    = {0, 0, 0, 0.04},
    formula_bg  = {0.94, 0.95, 0.97, 0.95},
    formula_border = {0, 0, 0, 0.06},
    formula_text = {0.20, 0.25, 0.35, 0.9},
    panel_bg    = {1, 1, 1, 0.97},
    panel_border = {0, 0, 0, 0.08},
    bone        = {0.15, 0.15, 0.20, 0.35},
    bone_highlight = {0.10, 0.10, 0.15, 0.9},
    joint       = {0.25, 0.25, 0.30, 0.5},
    joint_hover = {0.15, 0.15, 0.20, 0.7},
    joint_selected = {0.22, 0.47, 0.85, 1},
}

--- Layer colors (same in both modes, slightly adjusted saturation for light)
local layer_colors_dark = {
    foundation  = {0.506, 0.549, 0.973, 1},  -- #818cf8 indigo
    physics     = {0.984, 0.749, 0.141, 1},   -- #fbbf24 amber
    signal      = {0.655, 0.545, 0.980, 1},   -- #a78bfa violet
    cv          = {0.984, 0.443, 0.522, 1},    -- #fb7185 rose
    bboy        = {0.204, 0.827, 0.600, 1},    -- #34d399 emerald
    system      = {0.490, 0.827, 0.988, 1},    -- #7dd3fc sky
}

local layer_colors_light = {
    foundation  = {0.38, 0.42, 0.90, 1},     -- deeper indigo
    physics     = {0.85, 0.60, 0.05, 1},      -- deeper amber
    signal      = {0.50, 0.38, 0.90, 1},      -- deeper violet
    cv          = {0.90, 0.30, 0.40, 1},       -- deeper rose
    bboy        = {0.12, 0.65, 0.45, 1},       -- deeper emerald
    system      = {0.25, 0.55, 0.85, 1},       -- deeper sky
}

--- Semantic colors
local semantic = {
    success     = {0.204, 0.827, 0.600, 1},
    warning     = {0.984, 0.749, 0.141, 1},
    error       = {0.984, 0.443, 0.522, 1},
    info        = {0.490, 0.827, 0.988, 1},
}

--- Apply the current mode
local function applyMode()
    local palette = Theme.mode == "light" and light or dark
    local layers = Theme.mode == "light" and layer_colors_light or layer_colors_dark

    Theme.colors = {}
    for k, v in pairs(palette) do
        Theme.colors[k] = v
    end
    for k, v in pairs(layers) do
        Theme.colors[k] = v
    end
    for k, v in pairs(semantic) do
        Theme.colors[k] = v
    end

    -- Dimmed layer colors for backgrounds
    Theme.colors_bg = {}
    for _, key in ipairs({"foundation", "physics", "signal", "cv", "bboy", "system"}) do
        local c = Theme.colors[key]
        Theme.colors_bg[key] = {c[1], c[2], c[3], 0.08}
    end
end

-- Initialize
applyMode()

Theme.spacing = {
    xs = 4,
    sm = 8,
    md = 16,
    lg = 24,
    xl = 32,
    xxl = 48,
}

Theme.radius = {
    sm = 4,
    md = 8,
    lg = 12,
    xl = 16,
}

-- Fonts are initialized lazily since love.graphics isn't ready at require time
Theme._fonts = nil

function Theme.fonts()
    if Theme._fonts then return Theme._fonts end

    Theme._fonts = {
        title   = love.graphics.newFont(24),
        heading = love.graphics.newFont(16),
        body    = love.graphics.newFont(13),
        small   = love.graphics.newFont(11),
        mono    = love.graphics.newFont(12),
        formula = love.graphics.newFont(14),
    }
    return Theme._fonts
end

--- Toggle between light and dark mode
function Theme.toggleMode()
    Theme.mode = Theme.mode == "light" and "dark" or "light"
    applyMode()
end

--- Helper: set color from theme
function Theme.setColor(name, alpha)
    local c = Theme.colors[name]
    if c then
        love.graphics.setColor(c[1], c[2], c[3], alpha or c[4] or 1)
    end
end

--- Helper: get layer color by layer name
function Theme.layerColor(layer)
    return Theme.colors[layer] or Theme.colors.text
end

--- Helper: draw rounded rect
function Theme.roundRect(mode, x, y, w, h, r)
    r = r or Theme.radius.md
    love.graphics.rectangle(mode, x, y, w, h, r, r)
end

--- Helper: is currently light mode?
function Theme.isLight()
    return Theme.mode == "light"
end

return Theme
