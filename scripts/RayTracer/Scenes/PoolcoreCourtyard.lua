local RayTracer = require "RayTracer"

local PoolcoreCourtyard = {
    title = "CPU Ray Tracer · Poolcore Courtyard",
    statusName = "Poolcore Courtyard",
    background = RayTracer.Vec3.new(0.16, 0.42, 0.92),
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

function PoolcoreCourtyard.buildCamera(config)
    local Vec3 = RayTracer.Vec3
    return RayTracer.Camera.new {
        aspectRatio = config.width / config.height,
        imageWidth = config.width,
        verticalFov = 55,
        lookFrom = Vec3.new(0, 3.6, -8.5),
        lookAt = Vec3.new(0, 2.0, 7.0),
        up = Vec3.new(0, 1, 0),
        defocusAngle = 0,
    }
end

function PoolcoreCourtyard.build()
    local Vec3 = RayTracer.Vec3
    local SolidColor = RayTracer.SolidColor
    local whiteTile = RayTracer.Lambertian.new(
        SolidColor.new(Vec3.new(0.92, 0.95, 0.94))
    )
    local paleStone = RayTracer.Lambertian.new(Vec3.new(0.82, 0.88, 0.87))
    local poolTile = RayTracer.Lambertian.new(RayTracer.Checker.new(
        0.55,
        SolidColor.new(Vec3.new(0.18, 0.67, 0.70)),
        SolidColor.new(Vec3.new(0.32, 0.82, 0.78))
    ))
    local glass = RayTracer.Dielectric.new(1.5)
    local metal = RayTracer.Metal.new(Vec3.new(0.92, 0.95, 0.98), 0.08)
    local coral = RayTracer.Lambertian.new(Vec3.new(0.95, 0.22, 0.28))
    local sunshine = RayTracer.Lambertian.new(Vec3.new(0.98, 0.72, 0.12))
    local skyBlue = RayTracer.Lambertian.new(Vec3.new(0.12, 0.46, 0.92))
    local lavender = RayTracer.Lambertian.new(Vec3.new(0.65, 0.35, 0.90))
    local sunLight = RayTracer.DiffuseLight.new(
        SolidColor.new(Vec3.new(1.0, 0.96, 0.82)),
        6.0
    )
    local scene = RayTracer.Scene.new()

    scene:add(RayTracer.Quad.new(
        Vec3.new(-12, -0.35, -5),
        Vec3.new(0, 0, 27),
        Vec3.new(24, 0, 0),
        paleStone
    ))
    scene:add(RayTracer.Quad.new(
        Vec3.new(-5.5, -0.28, -2),
        Vec3.new(11, 0, 0),
        Vec3.new(0, 0, 20),
        poolTile
    ))

    addBox(scene, Vec3.new(-9.0, 0, -2), Vec3.new(-7.7, 2.3, 19), whiteTile)
    addBox(scene, Vec3.new(7.7, 0, -2), Vec3.new(9.0, 2.3, 19), whiteTile)
    addBox(scene, Vec3.new(-7.7, 0, 18), Vec3.new(7.7, 2.3, 19.2), whiteTile)

    local archDepths = { 5.5, 10.5, 15.5 }
    for i = 1, #archDepths do
        local z = archDepths[i]
        addBox(scene, Vec3.new(-7.2, 0, z), Vec3.new(-6.45, 5.2, z + 0.7), whiteTile)
        addBox(scene, Vec3.new(6.45, 0, z), Vec3.new(7.2, 5.2, z + 0.7), whiteTile)
        addBox(scene, Vec3.new(-7.2, 4.45, z), Vec3.new(7.2, 5.2, z + 0.7), whiteTile)
    end

    scene:add(RayTracer.Quad.new(
        Vec3.new(-5.0, 9.0, -12.0),
        Vec3.new(10.0, 0, 0),
        Vec3.new(0, 0, 8.0),
        sunLight
    ))

    scene:add(RayTracer.Sphere.new(Vec3.new(-3.2, 0.8, 3.2), 0.8, coral))
    scene:add(RayTracer.Sphere.new(Vec3.new(2.4, 0.65, 5.6), 0.65, sunshine))
    scene:add(RayTracer.Sphere.new(Vec3.new(-1.0, 1.05, 9.0), 1.05, skyBlue))
    scene:add(RayTracer.Sphere.new(Vec3.new(4.2, 0.55, 12.2), 0.55, lavender))

    addBox(
        scene,
        Vec3.new(-3.5, 0.0, -0.2),
        Vec3.new(-0.2, 3.1, 3.1),
        glass
    )
    scene:add(RayTracer.Sphere.new(Vec3.new(2.0, 1.35, 1.2), 1.35, metal))

    return scene
end

return PoolcoreCourtyard
