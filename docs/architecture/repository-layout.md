# 仓库目录与多业务边界

日期：2026-10-26。本文记录本次目录重构后的入口；能力验收以对应验证记录为准。

## 聚合仓库

六个子模块保持同级：`livekit-app`、`livekit-server`、`livekit-sdk-cpp`、`livekit-cpp`、`graphflow-cpp`、`webrtc`。
`docs/architecture` 维护跨仓库设计；`docs/integration/<业务或能力>` 维护联调、协议和验证。
`scripts/build`、`scripts/run` 分别负责跨模块构建与启动。生成文件放在各仓库的 `out` 中。

## 多业务客户端

```text
livekit-app/
  apps/remote-control/
    desktop/src/
      app/                  启动与窗口循环
      domain/               UI 无关状态快照
      services/             远控会话与 SDK 协调
      infrastructure/       HTTP、Windows 紧急热键
      features/remote_control/  ImGui 交互
    desktop/tests/          无窗口渲染、合成媒体与输入记录 fixture
    web/src/
      app/                  Web 产品入口
      services/             业务 API 请求
      features/remote_control/  控制界面和数据协议
    web/tests/
  apps/screen-cast/          传屏桌面端与 Web 接收端
  apps/conference/desktop/  会议窗口、会话、渲染测试与 macOS 打包
  apps/player/desktop/      本地播放器窗口、会话与无窗口测试
  packages/native/          跨产品 ImGui 与 HTTP 包
  cmake/NativeSDK.cmake      按产品选择 SDK 引擎
```

新产品使用 `apps/screen-cast/<端>` 等目录，与远控产品并列。每个 APP 的端拥有自己的入口、构建、配置和产物；控制/被控、发送/接收属于业务角色，有独立安装包需求时才拆入口。

跨产品复用出现后按语言建立 `packages/native`、`packages/web`；业务内部跨端代码放在 `apps/<业务>/shared`。跨语言共享契约，不强行共享实现。不建立空的移动端、传屏或公共包占位目录。

原生产品仅依赖 SDK 公共头；SDK 不再反向添加客户端工程。桌面端可从客户端根目录或 `apps/remote-control/desktop` 独立配置。Web 构建基路径为 `/apps/remote-control/`。

## 多业务服务

```text
livekit-server/
  cmd/business-api/          参数解析和进程入口
  internal/bootstrap/       配置、业务装配、路由、退出协调
  internal/businesses/remotecontrol/
    domain/                 远控会话持久化模型
    application/            授权、租约、状态转换、持久化端口
    transport/http/         远控请求解析和错误映射
    infrastructure/         远控 SQLite 仓储、媒体权限适配
  internal/platform/media/  不依赖具体业务的媒体管理客户端
  internal/infrastructure/
    database/               数据库连接配置
    http/                   公共 JSON 响应与错误包络
  api/remote-control/       远控 OpenAPI
  migrations/remote-control/ 远控数据库结构，嵌入可执行文件
```

新增传屏业务使用 `businesses/screencast`，自行维护配对、发送端/接收端策略和会话状态机。远控批准和输入权限不进入公共平台模块。业务通过适配器把已授予的权限转换为公共媒体能力；公共媒体客户端不认识远控 Session 或控制角色。

初期仍为 Go + SQLite 模块化单体。领域与用例不依赖 HTTP 或 SQLite；接口由业务使用方拥有。模块拥有自己的业务表和仓储，其他模块不直接读写。身份、项目、设备等公共模块在实现时建立。

远控 API 唯一前缀为 `/api/v1/remote-control/`；静态产品入口为 `/apps/remote-control/`。旧 API 前缀和根网页入口已移除，未知业务 API 返回 JSON 404。Web 目录参数为 `-remote-control-web`。

## 原生 SDK

`include/livekit` 是公共 API。`src/engines/rtc`、`src/engines/player` 拥有会话状态与场景构图；`src/scenarios/remote_control` 拥有 SDK 远控能力。

`src/media_graph` 保留通用有界队列和媒体事件支持；RTC 图登记及实例管理位于 RTC 引擎，通过 `livekit_rtc_graph` 编译。Player 的 FFmpeg 构图归 Player，通用图目标不链接 RTC 或 FFmpeg。

`src/media_nodes` 按 capture、codecs、demux、process、rtc（按需）、render、recording 组织；`src/backends` 放 WebRTC、FFmpeg 和 Windows 适配。现有 FFmpeg 节点仍直接调用底层 API，本轮未改变编解码和线程执行方式。

`src/server_sdk` 和 `LiveKit::ServerSDK` 提供服务管理与 Token 能力，可独立于 RTC/Player 构建。RTC 当前仍复用其中的认证工具。`src/support` 放网络与进程辅助；私有头与实现共置，不再使用 `src/internal/lk`。

SDK 示例保留 `examples/{room_client,web_viewer}`，CLI 位于 `tools/cli`。会议与播放器界面、应用测试、打包入口迁至 `livekit-app/apps/{conference,player}/desktop`；播放器 Windows 构建脚本位于 `livekit-app/scripts`。SDK Player 引擎和底层测试继续位于 SDK，构建入口为 `src/engines/player/CMakeLists.txt`。

独立服务管理构建：`LIVEKIT_BUILD_RTC=OFF`、`LIVEKIT_BUILD_PLAYER=OFF`、`LIVEKIT_BUILD_SERVER_SDK=ON`。
Windows 产品可用 `WEBRTC_PREBUILT_DIR` 复用同一源码、工具链、架构和静态 CRT 的 Release WebRTC 产物；该模式只生成 Release 配置，不支持混用 Debug。

## 媒体服务与基础库

`livekit-cpp/src` 按 app、transport、auth、rooms、rtc、sfu、backends/webrtc、turn、diagnostics 分组；示例配置位于 `config`，C++ 单测位于 `tests/unit`。集成测试运行器继续共用 `tests` 下的 Python/Node 依赖。

GraphFlow 的 core/engine 和 WebRTC 上游源码组织保持原样；只更新平台文档链接。媒体服务和业务服务仍为独立进程。

## 迁移与验证

不提供旧目录、旧脚本、旧构建选项或旧路由的包装入口。调用方、构建源清单、测试资源与文档同步使用新位置。
这是一组跨子模块的工作区修改；提交时须先提交各子模块，再由聚合仓库更新 gitlink，不能仅提交主仓库文档。

验证包括原生编译与 CTest、Go 测试与 vet、Web 编译与协议测试，以及合成媒体/输入记录器端到端测试。不会操作用户桌面；自动化通过不代表实际设备人工验收完成。
