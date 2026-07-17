local Vec3 = require "RayTracer.Math.Vec3"
local Ray = require "RayTracer.Math.Ray"
local Interval = require "RayTracer.Math.Interval"
local RNG = require "RayTracer.Math.RNG"
local Camera = require "RayTracer.Core.Camera"
local Scene = require "RayTracer.Core.Scene"
local Film = require "RayTracer.Core.Film"
local Renderer = require "RayTracer.Core.Renderer"
local NormalIntegrator = require "RayTracer.Integrator.NormalIntegrator"
local PathIntegrator = require "RayTracer.Integrator.PathIntegrator"
local Sphere = require "RayTracer.Geometry.Sphere"
local Lambertian = require "RayTracer.Material.Lambertian"
local Metal = require "RayTracer.Material.Metal"
local Dielectric = require "RayTracer.Material.Dielectric"
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
    PathIntegrator = PathIntegrator,
    Sphere = Sphere,
    Lambertian = Lambertian,
    Metal = Metal,
    Dielectric = Dielectric,
    PPMWriter = PPMWriter,
    AsciiPresenter = AsciiPresenter,
}
