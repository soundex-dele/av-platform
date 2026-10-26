# Remote-control protocol v1

HTTP 权威契约位于 `livekit-server/api/remote-control/openapi.json`。媒体使用现有 `/rtc` 双 PeerConnection，不启用 `/rtc/v1`。每个批准会话独享房间 `rc_<id>`，仅签发 `host_<id>` 和 `controller_<id>` 两个身份。

## 数据通道

topic 固定为 `av.remote-control.v1`，可靠有序、定向发送，UTF-8 JSON 最大 4096 字节。

控制端公共字段：`v:1`、`grant_id:string`、`epoch:uint64`、`seq:integer`。seq 从 1 单调递增，不超过 JavaScript 安全整数。身份取 SFU 认证后的发送者，忽略业务负载中自报身份；同授权和 epoch 下只接受新序号。

| type | 额外字段 | 行为 |
| --- | --- | --- |
| heartbeat | 无 | 每秒发送；3 秒无有效心跳停止控制 |
| layout_ack | layout_version | 确认当前布局；确认前不执行输入 |
| move | layout_version, x, y | 归一化坐标，范围 [0,1] |
| button | layout_version, x, y, button, down | button 0/1/2 对应左/中/右；布尔按下状态 |
| wheel | layout_version, x, y, delta | 有符号 Windows wheel 单位；范围 ±1200 |
| key | layout_version, code, down | 浏览器 KeyboardEvent.code；支持集合由 SDK 扫描码表定义 |
| release | 无 | 释放本会话所有按键/按钮，保持授权 |
| stop | 无 | 释放输入并结束本地授权 |

被控端每 500 ms 发送 `layout`：`v`、`type`、`grant_id`、`epoch`、`layout_version`、`width`、`height`、`active`。布局单调递增；变化时释放已按下输入并等待新 ack。浏览器只采纳宿主认证身份和本授权的消息。浏览器根据实际解码视频区域排除黑边，SDK 将归一化坐标映射到主屏物理像素。

鼠标移动发送前合并到最新位置，最高约 30 Hz；按钮自带位置，移动/按键/按钮共用可靠序列。Web 队列最多 256 条，单次发送最多等待 2 秒；被控输入队列最多 256 条。失败或超限结束控制，不允许丢掉 key-up 后继续运行。

公开 SDK：`RemoteControlSession::authorize/renew/set_layout/receive/tick/stop/status`，输入执行接口为 `ControlInputSink`。默认启用独立 watchdog；测试可禁用自动线程并传入确定性的单调时间。公共头文件不暴露 Windows、WebRTC 或 SDL 类型。
