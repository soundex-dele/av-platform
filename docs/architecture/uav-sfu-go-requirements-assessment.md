# 无人机音视频 SFU：Go LiveKit 版本需求评估报告

评估日期：2026-10-27（北京时间）。

**当前验收口径**：用户已确认只需模拟测试，不要求真机实测。见 [34 项模拟验收结果](../testing/uav-sfu-go-cpp-simulation-acceptance.md)，其中已有通过项；下文及历史报告的真机条件不再作为本轮门槛。

最新复测：见 [2026-10-28 严格传输策略与完整 34 项复测状态](../testing/uav-sfu-go-cpp-revalidation-20261028.md)。该轮继续使用 Go 服务端和原生 C++ SDK，新增客户端 UDP/TCP 强约束、负向测试及并行媒体场景；完整需求仍有未通过和未测项。

后续已按用户授权完成本机测试及部分修复：见 [Go SFU + C++ SDK 验证与修复报告](../testing/uav-sfu-go-cpp-validation-report.md) 和 [34 项测试说明](../testing/uav-sfu-go-cpp-tests.md)。服务端使用 `D:/workspace/livekit`，媒体客户端使用本工作区的 C++ SDK。

**阅读口径：下文保留修复前的源码评估和最初执行记录，作为问题基线。当前执行结果、已修复默认统计周期及 SDK 编解码能力以验证与修复报告为准；本机自动化不代表实机或 34 项完整验收通过。**

- 需求基线：`D:/workspace/sdk/无人机音视频 SFU 需求说明.md`，V1.11，共 34 项需求。
- 评估对象：`D:/workspace/livekit`，Go LiveKit Server，提交 `a390d03d28c895742d9b13c0894880ee67733801`；评估开始时 Git 工作区无修改。
- 本报告独立于 [C++ 版本评估](uav-sfu-requirements-assessment.md)，不把 C++ 版本的能力或测试结果算到 Go 版本。
- 本次仅新增报告，未修改 Go 服务端、需求文档或原 C++ 评估报告。

## 1. 结论

**Go 版本比当前 C++ SFU 更接近这份需求，建议优先作为无人机媒体服务的实现基础；但当前代码和默认配置仍不能直接判为完整满足 V1.11。**

已有可复用实现包括：H.264/H.265 的协商与视频转发、多参与者音频、多轨发布和独立订阅、订阅需求聚合、备用编码回退、直接 ICE-TCP、NACK/RTX、PLI 限频、带宽分配、房间/轨道权限、重连状态、节点选择及监控。无需像 C++ 版本一样先从 VP8 扩展出完整 H.264/H.265 服务端路径。

最需要落实的事项：

1. **实时 UDP、回放 TCP 的强制分流。** Go 版有真正的直连 ICE-TCP，不需要 TURN；但传输选择不是逐视频轨道的业务开关。必须分开媒体连接，采用不同配置的媒体实例，或开发按参与者/连接生效的传输策略。
2. **H.265→H.264 全体回退。** 已有 `REGRESSION` 机制可复用，不能误选只给不兼容观看者补发另一编码的 `SIMULCAST` 模式。仍须接通机载发布者指令、首位观看者能力决策、旧观看者解码及重连后的状态。
3. **Q-06 发送节奏及有界队列。** 当前默认发送路径是 `PassThrough`；可选 `NoQueue` 实际有可增长队列，未见硬上限/TTL。`leaky-bucket` 在当前接线中会回退到 `NoQueue`，不能把类名或配置名当作需求已满足。
4. **Q-07 视频 FEC。** 有 Opus 带内 FEC 协商和音频 RED 基础，但当前核查未发现视频 FEC 完整协商、恢复和生成路径。协议包里存在 FlexFEC 常量不能算视频 FEC 已交付。
5. **端侧及业务闭环。** 机载 Linux ARM64 的采集、硬编、AEC/混音、TCP 主动连接，以及 Android/iOS/Web 业务端都需要单独交付。Go SFU 不替代这些模块。
6. **验收证据。** 1 s 全链路统计、严格多维准入、目标编码/协议的 P95 时延、容量和 8 h 长稳仍须实施与验证。

总体可行，主要风险集中在目标端 ICE-TCP/H.265 兼容、机载硬件反馈、pacing/队列和视频 FEC。不能提前承诺最大路数、所有手机兼容或完整时延达标。

## 2. 版本和评估口径

本地源码的 `version/version.go` 写着 `1.13.10`，但 `go.mod` 要求 Go 1.26.0，依赖中有 2026-10 的伪版本，还通过 `replace` 使用 LiveKit 的 Pion fork：

| 依赖 | 本地锁定版本 |
| --- | --- |
| protocol | `v1.53.1-0.20261021070436-f09f87aab29b` |
| mediatransportutil | `v0.0.0-20261014192331-dd8e31a0adc0` |
| webrtc-pion/v4 | `v4.2.18-warp.7` |
| ice/v4 | `v4.4.0-warp.3` |
| dtls/v3 | `v3.1.5-warp.3` |

**应按本地提交和依赖锁定交付，不应把它笼统等同于任意公开发行的 1.13.10 二进制。** WARP 属于代码中的实验能力，默认关闭，本需求无需启用。

结论基于实际实现、配置入口、缓存中锁定依赖源码及已有测试用例审阅。下文“已有基础”表示发现对应实现，**不表示完成无人机实机验收**。正式结果仍按需求使用“通过／未通过／未测／不适用”；本次不将完整端到端需求记为通过。

架构约束始终为：**无 TURN、客户端直连 SFU、实时视频两段 UDP、回放视频两段 TCP、多人全双工共享语音、仅实时视频进行 H.265/H.264 回退。** 不新增云端录像、文件检索、MCU 或跨节点无缝迁移要求。

## 3. 34 项需求逐项评估

| 编号 | 工程状态 | 当前依据及剩余工作 |
| --- | --- | --- |
| V-01 多摄像头独立发布与稳定识别 | 多轨基础已有，端侧映射待补 | Participant/MediaTrack 支持多轨与标识；业务需定义持久 deviceId/cameraId 和发布代次，不能把重建后的 SID 当物理摄像头身份。机载热插拔、枚举变化和重连映射另验。[G3] |
| V-02 多用户独立观看 | 已有核心基础 | 同一接收源分发多个 DownTrack，订阅按参与者维护，正常情况下同一编码层不需每个观看者重复上传。需按 H.265/H.264 及混合负载验证。[G3] |
| V-08 聚合订阅需求控制机载发布 | 已有较完整聚合基础 | dynacast 按所有订阅者及节点聚合最大质量，处理 OFF、延迟暂停和编码回退；仍需发布端响应订阅质量消息并启停真实摄像头/编码器。不是 SFU 单方面停下行就算关闭机载上传。[G4] |
| V-11 Web 多架无人机并发观看 | 底层可支持，应用待交付 | 可按设备建立逻辑房间，Web 多 Room 并行选轨并标识来源。官方 SDK 接口可作为实现基础，但本服务端仓库不包含完整无人机 Web 产品；实际并发解码和授权需验收。[G3][G10] |
| V-12 实时 H.265→H.264 全体回退 | 已有专用机制，仍需端到端适配 | H.264/H.265 路径及 REGRESSION 已有；备用流到达后能挂起原编码并迁移原订阅。需指定 H.264 备用、强制正确策略、首位观看者决策、机载执行和所有端实际解码。PREFER_REGRESSION 受人数阈值影响，不能当恒定保证。[G2][G5] |
| V-13 实时视频两段 UDP 直连 | 可配置基础已有，产品分流待实现 | UDP 实时实例可关闭 TCP 监听、禁止 TCP 回退、禁用内外部 TURN；设备和每个观看者实际选中 UDP 后才算满足。共享实例按轨道任意选择协议的业务能力未发现。[G6] |
| A-01 多人全双工 | SFU 核心基础已有，端侧待验 | 多参与者分别发布/接收 Opus，SFU 转发而不混音。至少无人机+两名用户同时说话，验证用户互听、多路解码混音、最终播放参考 AEC 和每条有向音频链路时延。[G3][G10] |
| A-02 多人加入与独立成员管理 | 已有核心基础 | 房间多成员、人数限制、订阅管理和移除 API 可复用；补无人机业务加入授权、容量提示与单成员故障不影响其他人的验证。不需要独占锁或私有音频房间。[G3][G10] |
| B-01 设备回放流接入 | 有通用媒体接入，目标用例待验 | SFU 不要求媒体来自摄像头，可接设备生成的回放 RTP。优先验证回放发布者经直接 ICE-TCP 接入及三端 ICE-TCP 播放；外部模块负责读文件、节奏、时间戳和编码兼容。[G2][G3][G6] |
| B-03 多回放会话独立转发 | 多轨基础已有，业务映射待补 | 不同进度用不同 streamId/playbackSessionId/publishEpoch，独立轨道/连接生命周期；seek/倍速由设备端处理。需验证一路变化不影响其他回放、实时及语音。[G3] |
| B-04 同回放源多人分发 | 已有核心转发基础，TCP 慢端待验 | 一源多 DownTrack 可复用，设备不需按观看者重复发布。TCP 慢连接是否阻塞共享路径、队列增长及端侧恢复仍是专门验收项。[G3][G7] |
| B-07 回放视频两段 TCP 直连 | 有直接 ICE-TCP 基础，尚未整体验收 | 底层有 TCP 监听、被动候选、TCP mux 与 ForceTCP；可单独部署 TCP 回放实例。机载和观看端必须支持主动 ICE-TCP，并与实时使用不同连接；当前代码对 Go 客户端明确标记不支持主动 ICE-TCP。[G6] |
| N-02 弱网优先音频/主画面 | 部分实现 | 带宽分配和视频优先级已有，默认 allow_pause=false；补主辅画面映射、音频预算/不可用提示、机载上行协调。不能把单层摄像头伪装成 SCREEN_SHARE 来获得优先级，其分配逻辑可能豁免限流。[G7] |
| Q-01 带宽估计与拥塞控制 | 已有机制，配置与端侧闭环待验 | 上行反馈和下行 REMB/TWCC、send-side BWE 路径已有；默认下行不是 TWCC send-side BWE。可选择并验证 TWCC 路径或目标端有效的等效机制，硬编码器目标/实际码率及帧率分辨率响应仍在机载端。[G7] |
| Q-02 NACK/RTX 与有界重传 | 部分满足 | 有缓存、NACK/RTX、次数/寿命边界；缓存包数可配，但部分重试/时间参数仍为默认或常量（如下行 maxAck=3）。需接出完整配置、验证每段重传预算与恢复效果；TCP 不免除所采用 RTP 栈的适用要求。[G8] |
| Q-03 PLI/关键帧恢复 | 已有较完整基础 | 按源层发送 PLI，并有可配置低/中/高质量限频及统计，RTCP 协商含 FIR 能力。实际 FIR 使用、多人同源限频及 H.265/H.264 恢复需联调验证。[G8] |
| Q-05 独立订阅质量控制 | 已有主要基础 | 每观看连接分配预算、每 DownTrack 选层/暂停，默认单层摄像头可进入管理逻辑；需开启/验证不足时暂停，确保弱观看者不压低共享源或拖住其他观看者，TCP 另验。[G3][G7] |
| Q-06 pacing/队列/缓冲 | 明确缺口 | 默认 PassThrough 不按目标码率平滑发送；NoQueue 是异步可增长队列，SetBaseCap(512) 是初始容量而非上限；leaky-bucket 配置当前回退 NoQueue。需接入与 BWE 联动的真正 pacing、有界队列/TTL、完整帧和依赖恢复、TCP 写入超时。[G7] |
| Q-07 Opus PLC/FEC 与视频 FEC | 音频有基础，视频缺口 | Opus fmtp 包含 useinbandfec=1，支持音频 RED 转换/转发；PLC/FEC 恢复仍由终端验证。未发现视频 RED/ULPFEC/FlexFEC 的完整媒体实现，必须补齐或选经目标端验证的可用实现，不能以 RTX/音频 RED 代替视频 FEC。[G9] |
| Q-08 默认 1 s 全链路质量 | 部分实现 | RTPStats、连接质量、Prometheus/telemetry 已有；默认节点统计约 2 s、连接质量更新 5 s、telemetry 汇总 30 s，不是完整 1 s 端到端采样。补设备/流/成员/方向关联、客户端解码冻结/音频中断及重连增量基线。[G11] |
| N-01 视频/音频 P95 时延 | 未测 | 无本需求负载下实时 UDP、回放 TCP 各 ≤500 ms 和多人音频各有向链路 ≤300 ms 的证据。TCP 缓冲/重传与端侧播放必须计入。[G13] |
| N-06 首帧/加入语音耗时 | 未测 | 无首帧 P95 ≤2 s、加入到双向可听 P95 ≤3 s 的目标设备统计；分别测首位和后加入、直接 TCP 建连、编码回退后的恢复。[G13] |
| P-02 接入容量 | 未测 | 固定扇出后增独立源，按 H.265 720p30/2 Mbps，实时/回放共同计配额，固定多人音频负载；不能引用宣传路数。[G13] |
| P-03 转发订阅容量 | 未测 | 固定源数和分布增订阅，单列 UDP/TCP/混合与 H.264 回退，记录切换峰值、音频扇出、PC/TCP 连接；未触边界只报告至少支持 N 路。[G13] |
| P-10 候选最高负载 8 h | 未测 | 无此次指定配置的 8 h 资源与质量报告；需记录单核/线程、pps、队列、内存增长、TCP 积压和重传。[G13] |
| P-11 配额/过载保护 | 已有较多基础，未完全覆盖 | 有节点总轨道/总字节率、每参与者音视频订阅上限、房间人数和节点选择限制；仍需源/订阅分开、连接/总缓存预算，以及已入房动态发布/订阅的严格准入。默认零限额与异步统计不能当安全边界。[G12] |
| V-04 单摄像头故障隔离 | SFU 有分轨基础，机载待验 | 独立 Receiver、撤轨和流状态可复用；机载捕获/硬编异常不能导致整进程或所有媒体重连。需审查 reconnect_on_publication_error 等策略并验证拔插/无帧超时。[G3][G14] |
| A-05 成员退出/异常清理 | 已有生命周期基础，业务待补 | 有断连清理、权限更新和移除；补业务授权失效后正在进行的音频撤权，并仅影响该成员。若视频/语音共用参与者，退出语音不应无条件踢掉仍合法观看的视频成员。[G10][G14] |
| A-06 幂等/成员代次隔离 | 部分实现 | identity、ParticipantID/版本和重连基础可复用；业务加入 requestId/memberId/connectionEpoch 仍需定义。按 identity 发迟到的移除操作可能作用于新会话，不能据重复 identity 处理宣称业务代次安全。[G10][G14] |
| B-06 中断/结束/重新发布 | 通用生命周期已有，回放语义待补 | 有轨道停止/重发、流状态和重连处理；补实时/回放类别、EOS/故障原因、稳定 streamId 与新代次，验证不误接旧流。[G3][G14] |
| N-04 网络变化恢复 | 服务端有基础，直连策略待定 | 已有 ICE restart、重连与失败回退机制；本项目必须禁止实时自动转 TCP、禁止 TURN，回放重连坚持 TCP。超期语音重新授权；客户端恢复和源进度另验。[G6][G14] |
| N-05 节点故障重建 | 有分布式/节点基础，端到端待验 | Redis 路由、节点可用性、房间分配和重连可复用；不能承诺媒体连接无缝迁移。补业务幽灵成员清理、发布/订阅重建及回放源恢复。[G12][G14] |
| N-08 长时运行/机载资源 | 未测 | 需在目标板/手机与服务端共同测 8 h，记录硬编通道、温度、功耗、多音轨混音/解码及资源回收。Go 服务端 ARM64 编译支持不能替代机载验收。[G13] |
| N-09 可观测与追溯 | 已有较好基础，业务关联待补 | 有房间/参与者/轨道日志、RTPStats、Prometheus 和事件；补 deviceId/cameraId/playbackSessionId 映射、终端质量接入与看板，和 Q-08 共用统计管线。[G11] |

## 4. 关键实现方案

### 4.1 UDP 实时和 TCP 回放：优先验证两个媒体实例

Go 版与原 C++ 评估最明显的不同是：**已有服务端被动 ICE-TCP 监听和 TCP-only 底层配置，可优先复用 WebRTC 回放，不必一开始就新建 WSS/MSE 回放协议。**

锁定依赖 `mediatransportutil/pkg/rtcconfig` 中，`ForceTCP` 会跳过 UDP network types，`TCPPort` 创建 `net.ListenTCP` 和 ICE TCP mux；Go 服务端显式 `DisableActiveTCP(true)`，由客户端主动拨入。这是客户端直接访问 SFU 的 ICE-TCP，不是 TURN/TCP，也不是信令 TCP。

较少修改核心传输的候选方案：同一台服务器先启动两个独立媒体实例，也可以后续部署为两个池。

| 实例 | 承载内容 | 传输约束 | 客户端连接 |
| --- | --- | --- | --- |
| 实时实例 | 实时视频及多人语音 | 仅开放媒体 UDP，关闭 TCP 媒体监听和自动回退，禁用 TURN | 机载和观看者建立实时 Room/PC |
| 回放实例 | 设备发布的回放视频 | ForceTCP，仅开放 ICE-TCP 媒体监听，禁用 TURN | 机载和观看者建立独立回放 Room/PC |

配置片段仅说明源码中可用开关，**不是已测试部署文件**；还需独立信令端口、API 密钥、可达公告地址和网络配置：

```yaml
# 实时实例（单独配置文件）
rtc:
  tcp_port: 0
  force_tcp: false
  allow_tcp_fallback: false
  allow_udp_unstable_fallback: false
  turn_servers: []
turn:
  enabled: false
```

```yaml
# 回放实例（另一个配置文件）
rtc:
  tcp_port: 7881
  force_tcp: true
  allow_tcp_fallback: false
  allow_udp_unstable_fallback: false
  turn_servers: []
turn:
  enabled: false
```

注意以下限制：

- `force_tcp` 在依赖中注释为测试用途，应作为需生产验证的实现入口；必须验证双 PeerConnection/单 PC 模式、重连和目标端，不仅检查 YAML 可解析。
- 两个实例若使用 Redis 调度，必须确保房间不能分配到错误传输池。初版可用独立部署/路由域和明确 API 地址；只给房间不同名字不能隔离普通节点调度。业务层关联 deviceId，不把实时和回放误建成同一共享传输。
- 若要求单进程混合承载，可在 transport 创建前根据服务端授权的业务模式设置每连接 network types/候选过滤。已有 `SetPreferTCP` 可参考，但还需 UDP-only 对称策略、不可篡改的模式、初次连接和重连一致性；不是给轨道添加 TCP 字段。
- 同一个 BUNDLE 媒体传输上的多轨不能分别宣称 UDP 与 TCP。机载发布端和所有观看端都必须拆连接，不能只拆 SFU 的一侧。
- ICE-TCP 媒体端口直接暴露给客户端，不能当普通 HTTPS/WSS 端口置于 HTTP 代理或 TLS 终止后；WebRTC 自身仍有 DTLS-SRTP 加密。信令可以独立使用 HTTPS/WSS。
- 本地 `ClientInfo.SupportsICETCP()` 对 Go SDK 返回 false，注释说明不支持 active TCP。服务器采用 Go 不等于发布者也必须用 Go；优先选择并验证支持主动 ICE-TCP 的机载原生客户端。Android/iOS/Web 同样需按实际 SDK/浏览器版本验证，不能单看服务端能力判断。

若目标端无法使用 ICE-TCP，再评估直接连接 SFU 的独立 TLS/TCP 回放模块（Web 侧 WSS+MSE/WebCodecs 等），保持一源多订阅、认证、有界缓冲和原样编码内容。该备选会增加协议/播放适配，不能靠 TURN 解决，也不能通过上行 RTMP/TCP、下行 WebRTC/UDP 声称双段 TCP 合格。

两实例的容量和网络开销必须一起报告；同一台机器上的两个实例不是两份独占硬件，不能直接相加各自压测最大值。

### 4.2 H.265/H.264 回退：复用 REGRESSION，避免混淆多编码并发

代码中默认 codec 列表已包含 H.265/H.264，buffer 解析相应关键帧/尺寸，Forwarder 有相应路径。`MediaTrack` 区分备用编码策略：

- `SIMULCAST`：允许不同观看者接收不同编码；不保证原 H.265 观看者统一切为 H.264。
- `REGRESSION`：指定备用编码流到达后可触发原编码挂起、Receiver 回退、原 DownTrack 转移及 dynacast 状态迁移，方向符合 V-12。
- `PREFER_REGRESSION`：是否回退取决于房间条件。本地默认 `CodecRegressionThreshold=5`，helper 使用参与人数判断，人数增长可能改变选择；不能用它代替“只要有不兼容观看者就回退”的硬要求。

建议实时源显式声明主 H.265、备用 H.264，采用 REGRESSION，并核实没有禁用 regression 或强制 simulcast 的策略覆盖。机载端响应 `SubscribedQualityUpdate` 等信令启动 H.264、请求关键帧并停止不再需要的 H.265 编码。若机载 SDK 不支持备用编码发布消息，需补适配或使用业务控制协议。

服务端现有回退触发点包含“收到备用编码”，不等于已经完成所有验收：

1. 首位观看者不支持 H.265 时，业务需在首次启动源前完成能力判断并直接发布 H.264，避免先发布 H.265 再切。
2. 已有 H.265 观看者必须实际收到并解码 H.264；DownTrack 对不支持 codec change 的端会关闭并走重新协商，需验证自动恢复与错误处理。
3. H.264 参数集/profile/packetization-mode 必须与各端相容，媒体就绪要检查关键帧和真实解码，不能仅见备用 RTP 就宣称播放成功。
4. 重连、源重新发布时保留有效观看者能力集合，仍有 H.264-only 观看者不得重新启动为 H.265。旧代次回调不能改变新源策略。
5. 回放不套用实时 regression 规则。设备需提供目标端能解码的回放源，SFU 不自动转码录像。

当前实现注释只支持向备用编码回退，不自动升级；需求并不要求所有不兼容观看者离开后立即升回 H.265，因此可保持 H.264。现有 dynacast regression 单测主要用 AV1→VP8 举例，不能当 H.265→H.264 真机播放证据。

### 4.3 多人语音：保留 SFU，端侧完成混音

按一架无人机一个逻辑语音会话组织，用户均可发布并听取其他参与者。每个音频源在 SFU 独立转发，端侧解码/混音和 AEC；无需服务端混音、唯一发言者锁或私有音频通道。共享语音仍需设备/会话授权，不代表允许匿名访问。

多人端侧验收需覆盖同时发言、用户互听、音量叠加、扬声器回声及完整混合播放参考。包含无人机的 N 个全互听发言端对应 N 路音频接入、N×(N−1) 份音频转发；DTX、静音和同时发言人数固定记录，不能按单人对讲的两路音频估算。

业务层补幂等加入、memberId/connectionEpoch、授权到期撤权和旧连接条件清理。若用户退出语音但仍可看视频，应取消相应音频发布/订阅，不直接移除整个参与者。现有房间权限/API 提供基础，但源端采集停止、业务到期执行和迟到请求隔离仍需接通。

### 4.4 pacing 与缓存：本地版本存在明确实现缺口

本报告不因为 LiveKit 的成熟度或 `pacer` 目录存在就判定 Q-06 通过：

- 默认 `UseSendSideBWE=false`，`transport.go` 使用 RemoteBWE + `NewPassThrough`，`Enqueue` 直接调用发送。
- 开启 send-side BWE 后默认 `NewNoQueue` 将包放入 deque，由 worker 尽快发送，没有按目标码率定时放行；`SetBaseCap(512)` 不限制增长。
- `leaky-bucket` 虽有类实现，当前 `transport.go` 明确说明它未由 BWE 驱动目标码率，并回退到 NoQueue。
- 当前这些 pacer 的 Enqueue 没有完整帧准入/依赖丢弃策略；不能用任意丢 RTP 包补上队列限制。

实现上需把带宽目标、padding/RTX 预算、音频优先级接到真正的 paced sender；对队列设置字节/时长边界并按编码帧和依赖丢弃/请求关键帧。TCP 连接增加写入截止时间、积压监测和慢订阅隔离，验证不会通过同步写入拖住同源其他订阅或整个房间。

已有 Pion/LiveKit 发送结构可扩展，但不能直接把 C++ 项目基于 libwebrtc 的 pacing 测试结果迁移过来。选择开源依赖实现也须验证与当前 fork 的 RTP/RTCP、反馈时刻和序号改写一致。

### 4.5 视频 FEC、重传及统计

当前 protocol 定义 `FlexFEC03CodecParameters`，但它不在 `VideoCodecsParameters` 默认注册列表中，默认房间 codecs 也没有视频 FEC；服务端中跳过 FlexFEC 的辅助判断不代表已有收发处理。没有发现可把“视频 FEC”视为已交付的端到端路径。

若保留 Q-07，应选择目标端共同支持的 FEC 机制，补协商、关联 SSRC/PT、上行恢复及按下行改写后的 RTP 重新生成保护信息，计入总预算。音频 Opus 带内 FEC/PLC 和音频 RED 与视频 FEC分别验收。若采用非 RTP TCP 回放，按需求第 2.4 节解释对应协议适用性，实时 UDP 视频 FEC要求仍保留。

重传方面，缓存包数和 PLI 限频已有配置，但下行 `maxAck=3` 等为常量，上行 NACK 使用锁定依赖的默认参数。需要把需求所要求的缓存、次数、时间窗口变成可部署配置，并分别验证上/下行恢复及过期淘汰；不要把源码中存在某个默认寿命当配置接口已完成。

质量统计可复用 RTPStats、telemetry、Prometheus；另建 1 s 会话采样和终端上报，关联设备/摄像头/源代次/成员/方向，明确丢包恢复前后及字节口径。WebRTC stats 之外补实际解码、呈现冻结、音频中断、TCP 积压和写入超时。默认的节点 2 s、质量 5 s、telemetry 30 s 不能单靠面板刷新改为完整 1 s 数据。

### 4.6 机载 ARM64、业务与容量边界

Go 服务端 `.goreleaser.yaml` 有 Linux ARM64 构建矩阵，Dockerfile 支持按目标架构无 CGO 构建；因此原 C++ WebRTC CMake 的 Linux ARM64 限制不适用于 Go 服务端本身。

但用户要求的是**机载客户端运行在 Linux ARM64**，而不是仅服务器能编译 ARM64。Go SFU 不包含目标板的摄像头采集、硬编、AEC/扬声器和回放读取。若继续使用现有 C++ SDK，其 Linux ARM64 构建/硬编问题仍需要解决；不能因为换了 Go 服务端就将它标为已完成。若选择 Go 发布客户端，必须另行解决本地服务端兼容表所指出的 active TCP 限制以及硬件编码集成。

已有节点轨道数/字节率、订阅上限和房间人数限制提供较好基础，但不是完整硬配额：节点数据由统计更新，当前限额检查主要出现在节点分配/入房路径。已有参与者持续发布、增加订阅时还需按需求完成资源预留/释放，分开源流、转发、连接和总缓存预算，并记录明确拒绝原因。目标参数必须由实际测试决定。

容量规格保持 H.265 单层 720p30、2 Mbps/路，Opus 32 kbps/发布源，启用鉴权、安全和 QoS；H.264 回退及切换峰值另测。固定硬件、两实例部署方式、每源扇出和多人语音负载，分别得到 P-02/P-03 边界，候选档位完成 8 h；不能借别的编码、关闭功能、分开实例结果或历史官方规模外推。

## 5. 与当前 C++ 版本的差异

| 维度 | 当前 C++ 版本 | 本次 Go 版本 | 对本项目的影响 |
| --- | --- | --- | --- |
| H.264/H.265 SFU | 主路径限定 VP8 | 已有 codec 注册、关键帧识别和转发 | Go 能显著减少服务端编码适配工作 |
| 全体编码回退 | 需新建闭环 | 已有 REGRESSION/备用编码迁移 | 优先接入和验证，仍需机载及首位观看者策略 |
| 订阅需求聚合 | 缺完整源端闭环 | dynacast 聚合及通知已有 | 机载 SDK 对接后更接近 V-08 |
| 直接 TCP | 未证明完整接入 | 有被动 ICE-TCP 与 ForceTCP | 优先验证双实例 WebRTC 回放，仍依赖各端主动 TCP |
| 多人语音/权限 | 通用多轨基础 | 多成员/轨道权限/生命周期较完整 | 不需单人仲裁，业务与端侧仍需开发 |
| pacing | 有原生 libwebrtc pacing 与局部有界准入 | 本地默认 PassThrough，可选 NoQueue 无硬界限 | Go 不能在 Q-06 上直接判优，需明确补齐 |
| 视频 FEC | 未接入 | 未发现完整视频 FEC 路径 | 两个方案都需处理此 P0 缺口 |
| 运维/限额/节点 | 当前以单机基础为主 | 分布式路由、节点选择、监控/限额较完整 | Go 复用价值更高，但不等于容量/稳定性已验收 |
| 机载客户端 | Linux ARM64 等尚待适配 | 本仓库是服务端，不提供机载交付 | 切服务端不能消除机载端工作 |

**建议优先采用 Go 服务端，先做三个验证关口：两段 UDP/TCP 直连隔离、H.265→H.264 全体回退、多人音频/AEC。** 同时将 Q-06 pacing 和 Q-07 视频 FEC 作为明确开发任务，不能留到验收末期才发现缺失。

## 6. 建议实施顺序与验收关口

| 阶段 | 任务 | 完成依据 |
| --- | --- | --- |
| 1：版本冻结与最小通路 | 锁定此提交及 fork；部署无 TURN 的 UDP/TCP 两实例；目标板和真实三端接入；明确 active TCP 与 H.265 支持 | 设备→SFU、SFU→终端均有真实媒体协议证据及实际解码；不符合的客户端明确记录 |
| 2：核心媒体补齐 | 实时 H.264 备用 REGRESSION、首位能力决策、pacing/队列、视频 FEC、重传参数、机载硬编反馈 | 新旧观看者均能解码、弱端独立退化、丢包恢复可观测、队列有界 |
| 3：无人机业务 | 稳定源标识、dynacast 对接、多人语音成员生命周期、回放多会话、Web 多机及移动端 | 34 项功能用例逐项留证，摄像头/成员/回放异常不影响其他有效媒体 |
| 4：质量与上线验证 | 1 s 指标、两个方向独立弱网、P95 时延/首帧、混合容量、8 h、过载和节点重建 | 按 V1.11 完成 P0/P1 记录；未触及容量边界仅报告已验证下限 |

未获得机载 SoC/硬编 SDK、目标手机/浏览器版本、网络部署及回放源实现前，不给确定工期或最大路数承诺。现有服务端可复用程度更高，不等于需求可以零开发上线。

## 7. 本次验证及限制

已完成：源码与配置静态核对；审阅 `TestSubscribedMaxQuality`、`TestCodecRegression`、候选过滤、H.264 codec 注册、NACK/RTX 等已有测试入口；检查锁定依赖中的 TCP mux、codec 和 NACK 默认参数。**审阅用例不等于执行通过。**

发现 PATH 未包含 Go，随后使用工作区已有工具：

```text
D:/workspace/av-platform/out/tools/go/bin/go.exe version
go version go1.27.3 windows/amd64
```

尝试运行以下定向自动化检查：

```text
go test ./pkg/config ./pkg/rtc/dynacast ./pkg/sfu/pacer -count=1 -timeout=120s
```

命令停留在下载 `github.com/stretchr/testify v1.12.1`，未产生测试结果，已停止该次执行。随后用当前命令环境的 `GOPROXY=off` 和 `-mod=readonly` 核对本地依赖，三个包均在 setup 阶段报告 `module lookup disabled by GOPROXY=off`。因此本次结论为：**测试未执行完成，依赖准备受阻；不是断言失败，也不是通过。** 未修改或降级 go.mod/go.sum 来绕过依赖。

本次没有构建/运行 Go 媒体服务，没有执行目标端 UDP/TCP 媒体、H.265/H.264 切换、多人实机语音、FEC、时延、容量或长稳验收；没有使用桌面自动化。旧 C++/SDK 与某个 Go 二进制的历史互通记录不能替代对此提交和 V1.11 的验证。

## 8. 源码证据索引

链接指向本地 `D:/workspace/livekit` 和本机已缓存的锁定依赖。代码行号按本次版本记录；后续升级需重新核对。

- **G1 版本**：[go.mod](../../../livekit/go.mod)、[version.go](../../../livekit/version/version.go)、[发布矩阵](../../../livekit/.goreleaser.yaml)、[Dockerfile](../../../livekit/Dockerfile)。
- **G2 codec**：[配置默认编码列表](../../../livekit/pkg/config/config.go) 607–620 行；[媒体引擎](../../../livekit/pkg/rtc/mediaengine.go) 33 行起；[关键帧/尺寸解析](../../../livekit/pkg/sfu/buffer/buffer_base.go) 1162 行起；[Forwarder](../../../livekit/pkg/sfu/forwarder.go) 436 行。
- **G3 房间/多轨/订阅**：[room.go](../../../livekit/pkg/rtc/room.go)、[mediatracksubscriptions.go](../../../livekit/pkg/rtc/mediatracksubscriptions.go)、[subscriptionmanager.go](../../../livekit/pkg/rtc/subscriptionmanager.go)、[receiver_base.go](../../../livekit/pkg/sfu/receiver_base.go)。
- **G4 dynacast**：[质量聚合](../../../livekit/pkg/rtc/dynacast/dynacastqualityvideo.go)、[聚合管理](../../../livekit/pkg/rtc/dynacast/dynacastmanagervideo.go)、[上行通知](../../../livekit/pkg/rtc/mediatrack.go) 674 行起；[相关测试](../../../livekit/pkg/rtc/dynacast/dynacastmanager_test.go)。
- **G5 回退**：[mediatrack.go](../../../livekit/pkg/rtc/mediatrack.go) 112、524、662 行；[Receiver 切换](../../../livekit/pkg/rtc/mediatrackreceiver.go) 252 行起；[DownTrack 编码变化](../../../livekit/pkg/sfu/downtrack.go) 660 行起；[人数策略](../../../livekit/pkg/service/roommanager.go) `ShouldRegressCodec`；[客户端能力](../../../livekit/pkg/rtc/clientinfo.go) `SupportsCodecChange`。
- **G6 直连 TCP/UDP**：[部署配置注释](../../../livekit/config-sample.yaml) 58 行起；[RTC 配置嵌入](../../../livekit/pkg/config/config.go) 135 行起；[禁止服务端主动 TCP](../../../livekit/pkg/rtc/config.go) 70 行；[客户端主动 TCP 能力判定](../../../livekit/pkg/rtc/clientinfo.go) 80 行；[连接策略](../../../livekit/pkg/rtc/transportmanager.go) 739 行起；[候选过滤](../../../livekit/pkg/rtc/transport.go) 2458、2492、2567 行；[候选测试](../../../livekit/pkg/rtc/transport_test.go) 519 行起。
- **G7 QoS/pacing**：[RTC 反馈配置](../../../livekit/pkg/rtc/config.go)、[实际 pacer 选择](../../../livekit/pkg/rtc/transport.go) 580–613 行；[直接发送](../../../livekit/pkg/sfu/pacer/pass_through.go)、[NoQueue](../../../livekit/pkg/sfu/pacer/no_queue.go)、[LeakyBucket](../../../livekit/pkg/sfu/pacer/leaky_bucket.go)、[分配器](../../../livekit/pkg/sfu/streamallocator/streamallocator.go)、[单层屏幕轨道豁免](../../../livekit/pkg/sfu/streamallocator/track.go) 112 行。
- **G8 重传/PLI**：[缓存与限频配置](../../../livekit/pkg/config/config.go) 145 行起；[Buffer](../../../livekit/pkg/sfu/buffer/buffer_base.go) 411、673 行起；[下行次数常量](../../../livekit/pkg/sfu/sequencer.go) 32 行起；[接收器 PLI 参数](../../../livekit/pkg/sfu/receiver_base.go) 54 行起；[NACK/RTX 测试](../../../livekit/pkg/sfu/buffer/buffer_test.go)。
- **G9 FEC/RED**：[codec 注册](../../../livekit/pkg/rtc/mediaengine.go)、[Opus/RED receiver 选择](../../../livekit/pkg/rtc/wrappedreceiver.go)、下列锁定 protocol codec 定义。服务端 `pkg` 范围的视频 FlexFEC 相关命中主要为辅助排除判断，未发现完整接入实现。
- **G10 权限/API**：[轨道订阅权限](../../../livekit/pkg/rtc/uptrackmanager.go)、[RoomService](../../../livekit/pkg/service/roomservice.go)、[Participant](../../../livekit/pkg/rtc/participant.go)；客户端 SDK 为 [README 中的外部组件](../../../livekit/README.md)，不在本仓库内自动交付。
- **G11 统计**：[telemetryservice.go](../../../livekit/pkg/telemetry/telemetryservice.go) 166 行；[connectionstats.go](../../../livekit/pkg/sfu/connectionquality/connectionstats.go) 34 行；[节点统计配置](../../../livekit/pkg/config/config.go) `DefaultNodeStatsConfig`；[Prometheus](../../../livekit/pkg/telemetry/prometheus/node.go)。
- **G12 配额/调度**：[LimitConfig](../../../livekit/pkg/config/config.go) 374 行起；[节点限额判断](../../../livekit/pkg/routing/selector/utils.go) 59 行；[房间分配](../../../livekit/pkg/service/roomallocator.go) 135 行起；[订阅限额](../../../livekit/pkg/rtc/subscriptionmanager.go) 773 行起。
- **G13 验收边界**：本报告第 7 节与需求 V1.11 第 3、4 章；没有此次目标规格的性能/实机通过记录。
- **G14 生命周期**：[Participant](../../../livekit/pkg/rtc/participant.go)、[TransportManager](../../../livekit/pkg/rtc/transportmanager.go)、[RoomManager](../../../livekit/pkg/service/roommanager.go)、[错误重连策略](../../../livekit/pkg/config/config.go) 175 行起。

本机锁定依赖补充证据（路径包含版本，交付时建议随版本清单归档）：

- [RTCConfig/ForceTCP](C:/Users/admin/go/pkg/mod/github.com/livekit/mediatransportutil@v0.0.0-20261014192331-dd8e31a0adc0/pkg/rtcconfig/config.go)，78 行。
- [TCP mux 与 network types](C:/Users/admin/go/pkg/mod/github.com/livekit/mediatransportutil@v0.0.0-20261014192331-dd8e31a0adc0/pkg/rtcconfig/webrtc_config.go)，123–205 行。
- [Opus/H.265/FlexFEC 定义及注册集合](C:/Users/admin/go/pkg/mod/github.com/livekit/protocol@v1.53.1-0.20261021070436-f09f87aab29b/codecs/codecs.go)，Opus `useinbandfec=1`，169 行 H.265、177 行 FlexFEC、189 行视频注册集合。
- [上行 NACK 默认参数](C:/Users/admin/go/pkg/mod/github.com/livekit/mediatransportutil@v0.0.0-20261014192331-dd8e31a0adc0/pkg/nack/nack.go)，47 行起参数定义及默认值。
