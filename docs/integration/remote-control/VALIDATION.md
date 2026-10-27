# 远控验证记录

日期：2026-10-26，Windows x64，VS 2022、Node 24.13.0、Go 1.27.3。全部验证未使用 computer-use 或桌面自动化，未执行真实桌面输入注入。

## 构建与自动化结果

| 检查 | 结果 |
| --- | --- |
| SDK Release 完整构建，包括 ImGui host / headless fixture / render test | 通过 |
| 本工作区 C++ 媒体服务 Release 构建 | 通过；使用当前 SDK 构建中的原生 WebRTC 库 |
| Go 业务服务构建、`go test -v ./...`、`go vet ./...` | 通过；5 组业务测试 |
| 网页 `npm run build`、`npm test` | 通过；4 组测试 |
| SDK CTest：remote_control、media_graph、sdk、remote_host_render | 4/4 通过 |
| C++ 服务 CTest：turn-credentials、native-send、native-rtp、core | 4/4 通过 |
| C++ 与 TypeScript 共用消息样例 | 通过 |
| OpenAPI JSON 解析、PowerShell 启动/构建脚本语法解析 | 通过；启动脚本未代替人工部署验收 |

SDK 控制测试覆盖授权身份、布局确认、过期/旧序号、未知键、坐标越界、按钮整数溢出、非法滚轮值、布局变化释放、心跳超时、租约过期、失效授权不复活，以及注入失败后的释放重试。Windows 原生调用边界使用替代实现检查扩展扫描码、keyup、虚拟屏幕绝对坐标和安全桌面拒绝，不调用真实 `SendInput`。

业务测试覆盖未批准禁止连接、控制者不能批准/续租、重复批准不延长租约、重复撤销、租约/配对到期、服务重启撤权、跨会话凭证隔离、并发兑换单赢家、限流、哈希凭证存储和媒体 Token 权限。

ImGui 通过 SDL dummy + software renderer 渲染 idle/waiting/pending/approved/ended 五种状态，截图位于 `livekit-sdk-cpp/out/windows-x64/remote-app/remote-host-*.bmp`。已检查批准与待确认截图，确认信息及停止入口可见。网页截图已检查画面布局与连接状态。

## 最终跨仓库集成

运行入口：`livekit-app/apps/remote-control/web/tests/integration.mjs`。最终证据目录：

`out/remote-control/2026-10-26T05-08-41-489Z/`

该次使用本工作区构建的 Go 服务、C++ 媒体服务和 SDK fixture；自动启动并清理专用进程，浏览器为无头 Chromium。早先使用已有外部媒体二进制的初次结果保留，但最终结论以此目录为准。

| 场景 | 实测结果 |
| --- | --- |
| 合成 VP8 视频经 SFU 进入浏览器 | 通过；两个会话均检测到 320×180 实际解码画面，检查时各至少 5 帧 |
| 网页键鼠到原生 SDK 输入记录器 | 通过 |
| 双会话输入隔离 | 通过；A 的键盘输入未出现在 B |
| 失焦释放 Shift、主动停止和 fixture 退出 | 通过 |
| 暂停控制端 JS 定时器，保持媒体连接 | 通过；约 2765 ms 后释放 Shift |
| 关闭业务服务，保持媒体服务运行 | 通过；约 428 ms 后释放 Control，并退出被控会话 |

以上延迟是单次本机测量，不代表跨网 SLA。截图为合成画面，不是用户桌面。心跳/业务故障场景的 fixture 错误日志是预期停止原因，断言同时检查了按键释放及进程结束。

`evidence.json` 包含二进制 SHA-256、场景结果和帧数；`*.inputs.jsonl` 是模拟输入事件。最终三个二进制哈希：

- C++ 媒体服务：`76f1bc9ba4e884382955add4e513d5a3ed572980c18b446eefab00584b341a06`
- Go 业务服务：`83ae329df21aa03d0e245c19554e7078e9082821f72679ec90eecd2b19b0c1c9`
- SDK headless fixture：`7b0fcfad18934a6c7e25c5c125283d9b872b83e70f29a4946814a46299e2ca9f`

## 尚需人工验收

真实 Windows 主屏采集质量、不同 DPI/旋转、实际鼠标拖动和组合键、全局急停热键、权限受限窗口、真实网线中断与两台设备的局域网连通性尚未进行人工验收。公网、TURN、TLS 部署和生产容量也未验收。

既有 RTC 交接记录中的文件四轨与 Windows→Linux/WSL 失败，本次没有针对性修复或重新验收；本次通过不覆盖这些已知问题。

## 热键启动修复

修复了 F12 注册失败导致被控端退出的问题：Windows 为调试器保留 F12，默认快捷键改为 Ctrl+Alt+F10，冲突时尝试 Ctrl+Alt+F9；均失败时保留停止按钮和关闭窗口能力，并显示注册错误而不退出。界面显示实际注册成功的组合。

已重新构建 `av_remote_host.exe` 和 `remote_host_render_test.exe`，`remote_host_render` 通过。测试替代注册函数验证首选成功、首选冲突后的备用成功、全部冲突但仍能渲染三种情况；已检查无快捷键状态的程序内截图，停止按钮及说明完整可见。未在用户桌面注册热键或模拟按键，实际全局热键响应仍需人工验收。本次仅修改客户端热键/UI，不重跑媒体链路测试。

## 中文文字发送增量（2026-10-27）

实现了网页显式发送中文、表情和多行文字、能力协商、匹配请求 ID 的宿主回执、等待状态、5 秒未确认停止、断线清理和禁止自动重发。SDK 增加严格 UTF-8/长度校验、当前布局/授权/可靠序列约束、重复 ID 拦截、发送前释放修饰键与按钮。Windows 使用 Unicode 输入，部分失败后的未配对 key-up 保留重试；仅输入记录器与替代 Windows API 在本轮测试中执行，不调用真实 SendInput。

已通过的检查：

- SDK Release 构建与 `remote_control` CTest 1/1。覆盖 UTF-8 非法编码、控制字符、256 标量边界、补充平面字符、身份/布局/序号/租约拒绝、重复请求、旧 sink 不支持、失败后停止及释放重试。
- 显式运行 `livekit_remote_control_tests.exe docs/integration/remote-control/messages.json` 通过。普通 SDK CTest 不传跨仓库 fixture 参数，此项单独执行验证共享 JSON 契约。
- Web 单测 8/8，生产构建通过。覆盖文字验证、回执匹配、超时/取消、发送队列顺序、停止丢弃未发送文字。
- Windows 被控端、fixture、渲染测试构建成功，`remote_host_render` 1/1。已检查 `livekit-app/out/remote-control-desktop/remote-host-pending.bmp`，中文授权范围与停止按钮完整可见。
- `out/remote-control/2026-10-27T04-54-37-602Z/evidence.json` 与 `2026-10-27T05-00-39-029Z/evidence.json` 中，文字发送、成功回执、超长拒绝、重复提交不重发、双会话隔离、停止后禁用及草稿清理的场景通过。已检查其中桌面/390px 窄屏截图，页面无横向溢出。这两轮的**完整套件均失败**，不能称端到端全部通过。

本轮保留的失败：

| 证据目录（位于 `out/remote-control/`） | 实际结果 |
| --- | --- |
| `2026-10-27T04-54-37-602Z` | 文字场景通过；随后无文字能力宿主的视频帧等待超时 |
| `2026-10-27T04-56-26-699Z` | 尚未发送文字，第二个会话 30 秒仅解码 3 帧；`host-b.rtc.json` 保存浏览器统计 |
| `2026-10-27T05-00-39-029Z` | 文字场景再次通过；随后宿主收到 177 个仅含头部/填充的 RTX 包，0 帧解码；`media-metrics.txt` 同时记录 1 个预算暂停流、无 pacer admission drop。指标为多会话汇总，尚不能据此确定根因 |
| `2026-10-27T04-58-31-199Z` | 使用官方 LiveKit 1.13.10 做诊断对照，宿主 `heartbeat_timeout`，未完成首次控制连接；不能作为通过基线 |

测试器保留原有 30 秒至少 5 帧门槛，增加失败截图、浏览器 RTCStats、C++ SFU metrics、Web 产物哈希与媒体后端标识。默认仍使用 C++ SFU；可用 `RC_MEDIA_SERVER_KIND=official` 配合 `RC_MEDIA_SERVER` 指定官方服务进行诊断。本轮没有修改或重建 C++ SFU/Go 业务服务，具体使用的二进制哈希见每轮 evidence。

当前限制：新文字功能的合成输入链路已验证，但完整远控媒体回归仍不通过。实际目标应用中的中文、换行、Tab、表情和权限受限窗口仍需人工验收；成功回执不证明目标应用已接收文字。C++ SFU 的带宽/启动时序与官方服务的初始心跳失败都需要继续诊断，不能用此前的成功记录覆盖本轮失败。

## 初始握手修复（2026-10-27）

后续诊断 `out/remote-control/2026-10-27T05-11-11-866Z` 与 `2026-10-27T05-16-12-991Z` 表明宿主在约 3.2 秒时停止，而浏览器按需数据通道尚未建立。网页改为在认证信令连接完成后启动第一条可靠心跳；SDK 区分首次握手与已建立控制：首次等待最多 10 秒且受业务租约约束，期间拒绝布局确认和全部输入，业务续租不能延长首次等待。首次有效心跳后保持 3 秒失联释放规则。

SDK 确定性单测覆盖延迟 5 秒握手、握手前拒绝输入、握手后 3 秒释放、续租不延长 10 秒窗口、业务租约优先、超时后不能复活。SDK 远控 CTest 1/1、共享 JSON 契约、桌面渲染 1/1、Web 8/8 单测及构建通过。

官方 LiveKit 1.13.10 的完整套件通过：`out/remote-control/2026-10-27T05-25-02-866Z/evidence.json`。保留原有视频门槛，覆盖六组场景：媒体/键鼠/失焦/停止/会话隔离，中文文字确认及边界，宿主不支持文字，额外延迟 4.5 秒的初始连接，已建立控制的心跳丢失释放，以及业务服务中断释放。心跳暂停场景单次实测释放约 2181 ms，业务中断约 313 ms；不是延迟 SLA。

此通过结果关闭本轮官方服务初始握手失败，不覆盖 C++ SFU 视频停滞；后者正在用无音频的原生弱网模拟进一步定位。测试 fixture 新增时序诊断，不输出输入内容或凭证；浏览器记录通道建立/关闭和消息数量。真实设备人工验收仍未执行。

## C++ SFU 视频恢复修复（2026-10-27）

原生 GoogCC 在应用受限、码率保持不变时，没有把延迟拥塞原因的变化通知探测控制器，导致后者继续拒绝周期性探测。现在将拥塞原因纳入变化检测；SFU 在全部媒体暂停且仍需要视频时，提供不超过当前目标一半的填充需求，维持反馈并保留应用受限检测空间。实际速率及探测仍由原生拥塞控制和 pacer 决定，没有强制提高带宽估计或绕过拥塞保护。补丁及源码校验保存在 `livekit-cpp/patches/webrtc-m137-probe-cause-refresh.patch` 和 `cmake/CheckWebRTCPatches.cmake`。

复现测试也修正了最高档模拟包超过发送器容量的问题：按 MTU 分包，并要求拥塞前后确实收到媒体包。模拟链路在第 10 秒从 1.5 Mbps 降到 100 kbps，第 25 秒恢复；覆盖有音频、冷启动及完全无音频三种场景，检查暂停、最高层恢复、冷启动和音频优先级。同一修正测试在隔离编译的旧状态判断逻辑下再次失败（144155 bps 停滞），修复后通过。对照及通过日志分别为 `out/remote-video-legacy-cause-test.log`、`out/remote-video-minimal-test.log`。

重新构建媒体服务、远控桌面宿主和 fixture 后，C++ 后端完整六组集成通过：`out/remote-control/2026-10-27T06-13-31-752Z/evidence.json`。覆盖与官方对照相同的六组场景，未降低 30 秒至少 5 个解码帧门槛。失联释放本次记录为心跳中断约 2914 ms、业务中断约 543 ms，不作为延迟 SLA。媒体服务 `native-send`、`native-rtp`、`core` 三组 CTest 通过，远控桌面渲染 1/1 通过。

该结果关闭本轮已复现的视频恢复缺陷，证据限定于记录中的二进制哈希、合成媒体和输入记录器；不代表长期网络稳定性或真实 Windows 输入、显示器和设备已经人工验收。没有使用桌面自动化或真实输入注入。

## Qt6 双角色客户端（2026-10-27，macOS x86_64）

本轮将桌面入口迁移到 Qt Widgets，增加原生控制端、macOS 输入后端、权限引导、托盘与急停入口。ScreenCaptureKit 使用工作区共享的 SDK 主屏采集实现，不引入直播引擎。Windows 保留原工厂并新增 `/MD` 构建路径；本轮实际执行环境为 Intel macOS、Homebrew LLVM、Qt **6.11.1**，不将已有 Windows ImGui 验证记录视为新 Qt Windows 客户端已通过。

| 自动化检查 | 实际结果 |
| --- | --- |
| Qt 客户端、SDK、host/controller fixture 编译 | macOS x86_64 Release 通过 |
| 桌面 CTest | **5/5 通过**：迟到响应/取消、SDK 契约、原生协议与替代输入、普通 DPI 与 2× DPI offscreen 渲染 |
| Go 业务测试 | `go test ./...` 通过，业务二进制构建通过 |
| 网页控制端 | 单测 **8/8**、生产构建通过 |
| 原生控制端 → C++ SFU → SDK fixture | 通过；两个会话在 30 秒内达到至少 5 帧，结束检查时分别为 **13、14 帧**；不同文字标记只到达各自记录器，文字确认、按键释放、主动停止、控制进程终止与业务服务中断均通过 |
| 网页 → 同一 C++ SFU → 新 SDK fixture | **六组场景通过**；首会话 5 帧、4.5 秒延迟握手会话 10 帧、另一会话 7 帧；未降低门槛 |
| macOS 应用依赖与启动 | 39 个 Mach-O 文件的非系统依赖全部位于包内，ad-hoc 签名校验通过；复制到临时目录后 offscreen 启动通过 |

本轮原生证据：`livekit-app/out/remote-control-integration/native-20261027-qt6-final/evidence.json`。网页证据：`livekit-app/out/remote-control-integration/web-20261027-qt6/evidence.json`。两者记录了实际二进制 SHA-256；合成视频尺寸为 1280×720，没有读取用户屏幕。网页心跳中断释放单次测量约 3066 ms，业务中断约 524 ms，不作为延迟保证。沿用工作区已有 SFU 视频恢复修复，本轮未修改拥塞控制；上述结果只证明记录中的构建和场景通过。

Qt 程序内截图位于 `livekit-app/out/remote-control-macos-x86_64/remote-host-*.png`、`remote-controller.png` 及 `render-hidpi/`，覆盖首页、等待申请、待批准、被控、结束、权限缺失、错误与控制窗口。检查了中文可读性、授权范围、停止入口、黑边不注入、暂停释放和权限不足禁止批准。macOS 输入测试使用替代 API，覆盖左右修饰键、Retina 坐标、拖动、Unicode 补充平面字符、部分释放失败重试；没有真实 CGEventPost 或 SendInput 注入。

应用包：`livekit-app/out/remote-control-macos-x86_64/package/av_remote_host.app`。打包脚本检查实际运行库版本并写入 Info.plist：**当前包要求 macOS 15+**，因为本机 OpenSSL、PCRE2、zstd 的最低系统版本为 15；源码构建目标仍是 14。没有修改运行库版本标记伪装兼容性。若要交付 macOS 14 包，须使用兼容 14 的依赖重新构建及验证。

最终压缩包为同目录的 `AVRemote-macOS15-x86_64.zip`（约 39 MB，SHA-256：`3ef61b3acc8a21957c83dd7e4834f8958da08ad9b85bcd686aa33b843450f56e`）。最终包包含重新生成连接码及 Shift+Tab 焦点处理改动；应用二进制哈希、主机版本、依赖审计和测试日志保存在 `livekit-app/out/remote-control-integration/qt6-validation/`。

本轮未完成的交付与验收：

- Windows Qt `/MD` 构建、便携包依赖检查以及 macOS arm64 构建尚未在对应环境执行；仓库提供配置与脚本，**不代表已产出这两种包**。
- macOS 14 运行兼容性未验证，当前本机包不支持该版本。当前 macOS 包为本地 ad-hoc 签名，未做 Developer ID 公证。
- Windows↔Windows、Windows↔macOS、macOS↔macOS 的真实屏幕采集、主屏/Retina 变化、拖动/组合键、目标应用文字输入、锁屏/注销与权限撤销、权限弹窗、托盘及全局急停仍需实际设备人工验收。
- 合成媒体测试、替代输入 API 和 offscreen 截图不能替代这些人工验收；全程未使用桌面自动化工具。
