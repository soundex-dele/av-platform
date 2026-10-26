# AV Platform

音视频平台的聚合仓库，用于维护平台架构文档和各模块的固定版本依赖。平台规划包含客户端、SDK、媒体服务和业务服务；SDK 提供传屏、视频会议、远程控制、播放器和剪辑能力。

当前阶段是架构设计与已有模块整合，完整平台和统一 SDK 尚未实现。

## 架构文档

- [目录结构与多业务边界](docs/architecture/repository-layout.md)：客户端按 APP/端组织，业务服务按领域组织，包含重构后的构建与 API 入口。
- [目录重构验证](docs/integration/layout-refactor/VALIDATION.md)：构建矩阵、模块测试、路由隔离与无桌面操作的远控端到端结果。

- [远程协助实现与运行](docs/integration/remote-control/README.md)：浏览器控制 Windows、ImGui 被控端、Go + SQLite 授权服务及无桌面操作的跨仓库验证。
- [传屏首版实施方案](docs/integration/screen-cast/IMPLEMENTATION.md)：Windows 向浏览器一对一传屏的已确认范围、实现规划与验收要求，尚未实施。

- [平台总体设计](docs/architecture/platform-design.md)：仓库职责、跨仓库契约、关键流程、部署和实施阶段。
- 各仓库设计：[客户端](livekit-app/docs/design.md)、[业务服务](livekit-server/docs/design.md)、[SDK](livekit-sdk-cpp/docs/design.md)、[媒体服务](livekit-cpp/docs/design.md)、[GraphFlow](graphflow-cpp/docs/design.md)、[WebRTC](webrtc/docs/av-platform-design.md)。

- [RTC 功能现状与暂停交接](docs/integration/rtc/STATUS_AND_HANDOFF.md)：已实现功能、未完成能力、已知失败、提交记录与恢复入口。
- [RTC 实施规划](docs/integration/rtc/IMPLEMENTATION.md)与[验证记录](docs/integration/rtc/VALIDATION.md)：保留原验收范围和实际测试结果。

- [SDK 架构设计](docs/architecture/sdk-architecture.md)：公共 API、场景引擎、媒体图运行时、媒体节点、线程与生命周期、模块集成和实施顺序。

## 子模块

| 路径 | 定位 | 上游 |
| --- | --- | --- |
| `graphflow-cpp` | 通用图运行时基础，用于节点组织、生命周期与控制事件 | [graphflow-cpp](https://github.com/soundex-dele/graphflow-cpp) |
| `livekit-sdk-cpp` | 现有原生 C++ RTC SDK，作为首个 RTC 后端的基础 | [livekit-sdk-cpp](https://github.com/soundex-dele/livekit-sdk-cpp) |
| `livekit-cpp` | 现有 C++ 媒体服务，用于联调及后续服务端演进 | [livekit-cpp](https://github.com/soundex-dele/livekit-cpp) |
| `webrtc` | 原生 WebRTC 及其 CMake 工程 | [webrtc](https://github.com/soundex-dele/webrtc) |
| `livekit-app` | 客户端应用：ImGui 远控被控端与浏览器控制端 | [livekit-app](https://github.com/soundex-dele/livekit-app) |
| `livekit-server` | 业务服务：Go + SQLite 远控授权服务 | [livekit-server](https://github.com/soundex-dele/livekit-server) |

保留上述同级目录布局，以兼容现有模块对相邻 WebRTC 源码目录的引用。各模块的构建要求和验证范围以模块自己的 README 为准；聚合仓库暂不提供统一构建入口。

业务仓库 `livekit-server` 与 `livekit-cpp` 当前同名媒体可执行文件的区别见总体设计。

## 获取代码

首次克隆主仓库时使用实际主仓库地址，并带上 `--recurse-submodules`。已经克隆主仓库后执行：

```bash
git submodule update --init --recursive
```

递归初始化会同时处理 `graphflow-cpp` 引用的 `utoolkit`。检查固定版本：

```bash
git submodule status --recursive
```

主仓库通过 gitlink 固定各子模块的提交；初始化或更新到主仓库记录的版本不需要使用 `--remote`。

## 更新模块版本

在对应子模块内完成修改、验证和提交，并确保该提交已上传到子模块远程。然后在主仓库记录新的子模块指针，例如：

```bash
git add graphflow-cpp
git commit -m "Update graphflow-cpp revision"
```

主仓库的提交不包含子模块内尚未提交的文件修改。提交涉及模块版本的改动时，应同时检查子模块状态和主仓库的指针差异。
