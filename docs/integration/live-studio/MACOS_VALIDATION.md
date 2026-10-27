# 直播助手 macOS 适配与验证

验证日期：2026-10-27。本记录仅描述本次 macOS 构建，不沿用 Windows 联调结果作为 macOS 验收结论。

## 构建与产物

- 构建环境：Intel x86_64、macOS 15.7.4、LLVM 22.1.2、FFmpeg 8.1，Release。
- 重建命令：在聚合仓库根目录执行 `./scripts/build/live-studio-macos.sh`。
- 应用：`livekit-app/out/live-studio-macos-x86_64/package/av_live_studio.app`。
- 源码最低目标为 macOS 14；本机 Homebrew 依赖使本次产物实际要求 **macOS 15.0 及以上**，打包脚本已据此设置 Info.plist。
- 应用包含非系统动态依赖，并完成本地 ad-hoc 签名。未使用 Developer ID 签名或公证。
- [构建说明与平台能力](../../../livekit-app/apps/live-studio/desktop/README.md)。

## 自动化结果

CTest：**6/6 通过，0 跳过**，总耗时 53.91 秒。

| 检查 | 结果 |
| --- | --- |
| studio_media_graph | 媒体图及 Opus 编解码回归通过 |
| studio_engine | 合成、混音、项目覆盖保存与录制通过；H.264/AAC 文件经 ffprobe 检查并完整解码 |
| studio_ui | SDL dummy 无窗口渲染与 1480 × 900 截图生成通过 |
| studio_http | 本地 HTTP fixture 的请求、错误、重定向拒绝、响应大小与超时检查通过 |
| studio_macos_backend | 实际离屏 Metal 与 CPU 合成对照、中文文字、图片方向/透明度、I420 和音频重采样检查通过 |
| studio_ui_retina | 模拟 2x backing buffer，2960 × 1800 截图生成通过 |

已查看普通与 2x 程序内截图：中文、预览和主要控件显示完整。2x 测试是离屏模拟，不代表真实多显示器切换已经验收。

## 打包验证

- `codesign --verify --deep --strict` 通过。
- 检查 29 个可执行文件/动态库路径条目，未发现指向包外的非系统绝对动态库依赖。
- 在 `/tmp` 工作目录运行包内应用，使用独立设置目录、SDL dummy 和软件渲染，完成 60 帧并以 0 退出，生成截图。
- 动态加载日志未出现 `/usr/local/` 或 `/opt/homebrew/` 依赖。
- 构建、CTest、打包、签名和运行日志保存在 `livekit-app/out/live-studio-macos-x86_64/validation/`，其中 `package-verification.json` 保存包检查结果。
- 界面截图位于构建目录的 `studio.png`、`studio-retina.png`；录制探测结果位于 `fixtures/recording-probe.json`。

## 尚未验收

本次未操作用户桌面，未采集真实设备，也未进行容量压测。以下项目需人工或独立环境验证：

- 摄像头、麦克风、屏幕/窗口/系统音频权限与真实采集，监听可听性、回声、热拔插和休眠恢复。
- Keychain 登录持久化、原生文件对话框、Finder 启动、真实 Retina 跨屏行为。
- 真实服务端直播、连麦、PK、网络异常恢复及长时间实时性能。
- Apple Silicon 原生构建与运行；本次只编译验证 Intel x86_64。
- 修改后的 Windows 构建回归。
