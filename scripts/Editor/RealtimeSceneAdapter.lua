local PreviewMaterialFactory = require "Editor.PreviewMaterialFactory"

local RealtimeSceneAdapter = {}
RealtimeSceneAdapter.__index = RealtimeSceneAdapter

local OBJECT_ID_VAR = "EditorObjectId"

local function vector(value)
    return Vector3(value[1], value[2], value[3])
end

local function midpoint(a, b)
    return {
        (a[1] + b[1]) * 0.5,
        (a[2] + b[2]) * 0.5,
        (a[3] + b[3]) * 0.5,
    }
end

local function boxCenter(object)
    return midpoint(object.minimum, object.maximum)
end

local function boxSize(object)
    return {
        object.maximum[1] - object.minimum[1],
        object.maximum[2] - object.minimum[2],
        object.maximum[3] - object.minimum[3],
    }
end

local function createQuadGeometry(node, object, material)
    local edgeU = vector(object.edgeU)
    local edgeV = vector(object.edgeV)
    local normal = edgeU:CrossProduct(edgeV):Normalized()
    local geometry = node:CreateComponent("CustomGeometry")
    geometry:SetNumGeometries(1)
    geometry:BeginGeometry(0, TRIANGLE_LIST)
    local vertices = {
        Vector3.ZERO,
        edgeU,
        edgeU + edgeV,
        Vector3.ZERO,
        edgeU + edgeV,
        edgeV,
    }
    local uvs = {
        Vector2(0, 0), Vector2(1, 0), Vector2(1, 1),
        Vector2(0, 0), Vector2(1, 1), Vector2(0, 1),
    }
    for index, position in ipairs(vertices) do
        geometry:DefineVertex(position)
        geometry:DefineNormal(normal)
        geometry:DefineTexCoord(uvs[index])
    end
    geometry:Commit()
    geometry:SetMaterial(material)
    return geometry
end

function RealtimeSceneAdapter.new(document)
    return setmetatable({
        document = document,
        scene = nil,
        cameraNode = nil,
        camera = nil,
        viewport = nil,
        octree = nil,
        debugRenderer = nil,
        objectNodes = {},
        objectDrawables = {},
        materialFactory = PreviewMaterialFactory.new(document),
        selectedId = nil,
    }, RealtimeSceneAdapter)
end

function RealtimeSceneAdapter:build()
    self.scene = Scene()
    self.octree = self.scene:CreateComponent("Octree")
    self.debugRenderer = self.scene:CreateComponent("DebugRenderer")

    local zoneNode = self.scene:CreateChild("PreviewZone")
    local zone = zoneNode:CreateComponent("Zone")
    zone.boundingBox = BoundingBox(
        Vector3(-500, -500, -500),
        Vector3(500, 500, 500)
    )
    zone.ambientColor = Color(0.32, 0.36, 0.42)
    zone.fogColor = Color(0.29, 0.40, 0.52)
    zone.fogStart = 180
    zone.fogEnd = 400

    local lightNode = self.scene:CreateChild("PreviewSun")
    lightNode.direction = Vector3(0.4, -1.0, 0.3)
    local light = lightNode:CreateComponent("Light")
    light.lightType = LIGHT_DIRECTIONAL
    light.color = Color(1.0, 0.94, 0.84)
    light.castShadows = true

    self.cameraNode = self.scene:CreateChild("EditorCamera")
    self.cameraNode.position = Vector3(0, 8, -18)
    self.camera = self.cameraNode:CreateComponent("Camera")
    self.camera.nearClip = 0.1
    self.camera.farClip = 500
    self.camera.fov = 60
    self.cameraNode:LookAt(Vector3(0, 2, 8), Vector3.UP, TS_WORLD)
    self.viewport = Viewport:new(self.scene, self.camera)
    renderer:SetViewport(0, self.viewport)
    renderer.hdrRendering = true

    self:rebuildObjects()
    return self.scene
end

function RealtimeSceneAdapter:dispose()
    self.materialFactory:clear()
    renderer:SetViewport(0, nil)
    if self.scene ~= nil then
        self.scene:Dispose()
        self.scene = nil
    end
end

function RealtimeSceneAdapter:createObject(object)
    local node = self.scene:CreateChild(object.name or object.id)
    node:SetVar(OBJECT_ID_VAR, Variant(object.id))
    local material = self.materialFactory:get(object.material)
    local drawable
    if object.type == "box" then
        local center = boxCenter(object)
        local size = boxSize(object)
        node.position = vector(center)
        node.scale = vector(size)
        drawable = node:CreateComponent("StaticModel")
        drawable:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        drawable:SetMaterial(material)
        drawable.castShadows = true
    elseif object.type == "sphere" then
        node.position = vector(object.center)
        node.scale = Vector3.ONE * (object.radius * 2)
        drawable = node:CreateComponent("StaticModel")
        drawable:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
        drawable:SetMaterial(material)
        drawable.castShadows = true
    elseif object.type == "quad" then
        node.position = vector(object.origin)
        drawable = createQuadGeometry(node, object, material)
        drawable.castShadows = true
    end
    self.objectNodes[object.id] = node
    self.objectDrawables[object.id] = drawable
    return node
end

function RealtimeSceneAdapter:rebuildObjects()
    for _, node in pairs(self.objectNodes) do
        node:Remove()
    end
    self.objectNodes = {}
    self.objectDrawables = {}
    for _, object in ipairs(self.document:getObjects()) do
        self:createObject(object)
    end
end

function RealtimeSceneAdapter:updateObject(id)
    local object = self.document:findObject(id)
    local oldNode = self.objectNodes[id]
    if oldNode ~= nil then
        oldNode:Remove()
        self.objectNodes[id] = nil
        self.objectDrawables[id] = nil
    end
    if object ~= nil then
        self:createObject(object)
    end
end

function RealtimeSceneAdapter:removeObject(id)
    local node = self.objectNodes[id]
    if node ~= nil then
        node:Remove()
        self.objectNodes[id] = nil
        self.objectDrawables[id] = nil
    end
    if self.selectedId == id then
        self.selectedId = nil
    end
end

function RealtimeSceneAdapter:refreshMaterial(name)
    self.materialFactory:invalidate(name)
    for _, object in ipairs(self.document:getObjects()) do
        if object.material == name then
            self:updateObject(object.id)
        end
    end
end

function RealtimeSceneAdapter:select(id)
    self.selectedId = id
end

function RealtimeSceneAdapter:getObjectId(node)
    if node == nil then
        return nil
    end
    local value = node:GetVar(OBJECT_ID_VAR)
    if value == nil then
        return nil
    end
    return value:GetString()
end

function RealtimeSceneAdapter:pick(normalizedX, normalizedY)
    if self.camera == nil or self.octree == nil then
        return nil
    end
    local ray = self.camera:GetScreenRay(normalizedX, normalizedY)
    local result = self.octree:RaycastSingle(ray, RAY_TRIANGLE, 500, DRAWABLE_GEOMETRY, 0xFFFFFFFF)
    if result == nil or result.node == nil then
        return nil
    end
    return self:getObjectId(result.node)
end

function RealtimeSceneAdapter:setViewportRect(rect)
    if self.viewport ~= nil then
        self.viewport:SetRect(rect)
    end
end

function RealtimeSceneAdapter:getCameraNode()
    return self.cameraNode
end

function RealtimeSceneAdapter:getCamera()
    return self.camera
end

function RealtimeSceneAdapter:getObjectCenter(id)
    local object = self.document:findObject(id)
    if object == nil then
        return nil
    end
    if object.type == "box" then
        return vector(boxCenter(object))
    elseif object.type == "sphere" then
        return vector(object.center)
    end
    return vector(object.origin) + (vector(object.edgeU) + vector(object.edgeV)) * 0.5
end

function RealtimeSceneAdapter:drawDebug(tool)
    if self.debugRenderer == nil then
        return
    end
    local drawable = self.objectDrawables[self.selectedId]
    if drawable ~= nil then
        self.debugRenderer:AddBoundingBox(
            drawable.worldBoundingBox,
            Color(1.0, 0.75, 0.15),
            false,
            false
        )
        local center = self:getObjectCenter(self.selectedId)
        if center ~= nil then
            local length = 2.0
            self.debugRenderer:AddLine(center, center + Vector3.RIGHT * length, Color.RED, false)
            self.debugRenderer:AddLine(center, center + Vector3.UP * length, Color.GREEN, false)
            self.debugRenderer:AddLine(center, center + Vector3.FORWARD * length, Color.BLUE, false)
            if tool == "scale" then
                self.debugRenderer:AddCross(center + Vector3.RIGHT * length, 0.18, Color.RED, false)
                self.debugRenderer:AddCross(center + Vector3.UP * length, 0.18, Color.GREEN, false)
                self.debugRenderer:AddCross(center + Vector3.FORWARD * length, 0.18, Color.BLUE, false)
            end
        end
    end

    local cameraData = self.document:getData().camera
    local renderCameraNode = self.scene:CreateChild("RenderCameraDebug")
    renderCameraNode.position = vector(cameraData.lookFrom)
    renderCameraNode:LookAt(vector(cameraData.lookAt), vector(cameraData.up), TS_WORLD)
    local renderCamera = renderCameraNode:CreateComponent("Camera")
    renderCamera.fov = cameraData.verticalFov
    self.debugRenderer:AddFrustum(renderCamera.frustum, Color(0.2, 0.8, 1.0), false)
    renderCameraNode:Remove()
end

return RealtimeSceneAdapter
