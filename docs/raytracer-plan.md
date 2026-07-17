# 纯 Lua 5.4 CPU 光线追踪渲染器策划案

## 1. 项目定位

实现一个使用 Lua 5.4 编写的、与显示前端解耦的纯 CPU 光线追踪计算库。

核心库只负责：

- 场景、几何体、材质和相机的数据表达；
- 射线生成、求交、散射和辐射度积分；
- 逐像素或逐 Tile 产生线性 RGB 浮点颜色；
- 通过回调交付像素、进度和统计数据。

核心库不得依赖 OpenGL、DirectX、Vulkan、CUDA、窗口系统或 UI 框架。PPM 文件、ANSI 控制台、ASCII 灰度图、引擎纹理等均作为可替换输出适配器存在。

项目不是实时光追方案。第一目标是正确、可测试、可扩展的离线路径追踪器；第二目标才是 Lua 层性能优化。

## 2. 参考项目与采用原则

参考源码统一存放于 `references/raytracing/`，只用于研究，不直接参与产品构建。

### 2.1 主算法基线

- 仓库：`RayTracing/raytracing.github.io`
- 本地路径：`references/raytracing/raytracing.github.io/`
- 固定提交：`0ab7db4c08fe23f23c0d9d30fed166c83cefed91`
- 许可证：CC0-1.0，见 `COPYING.txt`
- 用途：作为数学公式、功能递进顺序、参考场景和正确性基线。

首期主要参考：

- `src/InOneWeekend/vec3.h`
- `src/InOneWeekend/ray.h`
- `src/InOneWeekend/interval.h`
- `src/InOneWeekend/hittable.h`
- `src/InOneWeekend/hittable_list.h`
- `src/InOneWeekend/sphere.h`
- `src/InOneWeekend/material.h`
- `src/InOneWeekend/camera.h`
- `src/InOneWeekend/color.h`

后续阶段参考 `src/TheNextWeek/` 中的 AABB、BVH、纹理、运动模糊、四边形、变换和体积实现。

### 2.2 完整 Lua 单文件参考

- 仓库：`LingDong-/teapot.lua`
- 本地路径：`references/raytracing/teapot.lua/`
- 固定提交：`288a2c8e939c9b5e02d9fe16b4a9ebc5f4550759`
- 许可证：MIT，见 `LICENSE`
- 用途：研究纯 Lua 下的 BVH、OBJ、BSDF、显式光源采样、PPM 输入输出和热点代码组织。

不照搬已发现的实现问题：

- 球体内部命中必须用最终选择的 `t` 计算命中点和法线；
- 最近命中必须把射线的最大距离更新为最近的 `t`，而不是远交点；
- LookAt 相机基向量必须保存归一化结果；
- 非均匀缩放下法线使用逆转置变换；
- 垂直 FOV 使用三角函数换算，不做线性近似；
- OBJ 按位置、UV、法线的索引三元组展开，支持负索引和硬边。

### 2.3 模块化 Lua 参考

- 仓库：`jonasgeiler/3d-raytracer-lua`
- 本地路径：`references/raytracing/3d-raytracer-lua/`
- 固定提交：`c1c262389bcde22f1d233584764ea525ba14c00c`
- 许可证：MIT，见 `LICENSE.md`
- 用途：研究模块边界、Hittable 包装、材质、纹理、BVH、场景定义和渲染进度组织。

不引入其 LuaJIT/Lua 5.1 假设。所有实现以 Lua 5.4 为基线，位运算使用 Lua 5.4 原生运算符，且不依赖 FFI、BitOp 或 C 扩展。

## 3. 许可证策略

- 产品实现以 CC0 算法基线进行独立 Lua 编写；
- 借鉴 MIT 项目的架构与算法时保留必要的许可证和归属记录；
- 不把三个参考仓库打包进最终构建；
- 不复制许可证不明确或强 copyleft 项目的代码；
- 产品源码中记录算法出处，但避免逐行翻译参考实现。

## 4. 技术边界

### 4.1 核心层允许依赖

- Lua 5.4 标准语言能力；
- `math`、`table`、`string` 等纯计算标准库；
- 调用方注入的随机数、时间、输出和取消回调。

### 4.2 核心层禁止依赖

- 任意图形 API；
- 窗口、UI 或纹理对象；
- `io`、`os`、引擎全局对象等平台特有能力；
- 网络、线程、FFI 或本地动态库；
- 全局可变渲染状态。

### 4.3 适配层

提供以下独立适配器：

1. `PPMWriter`：写出 P3 ASCII PPM；
2. `AnsiPresenter`：用 ANSI true-color 与半块字符输出终端预览；
3. `AsciiPresenter`：把亮度映射为字符，不要求真彩终端；
4. `CallbackPresenter`：把 Tile/像素交给调用方；
5. 可选平台适配器：在不污染核心层的前提下使用宿主提供的文件或图像接口。

标准 Lua CLI 可使用 `io.write` 适配器；UrhoX 环境使用 `File` 或像素回调适配器。二者共享同一计算核心。

## 5. 目录设计

正式实现阶段使用以下结构：

```text
scripts/
├── main.lua
├── RayTracer/
│   ├── Math/
│   │   ├── Vec3.lua
│   │   ├── Ray.lua
│   │   ├── Interval.lua
│   │   └── RNG.lua
│   ├── Core/
│   │   ├── HitRecord.lua
│   │   ├── Scene.lua
│   │   ├── Camera.lua
│   │   ├── Film.lua
│   │   ├── Renderer.lua
│   │   └── RenderSettings.lua
│   ├── Geometry/
│   │   ├── Sphere.lua
│   │   ├── Plane.lua
│   │   ├── Triangle.lua
│   │   └── TriangleMesh.lua
│   ├── Acceleration/
│   │   ├── AABB.lua
│   │   └── BVH.lua
│   ├── Material/
│   │   ├── Lambertian.lua
│   │   ├── Metal.lua
│   │   ├── Dielectric.lua
│   │   └── DiffuseLight.lua
│   ├── Texture/
│   │   ├── SolidColor.lua
│   │   ├── Checker.lua
│   │   └── ImageTexture.lua
│   ├── Integrator/
│   │   ├── NormalIntegrator.lua
│   │   └── PathIntegrator.lua
│   ├── IO/
│   │   ├── PPMWriter.lua
│   │   ├── AnsiPresenter.lua
│   │   ├── AsciiPresenter.lua
│   │   └── CallbackPresenter.lua
│   └── Scenes/
│       ├── Normals.lua
│       ├── Materials.lua
│       ├── RandomSpheres.lua
│       └── CornellBox.lua
└── Tests/
    └── RayTracerTests.lua
```

实现时可先合并过小模块，避免过度拆分；但数学、求交、材质、积分器和输出适配器必须保持边界清晰。

## 6. 公共 API 草案

### 6.1 构建场景

```lua
local RT = require "RayTracer"

local scene = RT.Scene.new()
scene:Add(RT.Sphere.new(
    RT.Vec3.new(0, 0, 1),
    0.5,
    RT.Lambertian.new(RT.Color.new(0.7, 0.3, 0.3))
))
```

### 6.2 配置相机

```lua
local camera = RT.Camera.new {
    aspectRatio = 16 / 9,
    verticalFov = 40,
    lookFrom = RT.Vec3.new(3, 2, -3),
    lookAt = RT.Vec3.new(0, 0, 0),
    up = RT.Vec3.new(0, 1, 0),
    defocusAngle = 0,
    focusDistance = 4,
}
```

坐标约定为 Y-up、左手坐标系，Z 轴向前。参考项目中的相机与叉乘方向必须显式转换并通过测试验证，不能直接假设符号一致。

### 6.3 渲染

```lua
local job = RT.Renderer.new {
    width = 320,
    height = 180,
    samplesPerPixel = 16,
    maxDepth = 8,
    tileSize = 16,
    seed = 42,
    integrator = RT.PathIntegrator.new(),
    presenter = RT.CallbackPresenter.new {
        onTile = function(x, y, width, height, pixels)
        end,
        onProgress = function(done, total, stats)
        end,
    },
}

job:Render(scene, camera)
```

### 6.4 可中断和分步执行

渲染器支持：

```lua
job:Step(tileBudget)
job:IsComplete()
job:Cancel()
job:GetStats()
```

这保证同一个核心既可阻塞式离线渲染，也可被游戏循环或 GUI 每帧推进少量工作。

## 7. 数据与数学约定

- 颜色在计算过程中使用线性 RGB 浮点数；
- `Film` 保存样本平均后的线性 HDR RGB，是渲染结果的原始数据源，允许分量小于 0 或大于 1，不因预览显示而覆盖；
- 当前 NanoVG 预览仅在量化边界执行非负截断与 `[0, 1]` Clamp，再转换为 8-bit RGB；Clamp 后的颜色只用于显示，不写回 `Film`；
- 后续显示质量优化统一放在独立输出转换层：固定曝光、连续亮度色调映射、可选高光趋白、Linear RGB 到 sRGB 编码，并由 NanoVG、PPM、ANSI 等 Presenter 共享；
- 射线有效区间使用 `tMin`/`tMax`，以 epsilon 避免自相交；
- `HitRecord:SetFaceNormal(ray, outwardNormal)` 统一维护正面标志与朝向射线的法线；
- 所有方向向量在要求单位长度的边界处显式归一化；
- FOV 使用弧度参与三角函数，公共 API 接收角度；
- 随机采样使用可复现的独立 PRNG，不依赖全局 `math.random` 状态；
- 每个 Tile 或像素从全局 seed 派生子序列，确保改变渲染顺序不会改变结果；
- 初期使用有限最大深度；加入 Russian Roulette 后仍保留硬上限。

## 8. 渲染算法路线

### 阶段 A：最小正确光线追踪器

目标：输出可验证的球体法线图。

- Vec3、Color、Ray、Interval；
- Perspective Camera；
- Sphere 求交；
- Hittable Scene；
- NormalIntegrator；
- 单样本渲染；
- PPM 和 ASCII 输出；
- 固定 seed；
- 64×36、160×90 测试分辨率。

验收：

- 中心射线命中测试球；
- 切线、球内射线、负半径和最近命中测试；
- 输出 PPM Header 与像素数量正确；
- 固定 seed 结果稳定。

### 阶段 B：基础路径追踪

目标：复现官方材质球场景。

- 多重子像素采样；
- Lambertian 漫反射；
- Metal 镜面与 fuzz；
- Dielectric 折射、全反射和 Schlick 近似；
- 天空背景；
- 最大反弹深度；
- Gamma 校正；
- Thin lens 景深。

验收：

- 与官方参考场景构图和材质行为一致；
- fuzz 限制在合法区间；
- 玻璃球内外法线和折射率切换正确；
- 不产生 NaN、Inf 或明显黑斑。

### 阶段 C：可用的离线渲染任务

目标：从 Demo 演进为可嵌入计算库。

- Tile 调度；
- `Step`、取消、进度与统计；
- Film 累积缓冲；
- 渐进式采样；
- PPM、ANSI、ASCII、Callback 四种输出；
- 配置校验放在公共 API 边界；
- 不同输出端产生相同的量化颜色。

验收：

- 阻塞渲染与逐步渲染结果一致；
- Tile 顺序变化不影响固定 seed 结果；
- 取消后不继续分配渲染工作；
- 核心模块不引用任何显示或文件 API。

### 阶段 D：几何与 BVH

目标：支持复杂静态场景。

- AABB slab 求交；
- Triangle 与 Möller–Trumbore 求交；
- 平面或 Quad；
- 中位数切分 BVH；
- 扁平数组 BVH；
- 显式栈遍历；
- 最近命中裁剪；
- 可选 SAH 分桶构建；
- OBJ Loader 作为独立 IO 模块。

验收：

- BVH 与暴力遍历命中结果逐射线一致；
- 支持从包围盒内部发出的射线；
- 平行轴方向无除零错误；
- OBJ 支持 `v`、`vt`、`vn`、多边形三角化和负索引；
- BVH 场景具有可测量的求交次数下降。

### 阶段 E：灯光、纹理与质量提升

目标：支持 Cornell Box 和更稳定的路径追踪。

- DiffuseLight；
- Solid、Checker 和 PPM Image Texture；
- UV；
- 当前已完成最小 `ImageTexture.fromPPM()`：核心接收 ASCII P3 PPM 文本，按命中记录的 `u/v` 采样并保持原始线性 RGB；文件读取继续留在宿主适配层，核心不直接依赖文件系统；
- 当前已将 BVH 接入 `Scene:hit()` 主查询路径：Scene 缓存可选加速器，`add/clear` 自动失效，未构建时回退暴力遍历，并保留命中结果差分与查询统计；
- 矩形面光源；
- 显式光源采样；
- 阴影射线；
- Russian Roulette；
- 当前阶段保留线性 HDR `Film`，预览端暂用直接 Clamp；统一曝光、色调映射与 sRGB 输出标记为后续质量优化；
- 下一步再评估 MIS，不在第一版预埋复杂抽象。

验收：

- Cornell Box 能稳定出图；
- 低样本下显式光源采样显著降低噪声；
- 材质发光和背景发光职责明确；
- Russian Roulette 不改变期望亮度。

## 9. 性能策略

按以下顺序优化，不提前引入复杂机制：

1. 先建立正确性测试和基准场景；
2. 减少热点循环中的临时 table；
3. 对 Vec3 提供清晰 API，同时在交点和积分热点中允许局部标量运算；
4. 缓存频繁使用的函数与字段到 local；
5. 使用扁平 Film 数组和扁平 BVH 节点数组；
6. BVH 遍历使用复用的显式栈；
7. 先遍历较近子节点并收紧 `tMax`；
8. 渲染以 Tile 为单位，降低回调和控制台刷新频率；
9. 提供低分辨率渐进预览；
10. 只有基准证明必要时，才增加多进程 Tile Worker 适配器。

首版不使用协程模拟并行。协程可以用于让出执行权，但不会提供 CPU 并行加速。

## 10. 测试方案

### 10.1 单元测试

- Vec3 加减乘除、点积、叉积、归一化、反射、折射；
- 零向量与 near-zero 判断；
- 球体外部、内部、切线和未命中；
- AABB 六个方向、平行方向和盒内起点；
- 三角形正反面、边缘和退化三角形；
- Face normal 与 frontFace；
- 固定 seed PRNG 序列；
- PPM Header、量化、Gamma 与像素顺序。

### 10.2 差分测试

- 同一场景使用暴力遍历与 BVH，比较命中对象、距离和法线；
- 阻塞式与 Step 式渲染比较像素缓冲；
- PPM、ANSI、Callback 在颜色量化前使用同一 Film 数据；
- 关键参考场景保存低分辨率 golden checksum。

### 10.3 基准场景

- 单球法线图：64×36，1 spp；
- 材质球：160×90，8 spp，8 depth；
- Random Spheres：320×180，16 spp；
- Cornell Box：320×320，32 spp；
- 三角网格：固定射线集比较暴力遍历和 BVH。

基准记录：总射线数、主射线数、反弹射线数、AABB 测试数、Primitive 测试数、耗时和每秒射线数。

## 11. 日志与可观测性

首次交付保留以下日志：

- 渲染配置摘要；
- 场景 Primitive 与材质数量；
- BVH 节点数、叶节点数、最大深度和构建耗时；
- 每个阶段的进度；
- 总射线数、平均路径深度、命中率；
- NaN/Inf 像素计数；
- 完成、取消和错误原因。

稳定后移除逐 Tile 调试日志，只保留任务开始、任务结束、关键统计和错误日志。

## 12. 风险与应对

### 12.1 Lua 性能

风险：高分辨率、高 spp 和深路径会导致长时间计算。

应对：低分辨率渐进预览、Tile 调度、BVH、固定性能基准、减少临时对象；明确定位为离线 renderer。

### 12.2 数值稳定性

风险：自相交、法线方向错误、全反射边界和除零产生黑斑或 NaN。

应对：统一 `Interval`、face normal、epsilon 策略和有限值检测；为球内射线、切线、平行盒面等边界建立测试。

### 12.3 坐标系迁移

风险：参考实现多采用不同相机方向约定，直接移植会造成画面镜像、前后颠倒或叉乘方向错误。

应对：本项目固定 Y-up 左手坐标系；相机基向量和测试场景按该约定重新推导，并通过中心、左上、右下射线方向测试锁定行为。

### 12.4 平台文件能力

风险：标准 Lua CLI 的 `io` 与受限宿主环境的文件 API 不一致。

应对：计算核心不执行文件操作；PPM Writer 只依赖注入的 `write(chunk)` sink，由 CLI 或宿主适配器提供。

### 12.5 参考实现缺陷传播

风险：教学仓库可能存在边界 Bug 或为简洁牺牲正确性。

应对：以数学推导和官方算法为主；Lua 仓库只作结构及性能参考；通过单元、差分和 golden 测试验证每个阶段。

## 13. 交付节点

### 交付 1：法线图内核

- 纯计算核心；
- Sphere 场景；
- PPM 与 ASCII 输出；
- 单元测试；
- 固定 seed 与基础统计。

### 交付 2：基础路径追踪器

- 三种基础材质；
- 抗锯齿、递归反弹、景深；
- 官方材质球参考场景；
- 渐进式 Tile 渲染。

### 交付 3：BVH 与网格

- AABB、Triangle、BVH；
- OBJ 导入；
- 暴力遍历/BVH 差分测试与性能对比。

### 交付 4：Cornell Box

- 发光材质、面光源、纹理；
- 显式光源采样；
- Cornell Box；
- 最终性能与正确性报告。

## 14. 第一轮实施决策

开始编码时采用以下最小范围：

- Lua 5.4；
- 模块化而非单文件；
- 64×36 默认验证分辨率；
- NormalIntegrator 优先；
- Sphere 为唯一首期 Primitive；
- PPM sink 和 ASCII presenter；
- 固定 seed；
- 可阻塞 Render 和可分步 Step；
- 暂不实现 BVH、OBJ、多线程、MIS 或图形前端。

第一轮验收通过后再进入基础路径追踪材质阶段，避免在求交、坐标系或输出仍未验证时叠加复杂度。
