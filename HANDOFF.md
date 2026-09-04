# Hermes Dashboard 交接文档

更新时间：2026-08-25

## 项目定位

这是一个不依赖 Xcode 工程的原生 macOS AppKit 8-bit dashboard。程序使用 Swift 编译为 `.app`，固定以 1280x720 设计画布绘制，再按实际屏幕比例缩放。

- 本地项目：`/Users/yukarii/Documents/Codex/2026-08-25/https-github-com-mavskero-8bit-agent/work/8bit-agent-dashboard`
- GitHub：`https://github.com/Mavskero/8bit-agent-dashboard.git`
- 分支：`main`
- 本次源码基线提交：以 `main` 最新提交为准
- 当前用户的视觉设置已固化到 `DashboardStyles.defaults` / `DashboardLayout.defaults`，并随本项目资源一起推送到 `origin/main`

## 构建、启动与打包

```sh
cd /Users/yukarii/Documents/Codex/2026-08-25/https-github-com-mavskero-8bit-agent/work/8bit-agent-dashboard
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
- Session 卡片显示标题、状态灯、上下文分段方块和右端百分比；最新 session 使用更高饱和度背景，明显区别于四个历史 session。
- 时间冒号每秒闪烁，但小时、冒号、分钟使用固定几何锚点，分钟不会位移。
- 天气、系统级 Now Playing、Apple Music、GIF 壁纸和可替换天气/Agent 图片资源均有降级处理。
- 设置窗口使用浅色高对比外观；每个颜色支持取色板和 R/G/B 数值编辑，双击色块会在 `DEFAULT DISPLAY` 指定的屏幕打开取色板。每个文字样式都有独立的 `Smooth + 8x` 开关；开启后使用 8x 字体位图、抗锯齿、字体平滑和高质量插值，默认值沿用当前已固化设置。
- Import Font… 会把字体保存到 `~/Library/Application Support/Hermes Dashboard/Fonts`，立即加入字体列表并在后续启动时自动注册。
- Plan Usage / OAuth 设置通过官方 Codex app-server 读取 ChatGPT `codex` 周用量窗口；`BALANCE` 每 10 分钟刷新，`RESET` 服务端时间每 1 小时刷新，支持显示名称、bucket ID 和 Codex 路径。OAuth token 由 Codex 管理，读取失败保留缓存值。
- Runtime Status 实时显示 Codex model、thinking/reasoning 强度、Fast 状态、套餐、周剩余额度、重置倒计时和今日已结束 session 的累计 Tokens；Tokens 按 rollout 的非缓存输入增量加输出计算，不包含缓存命中的重复上下文或会话在当天以前的累计量。累计值按自然日持久化且同一天只增不减，避免运行中、闲置、短时数据库读取失败或重启时归零，并在 session 结束后以 0.85 秒数字增长动画更新。额度按 >=50、20-49、<20 显示绿/黄/红。
- Codex 来源会让左下角模块切换为 `CODEX AGENT`，读取当前 rollout 的 `Reasoning`、`CommandExecution`、`FileChange`、`Extension`、MCP 和 `AgentMessage` 条目。界面使用九种彩色动作标签、合并相邻同类事件，并逐字显示精简正文；不渲染长命令参数和原始工具输出。
- Codex/Hermes 的最终结果先显示通用的“正在总结输出结果”，再交给本机 Ollama `qwen3.5:2b` 总结。提示词根据活动区尺寸和用户字号提供显示容量，允许适当换行；预测到溢出或遇到省略号结尾时提前停在自然语句边界，并提示进入客户端查看。完成时清空过程事件，只以绿色 `[OUTPUT]` 流式显示；UI 不显示本地模型名称，失败时回退到本地精简文本。Codex 的未决授权调用显示为深紫红色 `[APPROVAL]`，收到对应工具结果后移除。
- Runtime Status 七行默认图标来自 `Resources/RuntimeStatusIcons`：Model、Thinking、Fast mode、Plan、Balance、Reset、Tokens。已确认的 `05-legacy-balance.png` 作为备用资源保留。Runtime Icons 设置可切回六种内置像素图案或自定义 PNG/GIF 路径，并可编辑每项 X/Y/Size（8–96 px）。主设置的 `Runtime Colors…` 为七个右侧字段内容提供独立取色器、HEX 输入和 Auto 恢复自动配色；覆盖值保存在 `DashboardLayout.runtimeValueColors`，旧设置解码时默认为空。
- `Weather Settings…` 默认选择和风天气 QWeather，可配置专属 API Host、API KEY、城市/LocationID/经纬度、刷新间隔，以及天气图标 X/Y 和 24–384 px 尺寸。API KEY 存入 macOS 钥匙串；也可切换 Open-Meteo 或 macOS Weather，失败时使用系统缓存/降级值。

## 当前项目默认设置

新安装且没有本机偏好时，App 默认使用当前用户确认过的设置：

```text
padding = 12
runtimeStatus = (770, 20), opacity = 0.2
hermesAgent = (16, 416), opacity = 0.2
activeSession = (618, 416), opacity = 0.2
sessionCardOpacity = 0.0
runtimeTitleSpacing = 48
runtimeIconTitleSpacing = 28
```

文字样式的字体、字号、颜色和 X/Y 坐标已全部写入 `DashboardStyles.defaults`。`Weather · Left Edge` 的 X 是天气字段的固定左边界；V2 右边界设置会在首次加载时换算为当时可见的左边界。天气短名称最长 7 个字符，图标 Y 锚定素材最上方的可见像素。音乐区按波浪动画和 `NOW PLAYING`、歌名、歌手三行排列，这四项分别支持位置、尺寸和颜色设置；暂停或停止后保留最近一次歌曲名与歌手，首次尚未读到歌曲时才显示 `-` 和空歌手，波浪仍持续动画。`Session Context Percent` 和 `Active Session · Last Conversation` 也有独立设置。套餐用量默认读取 Codex app-server 的 `codex` bucket 10080 分钟窗口，刷新间隔 30 分钟；用户可覆盖套餐显示名。默认天气源为 QWeather，城市为 Fuzhou，刷新间隔为 30 分钟；默认天气图标来自 `Resources/WeatherAssets/Static`，位置为 X=560、Y=48、尺寸 128。默认壁纸为 `Resources/kirby_s_chill_land.gif`，由 `build.sh` 自动复制到 App Bundle；设置中选择的外部 GIF 仍会覆盖它。点击 `Clear` 后会记录清除偏好，避免下次启动自动恢复 Bundle 壁纸。

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
runtimeStatus = (770, 20)
hermesAgent   = (16, 416)
activeSession = (618, 416)
```

底部模块尺寸：Hermes Agent 为 584x288，Active Session 为 636x288。Active Session 内部当前布局：

```text
最新 session 内框：x + 24, y + 10, width 596, height 108
子卡片第一行：   (x + 24,  y + 124, width 292, height 76)
                 (x + 328, y + 124, width 292, height 76)
子卡片第二行：   (x + 24,  y + 202, width 292, height 76)
                 (x + 328, y + 202, width 292, height 76)
```

Active Session 外框使用普通 `borderBright`，最新 session 内框使用高亮 `cyan` 边框和至少 0.16 的 cyan 填充。底部模块默认 y=416 是为避免 288px 高度超出外部 720px 画布而设置的；如果继续调整高度，必须同步检查 `y + height <= 712`。

Runtime Status 行首从模块原点的标题下方开始，每行间距 32px；标题与内容默认间距为 48，icon 与行标题默认间距为 28。行尾彩灯和右上角 CODEX/HERMES 来源字样已删除。齿轮按钮使用 54x54 的点击区域。

## 代码结构

- `Sources/HermesDashboard/main.swift`：App 入口。
- `Sources/HermesDashboard/AppDelegate.swift`：窗口、全屏层级、显示器、快捷键、鼠标指针和设置窗口生命周期。
- `Sources/HermesDashboard/Models.swift`：`DashboardModel`、`DashboardLayout`、文字样式、运行状态和显示器偏好。
- `Sources/HermesDashboard/DashboardView.swift`：主画布、时钟、Runtime Status、Hermes Agent、Active Session 绘制。
- `Sources/HermesDashboard/PixelDrawing.swift`：像素字体、像素图形、边框和分段进度条。
- `Sources/HermesDashboard/Services.swift`：系统级 Now Playing / Apple Music、Weather、状态 JSON、Codex SQLite/JSONL 实时读取。
- `Sources/HermesDashboard/SettingsWindowController.swift`：主设置窗口、字体样式编辑、布局/透明度编辑、文件选择器。
- `Resources/Fonts/`：随 App 打包的 Silkscreen 字体。
- `outputs/HermesDashboard.app.zip`：当前可交付压缩包。

## Codex 实时数据链路

Codex 来源由 `RuntimeStatusService` 读取：

1. `~/.codex/sqlite/codex-dev.db` 的 `local_thread_catalog`：最近 session 的标题和更新时间。
2. `~/.codex/thread_history_1.sqlite` 的 `thread_turns`：最新 turn 状态，映射为 `RUNNING`、`DONE`、`ERROR`。
3. `~/.codex/state_5.sqlite` 的 `threads`：rollout 路径、token 计数等。
4. 对每个 rollout 文件尾部读取 `token_count` 事件，优先使用 `last_token_usage` 计算当前上下文占用；今日 Tokens 则扫描已完成任务截止点前的累计事件差值，只累加非缓存输入和输出。
5. 如果 SQLite 不可用，则回退到 `~/.codex/session_index.jsonl`，只提供最近 5 个标题和更新时间。

`DashboardModel` 默认每 2 秒刷新动态数据；`DashboardView` 使用 0.12 秒动画 timer 驱动像素小人、运行灯和 GIF，另有 1 秒 timer 驱动时间冒号。

## 偏好设置与兼容性

- `dashboardStyles`：文字样式 JSON。
- `dashboardLayout`：padding、模块坐标、模块透明度和 `sessionCardOpacity`。
- `preferredDisplayID`：默认显示器。
- `runtimeSource`：Codex 或 Hermes。
- `wallpaperPath` / `assetFolderPath`：壁纸和资源目录。
- `wallpaperCleared`：用户明确清除 Bundle 默认壁纸后的标记。
- `weatherSettings`：天气源、天气图标包、QWeather API Host、城市、刷新间隔和图标 X/Y/尺寸；QWeather API KEY 单独保存在 macOS 钥匙串；`planUsageSettings`：套餐显示名、bucket、Codex 路径和上次成功的周窗口；OAuth 凭据由 Codex 管理；`DashboardLayout.runtimeTitleSpacing` / `runtimeIconTitleSpacing` / `runtimeIcons`：Runtime 间距，以及各图标 X/Y/Size 设置。

`DashboardLayout` 对旧配置做了迁移：旧的 492、444、327、417、420 底部 y 值会迁移到 416；自定义的其他坐标保持不变。

## 接管时建议先做的检查

1. `git status --short --branch`，确认已在 `main` 且没有意外改动。
2. 运行 `./build.sh`，确认 Swift 编译和资源复制正常。
3. 启动 App 截图检查：底部模块不越界、最新 session 内框高亮、四个子卡片右端对齐、分段进度条与百分比可见。
4. 打开设置，确认 `Layout / Opacity…` 中存在 `SESSION CARDS` 字段。
5. 用 SQLite 检查当前会话状态和 token 数据是否存在；不要把 `~/.codex` 中的私密内容提交到仓库。
6. 修改后同步 `outputs/HermesDashboard.app.zip`，运行 `unzip -t`，再提交和推送。

## 已知注意事项

- `README.md` 中仍有早期版本的“7:9”描述，当前代码和交付视觉已经是 9:7；后续若更新 README，应以本文件和 `DashboardView.swift` 当前常量为准。
- `state_5.sqlite`、`thread_history_1.sqlite` 和 `codex-dev.db` 是本机运行时数据，不属于项目文件，不能复制进仓库。
- Weather.app 和 Apple Music 降级读取可能需要 macOS 隐私权限；系统级 Now Playing 不依赖播放器专属的 Apple Events 权限。QWeather Keychain 凭证在后台加载，系统等待钥匙串授权时不能阻塞音乐、Runtime 或主界面刷新。权限不足时程序应继续使用降级数据，不要把权限错误当作启动失败。
- 全屏 screen-saver 层级窗口会影响文件选择器，所以设置中的文件面板通过临时降低父窗口层级来打开；修改窗口层级时需要复测 Choose GIF / Choose Folder。
- 套餐用量依赖本机可执行的 `codex` 和 ChatGPT 登录。设置中的 OAuth 浏览器流程与 Codex 共用账号和凭据；Dashboard 本身不读取 token。
- Codex 闲置时若状态源暂时返回空模型或 `custom`，Runtime Status 会保留上一轮真实模型名。
