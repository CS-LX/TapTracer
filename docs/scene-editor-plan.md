# 简化 3D 场景编辑器实施文案

## 1. 目标

把当前应用从“启动即显示光追工作区”调整为“默认进入实时 3D 场景编辑器，需要时再进入光追结果界面”。

编辑器不是 Blender 的缩小复刻，而是面向当前 JSON 光追场景格式的专用工具：

- 只创建和编辑 `quad`、`box`、`sphere`；
- 实时视口使用 UrhoX 光栅化渲染，提供快速近似预览；
- 当前场景数据始终以一个可编辑的 JSON 文档模型为唯一数据源；
- 点击“渲染”后，才把当前内存中的 JSON 文档编译为光追场景并开始 CPU 路径追踪；
- 不修改光追核心、积分器、几何求交、材质散射或 Renderer。

## 2. 本轮明确不做

为保证在一到两个开发节点内完成，以下内容不进入本轮：

- 任意 Mesh、模型导入、骨骼或动画；
- 旋转 Gizmo；
- 撤销/重做历史；
- 多选、父子层级和集合；
- 纹理文件导入与 UV 编辑；
- 节点图材质编辑器；
- 多场景标签页；
- 完整复制 Blender 的快捷键和窗口系统。

不做旋转的原因不是引擎限制，而是当前光追 JSON 的 `box` 是轴对齐 `minimum/maximum`，`sphere` 是 `center/radius`，并没有通用对象变换。为了避免为了编辑器反向侵入光追几何层，本轮只做位置与大小。

## 3. 最终工作区

### 3.1 默认编辑模式

应用启动后只显示编辑器，不创建光追 Renderer，不分配光追显示纹理，也不显示渲染进度 UI。

桌面布局：

```text
┌──────────────────────────────────────────────────────────────┐
│ 添加 Quad  Box  Sphere | 移动  缩放 | 保存 | 渲染           │
├──────────────┬────────────────────────────┬──────────────────┤
│ 场景层级     │                            │ Inspector        │
│              │       实时 3D 视口         │ 对象 / 摄像机    │
│ 材质库       │                            │ 材质 / 场景      │
│              │                            │                  │
├──────────────┴────────────────────────────┴──────────────────┤
│ 当前工具、选中对象、保存状态、操作提示                       │
└──────────────────────────────────────────────────────────────┘
```

采用现有 Yoga UI 作为全部面板、按钮、列表、输入框、下拉框和颜色选择器。实时 3D 场景由 UrhoX Viewport 渲染在中间矩形内，Viewport 的物理像素 Rect 每次根据 Yoga 布局结果更新。

### 3.2 渲染模式

点击顶部“渲染”后立即执行：

1. 提交 Inspector 中尚未失焦的值；
2. 校验当前内存 JSON 文档；
3. 将文档编译为当前光追公开对象；
4. 隐藏编辑视口、场景层级、材质库和预览 Inspector；
5. 显示现有光追结果画布、进度条和独立的 Render Inspector；
6. 创建 Renderer 并开始渲染。

渲染模式提供“返回编辑”按钮。返回时取消未完成渲染，释放或隐藏光追显示资源，恢复实时编辑视口。编辑数据不能因进入或退出渲染模式而丢失。

## 4. 数据架构

### 4.1 唯一场景文档

新增 `SceneDocument`，内部保持与 `MaterialShowcase.json` 等价的普通 Lua table：

```text
metadata
background
camera
textures
materials
objects
```

编辑器、实时预览和光追渲染都读取同一个 `SceneDocument`：

```text
打包 JSON / 用户保存覆盖
           ↓
     SceneDocument
       ↙       ↘
实时预览适配器   JSON 光追编译器
       ↓              ↓
UrhoX Scene       RayTracer Scene
```

不允许实时预览维护一套独立的隐藏场景配置。对象 Inspector 修改的是 `SceneDocument.objects`，材质 Inspector 修改的是 `SceneDocument.materials`，光追按钮使用的也是同一个文档快照。

### 4.2 JSON 编译器调整

现有 `JsonSceneLoader` 保留资源加载入口，并在 SceneFormat 层增加“直接编译内存文档”的公开入口，例如：

```lua
JsonSceneLoader.load(resourcePath)
JsonSceneLoader.compileDocument(document, sourceName)
```

这是光追模块外的上层调整。它只继续调用当前公开的 `Scene`、`Camera`、`Quad`、`Sphere` 和材质构造器，不修改任何光追核心文件。

### 4.3 对象稳定标识

给 JSON 对象补充可选的 `id` 和 `name`：

```json
{
  "id": "object-001",
  "name": "Glass Sphere",
  "type": "sphere",
  "center": [-4.8, 2.05, 4.2],
  "radius": 1.8,
  "material": "glass"
}
```

`id/name` 只服务于编辑器层级、选中状态和增删操作；现有光追解析可忽略它们，不改变渲染语义。

### 4.4 保存策略

打包在 `assets/Scenes/` 的 JSON 是只读基线，运行时不直接覆盖项目资源。编辑器使用：

- “保存”：将当前文档编码到用户可写目录中的场景覆盖文件；
- 下次启动：优先读取用户覆盖，没有覆盖时读取打包 JSON；
- “恢复内置场景”：删除或忽略用户覆盖，重新载入打包 JSON；
- 点击“渲染”：始终渲染当前内存文档，不要求用户先保存。

这样既符合运行时文件沙箱，也确保编辑结果跨会话保留。

## 5. 实时 3D 预览

### 5.1 预览场景

新增独立的 `Editor/RealtimeSceneAdapter.lua`，根据 `SceneDocument` 创建 UrhoX Scene：

- `box` → `Models/Box.mdl`；
- `sphere` → `Models/Sphere.mdl`，按内置直径 1 米换算为 `radius * 2` 的统一缩放；
- `quad` → CustomGeometry 四顶点平面，直接使用 `origin + edgeU + edgeV`，保证能表示水平或垂直 Quad；
- 固定 Daytime 预览光照、Zone、地平参考网格；
- 每个预览 Node 保存对应 JSON 对象 `id`，便于射线选择和增量更新。

材质或变换改变时只更新受影响的 Node/Material，不重建整个场景。结构性增删后才更新层级列表。

### 5.2 编辑摄像机与渲染摄像机

两者明确分离：

- Editor Camera：只用于自由漫游，不写入光追 camera；
- Render Camera：来自 JSON `camera`，用 DebugRenderer 绘制视锥和方向标记。

Editor Camera 操作：

- 按住右键 + 鼠标：观察方向；
- 右键按住时 WASD：前后左右；
- Space / C：上升 / 下降；
- Shift：加速；
- F：聚焦选中对象。

摄像机 Inspector 提供：

- `lookFrom`、`lookAt`、`up`、`verticalFov`、`defocusAngle`；
- “从渲染摄像机观察”；
- “将当前编辑视角设为渲染摄像机”。

因此用户既可以自由漫游，也可以直观看到最终光追摄像机的构图。

### 5.3 选择

鼠标点击实时视口时：

1. 将鼠标位置换算为视口内 0–1 坐标；
2. 调用 `Camera:GetScreenRay()`；
3. 使用 `Octree:RaycastSingle(..., RAY_TRIANGLE, ...)`；
4. 从命中 Node 取得对象 ID；
5. 同步场景层级选中项与 Object Inspector。

选中对象通过 DebugRenderer 绘制 BoundingBox。点击空白区域取消选择。

### 5.4 轻量 Gizmo

引擎当前没有可直接复用的 Blender 式 Transform Gizmo，因此在编辑器外层自行实现一个受控版本：

- 红 X、绿 Y、蓝 Z 三轴；
- 工具仅有 Move 和 Scale；
- Gizmo 始终按相机距离保持近似固定屏幕尺寸；
- 轴线由 DebugRenderer 绘制；
- 轴命中使用 `WorldToScreenPoint()` 后的屏幕距离判断，不把 Gizmo 注册成场景对象；
- 拖动量投影到选中轴，实时写回 `SceneDocument` 并更新预览 Node；
- Escape 取消本次拖动。

几何体约束：

- Box：Move 改中心，Scale 分轴改变宽高深，并回写 `minimum/maximum`；
- Sphere：Move 改 `center`，Scale 只做统一半径，避免预览椭球与光追球体不一致；
- Quad：Move 改 `origin`，Scale 改 `edgeU/edgeV` 长度；不提供法线方向旋转。

Inspector 数值输入与 Gizmo 操作必须走同一个对象更新接口，防止两套状态不同步。

## 6. Inspector 设计

不复用当前“一个 Inspector 塞全部内容”的结构，而是复用其扁平视觉样式和数值控件模式，拆成两个工作区 Inspector。

### 6.1 Preview Inspector

编辑模式右侧使用 Tabs：

#### Object

- 名称、类型、材质下拉框；
- Position；
- Box Size / Sphere Radius / Quad Edge U、Edge V；
- 删除对象；
- 复制对象可不进入本轮。

#### Camera

- 渲染摄像机参数；
- 从渲染摄像机观察；
- 当前视角写入渲染摄像机。

#### Scene

- 场景标题、状态名、天空背景色；
- 保存、恢复内置场景；
- 对象数、材质数和未保存状态。

### 6.2 Render Inspector

只在渲染模式显示，沿用当前完整渲染参数：

- 分辨率、SPP、最大深度、Seed、Exposure；
- Tile/步进预算；
- MIS、Denoise、Transmission Denoise；
- 预设；
- 开始/停止/重新渲染。

进入渲染模式时顶部“渲染”已经自动开始第一次渲染；Inspector 中的按钮用于停止和参数调整后的重新渲染。

## 7. 材质库 UI

### 7.1 是否需要

需要。对象保存的是 `material` ID，而材质定义是共享资产。如果没有材质库，只在对象 Inspector 中放颜色参数，会产生重复材质、悬空引用和无法统一修改的问题。

### 7.2 材质库面板

左侧下半区显示材质列表：

- 色块预览、名称、模式、使用次数；
- 新建材质；
- 删除材质；
- 选中材质后右侧切换到 Material Inspector；
- Object Inspector 用下拉框为物体选择已有材质。

新建材质默认创建 Lambertian。删除未使用材质可直接执行；删除正在使用的材质时，先将引用替换为不可删除的 `Default` 材质，再删除，禁止留下悬空引用。

### 7.3 Material Inspector

共同字段：

- 材质 ID/名称；
- 模式：Lambertian / Metal / Dielectric / DiffuseLight。

模式字段：

- Lambertian：颜色或现有 Checker 纹理引用；
- Metal：颜色、Fuzz；
- Dielectric：IOR；
- DiffuseLight：颜色、Intensity。

本轮不做任意贴图导入。当前 Checker 在光追中保持精确，实时预览可先使用两色平均值拟合。

### 7.4 光追材质到实时材质的拟合

所有程序化实时材质都创建独立 Material 实例，不能修改 ResourceCache 中的共享资源。

| JSON 光追材质 | 实时预览 Technique | 近似参数 |
|---|---|---|
| Lambertian | `Techniques/PBR/PBRNoTexture.xml` | Metallic=0，Roughness=0.8，颜色=Albedo |
| Metal | `Techniques/PBR/PBRNoTexture.xml` | Metallic=1，Roughness≈max(0.05, Fuzz)，颜色=Albedo |
| Dielectric | `Techniques/PBR/PBRNoTextureAlpha.xml` | 半透明浅色，Roughness=0.05；IOR 只显示在 Inspector，预览不保证精确折射 |
| DiffuseLight | `Techniques/PBR/PBRNoTexture.xml` | MatEmissiveColor=Color×Intensity，基础色同步 |

预览固定光照负责让所有物体可见。DiffuseLight 的实时材质只拟合“发亮外观”，不会精确模拟光追面光源照明；最终效果以点击渲染后的光追结果为准。

## 8. 模块边界

由于 `main.lua` 已接近 1000 行，编辑器不能继续堆入入口文件。建议新增：

```text
scripts/
├── Editor/
│   ├── AppController.lua
│   ├── SceneDocument.lua
│   ├── SceneDocumentStore.lua
│   ├── RealtimeSceneAdapter.lua
│   ├── PreviewMaterialFactory.lua
│   ├── SelectionController.lua
│   ├── GizmoController.lua
│   ├── EditorCameraController.lua
│   └── UI/
│       ├── EditorWorkspace.lua
│       ├── SceneHierarchy.lua
│       ├── MaterialLibrary.lua
│       ├── PreviewInspector.lua
│       └── RenderWorkspace.lua
├── SceneFormat/
│   └── JsonSceneLoader.lua
└── main.lua
```

`main.lua` 只负责生命周期和将事件转发给 `AppController`。

## 9. 两步实施方案

只建立两个可验收节点，不继续细拆版本。

### 第一步：完成可用的实时编辑闭环

一次性完成：

- SceneDocument 与用户覆盖保存；
- JSON 当前场景加载；
- UrhoX 实时场景适配；
- Editor Camera 漫游和 Render Camera 可视化；
- 场景层级；
- 添加、选择、删除 Quad/Box/Sphere；
- Move/Scale Gizmo；
- Preview Inspector；
- 材质库、材质选择、材质 CRUD 与实时拟合；
- 当前 MaterialShowcase 在编辑器中保持内容等价。

第一步验收标准：启动后只出现编辑器；可以新建三种几何体、通过视口和层级选中、用 Gizmo 和 Inspector 改位置大小、切换并编辑材质、保存后重启仍可恢复。

### 第二步：接回惰性光追模式并完成整体验收

一次性完成：

- Render Workspace 与 Render Inspector；
- 点击“渲染”才创建光追场景、显示纹理并启动 Renderer；
- 当前内存文档直接编译渲染；
- 停止、重新渲染、返回编辑；
- 编辑后再次渲染不会使用旧场景或旧 BVH；
- 宽屏和窄屏布局验证；
- JSON/Lua 双模式、J.6.1、J.4 回归检查与正式构建。

第二步验收标准：启动阶段没有光追任务和光追 UI；修改物体或材质后点击渲染，结果来自当前编辑文档；返回编辑后可继续修改；所有既有光追语义检查保持通过。

## 10. 光追修改边界

本方案不需要修改光追底层，也不计划修改以下目录：

```text
RayTracer/Core
RayTracer/Integrator
RayTracer/Geometry
RayTracer/Material
RayTracer/Texture
RayTracer/Acceleration
```

允许的 A 类上层调整：

- `SceneFormat/JsonSceneLoader.lua` 增加内存文档编译入口；
- `RayTracer/Runtime/RenderController.lua` 如有必要增加显式释放/重置接口；
- 现有 Render Inspector 拆分和复用；
- `main.lua` 改为编辑/渲染模式控制并模块化。

如果实施时发现必须修改光追几何表达、求交、材质散射、积分器或 Renderer 核心，立即停止开发并说明原因，等待确认。

## 11. 确认项

建议按本文的两步方案实施，并确认以下产品取舍：

- 只做 Move 与 Scale，不做 Rotation；
- Sphere 只允许统一缩放；
- Quad 只调整位置与两条边长度，不旋转法线；
- Checker 实时预览使用平均色，光追保持精确；
- DiffuseLight 实时预览只拟合自发光外观；
- 保存到用户覆盖文件，不在运行时覆盖打包 assets；
- 材质库属于第一步必做内容。
