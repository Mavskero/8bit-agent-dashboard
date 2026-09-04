# Hermes Dashboard

这是一个不依赖 Xcode 工程的原生 macOS AppKit dashboard，设计画布固定为 1280×720，并在启动时以全屏窗口显示。窗口隐藏 Dock 和顶部菜单栏，实际显示器尺寸不同于 1280×720 时，会在内部按 16:9 画布等比缩放；画布上下区域按 9:7 比例分割。

## 最终目标设计图

![Hermes 8-bit dashboard final design](outputs/hermes-8bit-dashboard-weather-nowplaying-final.png)

这张图是 UI 目标稿；Hermes Agent 区域只显示一个最大的实时像素小人，并根据当前运行状态切换动作与状态文案，设置窗口可替换字体、图标与 GIF 壁纸。

## 构建与运行

```sh
./build.sh
open build/HermesDashboard.app
```

运行期间可以点击 Runtime Status 标题右侧的齿轮按钮，或按 `S` / `⌘,` 打开设置窗口，按 `Esc` 或 `⌘Q` 退出。快捷键由应用级事件分发处理，即使全屏窗口的第一响应者暂时变化也能生效；在设置输入框中输入 `S` 不会误触发。鼠标启动时保持可见，停止活动 10 秒后自动隐藏，再次移动或点击会立即显示。

## 字体、颜色与字号

设置窗口的 `TEXT STYLE OVERRIDES` 区域可以分别修改 Clock、Date、Temperature、Weather、Music、Runtime Status、Hermes Agent、Active Session 和 Session Context Percent 等元素。天气文字的 X 是左边界；当前天气名称统一为 3–7 个字符的短名称。天气图标的 Y 锚定素材最上方的可见像素，因此切换含不同透明边距的素材时不会上下跳动。音乐区的波浪动画、`NOW PLAYING`、歌名和歌手各有独立设置；每一项都支持 X/Y 画布坐标、字号或图形尺寸、颜色，文字项还支持字体和平滑渲染。没有歌曲播放时歌名显示 `-`，歌手留空，波浪仍持续播放。面板内文字的坐标相对于对应面板原点。颜色既可通过色块选择，也可直接编辑 R/G/B 数值，双击色块后取色板会出现在 `DEFAULT DISPLAY` 指定的屏幕。

- `Silkscreen-Regular` / `Silkscreen-Bold`：随 App 打包的开源像素字体，默认用于目标稿风格
- `Pixelon`：随 App 打包的像素字体，项目内使用该字体的默认文字无需依赖系统预装字体
- `Pixel Grid (built-in)`：兼容旧版本的内置 8bit 字体
- 系统已安装字体，或用 `Import Font…` 导入 `.ttf` / `.otf` / `.ttc`
- 字号
- 颜色
- `Smooth + 8x`：按文字元素开启 8x 高分辨率字体位图、抗锯齿、字体平滑和高质量插值；默认值沿用当前已固化设置

设置中的 `Import Font…` 会将字体保存到 Application Support，立即加入所有文字样式的字体列表，并在以后启动时自动注册。

修改后即时生效并保存到应用偏好设置；`Reset Text Styles` 恢复预览图默认样式。

点击 `Layout / Opacity…` 可以修改整个画布的上下左右 padding、Runtime Status / Hermes Agent / Active Session 三个模块的 X/Y 坐标，以及三个模块背景透明度。修改会立即生效并保存到下次启动。

## 可替换天气与 Agent 图标

应用默认使用 `Resources/WeatherAssets/Static` 中的 1254×1254 透明 PNG 天气图标，并按晴天、夜晚、多云、阴天、雾、毛毛雨、雨、雪和雷暴状态自动切换。构建脚本会把整套资源复制到 App Bundle。`Weather Settings…` 中可以独立设置天气图标的画布 X/Y 坐标和显示尺寸。

在设置中选择 `WEATHER / AGENT ASSET FOLDER`，程序会读取用户指定目录下的 PNG、JPG 或 GIF：

```text
weather-clear.png       weather-cloudy.png
weather-rain.gif        weather-snow.png
hermes-working.png      hermes-thinking.gif
hermes-done.png         hermes-error.png
```

也可以放入 `weather/`、`hermes/`、`agent/` 或 `icons/` 子目录。Agent 会优先按当前状态寻找 `hermes-working`、`hermes-thinking`、`hermes-done` 等文件，GIF 会按原始帧时长播放；找不到时自动回退到内置像素图标。

## Runtime Status 数据

Runtime Status 会实时显示当前 model、thinking/reasoning 强度、Fast 状态、ChatGPT 套餐、套餐周剩余额度、下次重置倒计时和今日已结束 Codex session 的累计 Tokens。今日 Tokens 从 rollout 的每次用量增量计算，口径为非缓存输入加输出，不再把会话的历史累计值或缓存命中的重复上下文计入；当天结果会按自然日持久保存为单调累计值，任务重新运行、短时读取失败、应用闲置或重启都不会把已确认的数值清零。Codex 模式会优先读取 `~/.codex` 的线程数据库、当前 rollout 和 `~/.codex/config.toml`；session 卡片继续显示各会话的上下文占用。thinking 与套餐剩余比例会分别按强度和余量使用不同颜色。
Codex 闲置时如果状态源短暂返回空模型或 `custom`，界面会保留上一轮真实模型名。

选择 `Codex Desktop` 后，左下角标题会切换为 `CODEX AGENT`，并从当前 Codex rollout 提取思考、工具、文件修改、搜索、状态、授权等待、错误和最终输出。信息统一显示为 `[THINKING]`、`[TOOLS]`、`[FILES]`、`[SEARCH]`、`[STATUS]`、`[APPROVAL]`、`[ERROR]`、`[RESULT]`、`[OUTPUT]`；其中等待用户授权使用醒目的深紫红色标签，授权完成后自动移除。标签各用不同颜色，正文只保留简短语义描述；Shell 参数和长控制命令不会直接显示。相邻同类活动会合并，文字以每帧四个字符的速度快速逐字出现。

最终输出不会直接进入信息流。Dashboard 会先显示通用的 `[STATUS] 正在总结输出结果`，在独立后台队列通过本机 Ollama 的 `qwen3.5:2b`（`127.0.0.1:11434`）生成以核心结论为主、可适当换行的纯文本摘要。提示词会根据活动区和用户设置的字号给出行数及容量目标；预测到内容放不下或模型以省略号收尾时，会提前停在自然语句边界并显示“详情请进入客户端查看”。摘要完成后会清空此前的思考和工具过程，只以绿色 `[OUTPUT]` 快速逐字显示结果；界面不会暴露本地摘要模型名称，模型不可用时使用本地精简结果。

主设置中的 `Plan Usage / OAuth…` 通过官方 Codex app-server 的 `account/rateLimits/read` 读取 ChatGPT 套餐用量。默认选择 `codex` bucket 的 10080 分钟周窗口，以 `100 - usedPercent` 显示 `BALANCE`，并使用服务端 `resetsAt` 计算 `RESET` 倒计时。Balance 每 10 分钟刷新，Reset 的服务端时间每 1 小时刷新；可配置显示名称、bucket ID 和 Codex 可执行文件。`Authorize with ChatGPT` 会打开官方浏览器 OAuth，令牌由 Codex 保存并自动刷新，Dashboard 不读取或保存令牌。Runtime Status 默认使用 `Resources/RuntimeStatusIcons` 中已确认的透明像素 PNG；Runtime Icons 设置支持六种内置图案、自定义 PNG/GIF，以及每一行独立的 X、Y 和 8–96 px 尺寸。

`Weather Settings…` 可以选择天气源和天气图标包，并设置图标的 X/Y 位置与 24–384 px 显示尺寸。默认图标包为 `Standard`；`Reference style` 使用 `Resources/WeatherAssets/Alternate/ReferenceStyle` 中的备选素材，缺少的夜间晴天图标自动回退到 `Static/07-moon.png`。默认天气源使用和风天气 QWeather；需要填写和风控制台分配的专属 API Host、项目中的 API KEY 凭据、城市或 LocationID，以及刷新间隔。API KEY 保存在 macOS 钥匙串中，其他设置保存在应用偏好设置中。启动时在后台读取钥匙串，因此 macOS 等待凭证授权时不会阻塞音乐、Runtime 或界面刷新。和风天气先通过 GeoAPI 解析城市，再调用 v1 实时天气接口；天气行只显示天气状况，不附加来源字段。

设置数据位于项目目录之外：普通偏好（包括天气图标位置、套餐显示名称和上次成功的周用量）保存在 `~/Library/Preferences/com.hermes.dashboard.plist`，QWeather API KEY 保存在 macOS 钥匙串，ChatGPT OAuth 凭据由 Codex 管理，导入字体保存在 `~/Library/Application Support/Hermes Dashboard/Fonts`。删除项目源码或覆盖安装同一 Bundle ID 的 App 不会清除这些数据。

天气源也可以切换为 Open-Meteo 或 macOS Weather。城市支持名称、LocationID 或经纬度；天气请求失败时继续使用 macOS Weather 缓存/辅助功能数据和内置降级值。仪表盘温度旁显示当前天气条件短名称，例如 `CLEAR`、`PARTLY`、`CLOUDY`、`RAIN`、`SNOW` 或 `UNKNOWN`。

设置窗口可以切换 Codex Desktop 和 Hermes Agent。程序会按下面的顺序查找状态文件：

- `~/Library/Application Support/Codex/status.json`
- `~/Library/Application Support/HermesAgent/status.json`
- `~/Library/Application Support/Hermes Dashboard/codex.json`
- `~/Library/Application Support/Hermes Dashboard/hermes.json`

也支持环境变量 `CODEX_DASHBOARD_STATUS_PATH` 和 `HERMES_DASHBOARD_STATUS_PATH` 指向自定义 JSON。示例见 [status.example.json](status.example.json)。

`active session` 的进度优先使用 `contextUsedTokens / contextLimitTokens` 计算，正是当前上下文占比；没有 token 数时才使用 `contextPercent`。

当 Runtime Status 来源选择 `Codex Desktop` 时，Active Session 会读取 `~/.codex/session_index.jsonl`，按更新时间排序并展示最近 5 个 Codex 任务；任务标题和最近更新时间会实时刷新。

## 系统数据源

- 音乐：优先读取 macOS 控制中心的系统级 Now Playing 信息，可实时识别 Apple Music、Spotify、浏览器及其他接入系统媒体会话的播放器；Apple Music 另保留 Apple Events 降级读取。首次触发降级路径时，可能需要在“系统设置 → 隐私与安全性 → 自动化”允许 Hermes Dashboard 访问 Music。
- Weather：先读取 macOS Weather 的本地缓存；缓存不可用时尝试读取 Weather.app 的辅助功能树。若 macOS 没有授予辅助功能权限，则使用最后可用/设计稿示例值。权限位置是“系统设置 → 隐私与安全性 → 辅助功能”。

## GIF 壁纸

按 `S` 打开设置，选择本地 GIF。GIF 会以低透明度绘制在 dashboard 后方，并按照原始帧时长播放；点击 `Clear` 后恢复无星星特效的纯色像素背景。资源文件夹也可随时点击 `Clear` 恢复内置天气与 Agent 图标。

## 默认显示器

设置窗口的 `DEFAULT DISPLAY` 下拉菜单会列出当前连接的所有显示器。选择后 Dashboard 会立即移动到对应屏幕，并在后续启动时继续使用该屏幕；如果所选显示器暂时未连接，程序会回退到 macOS 主屏幕。
