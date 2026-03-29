--- Section 1.1: The Joint Model
--- Interactive SMPL-like skeleton. Click joints to inspect hierarchy.
--- Shows parent-child bone chains, joint names, body part grouping.
--- Research bridge: experiments/components/panel.py skeleton topology

local Theme = require("shell.theme")
local Draw = require("lib.draw")
local Skeleton = require("lib.skeleton")
local Widgets = require("lib.widgets")

local Section = {}
Section.__index = Section

Section.meta = {
    id = "1.1",
    title = "The Joint Model",
    layer = "foundation",
    description = "Interactive skeleton with 24 SMPL joints. Click to inspect hierarchy, drag to repose.",
    research_mapping = "experiments/components/panel.py",
    data_bridge = false,
    prerequisites = {},
}

local skel
local highlight_chain = nil
local info_joint = nil
local show_all_labels = false
local show_body_parts = false
local dragging_joint = nil
local body_part_highlight = nil

function Section:load()
    local sw, sh = love.graphics.getDimensions()
    -- Center skeleton in left 2/3 of screen
    local area_w = sw * 0.65
    local area_h = sh - 80  -- minus title bar
    local scale = math.min(area_w, area_h) * 0.9
    local ox = (area_w - scale) / 2
    local oy = 70  -- below title bar

    skel = Skeleton.new(scale, ox, oy)
    skel.show_labels = true
    skel.joint_radius = 7

    highlight_chain = nil
    info_joint = nil
    show_all_labels = false
    show_body_parts = false
    dragging_joint = nil
    body_part_highlight = nil
end

function Section:update(dt)
    if not skel then return end

    local mx, my = love.mouse.getPosition()

    -- Update hover
    if not dragging_joint then
        skel.hovered_joint = skel:hitTest(mx, my, 18)
    end

    -- Drag joint
    if dragging_joint then
        if love.mouse.isDown(1) then
            skel.joints[dragging_joint] = skel:fromScreen(mx, my)
        else
            dragging_joint = nil
        end
    end

    -- Apply body part colors when highlighting
    skel.joint_colors = {}
    skel.bone_colors = {}

    if show_body_parts then
        local part_colors = {
            torso     = {0.490, 0.827, 0.988},  -- sky
            left_arm  = {0.984, 0.749, 0.141},  -- amber
            right_arm = {0.984, 0.443, 0.522},  -- rose
            left_leg  = {0.204, 0.827, 0.600},  -- emerald
            right_leg = {0.655, 0.545, 0.980},  -- violet
        }

        for part, joints in pairs(Skeleton.BODY_PARTS) do
            local c = part_colors[part]
            if c then
                local alpha = (body_part_highlight == nil or body_part_highlight == part) and 1 or 0.15
                for _, j in ipairs(joints) do
                    skel.joint_colors[j] = {c[1], c[2], c[3], alpha}
                end
            end
        end
    end
end

function Section:draw()
    local sw, sh = love.graphics.getDimensions()

    -- Background
    love.graphics.setColor(unpack(Theme.colors.bg))
    love.graphics.rectangle("fill", 0, 0, sw, sh)
    Draw.dotGrid(0, 0, sw, sh, 30, 1, {1, 1, 1, 0.02})

    -- Title bar
    local title_h = Draw.titleBar(Section.meta.title, Section.meta.layer, Section.meta.id)

    -- Draw skeleton
    skel:draw(highlight_chain)

    -- Draw velocity arrows at hovered joint (demo)
    if skel.hovered_joint and not dragging_joint then
        local pos = skel.joints[skel.hovered_joint]
        local jx, jy = skel:toScreen(pos)
        -- Show a subtle "drag me" indicator
        love.graphics.setColor(unpack(Theme.colors.text_muted))
        love.graphics.circle("line", jx, jy, 20)
    end

    -- Sidebar
    self:drawSidebar(sw, sh)

    -- Formula
    Draw.formula(
        "skeleton: 24 joints, parent-child hierarchy, SMPL topology",
        20, sh - 40
    )
end

function Section:drawSidebar(sw, sh)
    local sidebar_x = sw * 0.67
    local sidebar_w = sw * 0.30
    local y = 80

    -- Joint info panel
    if info_joint then
        local name = Skeleton.JOINT_NAMES[info_joint]
        local parent_idx = Skeleton.PARENTS[info_joint]
        local parent_name = parent_idx > 0 and Skeleton.JOINT_NAMES[parent_idx] or "(root)"
        local body_part = skel:bodyPartOf(info_joint)
        local is_contact = false
        for cname, cidx in pairs(Skeleton.CONTACT_JOINTS) do
            if cidx == info_joint then is_contact = true; break end
        end

        local pos = skel.joints[info_joint]

        Draw.infoPanel(sidebar_x, y, sidebar_w, {
            {"Joint", name},
            {"Index", info_joint},
            {"Parent", parent_name},
            {"Body Part", body_part},
            {"Contact Joint", is_contact and "yes" or "no"},
            {"Position", string.format("(%.2f, %.2f)", pos.x, pos.y)},
            {"Chain Depth", #(skel:chainToRoot(info_joint))},
        })

        y = y + 220
    else
        -- Instructions
        love.graphics.setColor(unpack(Theme.colors.text_muted))
        love.graphics.setFont(Theme.fonts().body)
        love.graphics.printf(
            "Click a joint to inspect its hierarchy.\nDrag joints to repose the skeleton.",
            sidebar_x, y, sidebar_w, "left"
        )
        y = y + 60
    end

    -- Controls
    y = y + 20

    -- Toggle: show all labels
    Widgets.button(sidebar_x, y, show_all_labels and "Hide All Labels" or "Show All Labels",
        {w = sidebar_w / 2 - 4})
    y = y + 40

    -- Toggle: body parts
    Widgets.button(sidebar_x, y, show_body_parts and "Hide Body Parts" or "Color Body Parts",
        {w = sidebar_w / 2 - 4, color = Theme.colors.physics})
    y = y + 40

    -- Reset button
    Widgets.button(sidebar_x, y, "Reset Pose",
        {w = sidebar_w / 2 - 4, color = Theme.colors.error})
    y = y + 60

    -- Body part legend (when active)
    if show_body_parts then
        local parts = {
            {"Torso", {0.490, 0.827, 0.988}},
            {"Left Arm", {0.984, 0.749, 0.141}},
            {"Right Arm", {0.984, 0.443, 0.522}},
            {"Left Leg", {0.204, 0.827, 0.600}},
            {"Right Leg", {0.655, 0.545, 0.980}},
        }

        love.graphics.setFont(Theme.fonts().small)
        for _, part in ipairs(parts) do
            local c = part[2]
            love.graphics.setColor(c[1], c[2], c[3], 0.7)
            love.graphics.circle("fill", sidebar_x + 8, y + 6, 5)
            love.graphics.setColor(unpack(Theme.colors.text_dim))
            love.graphics.print(part[1], sidebar_x + 20, y)
            y = y + 20
        end
    end

    -- Teaching note
    y = sh - 120
    love.graphics.setColor(unpack(Theme.colors.text_muted))
    love.graphics.setFont(Theme.fonts().small)
    love.graphics.printf(
        "This skeleton uses the SMPL 24-joint topology, the same layout " ..
        "used by JOSH and GVHMR in the bboy-analytics pipeline. Joint 1 " ..
        "(pelvis) is the root — every other joint traces back to it through " ..
        "the parent chain.",
        sidebar_x, y, sidebar_w, "left"
    )
end

function Section:mousepressed(x, y, button)
    if button ~= 1 then return end

    local sw, sh = love.graphics.getDimensions()
    local sidebar_x = sw * 0.67
    local sidebar_w = sw * 0.30

    -- Check sidebar buttons
    local btn_y = (info_joint and 300 or 160)

    if Widgets.buttonClicked(sidebar_x, btn_y, sidebar_w / 2 - 4, 32, x, y) then
        show_all_labels = not show_all_labels
        skel.show_indices = show_all_labels
        return
    end

    btn_y = btn_y + 40
    if Widgets.buttonClicked(sidebar_x, btn_y, sidebar_w / 2 - 4, 32, x, y) then
        show_body_parts = not show_body_parts
        return
    end

    btn_y = btn_y + 40
    if Widgets.buttonClicked(sidebar_x, btn_y, sidebar_w / 2 - 4, 32, x, y) then
        skel:reset()
        highlight_chain = nil
        info_joint = nil
        return
    end

    -- Check skeleton hit
    local hit = skel:hitTest(x, y, 18)
    if hit then
        skel.selected_joint = hit
        info_joint = hit
        highlight_chain = skel:chainToRoot(hit)
        dragging_joint = hit
    else
        -- Deselect
        skel.selected_joint = nil
        info_joint = nil
        highlight_chain = nil
    end
end

function Section:mousereleased(x, y, button)
    if button == 1 then
        dragging_joint = nil
    end
end

function Section:mousemoved(x, y, dx, dy)
    -- Hover handled in update
end

function Section:keypressed(key)
    if key == "r" then
        skel:reset()
        highlight_chain = nil
        info_joint = nil
    elseif key == "l" then
        show_all_labels = not show_all_labels
        skel.show_indices = show_all_labels
    elseif key == "b" then
        show_body_parts = not show_body_parts
    end
end

function Section:unload()
    skel = nil
    highlight_chain = nil
    info_joint = nil
end

return Section
