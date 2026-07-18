local SceneCatalog = require "RayTracer.Scenes.SceneCatalog"

local function runChecks()
    local active = SceneCatalog.active
    local archived = SceneCatalog.archived.PoolcoreCourtyard

    assert(active ~= nil, "active scene must exist")
    assert(active.statusName == "Open Material Field",
        "MaterialShowcase must remain active")
    assert(archived ~= nil, "PoolcoreCourtyard archive must exist")
    assert(archived.statusName == "Poolcore Courtyard",
        "PoolcoreCourtyard archive identity")

    local activeScene = active.build()
    local archivedScene = archived.build()
    assert(#activeScene.objects == 52, "MaterialShowcase object count")
    assert(#activeScene.lights == 2, "MaterialShowcase light count")
    assert(#archivedScene.objects == 86, "PoolcoreCourtyard object count")
    assert(#archivedScene.lights == 1, "PoolcoreCourtyard light count")

    activeScene:buildBVH()
    archivedScene:buildBVH()
    assert(activeScene:getAccelerator() ~= nil, "MaterialShowcase BVH")
    assert(archivedScene:getAccelerator() ~= nil, "PoolcoreCourtyard BVH")

    local config = { width = 256, height = 144 }
    assert(active.buildCamera(config) ~= nil, "MaterialShowcase camera")
    assert(archived.buildCamera(config) ~= nil, "PoolcoreCourtyard camera")
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
