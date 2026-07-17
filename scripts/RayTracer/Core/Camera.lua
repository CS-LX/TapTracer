local Vec3 = require "RayTracer.Math.Vec3"
local Ray = require "RayTracer.Math.Ray"

local Camera = {}
Camera.__index = Camera

function Camera.new(options)
    options = options or {}
    local aspectRatio = options.aspectRatio or 16 / 9
    local imageWidth = options.imageWidth or 64
    local imageHeight = math.max(1, math.floor(imageWidth / aspectRatio))
    local lookFrom = options.lookFrom or Vec3.new(0, 0, 0)
    local lookAt = options.lookAt or Vec3.new(0, 0, -1)
    local up = options.up or Vec3.new(0, 1, 0)
    local verticalFov = options.verticalFov or 90
    local focusDistance = options.focusDistance or (lookFrom - lookAt):length()
    local defocusAngle = options.defocusAngle or 0
    local theta = math.rad(verticalFov)
    local viewportHeight = 2 * math.tan(theta / 2) * focusDistance
    local viewportWidth = viewportHeight * aspectRatio
    local w = (lookFrom - lookAt):unit()
    local u = up:cross(w):unit()
    local v = w:cross(u)
    local viewportU = u * viewportWidth
    local viewportV = v * -viewportHeight
    local pixelDeltaU = viewportU / imageWidth
    local pixelDeltaV = viewportV / imageHeight
    local viewportUpperLeft = lookFrom - w * focusDistance - viewportU / 2 - viewportV / 2
    local pixel00 = viewportUpperLeft + (pixelDeltaU + pixelDeltaV) * 0.5
    local defocusRadius = focusDistance * math.tan(math.rad(defocusAngle / 2))

    return setmetatable({
        imageWidth = imageWidth,
        imageHeight = imageHeight,
        center = lookFrom,
        pixel00 = pixel00,
        pixelDeltaU = pixelDeltaU,
        pixelDeltaV = pixelDeltaV,
        defocusDiskU = u * defocusRadius,
        defocusDiskV = v * defocusRadius,
        defocusAngle = defocusAngle,
    }, Camera)
end

function Camera:getRay(pixelX, pixelY, rng)
    local offsetX = rng:nextFloat() - 0.5
    local offsetY = rng:nextFloat() - 0.5
    local pixelCenter = self.pixel00 + self.pixelDeltaU * (pixelX + offsetX) + self.pixelDeltaV * (pixelY + offsetY)
    local origin = self.center

    if self.defocusAngle > 0 then
        local disk = Vec3.randomInUnitDisk(rng)
        origin = self.center + self.defocusDiskU * disk.x + self.defocusDiskV * disk.y
    end

    return Ray.new(origin, pixelCenter - origin)
end

return Camera
