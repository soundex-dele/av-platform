# 直播伴侣跨端契约

HTTP 契约见 `livekit-server/api/live-studio/openapi.json`。业务命令返回 JSON；错误为 `{ "error": "code" }`。账号、媒体凭证、PK 计分均由服务端授权。

## 身份与入场

浏览器采用 HttpOnly、SameSite=Strict 会话 Cookie；非本机域名设置 Secure，公网必须通过 HTTPS 部署。桌面使用 `Authorization: Bearer <session>`，登录/刷新请求带 `X-AV-Client: desktop` 才返回 session_token。账号会话与 LiveKit 媒体 JWT 不可互换。

匿名观看会话通过 av_visitor Cookie 标识；匿名踢人只约束该会话，重新建立身份不构成强身份封禁。注册账号可以观看、互动及开播。单账号最多一场活跃直播，全平台首版最多五场。

`POST start` 返回场次 `id`、固定直播间 `room`、owner 和 starting 状态。`POST broadcasts/{id}/connect` 默认取得节目房间凭证；`{"stage":true}` 取得经授权的互动房间凭证。返回 media_url、media_token、participant_identity、role、expires_at。观众不可发布，嘉宾批准后才可进入互动房间。业务服务不接受客户端自报的角色。

媒体 JWT 额外包含 studio_grant。C++ SFU 在普通连接、完整重连、resume 及 validate 入口异步请求同机 admission 接口；未配置、超时、拒绝均失败关闭。刷新 JWT 保留 grant，禁止因刷新而脱离业务授权。用户下麦、封禁、结束直播立即撤销 grant，并将媒体连接清理写入同一事务的持久任务表，提交后执行；失败时由后续请求和周期清理重试，服务重启不丢失。存在待清理任务时不签发该连接的新授权。

## 直播状态

场次状态为 starting、live、reconnecting、ended。主播每三秒发送 connected 心跳，业务服务通过媒体管理 API 检查实际发布轨道后确认 live；超过 60 秒没有有效媒体心跳则结束。presence 仅刷新在线状态，不改变主播发布状态。结束态可继续读取快照，但拒绝新的入场及互动。

节目房间只输出主播的最终合成流；互动房间交换不含远端返回媒体的本地流。嘉宾模式最多四人（主播加三人），PK 模式为两个主播。观众进入节目房间，参与连麦后暂停节目音频并听互动房间，避免重复声音。

## 事件

`GET broadcasts/{id}/events?after=<seq>` 支持 WebSocket；普通 GET 返回最多 200 条。消息为事件数组，每项 `{seq, kind, payload, created}`，seq 为单调递增数据库序号，不要求同房间连续；created 为服务端 Unix 秒。

事件类型包括 broadcast、chat、gift、guest、mute、kick、pk。消息显示使用文本节点，禁止把用户消息插入 HTML。客户端按 seq 去重，断线重连从最后收到的 seq 补取；快照包含 seq、broadcast、viewers、online、guests、pk 和 leaderboard。

聊天 payload 包含 user_id、name、text；礼物包含 user_id、name、points；嘉宾包含 user_id、state；治理事件包含 identity、enabled；PK payload 为完整 PK 快照。事件展示不是业务授权依据。

## 礼物与 PK

送礼命令包含 points 和 request_id，同一账号的 request_id 全局唯一。重复同参返回成功，不再次扣分；不同参同键返回 409。积分余额按 UTC+8 日期计算，每天 100，且不允许负数。扣分、礼物入账及 PK 更新在同一事务完成。

PK 状态为 invited、active、finished、cancelled。仅被邀请方可接受，邀请 60 秒到期；接受时锁定 started 与 deadline=started+300。有效计分区间为 `[started, deadline)`，以数据库事务内的服务端时间为准。分数是场次收到的免费礼物积分。结束计分后同分 winner 为空，否则 winner 为获胜场次 ID。

PK 主动退出判负；30 秒未获得有效媒体心跳判负，双方失联取消。服务重启取消进行中的 PK，保留礼物账本，结束旧直播。客户端不能提交分数或胜负结果。
