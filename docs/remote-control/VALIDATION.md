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

运行入口：`livekit-app/web/tests/integration.mjs`。最终证据目录：

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
