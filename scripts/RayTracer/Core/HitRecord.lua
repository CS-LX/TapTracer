local HitRecord = {}
HitRecord.__index = HitRecord

function HitRecord.new()
    return setmetatable({
        point = nil,
        normal = nil,
        t = 0,
        frontFace = true,
    }, HitRecord)
end

function HitRecord:setFaceNormal(ray, outwardNormal)
    self.frontFace = ray.direction:dot(outwardNormal) < 0
    self.normal = self.frontFace and outwardNormal or -outwardNormal
end

return HitRecord
