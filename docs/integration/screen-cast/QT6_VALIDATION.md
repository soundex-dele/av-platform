# Qt6 双平台改造验证（2026-10-27）

本轮在 macOS x86_64 开发机执行。以下为自动化结果，不代表实际屏幕采集或真实设备验收。此前 Windows/ImGui 验证记录仅属于历史实现。

## 已执行的自动化检查

- Qt 6.11.1 界面独立编译；`QT_QPA_PLATFORM=offscreen` 下普通和 2× DPI 渲染测试通过。
- 输入校验、带空格投屏码、前导零、空显示器列表、重复点击、状态控制、连接中取消、关闭等待、I420 色彩/stride 校验及停止后的旧帧隔离通过。
- Qt 程序内截图覆盖 800×600、1040×720 的六种状态与设置页；最小尺寸选屏布局已根据截图调整并复验。
- Web TypeScript/Vite 构建、两项现有单元测试通过。
- Headless Chromium 在 390、800、1280 宽度下验证等待、过期、错误与模拟播放布局，未发现横向溢出或页面异常。播放布局使用合成画布视频，不是媒体端到端证据。
- Go 投屏业务模块测试通过，并构建独立联调业务服务二进制。
- 新增 ScreenCaptureKit Objective-C++ 源码使用实际构建参数进行独立语法检查，通过。

## 完整应用与运行包

- macOS x86_64 原生应用与合成发送器构建完成，完整 CTest **5/5 通过**：普通/高 DPI 界面、应用运行库、模拟屏幕尺寸与选择规则、会话取消与权限检查。
- 运行包：`livekit-app/out/screen-cast-macos-x86_64/package/av_screen_cast.app`。
- Qt/媒体依赖完整性检查、本地 ad-hoc 签名校验、安装包 `QT_QPA_PLATFORM=offscreen --check-runtime` 均通过。运行检查不会枚举或采集真实桌面。
- 本地运行包实际最低 **macOS 15.0**，由随包依赖决定；源码仍以 14.0 为最低构建目标。构建面向 macOS 14 的发布包需使用兼容该版本的 Qt/媒体依赖。
- 修复并复验了安装组件遗漏、Info.plist 格式、Homebrew Qt 模块库搜索路径以及 offscreen 插件失效符号链接问题。

## 最终链路回归

第三轮完整通过，`evidence.json` 的 `passed` 为 `true`。使用真实 C++ SFU、Go 业务服务、C++ 合成视频发送器及无头 Chromium，覆盖：

- 双会话配对、1280×720 实际解码（每路至少 80 帧）、本地预览、接收端停止和会话隔离。
- 发送端崩溃、发送端主动停止、创建期间取消。
- 媒体服务中断和业务服务中断后的会话收尾。

最终证据：`out/screen-cast/2026-10-27T14-52-21-678Z/evidence.json`，同目录保存日志、截图和二进制 SHA-256。环回候选修正后本轮未复现前一轮的 VPN 路径停帧；不将此结果扩大为所有实际网络环境均已验收。

## 证据位置

- Qt UI：`livekit-app/out/screen-cast-ui/screenshots/`
- Web UI：`livekit-app/out/screen-cast-web-ui/`
- 完整 macOS 构建：`livekit-app/out/screen-cast-macos-x86_64/`

## 集成首次运行发现的问题

首轮已通过 1280×720 双会话实际解码、本地预览、接收端停止、会话隔离与发送端崩溃清理；在发送端定时停止场景超时。原测试按循环次数计时，存在 CPU 负载下的睡眠调度漂移，且退出等待窗口不足以稳定覆盖清理。改为 `steady_clock` 截止时间，并为该 24 秒场景留足清理等待窗口。

首轮证据保存在 `out/screen-cast/2026-10-27T14-42-55-964Z/`，保留失败记录，不将部分场景通过表述为整轮通过。

## 验收边界

- Windows Qt6 应用的构建及运行尚未在 Windows 机器上执行，不能沿用历史 ImGui 通过结果。
- arm64 构建入口已提供，本轮实际构建架构为 x86_64。
- 真实 macOS 屏幕录制授权、权限撤销、Retina/混合 DPI、横竖屏、显示器热插拔、鼠标捕获和两机局域网体验仍需人工验收。
- 未使用 computer-use、桌面自动化或真实桌面采集进行测试；未发布或公证。

## 本机媒体路径修正

第二轮主动停止和创建中取消已通过；后续连接收到 11 帧后停帧，诊断记录显示候选从 LAN 地址切换至本机 VPN 地址。SFU 默认排除环回网卡，而 SDK 已允许环回，因此补齐 SFU `network_ignore_mask=0`，让 localhost 联调具备直接环回候选。该修改不改变信令/API，也不修改系统网卡、VPN 或防火墙。

第二轮证据：`out/screen-cast/2026-10-27T14-47-11-377Z/`。

联调 SFU 构建目录为 `out/screen-cast-sfu-build/`，从仓库 SFU 源码生成测试构建入口 `out/screen-cast-sfu-source/`，复用已编译的同版本 Protobuf 3.21.12 与 WebRTC 静态库；使用 Release / LLVM / libc++，SFU 自身优化级别为 O1。测试使用真实媒体服务，不是媒体模拟器。
