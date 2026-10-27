# AV 会议验证记录

日期：2026-10-27。环境：macOS x86_64、Qt 6.11.1、Homebrew LLVM 22、仓库 WebRTC x86_64 预编译库。GUI 为 Qt Widgets，验证使用 offscreen 与 QWidget::render()，未使用桌面自动化，未访问摄像头、麦克风或显示器捕获设备。

## 自动化结果

| 检查 | 结果与范围 |
| --- | --- |
| macOS 安装包 | Qt 与媒体动态库收集、依赖修复、ad-hoc 签名完成；`codesign --verify --deep --strict`、包内依赖检查、4 秒 offscreen 启动均通过，运行时未加载 Homebrew 动态库 |
| C++20 / Qt 编译 | 会议应用、Qt 测试、业务/媒体集成客户端、音频设备边界测试均编译成功 |
| CTest | 3/3 通过：conference_chat、conference_audio_devices、conference_widgets |
| Qt Test | 8 项（含初始化/清理）通过，覆盖登录 → 快速入会、九位会议号表单、等候室、25 人分页、共享优先与成员离开、权限/错误状态、过期 HTTP 响应取消、媒体连接取消不阻塞 GUI |
| 视频转换 | 奇数宽高、I420 步长与颜色、等比显示、九路 640×360 最新帧批次、刷新期间事件循环响应、缓存清理 |
| Go | `go test ./...` 通过；conference、identity、livestudio 的 `-race` 通过；`go vet ./...` 通过 |
| 业务规则 | 游客审批、凭证撤销、权限、密码、预约 UTC、九位会议号冲突重试、25 人并发容量、幂等、历史范围、结束与凭证并发、主持转让/超时、共享互斥、清理串行、重启后媒体命令重试 |
| 直播兼容 | 原 livestudio 包测试与共享认证注册/登录/刷新/改密/退出测试通过 |
| 原生媒体全链路 | 隔离 Go 业务服务 + 本仓库 C++ SFU + 无硬件 SDK 客户端通过；实际解码合成视频和非静音音频、中文可靠聊天、主持人静音、共享源授权/撤销、重新连接、移出后的旧 Token 拒绝、结束清理及旧 Token 拒绝 |

原生媒体报告：[media-integration.json](results/media-integration.json)，记录本次三个二进制的 SHA-256。运行目录：`out/conference-integration/20261027-225411`，包含客户端与隔离服务日志。测试使用独立 SQLite 数据库和端口，结束时停止测试服务。

安装包验证：[package.json](results/package.json)。交付包位于 `livekit-app/out/conference-qt-macos-x86_64/AV-Meeting-macOS-x86_64.zip`；应用本体位于同目录的 `package/livekit_conference_demo.app`。安装规则包含 offscreen 插件，支持不操作桌面的复验。

原始自动化结果：[CTest](results/ctest.txt)、[Go 全量测试](results/go-test.txt)、[Go race](results/go-race.txt)。WebRTC 的 libaom 汇编对象产生已有的 macOS 平台 load command 链接警告；本次编译与原生媒体运行均成功。

## 程序渲染截图

截图覆盖普通窗口、窄窗口、长中文、等待与错误状态，各有 1×、2× 输出。这里的 2× 是 QImage devicePixelRatio 渲染检查，不等于真实显示器切换验收。

- [首页](screenshots/home-1x.png) / [2×](screenshots/home-2x.png)
- [等候室](screenshots/waiting-1x.png) / [2×](screenshots/waiting-2x.png)
- [25 人会议第一页](screenshots/meeting-1x.png) / [2×](screenshots/meeting-2x.png)
- [窄窗口分页](screenshots/meeting-narrow-1x.png) / [2×](screenshots/meeting-narrow-2x.png)
- [连接错误](screenshots/meeting-error-1x.png) / [2×](screenshots/meeting-error-2x.png)

## 构建与运行复现

本机首次验证使用独立客户端工程，构建目录为 `livekit-app/out/conference-qt-macos-x86_64`。根工程预设的源码目录不同，复用前请选择新的 `-B` 目录，避免 CMake 缓存来源冲突。新环境按客户端 README 的 Qt 预设构建。

```sh
QT_QPA_PLATFORM=offscreen ctest --test-dir livekit-app/out/conference-qt-macos-x86_64 --output-on-failure
(cd livekit-server && go test ./...)
python3 livekit-app/apps/conference/desktop/tests/run_business_integration.py \
  --client "$PWD/livekit-app/out/conference-qt-macos-x86_64/Release/livekit_conference_business_integration" \
  --media-server "$PWD/livekit-cpp/out/conference-macos/livekit-server" \
  --business-server "$PWD/livekit-server/out/conference/business-api"
```

## 尚未执行的目标平台与设备验收

Windows MSVC x64 和 macOS arm64 已提供构建/部署配置，本机未执行对应平台编译或运行。Windows 需匹配的动态 Qt、`/MD` WebRTC/媒体依赖，并使用新构建缓存；不能把本次 Intel Mac 结果视为 Windows/ARM 通过。

中文输入法实际候选窗、摄像头/麦克风/录屏/本地网络权限、真实摄像头切换、扬声器听感与回声、Finder/Explorer 启动、跨屏缩放和真实 25 人网络压力仍需人工验收。当前测试验证 25 人业务/界面状态和九路可见图像处理，不声称完成 25 台设备性能验收。发布还需要分发者的正式签名及 macOS 公证。
