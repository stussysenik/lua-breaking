--- lib/skeleton.lua
--- SMPL-like skeleton topology for breakdancing visualization.
--- 24 joints with parent-child hierarchy, bone connections, and body part grouping.
--- Maps to bboy-analytics joint indexing (experiments/components/panel.py).

local Vec = require("lib.vector")
local Theme = require("shell.theme")

local Skeleton = {}
Skeleton.__index = Skeleton

--- Joint names indexed from 1 (Lua convention)
--- Matches SMPL 24-joint layout used in bboy-analytics
Skeleton.JOINT_NAMES = {
    "pelvis",         -- 1  (root)
    "l_hip",          -- 2
    "r_hip",          -- 3
    "spine1",         -- 4
    "l_knee",         -- 5
    "r_knee",         -- 6
    "spine2",         -- 7
    "l_ankle",        -- 8
    "r_ankle",        -- 9
    "spine3",         -- 10
    "l_foot",         -- 11
    "r_foot",         -- 12
    "neck",           -- 13
    "l_collar",       -- 14
    "r_collar",       -- 15
    "head",           -- 16
    "l_shoulder",     -- 17
    "r_shoulder",     -- 18
    "l_elbow",        -- 19
    "r_elbow",        -- 20
    "l_wrist",        -- 21
    "r_wrist",        -- 22
    "l_hand",         -- 23
    "r_hand",         -- 24
}

--- Parent index for each joint (1-indexed, 0 = root)
Skeleton.PARENTS = {
    0,   -- 1 pelvis (root)
    1,   -- 2 l_hip
    1,   -- 3 r_hip
    1,   -- 4 spine1
    2,   -- 5 l_knee
    3,   -- 6 r_knee
    4,   -- 7 spine2
    5,   -- 8 l_ankle
    6,   -- 9 r_ankle
    7,   -- 10 spine3
    8,   -- 11 l_foot
    9,   -- 12 r_foot
    10,  -- 13 neck
    10,  -- 14 l_collar
    10,  -- 15 r_collar
    13,  -- 16 head
    14,  -- 17 l_shoulder
    15,  -- 18 r_shoulder
    17,  -- 19 l_elbow
    18,  -- 20 r_elbow
    19,  -- 21 l_wrist
    20,  -- 22 r_wrist
    21,  -- 23 l_hand
    22,  -- 24 r_hand
}

--- Bones to draw (pairs of joint indices)
Skeleton.BONES = {
    -- Spine
    {1, 4}, {4, 7}, {7, 10}, {10, 13}, {13, 16},
    -- Left leg
    {1, 2}, {2, 5}, {5, 8}, {8, 11},
    -- Right leg
    {1, 3}, {3, 6}, {6, 9}, {9, 12},
    -- Left arm
    {10, 14}, {14, 17}, {17, 19}, {19, 21}, {21, 23},
    -- Right arm
    {10, 15}, {15, 18}, {18, 20}, {20, 22}, {22, 24},
}

--- Body part groupings for energy/velocity visualization
Skeleton.BODY_PARTS = {
    torso    = {1, 4, 7, 10, 13, 16},
    left_arm = {14, 17, 19, 21, 23},
    right_arm = {15, 18, 20, 22, 24},
    left_leg = {2, 5, 8, 11},
    right_leg = {3, 6, 9, 12},
}

--- Contact joints (for force/balance analysis)
Skeleton.CONTACT_JOINTS = {
    l_ankle = 8,
    r_ankle = 9,
    l_foot  = 11,
    r_foot  = 12,
    l_wrist = 21,
    r_wrist = 22,
    l_hand  = 23,
    r_hand  = 24,
    head    = 16,  -- headspins
}

--- Default standing pose (2D screen positions, normalized 0-1)
--- Y-down screen coordinates, centered at pelvis
local function defaultPose()
    return {
        Vec.new(0.50, 0.45),  -- 1 pelvis
        Vec.new(0.46, 0.48),  -- 2 l_hip
        Vec.new(0.54, 0.48),  -- 3 r_hip
        Vec.new(0.50, 0.38),  -- 4 spine1
        Vec.new(0.44, 0.60),  -- 5 l_knee
        Vec.new(0.56, 0.60),  -- 6 r_knee
        Vec.new(0.50, 0.32),  -- 7 spine2
        Vec.new(0.43, 0.74),  -- 8 l_ankle
        Vec.new(0.57, 0.74),  -- 9 r_ankle
        Vec.new(0.50, 0.26),  -- 10 spine3
        Vec.new(0.43, 0.78),  -- 11 l_foot
        Vec.new(0.57, 0.78),  -- 12 r_foot
        Vec.new(0.50, 0.20),  -- 13 neck
        Vec.new(0.46, 0.23),  -- 14 l_collar
        Vec.new(0.54, 0.23),  -- 15 r_collar
        Vec.new(0.50, 0.14),  -- 16 head
        Vec.new(0.40, 0.24),  -- 17 l_shoulder
        Vec.new(0.60, 0.24),  -- 18 r_shoulder
        Vec.new(0.34, 0.34),  -- 19 l_elbow
        Vec.new(0.66, 0.34),  -- 20 r_elbow
        Vec.new(0.30, 0.44),  -- 21 l_wrist
        Vec.new(0.70, 0.44),  -- 22 r_wrist
        Vec.new(0.29, 0.46),  -- 23 l_hand
        Vec.new(0.71, 0.46),  -- 24 r_hand
    }
end

--- Create a new skeleton instance
--- @param scale number? Scale factor (default 400)
--- @param offset_x number? X offset (default 0)
--- @param offset_y number? Y offset (default 0)
function Skeleton.new(scale, offset_x, offset_y)
    local self = setmetatable({}, Skeleton)
    self.scale = scale or 400
    self.offset_x = offset_x or 0
    self.offset_y = offset_y or 0
    self.joints = defaultPose()
    self.joint_radius = 6
    self.bone_width = 3
    self.selected_joint = nil
    self.hovered_joint = nil
    self.joint_colors = {}  -- per-joint color override (for velocity/energy viz)
    self.bone_colors = {}   -- per-bone color override
    self.show_labels = false
    self.show_indices = false
    return self
end

--- Convert normalized joint position to screen coordinates
function Skeleton:toScreen(joint_pos)
    return
        joint_pos.x * self.scale + self.offset_x,
        joint_pos.y * self.scale + self.offset_y
end

--- Convert screen coordinates to normalized joint position
function Skeleton:fromScreen(sx, sy)
    return Vec.new(
        (sx - self.offset_x) / self.scale,
        (sy - self.offset_y) / self.scale
    )
end

--- Find joint at screen position (returns index or nil)
function Skeleton:hitTest(sx, sy, radius)
    radius = radius or (self.joint_radius * 2)
    local best_dist = radius
    local best_idx = nil

    for i, pos in ipairs(self.joints) do
        local jx, jy = self:toScreen(pos)
        local dx, dy = sx - jx, sy - jy
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist < best_dist then
            best_dist = dist
            best_idx = i
        end
    end
    return best_idx
end

--- Get chain from joint to root
function Skeleton:chainToRoot(joint_idx)
    local chain = {joint_idx}
    local parent = Skeleton.PARENTS[joint_idx]
    while parent > 0 do
        table.insert(chain, parent)
        parent = Skeleton.PARENTS[parent]
    end
    return chain
end

--- Get body part name for a joint index
function Skeleton:bodyPartOf(joint_idx)
    for part, joints in pairs(Skeleton.BODY_PARTS) do
        for _, j in ipairs(joints) do
            if j == joint_idx then return part end
        end
    end
    return "unknown"
end

--- Draw the skeleton
--- @param highlight_chain table? Chain of joint indices to highlight
function Skeleton:draw(highlight_chain)
    local chain_set = {}
    if highlight_chain then
        for _, idx in ipairs(highlight_chain) do
            chain_set[idx] = true
        end
    end

    -- Draw bones
    for _, bone in ipairs(Skeleton.BONES) do
        local j1, j2 = self.joints[bone[1]], self.joints[bone[2]]
        local x1, y1 = self:toScreen(j1)
        local x2, y2 = self:toScreen(j2)

        local in_chain = chain_set[bone[1]] and chain_set[bone[2]]

        if self.bone_colors[bone[1] .. "-" .. bone[2]] then
            local c = self.bone_colors[bone[1] .. "-" .. bone[2]]
            love.graphics.setColor(c[1], c[2], c[3], c[4] or 0.8)
        elseif in_chain then
            love.graphics.setColor(unpack(Theme.colors.bone_highlight))
        else
            love.graphics.setColor(unpack(Theme.colors.bone))
        end

        love.graphics.setLineWidth(in_chain and (self.bone_width + 1) or self.bone_width)
        love.graphics.line(x1, y1, x2, y2)
    end

    -- Draw joints
    for i, pos in ipairs(self.joints) do
        local jx, jy = self:toScreen(pos)
        local is_selected = (i == self.selected_joint)
        local is_hovered = (i == self.hovered_joint)
        local in_chain = chain_set[i]

        -- Joint fill
        if self.joint_colors[i] then
            local c = self.joint_colors[i]
            love.graphics.setColor(c[1], c[2], c[3], c[4] or 1)
        elseif is_selected then
            love.graphics.setColor(unpack(Theme.colors.joint_selected))
        elseif in_chain then
            love.graphics.setColor(unpack(Theme.colors.bone_highlight))
        elseif is_hovered then
            love.graphics.setColor(unpack(Theme.colors.joint_hover))
        else
            love.graphics.setColor(unpack(Theme.colors.joint))
        end

        local r = self.joint_radius
        if is_selected then r = r + 3 end
        if is_hovered then r = r + 1 end
        if i == 1 then r = r + 2 end  -- pelvis is larger

        love.graphics.circle("fill", jx, jy, r)

        -- Joint ring
        if is_selected or is_hovered then
            love.graphics.setColor(unpack(Theme.colors.text_muted))
            love.graphics.circle("line", jx, jy, r + 3)
        end

        -- Labels
        if self.show_labels and (is_selected or is_hovered or self.show_indices) then
            love.graphics.setColor(unpack(Theme.colors.text))
            local name = Skeleton.JOINT_NAMES[i]
            if self.show_indices then name = i .. ": " .. name end
            love.graphics.print(name, jx + r + 6, jy - 6)
        end
    end

    love.graphics.setLineWidth(1)
end

--- Set joints from an array of {x, y} or Vec positions (normalized)
function Skeleton:setJoints(positions)
    for i, pos in ipairs(positions) do
        if pos.x then
            self.joints[i] = pos
        else
            self.joints[i] = Vec.new(pos[1], pos[2])
        end
    end
end

--- Set joints from 3D data (project to 2D, ignoring Z for now)
function Skeleton:setJoints3D(positions_3d, project)
    project = project or function(p) return p.x, p.y end
    for i, pos in ipairs(positions_3d) do
        local px, py = project(pos)
        self.joints[i] = Vec.new(px, py)
    end
end

--- Reset to default standing pose
function Skeleton:reset()
    self.joints = defaultPose()
    self.selected_joint = nil
    self.hovered_joint = nil
    self.joint_colors = {}
    self.bone_colors = {}
end

return Skeleton
