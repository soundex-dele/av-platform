# C++ SDK 客户端能力补齐方案

日期：2026-10-27。状态：分阶段实施中；P0/P1、P2 音视频 pull 输出及首版应用 I420/PCM 输入已有部分交付，其余范围仍有效。具体完成项和自动化证据见 [客户端补齐实施记录](../../livekit-sdk-cpp/docs/client-parity-progress.md)，不以本方案内容代表能力已实现。

基线：当前 `livekit-sdk-cpp` 工作树；Go 对照为 `D:/workspace/server-sdk-go`，版本 2.19.0，提交 `743ab2d6b12ff24c2b2f9a0cc208c7afe8602571`，protocol v1.53.0。

## 1. 范围与交付原则

用户明确排除服务端管理 API。本方案只补齐客户端 RTC、媒体输入输出、数据通信、连接恢复、客户端加密及其工程质量。不新增 RoomService、Egress、Ingress、SIP、Agent 管理或号码管理 API；已有 ServerSDK 保留兼容。客户端入会 Token 及刷新由调用方业务服务提供。

保留原生 libwebrtc M137、现有媒体图、Room/Participant/TrackPublication 和 C++20；不引入 Go 子进程，不公开 Pion/libwebrtc/GraphFlow 类型。采用增量 API，原有 MediaSpec、视频回调和 CLI 继续可用。已有 Player、采集、远控作为回归消费者，不重新建设播放器或扩展剪辑功能。

“对齐”指可观察行为和 LiveKit wire 协议兼容，不要求复制 Go 的类型体系。Pion interceptor、PeerConnection 指针等后端专属 API 不逐项搬运，使用 SDK 自有能力查询、统计、RTP/RTCP 观察和传输配置表达可支持的用途。

SVC、GPU 零拷贝、硬件 codec 全覆盖属于额外增强，不作为本地 Go SDK 已支持能力的推定；单独设能力和验收门槛。

## 2. 当前关键约束

- 设计基线曾存在信令 SDK version=0.2.0 与 CMake 0.3.0 不一致；实施中已统一为生成的 0.3.0。默认 protocol 仍为 12；元数据成功确认可显式选择 15，已有官方服务端确认及恢复测试。尚未启用 17，不能仅修改协议数字宣称兼容。
- `protocol/livekit.proto` 是手写子集，缺少恢复、RPC、stream、DataTrack、加密等消息。
- `room.cpp` 同时拥有 Peer、发布状态、信令循环和清理；须逐步抽出内部模块，保持每个阶段可独立回归。
- 现有 RoomState generation 同时承担会话隔离；恢复原会话与重新入会需要不同代次语义。
- RTC 视频为 I420 值对象，Player 帧为文件时间线上的 RGBA/shared buffer；不能直接把 Player 时间戳当作 RTC 采集时间。
- 当前视频图绕过 WebRTC 解码完成回调，缺少实际音频播放时钟同步，部分原生解码统计失真。
- 历史文档包含不同日期和服务端的通过/失败记录；P0 必须重新建立当前二进制基线，不能用旧通过覆盖失败。

## 3. 分阶段交付

| 阶段 | 内容 | 依赖 | 完成条件 |
|---|---|---|---|
| P0 | 协议、错误、能力与测试基线 | 无 | 原有 consumer/CLI/SDK 回归；新增 wire fixture 双向检查 |
| P1 | 自动重连、恢复、区域与迁移 | P0 | 故障注入后状态、轨道、数据行为符合恢复契约 |
| P2 | PCM、原始视频、编码帧、RTP 扩展及输出隔离 | P0；与 P1 契约统一 | 真实媒体双向互通，过载与关闭有界 |
| P3 | Simulcast、质量、权限及音画同步 | P1、P2 | 三层发送/选层、权限变更和长时同步测试 |
| P4 | RPC、文本/字节流、文件、转写、DTMF | P0、P1；可在 P2/P3 完成前推进 | C++↔Go 双向协议互通与负面测试 |
| P5 | DataTrack | P1、P4 的数据调度底座 | 发布订阅、帧分片/重组、过载及恢复互通 |
| P6 | 数据与媒体 E2EE | P2、P4；DataTrack 加密依赖 P5 | 固定测试向量和跨 SDK 双向解密通过 |
| P7 | 单 PeerConnection、平台构建与发布收口 | P1；发布依赖各阶段 | 连接模式兼容、独立 consumer 与平台矩阵 |

每阶段可交付并保持功能开关；不等待全部功能齐备再合入。原始 RTP、SVC、特定 codec 单独报告已实现/未支持，不用空实现填满接口。

## 4. P0：协议和运行时底座

### 协议来源

固定 protocol v1.53.0 对应源码提交，优先从上游 schema 生成内部消息；先验证其 protoc/runtime 和自定义 options 依赖与当前 WebRTC Protobuf 构建是否冲突。如需暂时保留裁剪 schema，维护明确字段清单和上游描述符检查，检测字段号、类型、oneof、枚举及 presence 漂移。不能只依据 upstream 文本快照手工增加字段。

增加 Join/ServerInfo/ClientConfiguration、Leave.action、RefreshToken、Reconnect/SyncState、RoomMoved、RequestResponse，以及后续阶段所需数据消息。保留未知字段兼容和消息大小限制。protocol 12 的已有连接保持回归，protocol 17 行为矩阵通过后才上调默认声明。

### 内部模块和公共契约

- `SignalSession`：连接、握手、心跳、Token 更新、消息编解码与恢复。
- `PeerTransport`：publisher/subscriber 或 single-PC，ICE/SDP/媒体通道；协商串行化。
- `PublicationRegistry`：源、稳定本地 ID、服务器 SID、订阅和设置快照。
- `PendingRequests`：请求 ID、deadline、取消、最多一次完成、断开清理。
- `DataRouter`：按 protobuf payload 类型分发；有界数据调度。
- `Capabilities`：分别表达本地编译能力、当前协商结果和未确认的服务端能力；未知不等于支持。

引入自有 `SDKError`（domain/code/retryable/backend_reason）和操作级取消/超时，继续以 future/异常兼容旧 API。区分“入队”“已发送”“服务器确认”“对方业务完成”。通过 request ID 收到服务端响应的操作提供确认语义，旧方法不悄悄改变其完成时机。

默认回调保持现有串行契约；新增可选串行控制执行器。媒体输出使用独立有界 pull 队列或显式执行器，不能由慢视频/音频消费者堵住信令。停止屏障清理排队回调，不在 WebRTC 锁内调用应用；执行器寿命和回调内销毁限制写入文档。

## 5. P1：连接恢复

增加 `reconnecting` 状态、`ReconnectOptions`、`on_reconnecting`、`on_reconnected`、`on_room_moved`，以及可取消、有截止时间的 TokenProvider。重试采用退避与抖动、总时间预算；主动离开、踢人、重复 identity 替换、明确权限拒绝等不进入无限重试。

恢复路径：

1. 信令断开但 PeerConnection 存活：保留媒体，按协议恢复信令，发送 SyncState、处理 SDP/订阅/数据状态。
2. ICE 失败：根据协议支持进行 ICE restart 和串行协商；失败后升级完整重连。
3. 服务端无法恢复：重建传输、重新 join、重发可重放的发布配置，恢复订阅/静音/质量设置。
4. 区域重定向或房间迁移：验证目的地址策略，使用服务端更新 Token，切换后更新 room 和参与者映射。区域发现可关闭，自建部署不强制依赖 Cloud。

维护三类 ID：逻辑 Room 生命周期 ID、传输 epoch、publication 实例 generation。恢复原会话保留逻辑句柄并隔离旧传输回调；完整重新入会按现有契约使旧 Participant/Publication 句柄失效，重新发出绑定事件。源对象可保留，但旧服务器 SID 不可复用。发布配置有稳定本地 ID，便于应用重绑定。

自动恢复只重放明确可恢复的“期望状态”。已发送但未确认的 publish/RPC/文件写入不得盲目重发；旧请求返回明确中断或结果未知。普通 data 不承诺断线持久化。文件源需声明可重启、续读或不可恢复；外部实时源保持有界缓存，不回放积压旧帧。

验收：仅断 WebSocket、丢 UDP、ICE 失败、服务重启、Token 过期/刷新失败、重试中取消、踢人、迁移、旧回调迟到；检查重复轨道、重复事件、future 泄漏及恢复后真实音视频增长。远控在断线时立即释放按键和鼠标，重连不得自动恢复旧控制授权。

## 6. P2：媒体公共接口

建议新增自有 `LocalMediaTrack`、`AudioSource`、`VideoSource`、`EncodedTrack` 和远端 reader/sink。名称为设计草案。MediaSpec 转为创建这些源的便捷入口，继续支持原代码。

当前增量提供 `VideoFrameStream`、`AudioFrameStream` 和 `MediaSpec.video_source`/`I420VideoSource`。I420 输入首版固定尺寸、CPU 像素、正 stride、已转正，使用提交时的本地单调时钟；外部采集时间、RGBA 转换、动态尺寸和 GPU buffer 尚未交付，不能将本增量视为原始视频接口全部完成。

PCM 输入增量提供 `MediaSpec.audio_source`/`PcmAudioSource`，支持 PCM16/float32、七种采样率、单/双声道、10 ms 整数倍写入、独立 sinc 重采样、可选 steady_clock 采集时间和有界输入。音频欠载/时间缺口补静音，迟到及调度跳过分别计数；官方服务端双轨/立体声及 rejoin 已有自动化证据。任意大小 PCM 块、设备时钟漂移补偿、Go 实际互通及长期音画同步仍不能由本增量推定完成。

### 分层落地

1. PCM 输入/输出：先支持 PCM16/float32、显式采样率/声道、duration 和采集时间。接入重采样/Opus；远端提供逐轨 PCM，混音后输出另设接口。多条外部音轨须有独立源和编码状态，不能全部绕进默认麦克风 ADM。
2. 原始视频：首版 CPU I420，显式转换 RGBA；拥有或共享只读 Buffer、stride、rotation、时间基和 stream generation。后续独立扩展 GPU buffer。
3. 编码帧：通过私有 backend adapter 接入既有编码透传/接收边界，提供 codec/fmtp、关键帧、PTS/DTS、duration、codec config 与时钟信息。VP8/Opus 优先；H.264 需单独验证 profile、SPS/PPS、packetization-mode，不能将输入 H.264 后转 VP8 计作 H.264 发布。
4. RTP/RTCP：先完成包观察和发送接入原型，明确读取是在解密后/重传修复前后哪个位置。M137 公共 PeerConnection 不等价于 Pion TrackRemote.ReadRTP；必要适配集中在私有后端并固定版本。外部 RTP 发布要处理 PT、SSRC、序号、时间戳、扩展、RTX/NACK 和 RTCP 归属，避免重复反馈。原型未通过前不对外承诺任意 RTP 注入。

编码样本发送仍由 libwebrtc 负责 RTP 分包、pacing、SRTP、拥塞控制和反馈。预编码轨道需提供关键帧请求和目标码率反馈给调用方；外部编码器不能响应时明确报告能力限制。

媒体不装进现有 JSON Command：控制命令仅注册源/句柄，帧走有界队列。写入结果区分 accepted/backpressure/closed。视频可丢过期完整帧；编码参考帧丢弃后等待可解码边界，音频按时间连续性处理，禁止无声无限堆积。

验收：合成 PCM→发布→Go PCM 接收；I420→发布→对端校验；Go 编码样本→C++ reader；C++ 编码样本→Go；取消、快慢消费者、EOS、时间戳回绕、关闭后写入、多房间与独立多音轨。

## 7. P3：多层视频、权限和同步

### Simulcast 与订阅

增加 `VideoEncoding`（rid、scale、max_bitrate、max_fps、active）、发布层列表和 `set_video_quality`。首版 VP8 三层，创建 transceiver 时配置多个 send_encodings，并在 AddTrack 上报真实层信息。

既有 GraphVideoSender 主动编码结构必须保留每层 codec metadata、RID/空间层与时间层标识，不能复制单路编码包冒充三层。带宽更新进入真实编码器；处理 SubscribedQualityUpdate，支持层启停和关键帧请求。尺寸和 quality 的优先规则对齐 Go/协议，并在重连后恢复。

接入 `set_subscription_permission`、权限变更事件及被拒绝订阅的错误。fps/priority 仅对支持的服务器生效，不能把请求发出等同于服务器执行。SVC 在 VP8 simulcast 稳定后独立验证 VP9/AV1 编码、依赖描述及 SFU 能力。

### 音画同步

接收侧建立 RTP/RTCP sender report 到共同呈现时间的映射，按参与者/同步组关联音视频，不能把不同参与者强行共用一个源时钟。以实际音频 playout position 为主时钟，处理设备延迟、漂移、丢帧和重连时钟重置；无音频时回退本地单调时钟。

决定并固定解码统计反馈边界：图内统计为真实解码/呈现来源，WebRTC 统计标注不适用字段；如恢复原生反馈须验证不会重复呈现。不能伪造解码完成来修饰指标。

验收：三层独立可解码、上下行带宽收缩、停层/恢复、订阅尺寸切换、重连后设置恢复。以含闪光/脉冲时间标记的合成媒体测 AV 偏差；建议自动化目标为两小时绝对偏差 P95≤80 ms、最大≤150 ms，作为待校准的验收目标，不是现有实测结果。物理扬声器/屏幕同步另行人工验收。

## 8. P4：RPC 与数据流

DataRouter 按官方 protobuf payload 分发，普通 UserPacket、RPC、stream、transcription、DTMF 分开；不得用自定义 JSON topic 伪装官方协议。

- RPC：`perform_rpc`、注册/注销异步处理器；实现 request/ack/response、版本/大小检查、deadline、错误码、调用者校验和有限重复请求去重。处理器在独立执行器运行；断开取消；不承诺跨重连 exactly-once，业务幂等键由应用提供。
- 文本/字节流：header/chunk/trailer、stream ID、topic、attributes、UTF-8 跨 chunk、完整结束和异常结束。并发数、单流和总缓冲均有限额，writer 支持背压和取消。
- 文件：本地打开文件后分块发送，接收由应用明确提供目标路径或 sink；元数据文件名不能直接决定磁盘路径。默认断线失败，首版不承诺断点续传。
- 转写：结构化接收/发送事件，segment ID、track/participant、时间、language、final；支持更新未最终完成的 segment。仅承载转写数据，不实现 ASR 引擎。
- DTMF：对齐协议的数据消息及事件，号码/按键输入校验；不扩展服务端 SIP 管理。

控制消息、小消息和大文件采用有界公平调度，结合 bufferedAmount/low threshold 控制 SCTP 压力；不能承诺单个可靠通道内完全消除队头阻塞。保持现有 reliable/lossy 发布语义。

验收：C++↔Go 双向 RPC/stream；未知方法、超时、对端离开、非法 chunk、UTF-8 分界、取消文件、大文件与远控小消息共存。支持的自动化 Web 客户端用于补充互操作，不操作用户桌面。

## 9. P5：DataTrack

实现官方发布/取消发布信令、publication 状态、subscriber handles、分片和帧重组、序列/时间信息、订阅与恢复。单独管理 DataTrack 通道与流状态，不视为现有 publish_data 的别名。

对照 Go 的 freshness 策略：发送缓冲拥塞时保留最新待发完整帧，丢弃旧帧；重组缺片/超时清理。记录 dropped/expired/reassembly_error 指标。协议本身不具备的可靠交付不能由 API 暗示提供。

验收依赖支持 DataTrack 的固定版本官方服务端；本地 C++ SFU 若不支持，输出明确 unsupported/unknown，不以客户端字段存在标记通过。

## 10. P6：E2EE

增加 `KeyProvider`、每轨 EncryptionOptions、密钥轮换和状态事件。标准 AEAD 使用已有密码库；wire 格式、nonce/IV、key index、AAD、ratchet 和 codec 特殊处理均按 Go/官方协议实现，用测试向量校验。不能只套 AES-GCM 自定包格式。

数据加密在 DataRouter 序列化后/发送前，解密在 payload 分发前，支持哪些 payload 严格按协议。媒体使用 M137 已有 SetFrameEncryptor/SetFrameDecryptor 或受控 frame transformer 接口，位置为编码后、RTP 分包前及收包后、解码前。先验证与当前图透传路径相容，避免同帧双重加密。

对照本地 Go 优先 Opus、H.264，再 H.265；每个 codec 的加密互通与实际编解码/传输能力分别验收。VP8/VP9/AV1 不由“有 E2EE”推定支持。DataTrack 加密作为 P5 后增量。

缺密钥、错误密钥、认证失败时拒绝输出明文，密钥不进日志。重连、重新发布、轮换不得重用同一 key/nonce 对；密钥分发由应用可信通道负责。测试轮换窗口、乱序、旧帧、服务端插入帧标识及关闭清理。

## 11. P7：连接模式与交付

在 PeerTransport 内增加单 PeerConnection 策略，对齐 JoinRequest/响应、信令 endpoint、预发布轨道和协商方向，保留当前双 PC 默认路径直到兼容性通过。降级仅在明确不支持且不会重复建立业务会话时发生。

发布公共能力查询、codec 协商结果、传输/队列/重连/解密统计和自有日志 sink；扩展受支持的 ICE、IPv6、codec、码率/缓存配置。自定义 pacer/interceptor 或原生 PC 指针不作为必需公开 API，底层调度继续由 libwebrtc 管理。

平台顺序：Windows x64 自动化基线 → Linux 原生构建与无窗口互通 → macOS 构建/无窗口回归及设备人工验收。只有验证通过的平台列为支持；移动端、C ABI 和预编译多平台包另立交付，不混入协议补齐承诺。

## 12. 代码落点

| 目录 | 计划改动 |
|---|---|
| `include/livekit/room.hpp`、`participant.hpp` | 恢复、权限、质量和新发布重载 |
| `include/livekit/media*.hpp`、`media_core/` | 帧/包/源/sink 契约，保留既有类型适配 |
| `include/livekit/` 新头文件 | error、capabilities、rpc、streams、data_track、encryption |
| `src/engines/rtc/` | 从 room.cpp 提取 signal_session、peer_transport、registry、pending_requests、data_router |
| `src/media_nodes/`、`src/backends/webrtc/` | 自定义源、编码帧、逐轨 PCM、多层发送、同步和 cryptor adapter |
| `protocol/`、`cmake/` | 固定协议生成、版本来源、能力选项 |
| `tests/` | wire fixture、生命周期/故障注入、媒体与跨 SDK 集成 |

具体文件名以实施时内部模块边界为准；完成状态以实施记录和对应验收证据为准。

## 13. 验收与发布门槛

1. P0 记录当前源码提交、工作树差异、依赖 SHA、二进制 SHA 和测试端点版本；先复现文件四轨等历史问题，确认当前是否仍存在并定位归属。
2. 自动化分四层：纯状态机/协议单测；真实 libwebrtc 原生测试；C++↔Go 的官方服务端集成；本地 C++ SFU 兼容矩阵。高级功能须选真正实现该能力的服务端版本，不默认历史 1.13.10 足够。
3. 使用测试进程局部故障代理或注入接口控制网络，不修改用户全局网络。重连测试覆盖重复 100 轮，长期测试观察内存、线程、队列回到稳定区间。
4. 支持的平台运行独立 consumer 编译、CLI/SDK 回归、并发多房间、取消/析构与资源检查。适用平台增加 ASan/TSan，第三方问题单独归档。
5. 不使用 computer-use、桌面自动化或 @oai/sky。所有自动化使用编译、单元/集成、无窗口测试与程序内渲染截图。设备采集质量、AEC、真实音画同步、硬件编解码和多屏操作列为人工验收，自动化通过不替代人工结果。
6. 每个里程碑发布能力矩阵、限制和可运行示例；协议存在/调用成功/媒体质量达标分别记录，不混写为“完整支持”。

建议首先交付 P0+P1，再交付 P2 的 PCM/I420/编码帧和 P3 的 VP8 simulcast/同步；P4 可在恢复契约稳定后独立推进。原始 RTP、DataTrack、E2EE 和 single-PC 分别设专项验收，避免高风险后端适配阻塞基础客户端能力交付。
