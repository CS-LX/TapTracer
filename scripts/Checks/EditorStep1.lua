local SceneDocument = require "Editor.SceneDocument"
local EditorCameraController = require "Editor.EditorCameraController"
local ColorPicker = require "urhox-libs/UI/Widgets/ColorPicker"
local JsonSceneLoader = require "SceneFormat.JsonSceneLoader"

local function checkColorPickerContract()
    local received = nil
    local picker = ColorPicker {
        value = { r = 51, g = 102, b = 153, a = 255 },
        onChange = function(_, value)
            received = value
        end,
    }
    local initial = picker:GetValue()
    assert(initial.r == 51 and initial.g == 102 and initial.b == 153,
        "material color picker initial value")
    picker:SetRGB(17, 34, 68, 255)
    assert(received ~= nil
            and received.r == 17
            and received.g == 34
            and received.b == 68,
        "material color picker change value")
end

local function assertAngle(value, label)
    assert(type(value) == "number" and value == value, label)
end

local function checkCameraController()
    local previewScene = Scene()
    local cameraNode = previewScene:CreateChild("CameraCheck")
    cameraNode.position = Vector3(0, 8, -18)
    cameraNode:LookAt(Vector3(0, 2, 8), Vector3.UP, TS_WORLD)

    local controller = EditorCameraController.new(cameraNode)
    assertAngle(controller.yaw, "camera initial yaw")
    assertAngle(controller.pitch, "camera initial pitch")

    controller:applyLookDelta(10, 10000)
    assertAngle(controller.yaw, "camera look yaw")
    assert(controller.pitch == 89, "camera look pitch clamp")

    controller:focus(Vector3(2, 1, 4), 6)
    assertAngle(controller.yaw, "camera focus yaw")
    assertAngle(controller.pitch, "camera focus pitch")

    controller:useRenderCamera({
        lookFrom = { 1, 5, -9 },
        lookAt = { 0, 1, 3 },
        up = { 0, 1, 0 },
    })
    assertAngle(controller.yaw, "render camera yaw")
    assertAngle(controller.pitch, "render camera pitch")
    previewScene:Dispose()
end

local function runChecks()
    checkColorPickerContract()
    checkCameraController()
    local document = SceneDocument.load(
        "Scenes/MaterialShowcase.json",
        nil
    )
    assert(#document:getObjects() == 17, "editor source object count")
    assert(document:findObject("object-001") ~= nil, "stable object id")

    local added = document:addObject("sphere")
    assert(added.type == "sphere", "add sphere")
    assert(#document:getObjects() == 18, "object count after add")
    assert(document:updateObject(added.id, {
        center = { 2, 3, 4 },
        radius = 1.75,
    }), "update sphere")
    local changed = document:findObject(added.id)
    assert(changed.center[1] == 2 and changed.radius == 1.75,
        "sphere update values")

    local materialName = document:addMaterial()
    assert(document:getMaterials()[materialName] ~= nil, "add material")
    assert(document:updateObject(added.id, { material = materialName }),
        "assign material")
    assert(document:materialUsage(materialName) == 1, "material usage")
    assert(document:removeMaterial(materialName), "remove material")
    assert(document:findObject(added.id).material == "Default",
        "material fallback")

    local provider = JsonSceneLoader.compileDocument(
        document:snapshot(),
        "EditorSemanticCheck"
    )
    local scene = provider.build()
    assert(#scene.objects == 53, "compiled object count after sphere add")
    assert(#scene.lights == 2, "compiled light count")
    scene:buildBVH()
    assert(scene:getAccelerator() ~= nil, "compiled BVH")
    assert(provider.buildCamera({ width = 256, height = 144 }) ~= nil,
        "compiled camera")

    assert(document:removeObject(added.id), "remove sphere")
    assert(#document:getObjects() == 17, "object count restored")
end

function Start()
    local ok, errorMessage = pcall(runChecks)
    if ok then
        print("[EditorSemanticCheck] passed")
    else
        log:Write(LOG_ERROR,
            "[EditorSemanticCheck] " .. tostring(errorMessage))
    end
    engine:Exit()
end
