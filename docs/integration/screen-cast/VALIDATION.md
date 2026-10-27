# 传屏实现与验证记录

日期：2026-10-27（Asia/Shanghai）。代码已实现；以下自动化结果不等于实际设备人工验收。

## 交付

- 独立 Windows 发送端、浏览器接收端及 `/api/v1/screen-cast/` 业务模块。
- 显示器枚举、物理像素和负坐标采集、鼠标合成、横竖屏等比偶数尺寸计算、显式屏幕 ID 固定与模式变化停止。
- SDK 仅发布端可使用本地预览回调；默认空屏幕 ID 保留现有主屏跟随行为。
- 10 位随机一次性码、5 分钟有效期、角色凭证哈希、并发兑换、限流、双人权限隔离、连接/心跳超时、停止及重启清理。
- 公共 HTTP 和 ImGui 基础设施、构建和启动脚本、运行与 API 文档。

工作区同期有会议/播放器目录迁移，本次保留了这些改动并使用现有 `cmake/NativeSDK.cmake` 共享构建入口。未创建提交、未部署服务。

## 环境与自动化结果

Windows x64；Visual Studio 2022 / MSVC 14.44；Release 静态 CRT；Node.js 24.13.0；Go 1.27.3（模块要求 1.25+）；Chrome 156.0.8078.47 通过 Playwright 以 headless 模式启动。原生窗口截图来自 SDL dummy/software 的程序内渲染，不是桌面截图。集成发送端只生成合成图案，不枚举或采集实际桌面，不注入鼠标/键盘。

| 检查 | 实际结果 |
| --- | --- |
| Go `test ./...`、`vet ./...`、业务服务构建 | 通过，含既有远控测试 |
| Go 新增传屏测试 | 过期、重复及并发兑换、哈希凭证、鉴权、双角色媒体授权、30 秒连接/心跳期限、幂等停止、删除重试、重启终止、存储失败、限流、SQLite 迁移、业务路由隔离、HTTP 合约通过 |
| 传屏 Web `npm run build`、`npm test` | 构建和 API 合约测试通过 |
| 远控 Web `npm test`、`npm run build` | 4 项测试及构建通过 |
| Windows 传屏桌面与 fixture 构建 | 通过，产物在 `livekit-app/out/screen-cast-desktop/Release/` |
| SDK CTest 定向回归 | `screen_capture`、`remote_control`、`media_graph`、`sdk`，4/4 通过 |
| 传屏桌面 CTest | 无窗口六状态渲染、重复启动/取消，2/2 通过 |
| 远控桌面构建与 CTest | 构建通过，无窗口渲染 1/1 通过 |
| C++ SFU CTest | 既有二进制的 `turn-credentials`、`native-send`、`native-rtp`、`core`，4/4 通过；本次未修改 SFU |
| 传屏真实服务联调 | 两轮完整通过，见下表 |
| 远控真实服务联调 | 媒体/输入隔离、停止、失焦释放、心跳丢失和业务服务中断均通过 |
| PowerShell 脚本 | 两个新增脚本 AST 解析通过；各构建组件分别执行，未将整份 build/run 脚本作为验收运行 |
| diff 格式 | `git diff --check` 通过；部分既有文件有 Git 换行格式提示 |

实际主要命令（工作目录见命令路径）：

```powershell
# livekit-server 内
../out/tools/go/bin/go.exe test ./...
../out/tools/go/bin/go.exe vet ./...
../out/tools/go/bin/go.exe build -o out/livekit-business-api.exe ./cmd/business-api

# 仓库根目录；首次配置使用 VS 2022 x64、vcpkg x64-windows-static
cmake --build livekit-sdk-cpp/out/windows-x64 --config Release --target livekit_screen_capture_tests livekit_sdk_tests livekit_remote_control_tests livekit_media_graph_tests --parallel 4
cmake --build livekit-app/out/screen-cast-desktop --config Release --parallel 4
cmake --build livekit-app/out/remote-control-desktop --config Release --parallel 4
ctest --test-dir livekit-sdk-cpp/out/windows-x64 -C Release -R '^(screen_capture|remote_control|sdk|media_graph)$' --output-on-failure
ctest --test-dir livekit-app/out/screen-cast-desktop -C Release --output-on-failure
ctest --test-dir livekit-app/out/remote-control-desktop -C Release --output-on-failure
ctest --test-dir livekit-cpp/out/windows-x64 -C Release --output-on-failure
npm --prefix livekit-app/apps/screen-cast/web run build
npm --prefix livekit-app/apps/screen-cast/web test
npm --prefix livekit-app/apps/screen-cast/web run test:integration
npm --prefix livekit-app/apps/remote-control/web test
npm --prefix livekit-app/apps/remote-control/web run build
npm --prefix livekit-app/apps/remote-control/web run test:integration
```

桌面配置使用 `WEBRTC_PREBUILT_DIR=livekit-sdk-cpp/out/windows-x64` 的绝对路径，复用同源 Release WebRTC。GitHub 下载失败后，使用该目录 `_deps` 下已存在的固定版本 ImGui、IXWebSocket、Protobuf、SDL2 源码配置 `FETCHCONTENT_SOURCE_DIR_*`。

## 集成证据与失败记录

下列证据目录相对聚合仓库根目录。每轮包含进程日志和 `evidence.json`；成功轮包含接收页面截图及二进制 SHA-256。目录使用 UTC 时间戳。

| 目录 | 结果 |
| --- | --- |
| `out/screen-cast/2026-10-27T01-06-49-913Z` | 失败：仅发布端本地预览被 SDK 参数校验拒绝；修正校验并重新编译链接后关闭该问题 |
| `out/screen-cast/2026-10-27T01-12-35-205Z` | 失败：首帧后未在 30 秒内满足 80 帧断言。保留原始日志；本轮未保存浏览器 RTCStats，原因未确定，不能由后续通过推断已修复媒体稳定性 |
| `out/screen-cast/2026-10-27T01-15-47-755Z` | 完整通过 |
| `out/screen-cast/2026-10-27T01-31-07-667Z` | 最终构建后完整通过 |
| `out/remote-control/2026-10-27T01-28-48-794Z` | 既有远控端到端回归通过，未降低已有断言 |

两轮传屏成功运行均验证：两个并行会话各解码至少 80 帧 1280×720 视频、发送端本地预览、码不能重复兑换、会话间凭证不可混用；停止 A 后 B 继续增长至少 30 帧；接收端停止、发送端主动停止、发送进程崩溃、创建中取消、SFU 中断和业务服务中断都能终止。最终测试 runner 已补充失败时的浏览器视频计数、RTCStats 和页面截图。

最终传屏测试二进制 SHA-256：

- SFU：`a83bf74d9bcc1fec707801d3ed449305d986910812ba59ab347d36f766f919b3`
- 业务 API：`553280440c4ee5b4c2fb9d49db0b4476e8cdb2dccf636b37bbbf05e1de917fc0`
- 合成发送 fixture：`a3efc057209eb345f315003a64078e7f8bc11c9b55b5c4d36714d9624a46c8af`

其他本地证据：`out/screen-cast-desktop-build.log`、`out/screen-cast-sdk-build.log`、`out/screen-cast-remote-build.log`、`out/screen-cast-sdk-ctest.log`、`out/screen-cast-desktop-ctest.log`。六状态 BMP 位于 `livekit-app/out/screen-cast-desktop/screen-cast-*.bmp`。已目视检查程序生成的共享状态渲染及浏览器接收截图，未见裁切或空界面。

首次完整原生构建发现独立 PFFFT C 目标缺少 Windows `_USE_MATH_DEFINES`，已在 SDK 原生依赖装配中补上；DPI API 改用运行时解析，以兼容 SDK 的 Windows 头文件版本设置。最终构建与测试均包含这些修正。构建仍有第三方 CMake 弃用及编译警告，不代表零警告构建。

## 尚未人工验收

实际副屏/负坐标、混合 DPI、横竖屏切换、热拔插、鼠标形状与热点、文档可读性、实际最小化继续共享、两台设备局域网传屏、弱网和长期稳定性均未作人工验收。未操作用户桌面，未使用 computer-use。

不把本次两轮合成媒体通过扩展为真实设备、长时稳定性、延迟指标或历史 RTC 未关闭问题已解决。历史问题继续以 [RTC 现状与交接记录](../rtc/STATUS_AND_HANDOFF.md) 为准。
