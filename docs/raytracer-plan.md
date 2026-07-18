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
- 当前阶段保留线性 HDR `Film`，预览端暂用直接 Clamp；统一曝光、色调映射与 sRGB 输出属于阶段 I；
- MIS 不属于当前阶段，必须在阶段 F 的基准、阶段 G 的累积采样、阶段 H 的分辨率档位和阶段 I 的输出转换稳定后，按阶段 J 的数据决定是否实现；

验收：

- Cornell Box 能稳定出图；
- 低样本下显式光源采样显著降低噪声；
- 材质发光和背景发光职责明确；
- Russian Roulette 不改变期望亮度。

### 阶段 F：性能基准与可观测性

目标：先用数据确定瓶颈，再进行任何热点优化或默认分辨率提升。

- 为渲染任务记录开始时间、结束时间和有效计算耗时；计时器由调用方注入，计算核心不直接依赖引擎或 `os`；
- 统计主相机样本数、路径数、总反弹数、阴影射线数、场景命中数和背景未命中数；
- 保留 BVH 的 AABB 测试数、Primitive 测试数、节点数、叶节点数和最大深度；
- 派生每秒主样本数、每秒路径数、平均路径深度、每像素平均耗时；
- 区分路径追踪计算耗时与宿主显示纹理上传耗时，防止把显示瓶颈误判为积分器瓶颈；
- 建立固定 seed、固定场景和固定配置的基准入口；
- 基准至少覆盖材质球、Cornell Box 回归场景和 Poolcore Courtyard 展示场景；
- 输出紧凑摘要，不恢复逐 Tile 日志洪流。

验收：

- 同一配置连续运行的核心统计完全一致，耗时指标允许平台波动；
- 阻塞渲染与 `Step` 渲染的 Film 和计数统计一致；
- 计算耗时与显示上传耗时可以分别读取；
- 能用数据回答当前主要瓶颈位于积分、BVH、对象分配还是显示上传；
- 完成本阶段前，不修改默认分辨率、不实现 MIS、不做大范围热点重构。

阶段 F 实测结果（2026-07-18）：

- 核心回归测试：`[RayTracerTests] all tests passed`；计时注入、PathIntegrator 统计、重置清零和命中/未命中守恒均通过；
- 官方项目构建：通过；入口为 `scripts/main.lua`；
- Poolcore 固定配置：`160×90`、`16 spp`、`maxDepth=8`、`seed=42`、BVH 开启、动态纹理逐扫描块上传；
- Poolcore 场景构建统计：80 个对象、95 个 BVH 节点、48 个叶节点、最大深度 7；
- 真实 GLES 截图验证：可正常启动并生成 `screenshots/phase-f-poolcore.png`；截图帧 120 处于真实扫描过程，证明显示链路仍为逐扫描段更新；
- 完整视觉渲染超过当前沙箱运行窗口，未取得最终完成摘要；该限制来自当前逐块动态 `Texture2D:SetData()` 和 CPU 路径追踪成本，不判定为脚本错误；
- headless 运行未发现 Lua runtime error，但 30 秒短基准也未完成全画面，因此不把未完成运行的吞吐量作为稳定基线；
- 当前可确认的瓶颈方向是 CPU 路径积分与频繁纹理上传的组合成本，后续优化必须以阶段 G 的逐轮采样和阶段 H 的档位控制为边界，不在阶段 F 越界重构。

### 阶段 G：全画面逐轮累积采样

目标：先快速得到完整低噪预览，再逐轮提升整张画面的样本质量。

- 将当前“单个像素一次完成全部 spp”改为按 sample pass 累积；
- 第一轮让所有像素各获得 1 spp，之后继续第 2、3 轮，直到目标 spp；
- Film 增加样本和或等价的稳定累积数据，并记录每像素样本数；
- 每轮仍按小 Tile/扫描段分步执行，保持主循环可响应；
- 进度同时展示当前 pass、目标 spp、当前 pass 内像素进度和总样本进度；
- 固定 seed 的样本序列只由像素索引和 sample pass 决定，不受 Tile 顺序或每帧预算影响；
- 取消和重置必须清理累积状态，暂停/继续不得重复计算已经完成的样本；
- 动态纹理只上传新完成区域或受控批次，不恢复逐像素 NanoVG 绘制。

阶段 G 当前实现：

- `Film:addSample()` 使用运行平均值累积，不丢弃线性 HDR 的原始平均结果；
- `Film` 为每个像素记录 sample count，`clear()` 和 `set()` 保持计数语义一致；
- `Renderer` 改为按 `currentPass` 逐轮遍历全部 Tile，每个像素每轮只生成一个 sample；
- sample seed 仍由固定的 `seed + pixelIndex + sampleIndex` hash 推导，与 Tile budget 和执行顺序无关；
- `progress()` 改为总 sample progress，Presenter 仍收到统一的进度回调；
- 宿主显示按刚完成的 Tile 上传，状态栏显示当前 pass、当前 pass 进度和总进度；
- 当前保留 `samplesPerPixel=16`、`160×90` 和 Poolcore 场景，不提前进入阶段 H 的分辨率调整。

验收：

- 第一轮结束时整幅场景已经可辨认，而不是只出现顶部扫描区域；
- 每完成一轮，Film 的有效 spp 精确增加 1；
- 逐轮累积到 N spp 的结果与阻塞式 N spp 在固定 seed 下逐像素一致；
- 改变每帧 Tile 预算不改变最终 Film；
- UI 保持可更新，单次工作预算由阶段 F 的基准约束。

### 阶段 H：分辨率与质量档位

目标：在已有基准和逐轮采样基础上提高空间分辨率，而不牺牲渐进预览可用性。

- 提供明确的渲染档位，而不是散落修改常量；
- `preview`：默认交互预览，建议 `256×144`、低初始 spp；
- `quality-square`：方形展示，建议 `256×256`，适合 Poolcore 或 Cornell 基准；
- `offline`：高质量离线输出，允许 `512×512` 或更高分辨率；
- Film 分辨率、显示纹理分辨率和屏幕布局保持解耦；
- 根据阶段 F 的实测数据给出每个档位的预计像素量、样本量和完成成本；
- 分辨率变化不改变相机纵向 FOV，使用 aspect ratio 调整横向视野；
- 高质量档位继续保留逐轮预览，不等待全部样本完成后才显示。

阶段 H 当前实现：

- 新增 `RayTracer.Config.QualityPresets`，集中定义质量档位，Renderer 和 Film 不感知档位名称；
- `preview`：`256×144`、`32 spp`，作为当前默认档位，兼顾交互式渐进预览与最终观感；
- `quality-square`：`256×256`、`64 spp`，用于方形展示和质量验证；
- `offline`：`512×512`、`64 spp`，明确作为高成本离线档位，不默认启用；
- 当前通过 `main.lua` 的单一 `ACTIVE_QUALITY` 常量选择档位，避免阶段 H 引入额外菜单、命令行协议或状态系统；
- 显示画布根据实际 Film 宽高计算比例，采样调度仍沿用阶段 G 的逐轮累积和 Tile 分步执行。

验收：

- `256×144` 和 `256×256` 均能完整渐进显示且不触发 NanoVG 顶点缓冲问题；
- `512×512` 被明确归类为离线模式，不阻塞默认预览体验；
- 不同档位使用同一核心渲染路径；
- 改变窗口大小或 DPR 时，显示画布保持正确比例和清晰布局。

### 阶段 I：独立输出转换层

目标：在不修改线性 HDR Film 的前提下，统一所有显示和文件输出的颜色转换。

- 新增独立的 OutputTransform 或等价模块；
- 输入始终为 Film 中的线性 HDR RGB，输出为显示或编码目标需要的颜色；
- 保留 `direct-clamp` 作为基准和回归开关；
- 增加固定曝光控制；
- 选择连续、可测试的 tone mapping 曲线；
- 增加 Linear RGB 到 sRGB 编码；
- 可选高光趋白只能作用于输出值，禁止写回 Film；
- NanoVG/Texture2D、PPM、ANSI 和 Callback Presenter 共享同一转换逻辑；
- 明确纹理的 sRGB 标记，避免软件编码后再次由 GPU 重复转换；
- 用蓝天、白墙、浅青水面和彩球验证饱和度、白点、暗部和高光。

验收：

- 切换输出转换模式不会改变 Film 数据或采样统计；
- `direct-clamp` 与当前显示结果保持回归一致；
- tone mapping 不再产生整体灰雾、抬高黑位或明显降低彩球饱和度；
- HDR 高光具有连续层次，不再只依赖逐通道截断；
- 所有 Presenter 对同一像素产生一致的 8-bit 结果。

### 阶段 J：MIS、统一 BSDF 与全视图低噪路线

目标：在 AOV 语义纠偏、渐进采样和预览显示链路稳定后，降低漫反射、光泽、金属及玻璃后续路径的采样方差，并为 transmission 专用引导降噪建立正确的数据基础。

#### J.0：现有 AOV 对玻璃的适用边界

当前 Primary AOV 能改善 diffuse 和 glossy 表面，但不能直接安全地改善理想玻璃内部的透射噪声：

- 当前玻璃主命中记录的是玻璃表面的 Albedo、Normal、Depth 和 `delta_transmission` class；
- 玻璃像素的 Beauty 实际来自 Fresnel 反射或折射后的后续路径，画面内容通常属于玻璃后方的地面、墙体、天空或灯光；
- 因此主表面 Normal/Depth 与玻璃后方可见内容的几何边界并不对应；若直接使用现有 AOV 跨像素过滤玻璃，容易把不同折射内容混合，产生串色、重影、边界模糊或亮度漂移；
- 当前 AOV 仍有价值：可作为 transmission mask、玻璃轮廓硬边界、材质分类和 coverage 门禁，但默认必须继续让 `delta_transmission` 直通；
- 已完成的弱 transmission 显示候选仅使同类相邻亮度差下降约 `2.831%`，完整画面无可感知收益，证明仅复用主表面 AOV 不足以解决玻璃噪声；
- 若要真正过滤玻璃内容，需要新增“折射后首次非 delta 命中”引导，至少记录 refracted first-hit Normal、Depth、Albedo、material class 和有效 coverage；这属于 transmission/path AOV 扩展，不等同于直接启用当前 Primary AOV。

结论：现有 AOV 可保护玻璃边界并识别玻璃区域，但不能单独完成玻璃降噪。玻璃质量提升必须由采样方差降低和 transmission 专用引导共同完成。

#### J.1：固定基准与统一 BSDF 契约（已完成，2026-07-18）

- 保留当前无 MIS 路径作为差分基线和回归开关；
- 固定 Poolcore Courtyard、Cornell Box 和材质组合场景，分别记录 diffuse、glossy、metal、glass 与高光区域的均值、方差、颗粒指标和完成成本；
- 将非 delta 材质从单一 `scatter()` 扩展为最小统一契约：`sample()`、`evaluate()`、`pdf()`、`isDelta()`；
- delta reflection/transmission 保留离散事件及 Fresnel 概率，不对不可比较的离散/连续 PDF 强行加权；
- 不在第一版引入通用材质图、复杂闭包系统或无当前用途的抽象层。

实现结果：

- Lambertian、Metal、Dielectric、DiffuseLight 和基础 Material 已具备一致的 `sample/evaluate/pdf/isDelta` 方法名；
- Lambertian 已提供 `albedo/π` 的 BSDF evaluation 和 cosine hemisphere PDF；`sample()` 仍委托现有 `scatter()`，因此当前采样方向、RNG 消耗和 Beauty 完全不变；
- 完美 Metal 与 Dielectric 明确标记为 delta；连续方向上的 `evaluate()` 返回零、`pdf()` 返回零，而 `sample()` 的连续 `samplePdf` 返回 `nil`，避免伪造 Dirac delta 的普通概率密度；
- 当前 rough Metal 的经验 fuzz 分布尚无严格可配对的 BSDF/PDF，因此契约明确返回 `nil` 表示“不支持 MIS”，等待 J.3 GGX 替换；不使用猜测 PDF；
- DiffuseLight 明确不提供可散射 BSDF 方向，sample 返回空方向和零 PDF；
- PathIntegrator 继续只调用原有 `scatter()`，本阶段没有接入 MIS、没有改变 radiance、RNG、shadow ray 或 BVH 查询；
- 自动回归验证了 Lambertian evaluation/PDF、上下半球边界、delta 连续 PDF 语义、rough Metal 未支持状态，以及相同 RNG 下 `sample()` 与 legacy `scatter()` 的方向、衰减和 Dielectric 事件完全一致；
- Lua LSP 全工作区 0 Error；RayTracer 回归输出 `[RayTracerTests] all tests passed`；官方项目构建成功。

已通过门禁：

- 新旧接口在关闭 MIS 时产生相同的固定 seed Beauty 基线；
- PDF 非负、有限且与采样分布匹配；
- 不产生 NaN、Inf、负概率或重复发光贡献。

#### J.2：Lambertian NEE + MIS（已完成，2026-07-18）

- 将当前简化显式光源采样升级为可计算 light PDF 的标准 NEE；
- Lambertian 使用 cosine-weighted hemisphere sampling，并提供对应的 BSDF evaluation 与 PDF；
- 同时计算 light-sampling 与 BSDF-sampling 两种估计；
- 使用 power heuristic 合并权重；
- BSDF 路径直接命中发光体时按 MIS 权重计入 emission，避免与 NEE 重复计算；
- 玻璃 delta bounce 之后首次命中 diffuse 时，同样允许该 diffuse 顶点执行 NEE/MIS，从而降低透过玻璃后照明的方差。

实现结果：

- Lambertian 已改为 cosine-weighted hemisphere sampling，采样 PDF 与 `cosine / π` 匹配；
- Quad、Sphere 和 Triangle 均可把均匀面积采样 PDF 转换为指定命中点的立体角 PDF；
- NEE 与 BSDF-hit emission 使用 power heuristic 合并，并计入均匀选择光源的离散概率；
- `useMIS=false` 保留旧积分路径，默认 Preview 已启用 `useMIS=true`；
- rough Metal 仍不参与连续 MIS，继续留给 J.3 的 GGX 实现；理想玻璃仍保持 delta 事件，但其后续 diffuse 顶点可执行 NEE/MIS。

显示空间验收（2026-07-18）：

- 用户对完成态 Preview 人工检查后确认：玻璃区域噪点明显下降，未观察到重复发光、黑斑或异常亮点；
- 对 J.2 完成图与原基线图去除黑边、统一缩放后，在玻璃核心区域比较显示亮度高频代理：相邻亮度差 P90 下降约 `39.9%`，Laplacian 中位数下降约 `53.9%`；
- 玻璃上部区域的相邻亮度差 P90 下降约 `46.2%`，Laplacian 中位数下降约 `60.2%`；
- 两个玻璃 ROI 的平均显示亮度分别变化约 `-1.6%` 与 `-4.0%`，均在 `5%` 门限内；
- 两张截图的原始尺寸和黑边不同，因此以上数据只作为对齐后的显示空间噪声代理，不等同于线性 HDR Film 方差或严格逐像素 unbiasedness 证明。

结论：J.2 的代码闭环与 Preview 观感验收均已完成；当前证据支持“透过玻璃可见的 diffuse 内容噪声下降”，不宣称已解决理想玻璃 Fresnel、轮廓或焦散噪声。

预期收益：

- 白墙、棋盘格地面和其他漫反射区域的直接光噪声明显下降；
- 透过玻璃后落到 diffuse 表面的路径更容易找到面光源；
- 不承诺直接消除理想玻璃轮廓、Fresnel 分支或焦散噪声。

#### J.3：GGX 金属与光泽 MIS（已完成，2026-07-18）

- 用 GGX 微表面 BRDF 替换当前 `reflected + randomUnitVector * fuzz` 的经验扰动；
- 实现 GGX NDF、Smith masking-shadowing、Schlick Fresnel，以及与实现匹配的重要性采样和 PDF；
- 粗糙金属/光泽参与 light sampling 与 BSDF sampling 的 MIS；
- 完美镜面金属继续作为 delta reflection，不强行参与连续 PDF MIS；
- 使用金属球、高粗糙度球和小面积高光区域建立独立回归。

实现结果：

- rough Metal 已使用 GGX/Trowbridge-Reitz NDF、Smith masking-shadowing 和 Schlick Fresnel；
- GGX 半向量重要性采样与反射方向 PDF 匹配，路径吞吐使用 `BSDF × cos / PDF`；
- PathIntegrator 的直接光路径已改为通用 `evaluate × emission × cos / lightPdf`，Lambertian 与 rough Metal 共用 light/BSDF power-heuristic MIS；
- 完美镜面金属继续保持 delta reflection，连续 `evaluate/pdf` 返回零，不参与连续 MIS；
- `useMIS=false` 时保留原有兼容路径，没有引入通用材质图或额外闭包系统。

人工 Preview 验收（2026-07-18）：

- 用户在相同采样预算下观察到金属球反射倒影不再那么模糊，主观清晰度约提升 `10%`；该比例为肉眼估计，不作为脚本量化值；
- 未观察到明显异常亮点；
- 金属球没有整体变黑或过亮；
- 相同采样预算下颗粒没有显著恶化；
- 用户确认清晰度变化不是由画面亮度或截图缩放差异造成。

结论：J.3 的代码闭环、静态检查、正式构建和人工 Preview 验收均已完成；当前证据支持 GGX 改善了金属反射结构，同时未引入可感知的亮度或颗粒回归。

预期收益：

- 金属和光泽高光更稳定、更符合能量分布；
- 相同 spp 下高光颗粒和随机亮斑下降；
- 为后续粗糙玻璃提供一致的微表面接口基础。

#### J.4：transmission/path AOV 与玻璃显示降噪

- 主表面 Primary AOV 保持不变，继续用于玻璃 mask、轮廓和材质边界；
- 沿当前 sample 已选择的反射/折射路径复用既有 hit，不为采集 AOV 增加额外求交；
- 对折射分支记录首次非 delta 命中的 Normal、Depth、Albedo、material class、coverage 和有效标记；
- 条件允许时拆分 reflection/transmission 显示贡献或最小 lobe radiance，避免用同一组引导混合不相关路径；
- transmission 过滤只在 refracted guides 兼容时传播，并以主玻璃轮廓作为硬边界；
- 原始线性 HDR Film 永远不被降噪器修改；所有过滤仍只作用于独立显示副本；
- 不恢复已经证明收益不足的固定 `20%` 邻域混合候选。

门禁：

- 玻璃轮廓、折射后的棋盘格边界和遮挡边界不产生明显重影或串色；
- 玻璃区域平均亮度变化目标不超过 `5%`，并记录局部最大偏差；
- 开关 transmission 降噪时 Film、路径数、BVH 统计和 RNG 顺序完全一致；
- 固定样本预算下玻璃区域颗粒指标必须有可感知且可量化的下降，否则回退为直通。

#### J.5：自适应采样、firefly 与焦散专项

在 MIS 和 transmission/path AOV 验收后，再按数据决定是否实施：

- 根据 Film 均值方差和材质 class，将额外 sample 优先分配给玻璃、高光和高方差区域；
- 自适应停止必须设置最小 spp、最大 spp 和邻域稳定条件，避免边缘欠采样；
- 极端离群亮点只允许在显示副本使用基于局部统计的鲁棒权重或保守 firefly 控制，不修改无偏 Film；
- 若剩余噪声主要属于 `Light → Glass → Diffuse → Camera` 焦散路径，则普通相机路径 MIS 收益有限；只有基准证明焦散是主要质量瓶颈时，再评估 path guiding、photon mapping 或 bidirectional 方法；
- 不为当前 Poolcore 预览提前引入高复杂度焦散算法。

#### 阶段 J 执行顺序

严格按以下顺序推进，禁止把多个质量变量混入同一次基准：

1. `J.1` 统一 BSDF 契约与固定基线；
2. `J.2` Lambertian NEE + MIS；
3. `J.3` GGX 金属/光泽 + MIS；
4. `J.4` transmission/path AOV 与玻璃显示降噪；
5. `J.5` 自适应采样与必要的 firefly/焦散专项。

总体验收：

- 固定样本预算下，指定 diffuse、glossy、metal 和 glass 区域的方差可测量下降；
- MIS 不改变期望亮度，不重复计算发光贡献；
- 镜面、折射、漫反射和直接可见光源行为正确；
- 全视图在保持材质边界、折射结构和高光层次的前提下，噪点显著少于当前 `32 spp` 基线；
- 每个子阶段收益不足时记录数据并停止该候选，不为路线完整强行增加复杂度。

### 后续阶段执行顺序与门禁

严格按 `F → G → H → I → J` 执行，一次只推进一个阶段：

1. 当前阶段的代码、测试、官方构建和截图/基准验收全部通过；
2. 记录本阶段结果和已知限制；
3. 提交并推送稳定节点；
4. 才开始下一阶段。

禁止并行混入后续阶段功能。例如阶段 F 只建立基准，不顺手修改分辨率；阶段 G 只修改采样调度，不同时引入 tone mapping；阶段 H 不提前实现 MIS。

当前下一步固定为 **阶段 H-Preview-1：调度与显示上传**，原阶段 I/J 暂缓。

### 阶段 H-Preview：预览观感与交互速度优先

背景：阶段 G 已经解决“全画面逐轮累积采样”，但当前 preview 仍存在大面积地面/墙面噪点、单轮等待过长和低 spp 观感不佳的问题。因此原阶段 I（输出转换）与阶段 J（MIS）暂缓，先建立可在可观时间内获得漂亮 `256×144` 图像的 Preview Quality Track。

目标：

- `256×144` preview 在可观时间内完成首轮和可用质量预览；
- 噪声必须是正常 Monte Carlo 噪声，不得出现斜向黑带、固定网格黑纹或 Tile 边界伪影；
- 在不修改线性 HDR `Film` 的前提下，显示端可以平滑低 spp 结果；
- 每次优化都用固定 seed、固定 Poolcore 场景和阶段 F 统计判断收益。

当前质量档位调整：

- `preview` 固定为 `256×144`、`32 spp`，作为默认交互与质量预览；
- `quality-square` 固定为 `256×256`、`64 spp`，用于高样本方形质量验证；
- `offline` 固定为 `512×512`、`64 spp`，不作为默认预览；
- 档位只负责配置分辨率、spp 和调度预算，核心 `Renderer`、`Film`、`Integrator` 不感知档位名称。

执行顺序：

#### H-Preview-1：调度与显示上传

- 将当前 `64×1` Tile 和 `maxTilesPerStep=1` 的过度碎片化调度改为可控批次；
- 优先尝试 `64×4` 等较大 Tile，减少一轮需要的 Update 次数；
- 每次 Update 至少允许计算多个 Tile，但设置单帧预算，避免 UI 长时间卡死；
- 将 `Image` 像素写入与 `Texture2D:SetData()` 解耦，尽量做到每次 Update 至多上传一次整纹理；
- 保留计算耗时、上传耗时、最大单步耗时和上传次数统计；
- 不改变采样 seed、Film 数值和最终图像。

验收：

- `256×144` 单轮等待显著下降；
- UI 仍能持续响应；
- 显示上传次数显著下降；
- 固定 seed 下，调度批次变化不改变最终 Film。

#### H-Preview-1 实测对比结果（2026-07-18）

对比口径：固定 `256×144`、Poolcore 场景、seed=42、真实 GLES、截图帧=120；旧版使用 `64×1` Tile 且每个 Tile 上传一次纹理，新版使用 `64×4` Tile 且每次 Update 至多上传一次纹理。为隔离调度和上传变化，另以相同 `1 spp` 配置观察同一截图帧。

- 旧版 `1 spp` 在第 120 帧约完成 `10.2%`；
- 新版 `1 spp` 在第 120 帧约完成 `41.0%`；
- 固定截图帧下，新版覆盖的扫描区域约为旧版的 4 倍，与 Tile 高度从 1 增加到 4 的调度预期一致；
- 新版截图中 `256×144` 的真实 Film 仍按逐轮方式更新，没有改变采样顺序或 Film 语义；
- 新版上传逻辑已把局部像素写入和纹理提交分开，每次 Update 至多提交一次整纹理；
- 当前运行窗口未覆盖完整 32 spp，因此不能仅凭截图帧推导完整渲染总耗时；阶段 F 的统计字段仍用于最终完成态测量；
- 结论：H-Preview-1 已确认解决“单轮被 64×1 Tile 过度切碎”的结构性问题，调度推进速度约提升 4 倍；纹理上传次数也从每 Tile 一次降为每次 Update 一次。下一步应继续采集完整完成态的 `compute/upload/displayUploads`，再进入 H-Preview-2。

#### H-Preview-2：单路径成本控制

- 在固定场景上测量 `maxDepth=5/6/8` 的速度、平均路径深度、亮度和噪声差异；
- 仅为 Preview 设置更低的路径预算，不修改质量档位和离线基线的核心语义；
- 评估更早 Russian Roulette 的收益，但必须验证期望亮度没有明显偏移；
- 在 `Quad.new()` 中预计算求交所需的 `uu/uv/vv/determinant`，减少每次命中的重复计算；
- 暂不进行全局 Vec3、Ray、Interval 或 BVH 的大范围重写。

##### H-Preview-2 当前实现（2026-07-18）

- `preview` 保持 `32 spp`，路径最大深度从宿主默认 `8` 调整为独立配置 `maxDepth=6`；
- `quality-square` 和 `offline` 未设置独立深度，继续使用默认 `maxDepth=8`，保持离线基线不变；
- `Quad` 在构造阶段缓存 `uu/uv/vv/determinant`，命中阶段不再重复计算边向量点积和行列式；
- 未修改 Russian Roulette 的生存概率、Film 语义、采样 seed、BVH 或显示链路；
- 本轮先完成最小可验证成本控制，`maxDepth=5/6/8` 的完整观感与吞吐对比留待后续实测，不把未经测量的速度收益写成结论。

##### H-Preview-2 maxDepth 对比实验（2026-07-18）

对比固定 `256×144`、单轮 `1 spp`、seed=42、`64×4` Tile、同一 Poolcore 场景和真实 GLES；单轮用于隔离路径深度成本，不代表最终 Preview 画质。统计只读取 Renderer 完成态的 `compute`、`paths/s`、平均路径深度、BVH 求交和上传数据。

| maxDepth | compute | paths/s | 平均路径深度 | BVH box tests | primitive tests | upload |
|---:|---:|---:|---:|---:|---:|---:|
| 5 | 6.786s | 5432.4 | 2.339 | 2,860,488 | 875,006 | 0.062s |
| 6 | 7.224s | 5103.0 | 2.419 | 2,967,457 | 908,604 | 0.065s |
| 8 | 7.559s | 4876.8 | 2.493 | 3,068,240 | 939,458 | 0.072s |

- `maxDepth=5` 相对 `6` 的计算时间约减少 `6.1%`，`paths/s` 约提高 `6.5%`；
- `maxDepth=8` 相对 `6` 的计算时间约增加 `4.6%`，`paths/s` 约下降 `4.4%`；
- 三档单轮平均路径深度分别为 `2.339/2.419/2.493`，差异存在但没有改变 Poolcore 的基本构图；
- 当前 `1 spp` 截图均处于强噪声阶段，不能据此判断 `32 spp` 最终观感；`maxDepth=6` 保留了适度路径预算，同时避免把 Preview 进一步压到过低深度；
- 结论：正式 Preview 继续采用 `maxDepth=6`，目标保持 `32 spp`；本实验只确认单路径成本趋势，不宣称已解决低 spp 噪声。

验收：

- 单 sample 计算成本下降；
- Poolcore 的蓝天、白墙、水池和彩球构图保持稳定；
- 不新增黑带、错误阴影或明显亮度漂移；
- 统计可以区分路径积分成本、BVH 求交成本和显示上传成本。

#### H-Preview-3：显示端轻量降噪

- 新增独立的显示副本滤波，不修改 Film 原始线性 HDR 数据；
- 第一版只实现可关闭的 3×3 低风险、边缘感知滤波；
- 亮度/颜色差异过大的邻域不直接平均，避免抹平彩球、墙体和水面边缘；
- `denoise=false` 时必须恢复原始 Clamp 显示；
- 暂不引入深度/法线 AOV、复杂时域滤波或外部降噪器。

##### H-Preview-3 当前实现（2026-07-18）

- 新增 `RayTracer.Display.DisplayDenoise`，只在 `Film → Image` 显示副本路径计算；
- 使用 3×3 空间权重，并按中心像素的亮度差和 RGB 差异衰减邻域权重；
- `main.lua` 保留 `CONFIG.denoise` 开关，当前 Preview 默认开启；关闭时直接读取 Film 原始像素并执行 Clamp；
- PPM、ANSI、Callback Presenter 仍直接读取未经滤波的 Film；
- 通过中心高光保持、颜色保持和亮度边界测试验证滤波不会把高光直接抹平。

##### H-Preview-3 同采样对比实验（2026-07-18）

对比固定 `256×144`、`8 spp`、`maxDepth=6`、seed=42、`64×4` Tile 和同一 Poolcore 场景，只改变 `denoise=false/true`。两次积分统计完全一致：`294,912` paths、`714,097` bounces、`23,814,426` BVH box tests，证明显示滤波没有改变 Film 或采样路径。

| denoise | compute | paths/s | upload | filter | filteredPixels |
|---|---:|---:|---:|---:|---:|
| false | 59.300s | 4973.2 | 0.641s | 0.000s | 0 |
| true | 59.524s | 4954.5 | 0.785s | 3.502s | 448,869 |

- 路径积分耗时差异仅 `0.224s`（约 `0.38%`），属于同机运行波动，符合“降噪不进入 Integrator”的设计；
- 开启降噪新增 `3.502s` 显示滤波成本，约为无降噪 compute 的 `5.9%`；纹理上传时间增加 `0.144s`；
- Pool 中心区域相邻亮度差从 `30.40` 降至 `22.83`，下降约 `24.9%`；左侧地面从 `31.26` 降至 `23.38`，下降约 `25.2%`；
- 强边缘平均梯度保留约 `82.5%`，边缘有轻微软化，但彩球、墙体和水池轮廓仍可辨识；
- 全画面平均 RGB 绝对差为 `2.46/255`，说明滤波主要作用于局部高频颗粒，没有造成整体色调漂移；
- 结论：8 spp 下颗粒改善明确，边缘软化可控，当前 Preview 保持 `denoise=true`；正式采样目标恢复为 `32 spp`。

验收：

- `8～32 spp` 时地面和墙面颗粒明显下降；
- 彩球轮廓、墙体边界和水面边缘不严重模糊；
- 开关降噪不改变 Film 和采样统计；
- PPM、ANSI、Callback 仍读取未经显示滤波的 Film。

#### H-Preview-3A：AOV 降噪语义纠偏（当前下一步）

最新自查确认，后续加入的 Albedo/Normal/Depth 多尺度滤波原型与业界常见 AOV/À-Trous/SVGF 语义存在偏差，已在 Dielectric 水面上观察到明显亮度漂移。该问题不是普通参数调节问题；在纠偏完成前，多尺度 AOV 输出只作为问题复现基线，不作为可信 Preview 完成态。

完整偏差清单、纯 Lua 可行性、替代方案、分阶段路线和量化验收门禁见：

- [`aov-denoising-correction.md`](aov-denoising-correction.md)

执行顺序固定为：

1. `AOV-Correct-1`：AOV 按与 Beauty 相同的 sample 序列累积，并记录 hit coverage；
2. `AOV-Correct-2`：加入材质分类和 delta/specular 保守策略，优先消除水面提亮；
3. `AOV-Correct-3`：加入方差、可归零 Normal 权重、Depth gradient/step 和 HDR 高能样本鲁棒传播；
4. `AOV-Correct-4`：语义稳定后才比较 3×3 与标准 5×5 B3-spline kernel；
5. `AOV-Correct-5`：仅在保守方案不足时评估完整 diffuse/specular/transmission lobe 拆分与 Albedo demodulation。

门禁原则：

- 修复只能作用于 AOV 和显示副本，禁止修改线性 HDR Film；
- 开关降噪时路径、Film 和 BVH 统计必须一致；
- 默认 Preview 优先保持亮度和材质可信，不以最平滑为目标；
- 不能通过门禁的 Dielectric 方案回退为弱 step=1 或完全直通，不允许保留大面积亮度漂移。

#### H-Preview-4：质量档位重测

完成 H-Preview-1～3 及 H-Preview-3A 的 AOV 语义纠偏后，再根据实际数据决定：

- `preview` 目标固定为 `32 spp`，不再在 H-Preview-4 中重新降回 8 spp；
- `preview` 是否使用 `maxDepth=5/6`；
- `preview` 的单帧 Tile 预算和上传节流值；
- 降噪是否默认开启；
- `quality-square=256×256, 64 spp` 是否需要独立的更高计算预算。

禁止在数据出来前直接把 preview 提高到 `64 spp`，也不把“增加 spp”当作唯一降噪手段。

#### 暂缓的阶段 I/J

- 阶段 I 输出转换暂缓：当前主要问题是采样噪声、调度和单路径成本，不是曝光或 Tone Mapping；
- 阶段 J MIS 暂缓：只有 H-Preview 稳定后，才能用方差/收敛基准判断 MIS 是否值得引入；
- 在 H-Preview 完成前，不实现 MIS、不做大范围输出架构重构。

预览目标已经明确为 `32 spp`，其余档位为 `64 spp`；后续优化应围绕如何在可观时间内完成这些目标，而不是降低目标轮数。

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

## 14. 后续阶段索引

- `stage-f`: 性能基准与可观测性，固定场景与统计口径；
- `stage-g`: 全画面逐轮累积采样；
- `stage-h`: 预览、方形质量和离线高分辨率档位；
- `stage-i`: 独立曝光、色调映射与 sRGB 输出转换；
- `stage-j`: 基于方差和收敛数据评估 MIS。

## 15. 当前路线状态

- 阶段 A～E：已完成并通过既有验收；
- 当前展示场景：开放式 Poolcore Courtyard，保留 Cornell Box 作为回归基准的后续入口；
- 显示链路：Film → Image → Texture2D → BorderImage，支持逐扫描段实时更新；
- 当前预览仍使用直接 Clamp，Film 保持线性 HDR；
- 下一步：只实施阶段 F，不跨阶段修改默认分辨率或采样算法。

## 16. 第一轮实施决策

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
