# 远程协助 v1

浏览器控制 Windows 主屏，Windows 被控端使用 **ImGui + SDL2**。Go 业务服务管理本地同意后的短期授权；SQLite 持久化状态、清理任务与审计。C++ SDK 执行控制协议和 Windows 输入，C++ SFU 传输 VP8 画面及可靠数据。

## 构建和启动

依赖 VS 2022 C++、Windows SDK、CMake、vcpkg 静态依赖、Node 22+、Go 1.25+。沿用 SDK 的 `/MT` 和固定 WebRTC 源码；不复制单独的 SDK `.lib`。首次获取媒体服务依赖时：

```powershell
.\scripts\build-remote-control.ps1 -BootstrapMedia
```

设置 `LIVEKIT_API_KEY` 与 `LIVEKIT_API_SECRET`（至少 24 字符），仅供服务进程使用。然后启动：

```powershell
.\scripts\start-remote-control.ps1 -AdvertisedHost 192.168.1.20
```

将地址换成部署机器的局域网 IP。脚本在当前终端保持运行，Ctrl+C 清理它启动的两个服务。允许客户端访问业务 HTTP 8080、媒体 HTTP/WebSocket 7880、媒体 UDP 50000–50100；脚本不自动修改防火墙。

在被控 Windows 运行 `livekit-sdk-cpp/out/windows-x64/Release/av_remote_host.exe`，填写业务地址并创建连接码。控制者在 Chrome/Edge 打开同一业务地址，输入连接码和称呼。Windows 用户确认请求后才会发布屏幕。点击网页画面启用输入；失焦后需要再次点击。关闭或最小化正在控制的被控窗口会结束控制；也可使用停止按钮或 **Ctrl+Alt+F12**。

连接码 10 位、5 分钟有效，仅供一次申请；拒绝、超时、断线或结束后点击创建按钮生成新码。称呼由申请者自报，不代表经过认证的账号。首版无账号、无人值守、多屏选择、音频、剪贴板、文件传输、中文 IME 和安全桌面控制。

## 部署配置

`livekit-business-api` 参数：`-listen`、`-db`、`-web`、`-media-api`（受信 HTTP 管理地址）、`-media-url`（客户端可达 ws/wss 地址）。`-tls-cert` 与 `-tls-key` 可直接启用 HTTPS；客户端使用系统信任的证书，不忽略证书错误。

开发启动脚本提供 HTTP/WS 配置，只面向可信开发局域网。TLS 部署时将网页与 `/api/` 放在同一 HTTPS origin；将媒体 `/rtc` 通过支持 WebSocket 的反向代理暴露为 WSS，并正确配置 `-media-url`。媒体 UDP 与 TLS WebSocket 是不同链路，需要分别放行。公网 NAT/TURN 和公网证书部署不属于已验收范围。

SQLite 使用 WAL，单业务进程部署；迁移版本在 `schema_migrations`。`Store` 接口隔离 SQL，后续 PostgreSQL 适配须提供等价的状态保存/审计事务与单写者或并发版本控制。服务重启将所有未结束授权置为 revoked，后台重试删除媒体房间；不会自动恢复控制权。

`out/remote-run/media.json` 包含服务密钥，SQLite 包含哈希凭证及审计，按服务账户限制目录访问。客户端不持有媒体 API Secret，不把媒体 Token 持久化。日志和数据库不保存原始连接码或客户端凭证。

## 授权和故障边界

每次批准同时要求宿主凭证和本地 UI 操作。媒体数据发送权不代表输入授权。SDK 的授权方法仅供被控应用接入已认证业务接口，不能由数据包调用。

业务租约 10 秒，被控端每 3 秒查询并续租；本地期限从 HTTP 请求开始的单调时钟计算，保守扣除请求耗时。网络/存储错误结束本地会话。SDK 独立 watchdog 每 20 ms 检查租约和 3 秒控制心跳，因此 HTTP 线程阻塞也不会无限维持输入权限。定时值是策略，不构成实时操作系统的延迟保证。

本地停止先禁用输入、释放本会话按下的键和按钮，再通知服务；可靠队列过载、输入失败、媒体掉线、控制者离开均结束授权。注入返回失败时停止控制并保留待释放状态，在进程仍存活时重试；无法保证进程被强杀、操作系统故障或安全桌面拒绝时完成系统输入清理。

## 验证

本次执行结果见 [验证记录](VALIDATION.md)。

```powershell
cd livekit-app/web
npm test
npm run test:integration
```

端到端测试自动启动专用业务服务、C++ SFU、两个无窗口被控 fixture 和无头 Chromium。fixture **只发布合成视频，只记录输入，不采集或控制用户桌面**。可通过 `RC_MEDIA_SERVER`、`RC_BUSINESS_SERVER`、`RC_HOST_FIXTURE`、`RC_CHROME`、`RC_RESULTS` 指定二进制和输出。结果含二进制 SHA-256、解码帧数、事件记录和网页截图。

C++ 入口：`ctest --test-dir livekit-sdk-cpp/out/windows-x64 -C Release -R '^(remote_control|remote_host_render|sdk|media_graph)$' --output-on-failure`。业务入口：在 `livekit-server` 执行 `go test ./...`。

实际设备人工验收必须另行执行：两台机器的屏幕质量、DPI、拖动、组合键、全局急停、关闭窗口、断网释放及权限受限窗口。不把合成媒体、输入记录器或截图测试当作这些设备验收已完成。
