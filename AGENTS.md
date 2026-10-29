# 仓库协作约定

## 代码规范

- `livekit-sdk-cpp`、`livekit-app`、`livekit-cpp` 中本项目维护的原生代码遵循 [代码规范](docs/development/coding-standard.md)。

## 音视频流水线

- 后续新增或改造音视频流水线时，尽量优先使用 `GraphEngine`。

## 验证方式

- 不使用 `computer-use` 技能或其桌面自动化工具（包括 `@oai/sky`）操作应用或验证本仓库任务。
- 使用编译、单元/集成测试、无窗口测试及程序内渲染截图进行验证，不操作用户桌面。
- 验证结果应区分自动化检查与实际设备人工验收，不将前者表述为后者已完成。
