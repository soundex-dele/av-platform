# Remote-control protocol v1

HTTP 权威契约位于 `livekit-server/api/remote-control/openapi.json`。媒体使用现有 `/rtc` 双 PeerConnection，不启用 `/rtc/v1`。每个批准会话独享房间 `rc_<id>`，仅签发 `host_<id>` 和 `controller_<id>` 两个身份。

## 数据通道

topic 固定为 `av.remote-control.v1`，可靠有序、定向发送，UTF-8 JSON 最大 4096 字节。

控制端公共字段：`v:1`、`grant_id:string`、`epoch:uint64`、`seq:integer`。seq 从 1 单调递增，不超过 JavaScript 安全整数。身份取 SFU 认证后的发送者，忽略业务负载中自报身份；同授权和 epoch 下只接受新序号。

| type | 额外字段 | 行为 |
| --- | --- | --- |
| heartbeat | 无 | 每秒发送；首次握手最多等待 10 秒且受业务租约约束，之后 3 秒无有效心跳停止控制 |
| layout_ack | layout_version | 首次有效心跳后确认当前布局；确认前不执行输入 |
| move | layout_version, x, y | 归一化坐标，范围 [0,1] |
| button | layout_version, x, y, button, down | button 0/1/2 对应左/中/右；布尔按下状态 |
| wheel | layout_version, x, y, delta | 有符号 Windows wheel 单位；范围 ±1200 |
| key | layout_version, code, down | 浏览器 KeyboardEvent.code；支持集合由 SDK 扫描码表定义 |
| text | layout_version, text_id, text | 显式发送 UTF-8 文字；先释放本会话按键/按钮，再输入文字 |
| release | 无 | 释放本会话所有按键/按钮，保持授权 |
| stop | 无 | 释放输入并结束本地授权 |

被控端每 500 ms 发送 `layout`：`v`、`type`、`grant_id`、`epoch`、`layout_version`、`width`、`height`、`active`。布局单调递增；变化时释放已按下输入并等待新 ack。浏览器只采纳宿主认证身份和本授权的消息。浏览器根据实际解码视频区域排除黑边，SDK 将归一化坐标映射到主屏物理像素；macOS 输入后端再转换到 CoreGraphics 的逻辑坐标。原生控制端与网页使用相同的键码、序号和授权校验。

首次握手窗口从本地 `authorize` 开始计时，业务续租不能延长这 10 秒。在首次有效心跳之前拒绝布局确认和全部输入，仅允许认证后的心跳、释放和停止。业务租约先到期则立即终止。收到首次心跳后改用固定 3 秒失联门槛；布局变化不重置为首次握手宽限。网页在 `SignalConnected` 后立即启动可靠心跳，让按需数据通道开始协商，完整媒体连接完成后不重复创建队列。

### 显式文字发送

文字输入沿用业务 `keyboard` 授权范围；被控端的本地批准说明明确包含发送文字，不增加剪贴板或文件权限。

`layout` 增加向后兼容的可选字段 `text_input:boolean` 和 `text_result:{id,accepted,reason}`。只有 `text_input === true` 时网页启用文字输入；旧宿主或未实现文字输入的 `ControlInputSink` 继续支持键鼠，文字控件禁用。SDK 的 `supports_text()` 默认返回 false，自定义 sink 需显式实现文字输入与 `text_release` 清理后才能开启能力。

`text_id` 是每个授权内单调递增的正安全整数，与通道 `seq` 分开。文字仍需通过认证身份、可靠通道、授权/epoch、租约、序号和当前布局确认。拒绝重复 ID，避免使用新 seq 重复输入。通过这些门槛后，即使内容不合法或 sink 不支持，也消费该 text_id 并返回拒绝结果；不能以同一 ID 重试。

文字必须是严格合法 UTF-8，每次 1–256 个 Unicode 标量、最多 1024 字节。允许制表符、CR、LF；拒绝其他 C0/C1 控制字符、代理码点及无效编码。网页将 CRLF/CR 统一为 LF；Windows 使用 `KEYEVENTF_UNICODE` 下发 UTF-16，换行转 CR，CRLF 只输入一次，表情等补充平面字符保留代理对。发送前释放本会话仍按下的修饰键和鼠标按钮，不读取或覆盖任何剪贴板。

状态中的 `text_result` 重复报告最近一次文字请求结果，初始 id 为 0。`accepted:true` 只说明输入 sink 接受了整次输入，**不保证目标应用或输入框接收了文字**。状态不回显文字正文。拒绝原因包括 `invalid_text`、`unsupported`、`input_failed`；输入失败会停止授权，若连接先结束，控制端可能收不到最后的失败结果。Windows 部分注入后若有未配对的 Unicode key-down，会在停止后继续尝试释放，在清理成功前拒绝新授权；绝不重发文字正文。

网页一次只允许一个未确认请求，必须先点击远程画面选择目标，然后显式点击发送；输入框内 Enter 保留为换行。等待期间禁用发送和新的画面点击，收到匹配结果后才结束等待，成功时清空草稿。5 秒无确认则停止连接并提示“结果不确定”；断线、超时不自动重发，结束连接清除草稿。窗口失焦、页面隐藏或布局改变后，需要重新点击目标。文字发送不等同于远程 IME、剪贴板同步或文件传输。

鼠标移动发送前合并到最新位置，最高约 30 Hz；按钮自带位置，移动/按键/按钮共用可靠序列。Web 队列最多 256 条，单次发送最多等待 2 秒；被控输入队列最多 256 条。失败或超限结束控制，不允许丢掉 key-up 后继续运行。

公开 SDK：`RemoteControlSession::authorize/renew/set_layout/receive/tick/stop/status`，输入执行接口为 `ControlInputSink`。默认启用独立 watchdog；测试可禁用自动线程并传入确定性的单调时间。公共头文件不暴露 Windows、WebRTC 或 SDL 类型。

## Qt 桌面与平台适配

Qt 桌面控制端沿用上述 HTTP 和数据通道契约，没有新增服务端端点或迁移。控制端只显示认证宿主拥有的解码视频轨道；控制队列保持有界，失焦释放输入，布局变化清除待发输入并重新握手，停止丢弃未发送文字。

SDK 新增 `make_platform_control_input()` 与 `control_permissions()`，已有 `make_windows_control_input()` 保持可用。macOS 的平台输入工厂使用 CoreGraphics，屏幕采集使用共享 ScreenCaptureKit 后端；权限查询不会弹窗，申请权限仅由 Qt 本地按钮发起。`primary_control_layout()` 返回主屏物理尺寸，输入后端处理 Retina 缩放。Qt 类型不会进入 SDK 公共头文件。

最小化被控窗口不再撤销授权，托盘提供持续状态和急停入口；关闭主窗口或退出仍先停止本地输入，再尽力撤销业务授权。权限失效、锁屏、注销和采集失败终止会话，不尝试绕过权限或恢复旧授权。
