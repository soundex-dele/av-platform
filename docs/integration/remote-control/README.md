# Qt6 双平台远程协助

桌面客户端使用 **Qt Widgets + C++ SDK**，同一个应用可以控制其他设备，也可以接受协助。构建目标为 Windows x64 与 macOS 14+，macOS 提供独立 arm64/x86_64 配置；实际验证平台与运行库最低版本见验证记录。浏览器控制端继续兼容；Go 服务管理授权，C++ SFU 传输 VP8 画面和可靠控制消息。

首版面向可信局域网自建服务，每台客户端同时运行一个控制或被控会话，仅共享主屏。不包含账号、无人值守、文件传输、剪贴板同步、音频、多屏切换、远程 IME 或安全桌面控制。

## 使用

1. 在“设置”填写业务服务地址，例如 `http://192.168.1.20:8080`。客户端不配置媒体密钥。
2. 被控方生成 10 位连接码，5 分钟有效，仅供一次申请；复制后交给协助者。
3. 协助者填写对方连接码和称呼，点击连接。称呼由协助者填写，未经账号认证。
4. 被控方本地批准后才开始共享屏幕。macOS 需要屏幕录制与辅助功能权限；“设置”提供权限入口。权限变更后按系统提示重启应用并重新申请。
5. 在远程窗口点击画面启用键鼠；失焦会释放按键和鼠标，回到画面后重新点击。工具栏支持适应窗口、原始比例、全屏、暂停输入和断开。
6. 中文、表情和多行内容通过“发送文字”显式发送，每次最多 256 个 Unicode 字符。先点击远程目标输入框，再编辑文字并发送。等待确认期间禁用重复提交；5 秒未确认或断线后不自动重发。确认仅代表输入接口已提交，不保证目标应用收到文字。

被控端最小化后继续连接，托盘/菜单栏标记被控状态并提供停止操作。关闭主窗口、退出应用、关闭控制窗口或点击停止都会结束相应会话。Windows 急停优先使用 Ctrl+Alt+F10，冲突后尝试 Ctrl+Alt+F9；macOS 对应 Control+Option+F10/F9。注册失败会明确提示使用停止按钮或托盘，不影响程序启动。

本地仅保存服务地址、称呼和窗口尺寸，不持久化连接码、授权凭证或文字草稿。断线后必须重新申请，不自动恢复控制权。macOS 显示器断开、旋转或模式变化时停止采集并要求重新连接，以免旧画面与输入坐标失配。

## 构建与打包

Qt 6.8+（本次基线 6.11.1），CMake、C++20、原仓库 WebRTC 依赖。独立目标保留 `av_remote_host` 名称，现在同时提供控制和被控功能。UI 不再依赖 ImGui/SDL；使用 SDK 的 `VideoFrameStream` 在工作线程转换图像，Qt 只显示最新帧。

Windows 使用 VS 2022、Qt MSVC x64 动态版、vcpkg、Go 和 Node：

```powershell
.\scripts\build\remote-control.ps1 -QtPrefix C:/Qt/6.11.1/msvc2022_64 -BootstrapMedia
.\scripts\run\remote-control.ps1 -AdvertisedHost 192.168.1.20
```

Qt 客户端和它链接的 SDK/WebRTC 使用 `/MD`、`x64-windows-static-md`，SDK 构建目录为 `livekit-sdk-cpp/out/windows-x64-md`。原 SDK `/MT` 默认保留，媒体服务仍使用独立 `/MT` 构建。预编译 WebRTC 导入会校验运行库标记，禁止将旧 `/MT` 库链接进 `/MD` 客户端。便携包输出到 `livekit-app/out/remote-control-desktop/package`。

macOS 使用现有 Homebrew LLVM 工具链及 Qt、OpenSSL、libvpx、dav1d：

```bash
bash scripts/build/remote-control-macos.sh
# 只复用架构与工具链匹配的 WebRTC：
REMOTE_WEBRTC_PREBUILT="$PWD/webrtc/out/macos-x86_64" \
REMOTE_ARCH=x86_64 bash scripts/build/remote-control-macos.sh
```

输出目录为 `livekit-app/out/remote-control-macos-<arch>/package/av_remote_host.app`。arm64 与 x86_64 分别在匹配的编译环境构建。最终包的最低系统版本取源代码目标与打包依赖要求的较高者。分发包会包含 Qt 和本地动态库；本地构建使用 ad-hoc 签名，正式分发的 Developer ID 签名和公证由发布环境提供。

构建脚本会检查所有 Mach-O 依赖、签名，并将应用复制到临时目录执行 offscreen 启动测试，不注册热键、不申请权限、不采集或注入桌面。本机 Homebrew 运行库要求 macOS 15，当前 x86_64 包据此标注为 macOS 15+；生成 14+ 包需要使用最低版本不高于 14 的依赖重新构建。

可通过 `LIVEKIT_PROTOC_EXECUTABLE` 复用已构建的 protoc **3.21.12**；配置阶段验证版本，避免各应用重复编译代码生成工具。

## 自动化验证

```bash
ctest --test-dir livekit-app/out/remote-control-macos-x86_64 --output-on-failure
python3 livekit-app/apps/remote-control/desktop/tests/integration.py \
  --media /absolute/path/livekit-server \
  --business /absolute/path/business-api \
  --host /absolute/path/remote_host_fixture \
  --controller /absolute/path/remote_controller_fixture \
  --output /absolute/path/test-evidence
```

桌面 CTest 包括 SDK 消息契约、控制端协议、模拟 macOS 输入边界、取消后迟到响应和 Qt offscreen 截图。原生集成测试运行真实服务、合成 VP8 视频与输入记录器，保留 30 秒至少五帧门槛，覆盖文字确认、会话隔离、释放及业务服务失联。网页测试继续使用原 `npm test`、`npm run test:integration`。

自动化测试不会采集或注入用户桌面，也不调用桌面自动化工具。Windows/macOS 四种控制方向、真实采集、权限弹窗、拖动、DPI、托盘、急停及真实网络中断需另行人工验收。执行结果与未通过项见 [验证记录](VALIDATION.md)。

## 部署配置

`livekit-business-api` 参数：`-listen`、`-db`、`-remote-control-web`、`-media-api`（受信 HTTP 管理地址）、`-media-url`（客户端可达 ws/wss 地址）。`-tls-cert` 与 `-tls-key` 可直接启用 HTTPS；客户端使用系统信任的证书，不忽略证书错误。

开发启动脚本提供 HTTP/WS 配置，只面向可信开发局域网。TLS 部署时将网页与 `/api/` 放在同一 HTTPS origin；将媒体 `/rtc` 通过支持 WebSocket 的反向代理暴露为 WSS，并正确配置 `-media-url`。媒体 UDP 与 TLS WebSocket 是不同链路，需要分别放行。公网 NAT/TURN 和公网证书部署不属于已验收范围。

SQLite 使用 WAL，单业务进程部署；迁移版本在 `schema_migrations`。`Store` 接口隔离 SQL，后续 PostgreSQL 适配须提供等价的状态保存/审计事务与单写者或并发版本控制。服务重启将所有未结束授权置为 revoked，后台重试删除媒体房间；不会自动恢复控制权。

`out/remote-run/media.json` 包含服务密钥，SQLite 包含哈希凭证及审计，按服务账户限制目录访问。客户端不持有媒体 API Secret，不把媒体 Token 持久化。日志和数据库不保存原始连接码或客户端凭证。

## 授权和故障边界

每次批准同时要求宿主凭证和本地 UI 操作。媒体数据发送权不代表输入授权。SDK 的授权方法仅供被控应用接入已认证业务接口，不能由数据包调用。

业务租约 10 秒，被控端每 3 秒查询并续租；本地期限从 HTTP 请求开始的单调时钟计算，保守扣除请求耗时。网络/存储错误结束本地会话。SDK 独立 watchdog 每 20 ms 检查租约。首次控制通道握手最多等待 10 秒，业务租约仍优先约束，续租不能延长首次握手窗口；期间不接受布局确认或输入。收到首次有效心跳后，3 秒无有效控制心跳即停止并释放按键，因此 HTTP 线程阻塞也不会无限维持输入权限。定时值是策略，不构成实时操作系统的延迟保证。

本地停止先禁用输入、释放本会话按下的键和按钮，再通知服务；可靠队列过载、输入失败、媒体掉线、控制者离开均结束授权。注入返回失败时停止控制并保留待释放状态，在进程仍存活时重试；无法保证进程被强杀、操作系统故障或安全桌面拒绝时完成系统输入清理。

## 验证

本次执行结果见 [验证记录](VALIDATION.md)。

```powershell
cd livekit-app/apps/remote-control/web
npm test
npm run test:integration
```

端到端测试自动启动专用业务服务、C++ SFU、两个无窗口被控 fixture 和无头 Chromium。fixture **只发布合成视频，只记录输入，不采集或控制用户桌面**。可通过 `RC_MEDIA_SERVER`、`RC_BUSINESS_SERVER`、`RC_HOST_FIXTURE`、`RC_CHROME`、`RC_RESULTS` 指定二进制和输出。结果含二进制 SHA-256、解码帧数、事件记录和网页截图。

C++ 入口：`ctest --test-dir livekit-sdk-cpp/out/windows-x64 -C Release -R '^(remote_control|sdk|media_graph)$' --output-on-failure`。桌面端入口：`ctest --test-dir livekit-app/out/remote-control-desktop -C Release --output-on-failure`。业务入口：在 `livekit-server` 执行 `go test ./...`。

实际设备人工验收必须另行执行：两台机器的屏幕质量、DPI、拖动、组合键、全局急停、关闭窗口、断网释放及权限受限窗口。不把合成媒体、输入记录器或截图测试当作这些设备验收已完成。
