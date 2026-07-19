local SceneDocument = require "Editor.SceneDocument"
local JsonSceneLoader = require "SceneFormat.JsonSceneLoader"
local RenderMode = require "render_legacy"
local UI = require "urhox-libs/UI"

local function runChecks()
    local document = SceneDocument.load(
        "Scenes/MaterialShowcase.json",
        nil
    )
    local added = document:addObject("sphere")
    document:updateObject(added.id, {
        center = { 9, 2, 7 },
        radius = 1.25,
    })
    local provider = JsonSceneLoader.compileDocument(
        document:snapshot(),
        "EditorRenderModeCheck"
    )
    local scene = provider.build()
    assert(#scene.objects == 53, "render uses edited memory document")

    RenderMode.start {
        sceneProvider = provider,
        onBack = function() end,
    }
    assert(RenderMode.isRunning(), "on-demand render started")
    RenderMode.update(0.016)
    RenderMode.stop()
    assert(not RenderMode.isRunning(), "on-demand render stopped")
    UI.Shutdown()
end

function Start()
    local ok, errorMessage = pcall(runChecks)
    if ok then
        print("[EditorRenderModeCheck] passed")
    else
        log:Write(LOG_ERROR,
            "[EditorRenderModeCheck] " .. tostring(errorMessage))
    end
    engine:Exit()
end
