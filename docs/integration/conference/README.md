# AV 会议部署与验收

## 组成与启动

- `livekit-app/apps/conference/desktop`：Qt Widgets 客户端。
- `livekit-server/cmd/business-api`：Go + SQLite 业务服务，新增 `-conference` 开关。
- `livekit-cpp`：媒体服务。会议凭证包含 `conference_grant`，连接/重连时在线校验授权；**必须使用包含会议准入扩展的仓库媒体服务**。官方未扩展的 LiveKit 服务不能满足移出/结束后旧 Token 拒绝的验收条件。

业务服务与媒体服务首版部署在同一主机。媒体准入请求使用 loopback HTTP，并验证独立共享密钥。业务/媒体公网端口通过正常 TLS 入口暴露；客户端设置业务入口地址。媒体 `PublicURL` 必须对参会客户端可达。

```sh
# 两个服务共享以下媒体密钥与会议准入密钥，使用部署环境的随机值。
export LIVEKIT_API_KEY='your-key'
export LIVEKIT_API_SECRET='replace-with-a-random-secret-at-least-24-characters'
export CONFERENCE_ADMISSION_SECRET='replace-with-another-random-secret-at-least-24-characters'
export CONFERENCE_ADMISSION_PORT=8080

# 终端一：媒体配置中的 keys 与上面的媒体密钥一致。
/path/to/livekit-server --config /path/to/media.yaml

# 终端二：在 livekit-server 业务仓库构建、运行。
go build -o out/business-api ./cmd/business-api
./out/business-api -conference -db out/meeting.sqlite \
  -listen 127.0.0.1:8080 \
  -media-api http://127.0.0.1:7880 \
  -media-url ws://127.0.0.1:7880
```

`-conference` 可与 `-live-studio` 同时开启；共享 `/api/v1/auth/` 和账号数据库。启用会议无需启用直播。首次启动按幂等 SQL 创建会议表，不改写已有账号、远控或直播记录。停用会议开关可回退服务入口；保留数据库以便恢复。升级前备份 SQLite 数据库。

## 会议规则

快速会议立即启动，预约仅由创建者启动。游客始终先进入等候室；开启等候室时其他普通成员也需审批。等待者占用 25 人名额，停止轮询两分钟后释放。主持人离线保留身份两分钟，随后转让给最早入会的在线注册成员，没有合适成员则结束。普通成员断线保留两分钟恢复窗口。

锁会阻止新成员，不阻止未撤销会话重连。移出撤销当前账号/游客凭证的会议授权；游客换新身份仍可申请，但须重新审批。会议密码不等于账号密码，不用于识别现实身份。

单会只允许一名共享者。媒体源权限在服务端应用；释放共享时撤销屏幕发布权限和对应旧凭证。主持人静音由媒体 API 执行，邀请开麦由客户端征求本人同意，首版允许成员自行开麦。

API 的 `accepted` 表示持久化接受命令；`operations[].state` 为 `pending/retrying/done`，只有 `done` 表示对应媒体操作已完成。结束会议立即停止凭证签发，媒体清理失败时继续重试。客户端两秒轮询状态，媒体掉线/重连独立由 SDK 展示。

HTTP 契约：`livekit-server/api/conference/openapi.json`。新业务错误使用公共 `error.code/message/retryable` 与 `request_id` 包络；共享认证保留现有直播兼容响应。命令重试复用 `Idempotency-Key`，禁止把客户端角色声明当作权限依据。

## 测试与验收边界

自动化：Go 单元/HTTP 测试与 race 检查；Qt offscreen 截图与组件测试；合成媒体端到端覆盖实际音视频解码、中文聊天、静音、共享权限、重连、移出旧 Token 拒绝和结束清理。

```sh
python3 livekit-app/apps/conference/desktop/tests/run_business_integration.py \
  --client /absolute/path/to/livekit_conference_business_integration \
  --media-server /absolute/path/to/livekit-server \
  --business-server /absolute/path/to/business-api
```

测试报告记录二进制哈希，日志中不记录 Token。程序截图不等于真实设备验收；摄像头/麦克风/录屏权限、扬声器听感、中文输入法候选窗、跨显示器 DPI、Finder/Explorer 启动与实际 25 人网络性能需在目标设备人工验收。

## 交付验证

本机已执行的检查、测试原始结果、截图与未执行的人工项目见 [VALIDATION.md](VALIDATION.md)。macOS 安装包的依赖与无窗口启动可重复检查：

```sh
python3 livekit-app/apps/conference/desktop/tests/verify_macos_package.py \
  livekit-app/out/conference-qt-macos-x86_64/package/livekit_conference_demo.app \
  --report out/conference-package-verification.json
```

实现依据：[Qt QWidget 线程约束](https://doc.qt.io/qt-6.10/threads-modules.html)、[Qt CMake 部署](https://doc.qt.io/qt-6/cmake-deployment.html)。后台只处理 QImage 数据，QWidget 绘制及网络回复处理位于 GUI 线程。
