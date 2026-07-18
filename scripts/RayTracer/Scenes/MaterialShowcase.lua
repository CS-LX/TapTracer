local RayTracer = require "RayTracer"

local MaterialShowcase = {
    title = "CPU Ray Tracer · Open Material Field",
    statusName = "Open Material Field",
    background = RayTracer.Vec3.new(0.29, 0.56, 0.85),
}

local function addBox(scene, minimum, maximum, material)
    local Vec3 = RayTracer.Vec3
    local minX, minY, minZ = minimum.x, minimum.y, minimum.z
    local maxX, maxY, maxZ = maximum.x, maximum.y, maximum.z

    scene:add(RayTracer.Quad.new(
        Vec3.new(minX, minY, minZ),
        Vec3.new(maxX - minX, 0, 0),
        Vec3.new(0, maxY - minY, 0),
        material
    ))
    scene:add(RayTracer.Quad.new(
        Vec3.new(minX, minY, maxZ),
        Vec3.new(maxX - minX, 0, 0),
        Vec3.new(0, maxY - minY, 0),
        material
    ))
    scene:add(RayTracer.Quad.new(
        Vec3.new(minX, minY, minZ),
        Vec3.new(0, maxY - minY, 0),
        Vec3.new(0, 0, maxZ - minZ),
        material
    ))
    scene:add(RayTracer.Quad.new(
        Vec3.new(maxX, minY, maxZ),
        Vec3.new(0, maxY - minY, 0),
        Vec3.new(0, 0, minZ - maxZ),
        material
    ))
    scene:add(RayTracer.Quad.new(
        Vec3.new(minX, minY, minZ),
        Vec3.new(0, 0, maxZ - minZ),
        Vec3.new(maxX - minX, 0, 0),
        material
    ))
    scene:add(RayTracer.Quad.new(
        Vec3.new(minX, maxY, minZ),
        Vec3.new(maxX - minX, 0, 0),
        Vec3.new(0, 0, maxZ - minZ),
        material
    ))
end

local function diffuse(color)
    return RayTracer.Lambertian.new(color)
end

function MaterialShowcase.buildCamera(config)
    local Vec3 = RayTracer.Vec3
    return RayTracer.Camera.new {
        aspectRatio = config.width / config.height,
        imageWidth = config.width,
        verticalFov = 47,
        lookFrom = Vec3.new(0, 5.2, -15.0),
        lookAt = Vec3.new(0, 1.5, 10.0),
        up = Vec3.new(0, 1, 0),
        defocusAngle = 0,
    }
end

function MaterialShowcase.build()
    local Vec3 = RayTracer.Vec3
    local SolidColor = RayTracer.SolidColor
    local scene = RayTracer.Scene.new()

    local ground = RayTracer.Lambertian.new(RayTracer.Checker.new(
        3.0,
        SolidColor.new(Vec3.new(0.48, 0.55, 0.46)),
        SolidColor.new(Vec3.new(0.72, 0.70, 0.60))
    ))
    local pedestal = diffuse(Vec3.new(0.72, 0.74, 0.70))
    local white = diffuse(Vec3.new(0.88, 0.90, 0.86))
    local coral = diffuse(Vec3.new(0.88, 0.12, 0.08))
    local cobalt = diffuse(Vec3.new(0.08, 0.24, 0.88))
    local violet = diffuse(Vec3.new(0.55, 0.12, 0.78))
    local amber = diffuse(Vec3.new(0.96, 0.54, 0.06))
    local turquoise = diffuse(Vec3.new(0.04, 0.68, 0.60))
    local glass = RayTracer.Dielectric.new(1.5)
    local goldMetal = RayTracer.Metal.new(Vec3.new(0.95, 0.64, 0.22), 0.12)
    local copperMetal = RayTracer.Metal.new(Vec3.new(0.90, 0.34, 0.16), 0.24)
    local blueMetal = RayTracer.Metal.new(Vec3.new(0.18, 0.42, 0.92), 0.08)
    local daylight = RayTracer.DiffuseLight.new(
        SolidColor.new(Vec3.new(1.0, 0.98, 0.92)),
        7.0
    )
    local sun = RayTracer.DiffuseLight.new(
        SolidColor.new(Vec3.new(1.0, 0.88, 0.62)),
        5.0
    )

    -- 120 × 110 米开放地面，远端自然落入蓝色天空背景。
    scene:add(RayTracer.Quad.new(
        Vec3.new(-60, -0.05, -20),
        Vec3.new(0, 0, 110),
        Vec3.new(120, 0, 0),
        ground
    ))

    -- 前景三种核心材质：无色玻璃、有色金属、有色漫反射。
    addBox(scene, Vec3.new(-6.9, 0, 2.1), Vec3.new(-2.7, 0.35, 6.3), pedestal)
    scene:add(RayTracer.Sphere.new(Vec3.new(-4.8, 2.05, 4.2), 1.8, glass))

    addBox(scene, Vec3.new(-2.0, 0, 3.3), Vec3.new(2.0, 0.35, 7.3), pedestal)
    scene:add(RayTracer.Sphere.new(Vec3.new(0, 1.95, 5.3), 1.6, goldMetal))

    addBox(scene, Vec3.new(2.6, 0, 2.2), Vec3.new(6.8, 0.35, 6.4), pedestal)
    scene:add(RayTracer.Sphere.new(Vec3.new(4.7, 2.0, 4.3), 1.65, coral))

    -- 中景让玻璃同时折射高饱和颜色、亮面金属与几何轮廓。
    addBox(scene, Vec3.new(-7.8, 0, 11.2), Vec3.new(-5.2, 3.2, 14.0), cobalt)
    scene:add(RayTracer.Sphere.new(Vec3.new(-2.8, 1.35, 12.6), 1.35, copperMetal))
    addBox(scene, Vec3.new(0.1, 0, 11.1), Vec3.new(3.2, 3.7, 14.2), glass)
    scene:add(RayTracer.Sphere.new(Vec3.new(6.0, 1.45, 12.8), 1.45, violet))

    -- 远景彩色地标强化尺度、纵深和不同粗糙度反射。
    addBox(scene, Vec3.new(-10.5, 0, 20.0), Vec3.new(-8.0, 5.5, 22.5), amber)
    scene:add(RayTracer.Sphere.new(Vec3.new(-4.8, 1.2, 21.2), 1.2, blueMetal))
    addBox(scene, Vec3.new(1.7, 0, 19.7), Vec3.new(4.5, 4.2, 22.5), turquoise)
    scene:add(RayTracer.Sphere.new(Vec3.new(9.0, 1.45, 21.5), 1.45, white))

    -- 一块主面光提供稳定照明，暖色太阳球提供方向感并可直接入镜。
    scene:add(RayTracer.Quad.new(
        Vec3.new(-8.0, 12.0, -5.0),
        Vec3.new(16.0, 0, 0),
        Vec3.new(0, 0, 12.0),
        daylight
    ))
    scene:add(RayTracer.Sphere.new(Vec3.new(15.0, 15.0, 18.0), 2.2, sun))

    return scene
end

return MaterialShowcase
