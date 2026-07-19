local SceneCatalog = require "RayTracer.Scenes.SceneCatalog"

local function assertScene(provider, objectCount, lightCount, label)
    local scene = provider.build()
    assert(#scene.objects == objectCount, label .. " object count")
    assert(#scene.lights == lightCount, label .. " light count")
    scene:buildBVH()
    assert(scene:getAccelerator() ~= nil, label .. " BVH")

    local config = { width = 256, height = 144 }
    assert(provider.buildCamera(config) ~= nil, label .. " camera")
    return scene
end

local function runChecks()
    local active = SceneCatalog.active
    local jsonShowcase = SceneCatalog.json.MaterialShowcase
    local luaShowcase = SceneCatalog.lua.MaterialShowcase
    local archived = SceneCatalog.archived.PoolcoreCourtyard

    assert(active ~= nil, "active scene must exist")
    assert(active == jsonShowcase, "JSON MaterialShowcase must remain active")
    assert(active.sourceType == "json", "active scene source type")
    assert(active.sourcePath == "Scenes/MaterialShowcase.json",
        "active scene source path")
    assert(active.statusName == "Open Material Field",
        "MaterialShowcase must remain active")
    assert(luaShowcase ~= nil, "Lua MaterialShowcase must remain available")
    assert(archived ~= nil, "PoolcoreCourtyard archive must exist")
    assert(archived.statusName == "Poolcore Courtyard",
        "PoolcoreCourtyard archive identity")

    local jsonScene = assertScene(jsonShowcase, 52, 2, "JSON MaterialShowcase")
    local luaScene = assertScene(luaShowcase, 52, 2, "Lua MaterialShowcase")
    assertScene(archived, 86, 1, "Lua PoolcoreCourtyard")

    assert(#jsonScene.objects == #luaScene.objects,
        "JSON and Lua MaterialShowcase object parity")
    assert(#jsonScene.lights == #luaScene.lights,
        "JSON and Lua MaterialShowcase light parity")
end

function Start()
    local ok, errorMessage = pcall(runChecks)
    if ok then
        print("[SceneCatalogCheck] passed")
    else
        log:Write(LOG_ERROR, "[SceneCatalogCheck] " .. tostring(errorMessage))
    end
    engine:Exit()
end
