--- lib/physics.lua
--- Physics calculations for breakdancing visualization.
--- Force, energy, momentum, balance, and rotation.

local Vec = require("lib.vector")

local Physics = {}

--- Gravitational constant (scaled for visualization)
Physics.G = 9.81

--- Kinetic energy of a set of velocity vectors
--- K = Σ ||v_j||²
--- @param velocities table Array of Vec objects
--- @return number Total kinetic energy
function Physics.kineticEnergy(velocities)
    local sum = 0
    for _, v in ipairs(velocities) do
        sum = sum + v:len2()
    end
    return sum
end

--- Center of mass from joint positions (uniform mass assumed)
--- @param positions table Array of Vec objects
--- @return Vec Center of mass position
function Physics.centerOfMass(positions)
    local sum = Vec.new(0, 0)
    for _, p in ipairs(positions) do
        sum = sum + p
    end
    return sum * (1 / #positions)
end

--- Compactness: average distance from centroid
--- C(t) = (1/J) Σ_j ||p_j - centroid||
--- @param positions table Array of Vec objects
--- @return number Compactness value
function Physics.compactness(positions)
    local com = Physics.centerOfMass(positions)
    local sum = 0
    for _, p in ipairs(positions) do
        sum = sum + (p - com):len()
    end
    return sum / #positions
end

--- Moment of inertia about a pivot point (2D, uniform mass per joint)
--- I = Σ m_j * r_j²
--- @param positions table Array of Vec objects
--- @param pivot Vec Pivot point
--- @param mass number? Mass per joint (default 1)
--- @return number Moment of inertia
function Physics.momentOfInertia(positions, pivot, mass)
    mass = mass or 1
    local I = 0
    for _, p in ipairs(positions) do
        local r2 = (p - pivot):len2()
        I = I + mass * r2
    end
    return I
end

--- Angular momentum about a pivot (2D)
--- L = Σ r_j × (m_j * v_j)  (cross product z-component)
--- @param positions table Array of Vec objects
--- @param velocities table Array of Vec objects
--- @param pivot Vec Pivot point
--- @param mass number? Mass per joint (default 1)
--- @return number Angular momentum (scalar, positive = CCW)
function Physics.angularMomentum(positions, velocities, pivot, mass)
    mass = mass or 1
    local L = 0
    for i, p in ipairs(positions) do
        local r = p - pivot
        local v = velocities[i]
        -- 2D cross product: r.x * v.y - r.y * v.x
        L = L + mass * (r.x * v.y - r.y * v.x)
    end
    return L
end

--- Angular velocity from angular momentum and moment of inertia
--- ω = L / I
function Physics.angularVelocity(L, I)
    if math.abs(I) < 1e-10 then return 0 end
    return L / I
end

--- Support polygon from contact points (2D convex hull)
--- Returns ordered vertices of the convex hull
--- @param contacts table Array of Vec objects (2D contact positions)
--- @return table Ordered vertices of convex hull
function Physics.supportPolygon(contacts)
    if #contacts < 2 then return contacts end

    -- Graham scan for convex hull
    -- Find lowest point (highest y in screen coords)
    local pivot = contacts[1]
    for _, c in ipairs(contacts) do
        if c.y > pivot.y or (c.y == pivot.y and c.x < pivot.x) then
            pivot = c
        end
    end

    -- Sort by polar angle relative to pivot
    local sorted = {}
    for _, c in ipairs(contacts) do
        if c ~= pivot then table.insert(sorted, c) end
    end
    table.sort(sorted, function(a, b)
        local da = a - pivot
        local db = b - pivot
        local angle_a = math.atan2(da.y, da.x)
        local angle_b = math.atan2(db.y, db.x)
        return angle_a < angle_b
    end)

    -- Build hull
    local hull = {pivot}
    for _, p in ipairs(sorted) do
        while #hull >= 2 do
            local a = hull[#hull - 1]
            local b = hull[#hull]
            -- Cross product to check turn direction
            local cross = (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
            if cross <= 0 then
                table.remove(hull)
            else
                break
            end
        end
        table.insert(hull, p)
    end

    return hull
end

--- Check if a point is inside a convex polygon
--- @param point Vec 2D point
--- @param polygon table Array of Vec vertices (ordered)
--- @return boolean true if inside
function Physics.pointInPolygon(point, polygon)
    if #polygon < 3 then return false end

    local n = #polygon
    for i = 1, n do
        local j = (i % n) + 1
        local edge = polygon[j] - polygon[i]
        local to_point = point - polygon[i]
        local cross = edge.x * to_point.y - edge.y * to_point.x
        if cross < 0 then return false end
    end
    return true
end

--- Stability margin: minimum distance from COM to support polygon edge
--- @param com Vec Center of mass position (2D)
--- @param polygon table Support polygon vertices
--- @return number Stability margin (positive = stable, negative = unstable)
function Physics.stabilityMargin(com, polygon)
    if #polygon < 2 then return -1 end

    if not Physics.pointInPolygon(com, polygon) then
        return -1  -- outside polygon
    end

    local min_dist = math.huge
    local n = #polygon
    for i = 1, n do
        local j = (i % n) + 1
        local a = polygon[i]
        local b = polygon[j]
        local edge = b - a
        local to_com = com - a
        local edge_len = edge:len()
        if edge_len > 1e-10 then
            -- Distance from point to line segment
            local t = math.max(0, math.min(1, to_com:dot(edge) / (edge_len * edge_len)))
            local closest = a + t * edge
            local dist = (com - closest):len()
            if dist < min_dist then min_dist = dist end
        end
    end

    return min_dist
end

--- Centripetal force magnitude
--- F_c = m * v² / r
function Physics.centripetalForce(mass, velocity, radius)
    if radius < 1e-10 then return 0 end
    return mass * velocity * velocity / radius
end

--- Gyroscopic precession angular velocity
--- Ω = τ / (I * ω)
--- @param torque number Applied torque
--- @param I number Moment of inertia
--- @param omega number Spin angular velocity
--- @return number Precession rate
function Physics.precessionRate(torque, I, omega)
    local denom = I * omega
    if math.abs(denom) < 1e-10 then return 0 end
    return torque / denom
end

return Physics
