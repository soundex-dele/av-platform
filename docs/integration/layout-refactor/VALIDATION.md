# 多业务目录重构验证

日期：2026-10-26；环境：Windows x64、VS2022、静态 CRT、Go 1.25、Node。
本记录是自动化检查，不代表实际设备人工验收。

## 结果

| 范围 | 构建/检查 | 最终结果 |
| --- | --- | --- |
| RTC SDK、CLI、会议示例 | `livekit-sdk-cpp/out/windows-x64` 编译与完整 CTest | 9/9 通过 |
| Player-only | `livekit-sdk-cpp/out/player-windows-ffmpeg71` 编译与 CTest | 7/7 通过 |
| RTC + Player | `livekit-sdk-cpp/out/player-rtc-config` 编译与 CTest | 9/9 通过 |
| 独立 ServerSDK 消费工程 | `livekit-sdk-cpp/out/server-sdk-consumer`；只链接 `LiveKit::ServerSDK` | 编译与消费测试通过 |
| 媒体服务 | `livekit-cpp/out/windows-x64` 编译与 CTest | 4/4 通过 |
| 远控桌面 APP | `livekit-app/out/remote-control-desktop` 独立编译、dummy SDL 渲染 | 1/1 通过 |
| 业务服务 | `go build`、`go vet ./...`、`go test ./...` | 通过 |
| 远控 Web APP | `npm run build`、`npm test` | 构建成功，4/4 通过 |
| 远控端到端 | `npm run test:integration` | 3 个场景通过 |
| 迁移入口 | PowerShell AST 语法检查、平台/模块文档相对链接、各仓库 `git diff --check` | 通过 |

Player 首次样片生成在并行编译期间超过原 30 秒门槛；没有放宽超时，随后重跑完整 7 项测试通过。联合构建也通过相同样片与播放检查。

## 业务与路由

服务端原授权回归覆盖批准、撤销、重复请求、租约到期、重启撤权、并发兑换、跨会话隔离、凭证哈希存储和媒体 Token 权限。新增路由检查验证：

- `/api/v1/remote-control/` 分派到远控业务。
- 未实现的传屏 API 返回 JSON 404，不进入远控业务。
- 原 `/api/v1/pairings`、`/api/v1/control-grants` 不再提供兼容路由。
- 远控静态页面仅挂载在 `/apps/remote-control/`；根路径和其他 APP 路径不提供远控页面。

## 端到端证据

测试启动隔离业务服务、C++ SFU、无窗口原生 fixture 和无头 Chromium。
合成视频为 1280×720，浏览器确认至少解码 5 帧。输入仅写入记录器，未调用真实系统输入注入。

| 场景 | 结果 |
| --- | --- |
| 视频解码、键鼠消息、失焦释放、主动停止、双会话隔离 | 通过 |
| 控制心跳停止后释放按键 | 通过，观测约 2250 ms |
| 业务服务停止后释放按键 | 通过，观测约 213 ms |

上述耗时为本次自动化观测，不是产品时延保证。
本地完整证据（含二进制 SHA-256、日志、输入记录及截图）：
`out/remote-control/2026-10-26T09-36-09-949Z/`。

实际屏幕采集、麦克风/摄像头、系统输入、跨机器网络与公网 TURN 未在本次执行人工验收。历史 RTC 文件四轨与跨系统问题仍以原交接记录为准。

## 复现入口

从聚合仓库运行 `scripts/build/remote-control.ps1` 构建远控所需模块并执行模块测试；随后在 `livekit-app/apps/remote-control/web` 运行 `npm run test:integration`。

播放器独立构建使用 SDK 的 `scripts/build-player-windows.ps1`，配置相同 FFmpeg 开发包。
ServerSDK 消费工程通过 `cmake -S livekit-sdk-cpp/tests/consumer -B <目录> -DSDK_CONSUMER_COMPONENT=ServerSDK` 配置，并传入 Windows 静态 vcpkg 工具链；编译后运行该目录下的 CTest。

本次验证对应目录重构后的代码；各子模块提交版本由聚合仓库的 gitlink 记录。提交顺序为先提交子模块，再更新聚合仓库 gitlink。
