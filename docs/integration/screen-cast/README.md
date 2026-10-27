# Windows / macOS → 浏览器传屏

独立入口：`livekit-app/apps/screen-cast/desktop`（C++20 / Qt6 Widgets）和 `web`（TypeScript / Vite）。业务模块是 `livekit-server/internal/businesses/screencast`，使用独立 `screencast_sessions` 表。无音频、远程输入、一对多或自动重连。

## 构建与启动

在仓库根目录执行，依赖 Visual Studio 2022 C++ 工具链、CMake 3.24+、Windows SDK、Qt 6.8+（与 SDK 匹配的 `/MT` 静态运行库构建，例如 vcpkg `x64-windows-static` 的 qtbase）、vcpkg（默认 `D:/vcpkg`）、Node.js/npm、Go 1.25+；Go 也可放在 `out/tools/go/bin`。WebRTC 的固定源码及其补丁要求同 SDK 原生构建。

```powershell
./scripts/build/screen-cast.ps1 -VcpkgRoot D:/vcpkg
# 首次准备媒体依赖可追加 -BootstrapMedia
$env:LIVEKIT_API_KEY = 'local-cast'
$env:LIVEKIT_API_SECRET = '<至少24字符的随机服务端密钥>'
./scripts/run/screen-cast.ps1 -AdvertisedHost 192.168.1.20
```

脚本在后台启动 C++ SFU 与 Go 业务服务，Ctrl+C 结束这两个进程；日志在 `out/screen-cast-run/`。保持远控 `/apps/remote-control/` 路由，传屏页面使用 `/apps/screen-cast/`。可分别构建两个产品。

1. 接收者浏览器打开 `http://192.168.1.20:8080/apps/screen-cast/`，点击“接收投屏”。
2. 发送者手动启动 `livekit-app/out/screen-cast-desktop/Release/av_screen_cast.exe`，在“设置”填写同一业务地址，回到“投屏”选择显示器，输入 10 位投屏码，点击“开始投屏”。
3. 页面收到实际解码帧后显示“正在播放”，可全屏。桌面端显示本地预览，最小化继续共享；关闭窗口或任一端停止均结束会话。

业务 TCP 8080、媒体信令 TCP 7880、媒体 UDP 50000–50100 须在可信局域网内可达；根据实际防火墙规则放行，不自动修改防火墙。`AdvertisedHost` 必须是浏览器与发送端可达的服务机地址，跨机器不能用 `127.0.0.1`。客户端不需要媒体 API 密钥。首版只面向可信局域网，不提供公网部署配置。

## Qt6 桌面端与 macOS

桌面采用原生标题栏、蓝白卡片和“投屏 / 设置 / 帮助”导航。业务地址与窗口尺寸保存在 QSettings；不持久化投屏码或会话凭证。投屏码支持带空格粘贴、保留前导零，输入完成后才可开始。最小化继续共享，关闭时异步停止并等待资源释放。

macOS 源码最低目标 14.0，分别支持 arm64、x86_64 构建。需要 Qt 6.8+、Homebrew LLVM 及匹配 libc++、OpenSSL、libvpx、dav1d，以及仓库已有媒体依赖；脚本不会安装系统依赖。实际运行包的最低系统版本会根据所打包依赖提高，并写入 Info.plist。

```bash
./scripts/build/screen-cast-macos.sh
# 可选：SC_ARCH=arm64、SC_JOBS=4、SC_WEBRTC_PREBUILT=/absolute/matching/webrtc/build
# 产物：livekit-app/out/screen-cast-macos-<arch>/package/av_screen_cast.app
```

首次点击开始投屏时请求屏幕录制权限，拒绝或取消时不会兑换投屏码。请按界面提示到“系统设置 → 隐私与安全性 → 屏幕录制”授权；系统可能要求重新打开应用。macOS 后端使用 ScreenCaptureKit，固定共享所选显示器，采集物理像素、包含鼠标、不采集声音；屏幕断开或模式变化时结束会话。

Windows 构建可通过 `-Qt6Dir` 指定 Qt6 CMake 配置目录；构建脚本将运行包安装至 `livekit-app/out/screen-cast-desktop/package/`。必须使用匹配静态 CRT 的 Qt，避免混合 `/MT` 和 `/MD`。macOS 包仅使用本地 ad-hoc 签名，不包含 Developer ID 公证或商店发布。

接收浏览器的流程保持不变，Windows 和 macOS 共用原有服务端及 Web 页面。

## API 与状态

所有 API 位于 `/api/v1/screen-cast/`，响应禁止缓存。除创建与兑换外，都需要 `Authorization: Bearer <credential>`，凭证只在创建/兑换响应中返回一次，服务端只保存 SHA-256 哈希。

| 方法与路径 | 请求体 | 用途 |
| --- | --- | --- |
| POST `sessions` | `{}` | 创建接收会话；返回 `id`、`code`、`credential`、`expires_at` |
| POST `redeem` | `{"code":"0123456789"}` | 单次兑换；返回发送凭证 |
| GET `sessions/{id}` | 无 | 读取 `state`、`reason`、有效期 |
| POST `sessions/{id}/connect` | `{}` | 获得短期媒体 URL / JWT |
| POST `sessions/{id}/heartbeat` | `{"connected":true}` | 上报本端媒体连接，间隔 3 秒 |
| POST `sessions/{id}/stop` | `{}` | 幂等结束 |

状态：`waiting → paired → streaming → ended`，未兑换 5 分钟则 `expired`。配对后 30 秒内双方未连接、任一端心跳超过 30 秒、媒体断开或采集失败都会终止。投屏码不复用；重新共享必须创建新会话。发送端仅发布，接收端仅订阅，均不能发送数据，每个房间最多两人。

服务进程必须单实例使用同一 SQLite 数据库（与现有业务服务的部署模型一致）。兑换在进程内序列化并先持久化再返回，持久化失败不会消费码；每来源每分钟最多创建 10 次、兑换 30 次，不信任转发来源头。服务重启终止旧会话。结束状态先持久化，房间删除失败持续重试；结束后覆盖短期 JWT 有效期重复清理，避免旧 JWT 重建房间后遗留媒体。

屏幕 ID 为空的 SDK 调用继续默认主屏。传屏客户端明确选择 ID，使用物理像素区域，保持比例、不放大，横屏上限 1920×1080、竖屏 1080×1920，输出偶数尺寸，15 fps。显示模式或屏幕拓扑改变会结束采集并要求重新选择。

## 故障排查

- `code_unavailable`：投屏码过期、已兑换或输入错误，重新生成。
- `rate_limited`：等待一分钟后重试。
- `media_unavailable`：检查 SFU 进程、媒体 API 地址与两服务的密钥是否一致。
- 已配对但没有画面：检查信令地址和 UDP 端口，查看业务及媒体日志；30 秒连接超时会终止。
- `Display changed` / `Selected display unavailable`：重新刷新显示器。共享中不自动换屏。
- `heartbeat_timeout` / 业务 API 连接错误：检查业务进程与网络，恢复后重新生成码。
- CMake 下载失败：可用 `FETCHCONTENT_SOURCE_DIR_IXWEBSOCKET/PROTOBUF` 指向 SDK 已下载的对应固定版本源码。独立 Qt 发送端不构建 ImGui/SDL 渲染器。

## 自动化检查

```powershell
# 构建脚本包含 Go、Web、SDK、桌面和媒体原生检查
./scripts/build/screen-cast.ps1
# 真实服务 + 合成 C++ 视频发送 + 无头 Chromium
npm --prefix livekit-app/apps/screen-cast/web run test:integration
```

集成测试默认发现本机 Chrome/Edge，仅以 headless 方式运行；可设置 `SC_CHROME`。可用 `SC_MEDIA_SERVER`、`SC_BUSINESS_SERVER`、`SC_HOST_FIXTURE`、`SC_RESULTS` 覆盖路径。每次运行在 `out/screen-cast/<时间戳>` 保存 stdout/stderr、二进制哈希、截图和 `evidence.json`，失败也保留证据。测试只发布合成画面，不枚举或采集真实桌面，不注入输入。

本次 Qt6 实际执行情况见 [QT6_VALIDATION.md](QT6_VALIDATION.md)，历史验证见 [VALIDATION.md](VALIDATION.md)。真实多屏、混合 DPI、鼠标效果、文档清晰度、两机局域网体验必须人工验收，自动化通过不代表这些项目已验收。

### Qt 与 Web 无窗口验证

```bash
# 仅 UI：不链接媒体、不请求屏幕录制权限
cmake -S livekit-app/apps/screen-cast/desktop -B livekit-app/out/screen-cast-ui -DSCREEN_CAST_UI_ONLY=ON -DBUILD_TESTING=ON
cmake --build livekit-app/out/screen-cast-ui
ctest --test-dir livekit-app/out/screen-cast-ui --output-on-failure
npm --prefix livekit-app/apps/screen-cast/web ci
npm --prefix livekit-app/apps/screen-cast/web run build
npm --prefix livekit-app/apps/screen-cast/web run test:ui
```

Qt 截图在对应构建目录的 `screenshots/`，Web 布局状态截图在 `livekit-app/out/screen-cast-web-ui/`。Web UI 测试中的播放画面是画布生成的演示画面，实际媒体解码由 `test:integration` 单独验证。macOS 集成测试可用 `SC_MEDIA_SERVER`、`SC_BUSINESS_SERVER`、`SC_HOST_FIXTURE` 指向已构建的本地服务及合成发送器。自动化不采集真实桌面，不使用桌面自动化工具。
