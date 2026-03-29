--- shell/theme.lua
--- Design tokens for lua-breaking.
--- Layer colors match the bboy-analytics visual companion palette.

local Theme = {}

Theme.colors = {
    bg          = {0.04, 0.04, 0.06, 1},
    bg_surface  = {0.06, 0.06, 0.09, 1},
    bg_elevated = {0.09, 0.09, 0.12, 1},
    text        = {0.88, 0.88, 0.91, 1},
    text_dim    = {0.55, 0.55, 0.60, 1},
    text_muted  = {0.35, 0.35, 0.40, 1},
    border      = {1, 1, 1, 0.06},
    border_hover = {1, 1, 1, 0.12},
    accent      = {0.490, 0.827, 0.988, 1},

    -- Layer colors
    foundation  = {0.506, 0.549, 0.973, 1},  -- #818cf8 indigo
    physics     = {0.984, 0.749, 0.141, 1},   -- #fbbf24 amber
    signal      = {0.655, 0.545, 0.980, 1},   -- #a78bfa violet
    cv          = {0.984, 0.443, 0.522, 1},    -- #fb7185 rose
    bboy        = {0.204, 0.827, 0.600, 1},    -- #34d399 emerald
    system      = {0.490, 0.827, 0.988, 1},    -- #7dd3fc sky

    -- Semantic
    success     = {0.204, 0.827, 0.600, 1},
    warning     = {0.984, 0.749, 0.141, 1},
    error       = {0.984, 0.443, 0.522, 1},
    info        = {0.490, 0.827, 0.988, 1},
}

-- Dimmed layer colors for backgrounds (alpha 0.08)
Theme.colors_bg = {}
for _, key in ipairs({"foundation", "physics", "signal", "cv", "bboy", "system"}) do
    local c = Theme.colors[key]
    Theme.colors_bg[key] = {c[1], c[2], c[3], 0.08}
end

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

    -- Use built-in fonts with sizes (custom fonts loaded from assets/ later)
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

return Theme
