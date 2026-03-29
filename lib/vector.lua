--- lib/vector.lua
--- Lightweight 2D/3D vector math.
--- Returns new tables for safety; use _into variants for hot paths.

local Vec = {}
Vec.__index = Vec

--- Create a 2D or 3D vector
function Vec.new(x, y, z)
    return setmetatable({x = x or 0, y = y or 0, z = z}, Vec)
end

function Vec:is3d()
    return self.z ~= nil
end

function Vec:clone()
    return Vec.new(self.x, self.y, self.z)
end

--- Arithmetic
function Vec.__add(a, b) return Vec.new(a.x + b.x, a.y + b.y, a.z and b.z and (a.z + b.z) or nil) end
function Vec.__sub(a, b) return Vec.new(a.x - b.x, a.y - b.y, a.z and b.z and (a.z - b.z) or nil) end
function Vec.__mul(a, b)
    if type(a) == "number" then return Vec.new(a * b.x, a * b.y, b.z and (a * b.z) or nil) end
    if type(b) == "number" then return Vec.new(a.x * b, a.y * b, a.z and (a.z * b) or nil) end
    return Vec.new(a.x * b.x, a.y * b.y, a.z and b.z and (a.z * b.z) or nil)
end
function Vec.__unm(a) return Vec.new(-a.x, -a.y, a.z and -a.z or nil) end

function Vec:len2()
    local s = self.x * self.x + self.y * self.y
    if self.z then s = s + self.z * self.z end
    return s
end

function Vec:len()
    return math.sqrt(self:len2())
end

function Vec:normalize()
    local l = self:len()
    if l < 1e-10 then return Vec.new(0, 0, self.z and 0 or nil) end
    return Vec.new(self.x / l, self.y / l, self.z and (self.z / l) or nil)
end

function Vec:dot(other)
    local d = self.x * other.x + self.y * other.y
    if self.z and other.z then d = d + self.z * other.z end
    return d
end

--- 3D cross product
function Vec:cross(other)
    return Vec.new(
        (self.y * (other.z or 0)) - ((self.z or 0) * other.y),
        ((self.z or 0) * other.x) - (self.x * (other.z or 0)),
        (self.x * other.y) - (self.y * other.x)
    )
end

--- 2D perpendicular (rotate 90 degrees CCW)
function Vec:perp()
    return Vec.new(-self.y, self.x, self.z)
end

--- Distance
function Vec:dist(other)
    return (self - other):len()
end

--- Lerp
function Vec:lerp(other, t)
    return self + t * (other - self)
end

--- Rotate 2D by angle (radians)
function Vec:rotate(angle)
    local c, s = math.cos(angle), math.sin(angle)
    return Vec.new(self.x * c - self.y * s, self.x * s + self.y * c, self.z)
end

--- Angle of 2D vector
function Vec:angle()
    return math.atan2(self.y, self.x)
end

--- No-garbage variants: write result into `out`
function Vec.add_into(out, a, b)
    out.x = a.x + b.x
    out.y = a.y + b.y
    if a.z and b.z then out.z = a.z + b.z end
    return out
end

function Vec.sub_into(out, a, b)
    out.x = a.x - b.x
    out.y = a.y - b.y
    if a.z and b.z then out.z = a.z - b.z end
    return out
end

function Vec.scale_into(out, v, s)
    out.x = v.x * s
    out.y = v.y * s
    if v.z then out.z = v.z * s end
    return out
end

function Vec.__tostring(v)
    if v.z then
        return string.format("Vec(%.2f, %.2f, %.2f)", v.x, v.y, v.z)
    end
    return string.format("Vec(%.2f, %.2f)", v.x, v.y)
end

return Vec
