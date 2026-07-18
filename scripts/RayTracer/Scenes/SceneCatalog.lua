local MaterialShowcase = require "RayTracer.Scenes.MaterialShowcase"
local PoolcoreCourtyard = require "RayTracer.Scenes.PoolcoreCourtyard"

return {
    active = MaterialShowcase,
    archived = {
        PoolcoreCourtyard = PoolcoreCourtyard,
    },
}
