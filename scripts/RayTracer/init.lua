local Vec3 = require "RayTracer.Math.Vec3"
local Ray = require "RayTracer.Math.Ray"
local Interval = require "RayTracer.Math.Interval"
local RNG = require "RayTracer.Math.RNG"
local Camera = require "RayTracer.Core.Camera"
local Scene = require "RayTracer.Core.Scene"
local Film = require "RayTracer.Core.Film"
local Renderer = require "RayTracer.Core.Renderer"
local NormalIntegrator = require "RayTracer.Integrator.NormalIntegrator"
local Sphere = require "RayTracer.Geometry.Sphere"
local PPMWriter = require "RayTracer.IO.PPMWriter"
local AsciiPresenter = require "RayTracer.IO.AsciiPresenter"

return {
    Vec3 = Vec3,
    Color = Vec3,
    Ray = Ray,
    Interval = Interval,
    RNG = RNG,
    Camera = Camera,
    Scene = Scene,
    Film = Film,
    Renderer = Renderer,
    NormalIntegrator = NormalIntegrator,
    Sphere = Sphere,
    PPMWriter = PPMWriter,
    AsciiPresenter = AsciiPresenter,
}
