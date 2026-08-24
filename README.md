# Hermes Dashboard

这是一个不依赖 Xcode 工程的原生 macOS AppKit dashboard，设计画布固定为 1280×720，并在启动时以全屏窗口显示。窗口隐藏 Dock 和顶部菜单栏，实际显示器尺寸不同于 1280×720 时，会在内部按 16:9 画布等比缩放。

## 最终目标设计图

![Hermes 8-bit dashboard final design](outputs/hermes-8bit-dashboard-weather-nowplaying-final.png)

这张图是 UI 目标稿；当前 App 的 Hermes Agent 区域已改为只显示一个随运行状态切换的 Agent 小人，设置窗口可替换字体、图标与 GIF 壁纸。

## 构建与运行

```sh
./build.sh
open build/HermesDashboard.app
```

运行期间可以按 `S` 或 `⌘,` 打开设置窗口，按 `⌘Q` 退出。`S` 只在主 Dashboard 窗口激活时生效，避免在设置输入框里输入 S 时误触；`⌘,` 使用应用级监听，即使全屏窗口焦点切换后也可以打开设置。

## 字体、颜色与字号

设置窗口的 `TEXT STYLE OVERRIDES` 区域可以分别修改这些位置：Clock、Date、Temperature、Now Playing Artist、Now Playing Title、Runtime Status、Hermes Agent、Active Session、Recent Sessions。每一项都支持：

- `Pixel Grid (built-in)`：与预览图一致的内置 8bit 字体
- 系统已安装字体，或用 `Load Font…` 临时注册 `.ttf` / `.otf` / `.ttc`
- 字号
- 颜色

修改后即时生效并保存到应用偏好设置；`Reset Text Styles` 恢复预览图默认样式。

## 可替换天气与 Agent 图标

在设置中选择 `WEATHER / AGENT ASSET FOLDER`，程序会读取用户指定目录下的 PNG、JPG 或 GIF：

```text
weather-clear.png       weather-cloudy.png
weather-rain.gif        weather-snow.png
hermes-working.png      hermes-thinking.gif
hermes-done.png         hermes-error.png
```

也可以放入 `weather/`、`hermes/`、`agent/` 或 `icons/` 子目录。Agent 会优先按当前状态寻找 `hermes-working`、`hermes-thinking`、`hermes-done` 等文件，GIF 会按原始帧时长播放；找不到时自动回退到内置像素图标。

## Runtime Status 数据

设置窗口可以切换 Codex Desktop 和 Hermes Agent。程序会按下面的顺序查找状态文件：

- `~/Library/Application Support/Codex/status.json`
- `~/Library/Application Support/HermesAgent/status.json`
- `~/Library/Application Support/Hermes Dashboard/codex.json`
- `~/Library/Application Support/Hermes Dashboard/hermes.json`

也支持环境变量 `CODEX_DASHBOARD_STATUS_PATH` 和 `HERMES_DASHBOARD_STATUS_PATH` 指向自定义 JSON。示例见 [status.example.json](status.example.json)。

`active session` 的进度优先使用 `contextUsedTokens / contextLimitTokens` 计算，正是当前上下文占比；没有 token 数时才使用 `contextPercent`。

## 系统数据源

- Apple Music：通过 macOS Apple Events 读取当前歌曲、歌手、播放状态和进度。首次使用可能需要在“系统设置 → 隐私与安全性 → 自动化”允许 Hermes Dashboard 控制 Music。
- Weather：先读取 macOS Weather 的本地缓存；缓存不可用时尝试读取 Weather.app 的辅助功能树。若 macOS 没有授予辅助功能权限，则使用最后可用/设计稿示例值。权限位置是“系统设置 → 隐私与安全性 → 辅助功能”。

## GIF 壁纸

按 `S` 打开设置，选择本地 GIF。GIF 会以低透明度绘制在 dashboard 后方，并按照原始帧时长播放；点击 `Clear` 后恢复内置像素夜景背景。资源文件夹也可随时点击 `Clear` 恢复内置天气与 Agent 图标。
