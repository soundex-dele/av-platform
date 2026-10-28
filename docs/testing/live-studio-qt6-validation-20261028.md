# 直播助手 Qt 6 重写验证（2026-10-28）

桌面窗口、对话框、预览和事件循环已从 SDL2 / ImGui 改为 Qt 6 Widgets。保留 SDK Studio / GraphEngine、Session、项目 JSON 和账号凭证存储。Windows 构建成功；本报告仅记录自动化验证，不代表真实设备或在线业务已人工验收。

## 构建环境

- Windows 11 x64、VS 2022、Release、动态 CRT `/MD`。
- Qt 6.8.3：`D:/Qt/6.8.3/msvc2022_64`。
- WebRTC 复用 `livekit-app/out/conference-qt-windows`，已检查运行库标记；SDK 预编译导入兼容依赖库位于第三方子目录的布局。
- vcpkg `x64-windows`；FFmpeg 7.1；SDK 可选 SDL 播放窗口关闭。
- 构建目录：`livekit-app/out/live-studio-qt6`。

构建目标：`av_live_studio`、`studio_widgets_tests`、`studio_engine_tests`、`studio_graph_tests`、`studio_media_graph_tests`、`studio_publisher_fixture`。

## 检查结果

| 检查 | 最终结果 | 范围 |
|---|---|---|
| studio_media_graph | 通过 | SDK 媒体图 |
| studio_engine | 通过 | CPU/WARP 合成、混音、项目、录制 |
| studio_graph | 通过 | GraphEngine 生命周期与媒体边 |
| studio_ui | 通过 | Qt offscreen 横屏启动及截图 |
| studio_widgets | 通过 | 素材排序、属性、锁定、方向键、中文保存恢复、场景增删、素材对话框、离屏设备隔离、画布切换 |
| studio_widgets_hidpi | 通过 | QT_SCALE_FACTOR=2、1080 逻辑像素宽布局及画布切换 |
| studio_ui_portrait | 通过 | 720 × 1280 节目画布及截图 |
| studio_ui_hidpi | 通过 | 2 倍像素截图 |
| 安装目录离屏启动 | 通过 | 移除 Qt 环境变量、PATH 仅保留 Windows 系统目录，退出码 0，生成截图，无 stderr |
| 脚本及补丁检查 | 通过 | PowerShell 解析、修改的 JS 脚本语法、git diff --check |

完整 CTest 回归先通过 7/8；剩余失败是断言先于异步 GUI 预览刷新。修正测试等待条件后，重新构建并复测 `studio_widgets` 和 `studio_widgets_hidpi`，均通过。最终以上 8 个 CTest 项目均有通过结果，没有将失败的初始运行记作成功。

过程中还修复了素材列表选中后排序/删除按钮未同步启用、Qt offscreen 插件遗漏部署，以及 Windows offscreen 字体目录未设置的问题。程序内生成的横屏、竖屏截图已做视觉检查，中文文字正常。

## 本地产物与证据

- 开发程序：`livekit-app/out/live-studio-qt6/Release/av_live_studio.exe`。
- 已验证安装目录：`livekit-app/out/live-studio-qt6/package/av_live_studio.exe`。整个目录保留 Qt 插件、FFmpeg 和其他动态依赖，不能只复制 EXE。
- 横屏截图：`livekit-app/out/live-studio-qt6/studio.bmp`。
- 竖屏 / 高 DPI 截图：`studio-portrait.png` / `studio-hidpi.png`，位于同一构建目录。
- 最终界面测试日志：`livekit-app/out/live-studio-qt6/Testing/Temporary/LastTest.log`。
- 初始完整回归日志：`livekit-app/out/studio-qt6-tests.log`，保留初始失败，不覆盖为成功日志。
- 安装验证：`livekit-app/out/live-studio-qt6/package-smoke.json`、`package-smoke.png`。
- 配置、构建、安装日志：`livekit-app/out/studio-qt6-*.log`。

## 验证边界

未操作用户桌面，也未枚举或采集真实摄像头、麦克风、屏幕。隐藏模式跳过已存账号并在运行时过滤设备与视频源、关闭音频，保留原项目内容。

本次未执行真实服务器的登录/开播/聊天/连麦/PK 端到端验证，这些按钮仍连接原有 Session API；未重新验收真实设备、音频可听性、跨屏 DPI、容量和音画同步。macOS 的 Qt 构建、部署和设备权限需要在 macOS 上验证。安装验证是在本机现有 Windows/MSVC 运行库环境下执行，未宣称覆盖全新 Windows 系统。
