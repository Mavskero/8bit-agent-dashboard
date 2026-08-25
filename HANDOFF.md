# Hermes Dashboard 交接文档

更新时间：2026-08-25

## 项目定位

这是一个不依赖 Xcode 工程的原生 macOS AppKit 8-bit dashboard。程序使用 Swift 编译为 `.app`，固定以 1280x720 设计画布绘制，再按实际屏幕比例缩放。

- 本地项目：`/Users/yukarii/Documents/Codex/2026-08-24/github-plugin-github-openai-curated-remote/work/8bit-agent-dashboard`
- GitHub：`https://github.com/Mavskero/8bit-agent-dashboard.git`
- 分支：`main`
- 本次源码基线提交：以 `main` 最新提交为准
- 当前用户的视觉设置已固化到 `DashboardStyles.defaults` / `DashboardLayout.defaults`，并随本项目资源一起推送到 `origin/main`

## 构建、启动与打包

```sh
cd /Users/yukarii/Documents/Codex/2026-08-24/github-plugin-github-openai-curated-remote/work/8bit-agent-dashboard
./build.sh
open build/HermesDashboard.app
```

更新交付压缩包：

```sh
ditto build/HermesDashboard.app outputs/HermesDashboard.app
ditto -c -k --sequesterRsrc --keepParent outputs/HermesDashboard.app outputs/HermesDashboard.app.zip
unzip -t outputs/HermesDashboard.app.zip
```

停止调试实例：

```sh
killall HermesDashboard 2>/dev/null || true
```

## 当前已实现功能

- 全屏无边框窗口，隐藏 Dock 和菜单栏，支持多显示器默认屏幕选择。
- `S`、`Cmd+,` 或 Runtime Status 右侧齿轮打开设置；`Esc` 或 `Cmd+Q` 退出。
- 鼠标启动时可见，10 秒无活动后隐藏，再次活动立即显示。
- 内置 Silkscreen-Regular / Silkscreen-Bold 像素字体，可在设置中切换字体、字号、颜色和每类文字的 X/Y 坐标。
- Runtime Status、Hermes Agent、Active Session 支持模块位置、画布 padding 和背景透明度调整。
- Session 子卡片有独立的 `SESSION CARDS` 透明度设置。
- 上下画布当前为 9:7 比例：上区 405px、下区 315px。
- Hermes Agent 只显示一个最大像素小人，根据 working/thinking/done/idle/error 状态切换。
- Active Session 布局为：最新 session 与标题位于同一个高亮内框；其余四个 session 在下方两行、每行两列。
- Session 卡片只显示标题、状态灯和上下文分段方块进度条：绿色 DONE、红色 ERROR、蓝色闪烁 RUNNING。
- 时间冒号每秒闪烁，但小时、冒号、分钟使用固定几何锚点，分钟不会位移。
- 天气、Apple Music、GIF 壁纸和可替换天气/Agent 图片资源均有降级处理。
- 设置窗口使用浅色高对比外观；支持 Import Font… 注册本地字体。
- Provider Settings 支持 provider 名称、余额 base URL / path / JSON 字段路径、刷新间隔和上次余额持久化；余额请求读取 `OPENAI_API_KEY`，启动立即请求，失败保持旧值。
- Runtime Status 实时显示 Codex model、thinking/reasoning 强度、Fast 状态、provider 和余额；余额按 >=10、5-10、<5 显示绿/黄/红，thinking 按强度显示不同颜色。
- Runtime Icons 设置支持六种内置像素图案或自定义 PNG/GIF 路径，并可编辑每项 X/Y；可单独设置 Runtime 标题与内容间距。
- `WEATHER CITY` 设置使用 `wttr.in` 获取指定城市天气，留空时使用 macOS Weather 缓存/降级值。

## 当前项目默认设置

新安装且没有本机偏好时，App 默认使用当前用户确认过的设置：

```text
padding = 12
runtimeStatus = (770, 26), opacity = 0.2
hermesAgent = (16, 420), opacity = 0.2
activeSession = (618, 420), opacity = 0.2
sessionCardOpacity = 0.0
```

文字样式的字体、字号、颜色和 X/Y 坐标已全部写入 `DashboardStyles.defaults`。默认壁纸为 `Resources/kirby_s_chill_land.gif`，由 `build.sh` 自动复制到 App Bundle；设置中选择的外部 GIF 仍会覆盖它。点击 `Clear` 后会记录清除偏好，避免下次启动自动恢复 Bundle 壁纸。

## 关键视觉参数

主要绘制逻辑在 `Sources/HermesDashboard/DashboardView.swift`：

```text
designSize             = 1280 x 720
areaSplitY             = 405
runtimeModuleHeight    = 378
bottomModuleHeight     = 288
```

默认模块位置在 `Sources/HermesDashboard/Models.swift`：

```text
runtimeStatus = (770, 26)
hermesAgent   = (16, 420)
activeSession = (618, 420)
```

底部模块尺寸：Hermes Agent 为 584x288，Active Session 为 636x288。Active Session 内部当前布局：

```text
最新 session 内框：x + 24, y + 10, width 596, height 108
子卡片第一行：   (x + 24,  y + 124, width 292, height 76)
                 (x + 328, y + 124, width 292, height 76)
子卡片第二行：   (x + 24,  y + 202, width 292, height 76)
                 (x + 328, y + 202, width 292, height 76)
```

Active Session 外框使用普通 `borderBright`，最新 session 内框使用高亮 `cyan`。底部模块默认 y=420 是为避免 288px 高度超出外部 720px 画布而设置的；如果继续调整高度，必须同步检查 `y + height <= 712`。

Runtime Status 行首从模块原点的 `y + 62` 开始，每行间距 35px。行尾彩灯已删除。齿轮按钮在视图坐标中使用 42x42 的点击区域。

## 代码结构

- `Sources/HermesDashboard/main.swift`：App 入口。
- `Sources/HermesDashboard/AppDelegate.swift`：窗口、全屏层级、显示器、快捷键、鼠标指针和设置窗口生命周期。
- `Sources/HermesDashboard/Models.swift`：`DashboardModel`、`DashboardLayout`、文字样式、运行状态和显示器偏好。
- `Sources/HermesDashboard/DashboardView.swift`：主画布、时钟、Runtime Status、Hermes Agent、Active Session 绘制。
- `Sources/HermesDashboard/PixelDrawing.swift`：像素字体、像素图形、边框和分段进度条。
- `Sources/HermesDashboard/Services.swift`：Apple Music、Weather、状态 JSON、Codex SQLite/JSONL 实时读取。
- `Sources/HermesDashboard/SettingsWindowController.swift`：主设置窗口、字体样式编辑、布局/透明度编辑、文件选择器。
- `Resources/Fonts/`：随 App 打包的 Silkscreen 字体。
- `outputs/HermesDashboard.app.zip`：当前可交付压缩包。

## Codex 实时数据链路

Codex 来源由 `RuntimeStatusService` 读取：

1. `~/.codex/sqlite/codex-dev.db` 的 `local_thread_catalog`：最近 session 的标题和更新时间。
2. `~/.codex/thread_history_1.sqlite` 的 `thread_turns`：最新 turn 状态，映射为 `RUNNING`、`DONE`、`ERROR`。
3. `~/.codex/state_5.sqlite` 的 `threads`：rollout 路径、token 计数等。
4. 对每个 rollout 文件尾部读取 `token_count` 事件，优先使用 `last_token_usage` 计算当前上下文占用；没有时回退到 `total_token_usage` 或 `tokens_used`。
5. 如果 SQLite 不可用，则回退到 `~/.codex/session_index.jsonl`，只提供最近 5 个标题和更新时间。

`DashboardModel` 默认每 2 秒刷新动态数据；`DashboardView` 使用 0.12 秒动画 timer 驱动像素小人、运行灯和 GIF，另有 1 秒 timer 驱动时间冒号。

## 偏好设置与兼容性

- `dashboardStyles`：文字样式 JSON。
- `dashboardLayout`：padding、模块坐标、模块透明度和 `sessionCardOpacity`。
- `preferredDisplayID`：默认显示器。
- `runtimeSource`：Codex 或 Hermes。
- `wallpaperPath` / `assetFolderPath`：壁纸和资源目录。
- `wallpaperCleared`：用户明确清除 Bundle 默认壁纸后的标记。
- `providerSettings`：provider 名称、余额请求设置、刷新间隔和最后成功余额。
- `weatherCity`：天气 API 城市；`DashboardLayout.runtimeTitleSpacing` / `runtimeIcons`：Runtime 标题间距和图标设置。

`DashboardLayout` 对旧配置做了迁移：旧的 492、444、327、417 底部 y 值会迁移到 420；自定义的其他坐标保持不变。

## 接管时建议先做的检查

1. `git status --short --branch`，确认已在 `main` 且没有意外改动。
2. 运行 `./build.sh`，确认 Swift 编译和资源复制正常。
3. 启动 App 截图检查：底部模块不越界、最新 session 内框高亮、四个子卡片右端对齐、分段进度条可见。
4. 打开设置，确认 `Layout / Opacity…` 中存在 `SESSION CARDS` 字段。
5. 用 SQLite 检查当前会话状态和 token 数据是否存在；不要把 `~/.codex` 中的私密内容提交到仓库。
6. 修改后同步 `outputs/HermesDashboard.app.zip`，运行 `unzip -t`，再提交和推送。

## 已知注意事项

- `README.md` 中仍有早期版本的“7:9”描述，当前代码和交付视觉已经是 9:7；后续若更新 README，应以本文件和 `DashboardView.swift` 当前常量为准。
- `state_5.sqlite`、`thread_history_1.sqlite` 和 `codex-dev.db` 是本机运行时数据，不属于项目文件，不能复制进仓库。
- Weather.app 和 Apple Music 的读取可能需要 macOS 隐私权限；权限不足时程序应继续使用降级数据，不要把权限错误当作启动失败。
- 全屏 screen-saver 层级窗口会影响文件选择器，所以设置中的文件面板通过临时降低父窗口层级来打开；修改窗口层级时需要复测 Choose GIF / Choose Folder。
