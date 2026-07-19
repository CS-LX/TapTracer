local JsonSceneLoader = require "SceneFormat.JsonSceneLoader"
local MaterialShowcaseLua = require "RayTracer.Scenes.MaterialShowcase"
local PoolcoreCourtyard = require "RayTracer.Scenes.PoolcoreCourtyard"

local MaterialShowcaseJson = JsonSceneLoader.load(
    "Scenes/MaterialShowcase.json"
)

return {
    active = MaterialShowcaseJson,
    json = {
        MaterialShowcase = MaterialShowcaseJson,
    },
    lua = {
        MaterialShowcase = MaterialShowcaseLua,
        PoolcoreCourtyard = PoolcoreCourtyard,
    },
    archived = {
        PoolcoreCourtyard = PoolcoreCourtyard,
    },
}
