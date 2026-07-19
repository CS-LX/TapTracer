local RayTracer = require "RayTracer"

local JsonSceneLoader = {}

local function fail(path, message)
    error(string.format("JSON scene '%s': %s", path, message), 3)
end

local function requireTable(path, value, field)
    if type(value) ~= "table" then
        fail(path, field .. " must be an object or array")
    end
    return value
end

local function requireString(path, value, field)
    if type(value) ~= "string" or value == "" then
        fail(path, field .. " must be a non-empty string")
    end
    return value
end

local function requireNumber(path, value, field)
    if type(value) ~= "number" then
        fail(path, field .. " must be a number")
    end
    return value
end

local function vec3(path, value, field)
    requireTable(path, value, field)
    if #value ~= 3 then
        fail(path, field .. " must contain exactly three numbers")
    end
    return RayTracer.Vec3.new(
        requireNumber(path, value[1], field .. "[1]"),
        requireNumber(path, value[2], field .. "[2]"),
        requireNumber(path, value[3], field .. "[3]")
    )
end

local function readDocument(resourcePath)
    if not cache:Exists(resourcePath) then
        fail(resourcePath, "resource does not exist")
    end

    local file = cache:GetFile(resourcePath)
    if file == nil or not file:IsOpen() then
        fail(resourcePath, "resource could not be opened")
    end

    local source = file:ReadString()
    file:Close()

    local ok, document = pcall(cjson.decode, source)
    if not ok then
        fail(resourcePath, "invalid JSON: " .. tostring(document))
    end
    requireTable(resourcePath, document, "root")
    return document
end

local function buildTexture(path, name, descriptor)
    local field = "textures." .. name
    requireTable(path, descriptor, field)
    local textureType = requireString(path, descriptor.type, field .. ".type")

    if textureType == "solid" then
        return RayTracer.SolidColor.new(
            vec3(path, descriptor.color, field .. ".color")
        )
    end

    if textureType == "checker" then
        local scale = requireNumber(path, descriptor.scale, field .. ".scale")
        if scale == 0 then
            fail(path, field .. ".scale must not be zero")
        end
        return RayTracer.Checker.new(
            scale,
            RayTracer.SolidColor.new(
                vec3(path, descriptor.even, field .. ".even")
            ),
            RayTracer.SolidColor.new(
                vec3(path, descriptor.odd, field .. ".odd")
            )
        )
    end

    fail(path, field .. ".type has unsupported value '" .. textureType .. "'")
end

local function resolveTexture(path, textures, descriptor, field)
    if descriptor.texture ~= nil then
        local name = requireString(path, descriptor.texture, field .. ".texture")
        local texture = textures[name]
        if texture == nil then
            fail(path, field .. ".texture references unknown texture '" .. name .. "'")
        end
        return texture
    end
    if descriptor.color ~= nil then
        return RayTracer.SolidColor.new(
            vec3(path, descriptor.color, field .. ".color")
        )
    end
    fail(path, field .. " requires either texture or color")
end

local function buildMaterial(path, name, descriptor, textures)
    local field = "materials." .. name
    requireTable(path, descriptor, field)
    local materialType = requireString(path, descriptor.type, field .. ".type")

    if materialType == "lambertian" then
        return RayTracer.Lambertian.new(
            resolveTexture(path, textures, descriptor, field)
        )
    end

    if materialType == "metal" then
        local fuzz = descriptor.fuzz or 0
        requireNumber(path, fuzz, field .. ".fuzz")
        if fuzz < 0 or fuzz > 1 then
            fail(path, field .. ".fuzz must be between 0 and 1")
        end
        return RayTracer.Metal.new(
            vec3(path, descriptor.color, field .. ".color"),
            fuzz
        )
    end

    if materialType == "dielectric" then
        local ior = requireNumber(path, descriptor.ior, field .. ".ior")
        if ior <= 0 then
            fail(path, field .. ".ior must be greater than zero")
        end
        return RayTracer.Dielectric.new(ior)
    end

    if materialType == "diffuseLight" then
        local intensity = requireNumber(
            path,
            descriptor.intensity,
            field .. ".intensity"
        )
        if intensity < 0 then
            fail(path, field .. ".intensity must not be negative")
        end
        return RayTracer.DiffuseLight.new(
            resolveTexture(path, textures, descriptor, field),
            intensity
        )
    end

    fail(path, field .. ".type has unsupported value '" .. materialType .. "'")
end

local function materialForObject(path, materials, descriptor, field)
    local name = requireString(path, descriptor.material, field .. ".material")
    local material = materials[name]
    if material == nil then
        fail(path, field .. ".material references unknown material '" .. name .. "'")
    end
    return material
end

local function addBox(path, scene, descriptor, material, field)
    local minimum = vec3(path, descriptor.minimum, field .. ".minimum")
    local maximum = vec3(path, descriptor.maximum, field .. ".maximum")
    if minimum.x >= maximum.x
            or minimum.y >= maximum.y
            or minimum.z >= maximum.z then
        fail(path, field .. ".maximum must exceed minimum on every axis")
    end

    local minX, minY, minZ = minimum.x, minimum.y, minimum.z
    local maxX, maxY, maxZ = maximum.x, maximum.y, maximum.z
    local Vec3 = RayTracer.Vec3
    local Quad = RayTracer.Quad

    scene:add(Quad.new(Vec3.new(minX, minY, minZ),
        Vec3.new(maxX - minX, 0, 0), Vec3.new(0, maxY - minY, 0), material))
    scene:add(Quad.new(Vec3.new(minX, minY, maxZ),
        Vec3.new(maxX - minX, 0, 0), Vec3.new(0, maxY - minY, 0), material))
    scene:add(Quad.new(Vec3.new(minX, minY, minZ),
        Vec3.new(0, maxY - minY, 0), Vec3.new(0, 0, maxZ - minZ), material))
    scene:add(Quad.new(Vec3.new(maxX, minY, maxZ),
        Vec3.new(0, maxY - minY, 0), Vec3.new(0, 0, minZ - maxZ), material))
    scene:add(Quad.new(Vec3.new(minX, minY, minZ),
        Vec3.new(0, 0, maxZ - minZ), Vec3.new(maxX - minX, 0, 0), material))
    scene:add(Quad.new(Vec3.new(minX, maxY, minZ),
        Vec3.new(maxX - minX, 0, 0), Vec3.new(0, 0, maxZ - minZ), material))
end

local function addObject(path, scene, materials, descriptor, index)
    local field = "objects[" .. index .. "]"
    requireTable(path, descriptor, field)
    local objectType = requireString(path, descriptor.type, field .. ".type")
    local material = materialForObject(path, materials, descriptor, field)

    if objectType == "sphere" then
        local radius = requireNumber(path, descriptor.radius, field .. ".radius")
        if radius <= 0 then
            fail(path, field .. ".radius must be greater than zero")
        end
        scene:add(RayTracer.Sphere.new(
            vec3(path, descriptor.center, field .. ".center"),
            radius,
            material
        ))
        return
    end

    if objectType == "quad" then
        scene:add(RayTracer.Quad.new(
            vec3(path, descriptor.origin, field .. ".origin"),
            vec3(path, descriptor.edgeU, field .. ".edgeU"),
            vec3(path, descriptor.edgeV, field .. ".edgeV"),
            material
        ))
        return
    end

    if objectType == "box" then
        addBox(path, scene, descriptor, material, field)
        return
    end

    fail(path, field .. ".type has unsupported value '" .. objectType .. "'")
end

local function compile(resourcePath, document)
    if document.version ~= 1 then
        fail(resourcePath, "version must be 1")
    end

    local metadata = requireTable(resourcePath, document.metadata, "metadata")
    local camera = requireTable(resourcePath, document.camera, "camera")
    local textureDescriptors = requireTable(
        resourcePath,
        document.textures or {},
        "textures"
    )
    local materialDescriptors = requireTable(
        resourcePath,
        document.materials,
        "materials"
    )
    local objectDescriptors = requireTable(
        resourcePath,
        document.objects,
        "objects"
    )

    local textures = {}
    for name, descriptor in pairs(textureDescriptors) do
        textures[name] = buildTexture(resourcePath, name, descriptor)
    end

    local materials = {}
    for name, descriptor in pairs(materialDescriptors) do
        materials[name] = buildMaterial(resourcePath, name, descriptor, textures)
    end

    return {
        sourceType = "json",
        sourcePath = resourcePath,
        title = requireString(resourcePath, metadata.title, "metadata.title"),
        statusName = requireString(
            resourcePath,
            metadata.statusName,
            "metadata.statusName"
        ),
        background = vec3(resourcePath, document.background, "background"),
        buildCamera = function(config)
            requireTable(resourcePath, config, "camera config")
            local width = requireNumber(resourcePath, config.width, "camera config.width")
            local height = requireNumber(resourcePath, config.height, "camera config.height")
            if width <= 0 or height <= 0 then
                fail(resourcePath, "camera config dimensions must be greater than zero")
            end
            return RayTracer.Camera.new {
                aspectRatio = width / height,
                imageWidth = width,
                verticalFov = requireNumber(
                    resourcePath,
                    camera.verticalFov,
                    "camera.verticalFov"
                ),
                lookFrom = vec3(resourcePath, camera.lookFrom, "camera.lookFrom"),
                lookAt = vec3(resourcePath, camera.lookAt, "camera.lookAt"),
                up = vec3(resourcePath, camera.up, "camera.up"),
                defocusAngle = camera.defocusAngle or 0,
                focusDistance = camera.focusDistance,
            }
        end,
        build = function()
            local scene = RayTracer.Scene.new()
            for index, descriptor in ipairs(objectDescriptors) do
                addObject(resourcePath, scene, materials, descriptor, index)
            end
            return scene
        end,
    }
end

function JsonSceneLoader.load(resourcePath)
    requireString(resourcePath, resourcePath, "resourcePath")
    return compile(resourcePath, readDocument(resourcePath))
end

return JsonSceneLoader
