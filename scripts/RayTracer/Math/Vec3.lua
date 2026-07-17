local Vec3 = {}
Vec3.__index = Vec3

function Vec3.new(x, y, z)
    return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, Vec3)
end

function Vec3:clone()
    return Vec3.new(self.x, self.y, self.z)
end

function Vec3:lengthSquared()
    return self.x * self.x + self.y * self.y + self.z * self.z
end

function Vec3:length()
    return math.sqrt(self:lengthSquared())
end

function Vec3:nearZero()
    local epsilon = 1e-8
    return math.abs(self.x) < epsilon and math.abs(self.y) < epsilon and math.abs(self.z) < epsilon
end

function Vec3:unit()
    local length = self:length()
    if length == 0 then
        return Vec3.new(0, 0, 0)
    end
    return self / length
end

function Vec3:dot(other)
    return self.x * other.x + self.y * other.y + self.z * other.z
end

function Vec3:cross(other)
    return Vec3.new(
        self.y * other.z - self.z * other.y,
        self.z * other.x - self.x * other.z,
        self.x * other.y - self.y * other.x
    )
end

function Vec3:reflect(normal)
    return self - normal * (2 * self:dot(normal))
end

function Vec3:refract(normal, etaiOverEtat)
    local cosTheta = math.min((-self):dot(normal), 1.0)
    local perpendicular = (self + normal * cosTheta) * etaiOverEtat
    local parallel = normal * -math.sqrt(math.abs(1.0 - perpendicular:lengthSquared()))
    return perpendicular + parallel
end

function Vec3.random(rng)
    return Vec3.new(rng:nextFloat(), rng:nextFloat(), rng:nextFloat())
end

function Vec3.randomRange(rng, minValue, maxValue)
    local span = maxValue - minValue
    return Vec3.new(
        minValue + span * rng:nextFloat(),
        minValue + span * rng:nextFloat(),
        minValue + span * rng:nextFloat()
    )
end

function Vec3.randomInUnitSphere(rng)
    while true do
        local candidate = Vec3.randomRange(rng, -1, 1)
        if candidate:lengthSquared() < 1 then
            return candidate
        end
    end
end

function Vec3.randomUnitVector(rng)
    return Vec3.randomInUnitSphere(rng):unit()
end

function Vec3.randomInUnitDisk(rng)
    while true do
        local candidate = Vec3.new(-1 + 2 * rng:nextFloat(), -1 + 2 * rng:nextFloat(), 0)
        if candidate:lengthSquared() < 1 then
            return candidate
        end
    end
end

function Vec3.__add(left, right)
    return Vec3.new(left.x + right.x, left.y + right.y, left.z + right.z)
end

function Vec3.__sub(left, right)
    return Vec3.new(left.x - right.x, left.y - right.y, left.z - right.z)
end

function Vec3.__unm(value)
    return Vec3.new(-value.x, -value.y, -value.z)
end

function Vec3.__mul(left, right)
    if type(left) == "number" then
        return Vec3.new(left * right.x, left * right.y, left * right.z)
    end
    if type(right) == "number" then
        return Vec3.new(left.x * right, left.y * right, left.z * right)
    end
    return Vec3.new(left.x * right.x, left.y * right.y, left.z * right.z)
end

function Vec3.__div(left, right)
    return Vec3.new(left.x / right, left.y / right, left.z / right)
end

function Vec3.__tostring(value)
    return string.format("(%.6f, %.6f, %.6f)", value.x, value.y, value.z)
end

return Vec3
