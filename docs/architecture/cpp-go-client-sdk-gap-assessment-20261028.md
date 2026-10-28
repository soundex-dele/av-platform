# C++ 与 Go 客户端 SDK 差异及剩余实现方案

核对日期：2026-10-28。本文是当前源码的差异评估与实施建议，不代表新增功能已实现或已验收。

后续实施更新：本次评估之后已完成一轮客户端扩展及统一验证。当前接口范围见 [客户端扩展说明](../../livekit-sdk-cpp/docs/client-extensions.md)，实际测试结果和剩余边界见 [2026-10-28 验证报告](../../livekit-sdk-cpp/docs/client-extensions-validation-20261028.md)。下文保留实施前基线，不作为最新完成状态。

## 1. 范围与基线

- C++：`D:/workspace/av-platform/livekit-sdk-cpp`，版本 0.3.0，核对时 HEAD 为 `f46019c`，包含当前未提交的接口、传输策略及测试改动。使用 C++20、原生 libwebrtc M137 和 GraphEngine。
- Go：`D:/workspace/server-sdk-go`，版本 2.19.0，HEAD 为 `743ab2d`，依赖 `livekit/protocol v1.53.0`，信令协议声明为 17。
- 只比较 Go 仓库内作为房间参与者的 RTC 客户端能力及相关媒体工具。排除 RoomService、Egress、Ingress、SIP 管理、Agent 管理、号码管理及服务器 SDK 实现。
- `livekit-cpp` 是 SFU 服务端，不是本次 C++ SDK 比较对象。SDK 测试可连接固定版本服务端，但不以服务端功能或 Go 测试客户端的能力证明 C++ SDK 已支持。
- 本次进行了源码、公开头文件和已有验证记录核对；没有重新编译、运行互通或执行设备验收。历史通过只对原记录中的源码、二进制和环境有效。

结论：基础 RTC、原始媒体输入输出及常用消息已经有实现。剩余主要差距是文本/字节流、DataTrack、编码帧与 RTP 公共接口、多层与备用编码发布、E2EE，以及部分连接和工程契约。不能把此前方案中已经完成的 PCM、RPC、重连等重新列为缺失功能。

## 2. 当前差异矩阵

“已有”表示源码具备相应接口和实现，不表示全部异常、平台或设备已经验收。

| 能力 | Go 当前实现 | C++ 当前状态 | 剩余工作与边界 |
|---|---|---|---|
| Room / Participant / Publication | 房间、参与者、轨道、动态发布订阅、属性和回调 | 核心已有；值快照、future、会话代次句柄 | 不必照搬 Go 类型；继续完善事件、错误和线程契约 |
| 断线恢复 | resume、完整重连、区域连接规划及迁移处理 | resume、ICE restart、rejoin、TokenProvider、初始信令 failover、RoomMoved 已有 | 首次 JoinResponse 后 ICE/媒体连接失败的候选切换未补齐；真实 Cloud 和无缝迁移尚未验收 |
| 信令与连接模式 | protocol 17；双 PC、可选单 PC；可随 Join 预发布轨道 | 默认 12，可选 15；当前双 PC；裁剪 schema | 补齐相应协议行为与单 PC 协商；不能只修改协议号 |
| 原始媒体输入输出 | PCM 工具；远端 RTP 及媒体工具链 | I420/RGBA/旋转/采集时间输入，PCM16/float32 输入；有界视频/逐轨音频 pull 输出 | 固定视频尺寸；PCM 输入限 10 ms 整数倍；设备漂移补偿未完成 |
| PCM 互通范围 | `PCMRemoteTrack` 明确只支持 Opus，且不支持立体声 | C++ 输入支持多采样率和单双声道 | 已有记录仅证明 C++↔Go 单声道互通；C++ 双声道支持不能扩写为 Go 双声道互通 |
| 编码帧与文件原码发送 | `LocalTrack.WriteSample`、Reader/File track、编码样本工具 | 公开发布入口是 `MediaSpec` 与原始帧源；有内部 codec，但没有公共编码样本 source/sink | 增加编码 access unit 输入输出和按时间发送；内部编码透传不等于应用可直接提交压缩帧 |
| RTP / RTCP | `WriteRTP`、Pion TrackRemote、`OnRTCP`、`WritePLI` | 底层 WebRTC 有 RTP/RTCP；SDK 公共访问能力标为 unsupported | 先开放观察与关键帧请求，再独立评估 RTP 注入；不暴露 Pion/libwebrtc 对象 |
| 普通数据与 RPC | reliable/lossy、topic、定向消息；RPC | 已有普通消息、异步 RPC、DTMF、转写 | 保留现有语义；RPC 压缩和跨数据类型公平调度仍缺；转写是消息传输，不是 ASR |
| 文本/字节流、文件 | StreamText / SendText / StreamBytes / SendFile，topic reader handler | 未实现，能力查询明确 unsupported | 官方 header/chunk/trailer、背压、流结束/异常与文件 helper |
| DataTrack | 发布、订阅、schema/frame encoding、帧传输与重组 | 未实现，能力查询明确 unsupported | 需要单独的信令、状态机和传输实现，不是 `publish_data` 改名 |
| 接收质量和订阅权限 | SetVideoQuality / Dimensions / Enabled、订阅授权 | 已有对应能力及恢复映射 | 接收质量请求不代表本地具备多层发送 |
| Dynacast / Simulcast | 最多三层 simulcast；按订阅质量启停层 | 已有可选单层 Dynacast：聚合 ON/OFF 控制源、编码和 sender；无 simulcast | 保留单层能力，扩展真实多层编码、RID、层信息、逐层启停及带宽反馈 |
| 备用编码 | WithBackupCodec、WithBackupCodecForSimulcastTrack、BackupCodecPolicy；处理视频/音频 codec 订阅更新 | 没有公共备用编码配置；单层逻辑只处理当前 codec | 增加同一 publication 的多 codec 状态及按需发布；独立 H.264/H.265 发布不等于 H.265→H.264 回退 |
| E2EE | 数据加密；Opus/H.264/H.265 frame cryptor、key provider；DataTrack cryptor | 媒体/数据 E2EE 均未实现 | 数据、媒体、DataTrack 三部分分别验收；DTLS/SRTP 不等于 E2EE |
| 同步与可观测性 | RTP/RTCP 访问、`pkg/synchronizer` 时间映射工具、可配置 logger/interceptor/pacer | 原生 W3C stats、能力查询、图统计已有；视频按本地时钟呈现 | 缺公共 RTP 时间映射与音频播放时钟联动；图解码绕过 WebRTC 完成回调，不能直接把全部原生解码统计当成实际值 |
| 扩展配置 | Pion interceptor/pacer、重传缓冲、IPv6-only、DTLS 曲线、codec、logger 等 | relay-only、禁 TURN、UDP/TCP 严格传输等已有；部分扩展未公开 | 按用途提供自有配置/统计接口；不为 API 数量复制 Pion 专属机制，也不应推断 C++ 没有拥塞控制、NACK 或 pacing |
| 回调与封装 | Go 对象及 context；可获取原生 PC/track | C++ future/stop_token、串行控制回调、有限队列；原生类型封装在内部 | 可选控制执行器仍缺；慢控制回调不能等待同会话 future；新增接口继续有界、可取消 |

C++ 自身还提供设备采集、播放/录制以及独立 Player 等集成；它与 Go SDK 的定位不同。Player 的文件时间轴不能直接当成 RTC 的实时采集时间。SVC、GPU 零拷贝、完整硬件 codec 矩阵和移动端发布属于另行定义的增强范围，不从 Go 的 Simulcast 或 codec 常量推定支持。

## 3. 实现原则

1. 对齐 LiveKit wire 协议和应用可观察行为，保留 C++20、libwebrtc、现有公共对象与默认行为，不引入 Go 运行时。
2. 新增或改造媒体流水线优先使用现有 GraphEngine / RtcPipeline。信令和数据状态机保持独立，不为套图而增加调度层。
3. 媒体帧走有界队列；JSON Command 只传配置、注册源和句柄。每个队列定义字节/数量/时长限额、背压、停止和代次清理。
4. 延续 resume 保留句柄、完整 rejoin 使旧句柄失效并通过稳定 client_id 重建的契约。未确认发布、RPC、文件或用户消息不自动重放。
5. 每项能力分开记录本地实现、会话协商与服务端未知状态。高级功能启用依赖固定服务端版本及实际互通证据。

## 4. 分批实现与验收

以下是建议的新执行批次，和原方案 P0—P7 的剩余范围对应，不表示重新实施已完成部分。

### M0：固定现状和补齐公共基础

- 记录 C++ 工作树差异、Go revision、protocol 来源、依赖和构建产物 SHA；补齐当前新增 Dynacast/传输策略的能力说明，避免文档停留在旧状态。
- 增量抽出 `PeerTransport`、`PublicationRegistry`、`DataRouter/DataScheduler`；复用已有 SignalSession、PendingRequests、RpcSession，避免整块重写 room.cpp。
- 添加可选串行控制执行器；定义取消、停止屏障、回调异常及对象析构限制。保留现有默认串行回调行为。
- 将图内真实解码/呈现统计与 WebRTC 网络/传输统计分开；增加实际协商 codec 和逐轨统计，不把服务端允许列表当成实际使用结果。
- 继续用固定上游 descriptor 检查 schema。按后续功能增量引入字段，完成 12/15/17 行为矩阵后才调整默认协议。

验收：独立 consumer 编译、既有 SDK/CLI 回归、回调慢消费与取消/析构竞态、能力快照代次和 schema 合约测试。此批次是所有新增功能共同底座。

### M1：文本、字节流与文件

- 新增建议接口 `stream_text/send_text/stream_bytes/send_file`，以及 Room 的 topic 注册/注销、Text/ByteStreamReader/Writer。
- 实现官方 DataStream header/chunk/trailer：stream ID、发送者、topic、attributes、总长度、chunk 序号及结束状态；按 Go 的真实字段语义处理更新和可选值。
- 实现有界公平发送调度；控制/RPC 和大文件分配独立配额，结合 data channel buffered amount 控制准入。保持普通 reliable/lossy 语义，单个可靠 SCTP 通道仍可能有队头阻塞。
- 接收端限制活动流数量、总缓存、单流缓存和空闲期限，增量校验 UTF-8；断线明确失败，首版不做断点续传。
- 文件接收由调用方提供 sink 或明确路径；元数据文件名只作为描述，不自动决定写盘位置。

验收：C++↔Go 双向文本/二进制/文件，中文与 emoji 分块、空流、并发流、异常 trailer、长度和序号边界、发送者退出、慢消费者、取消，以及大文件与 RPC 共存。文件内容以 hash 对比。沿用现有 Go 互通夹具扩展，不修改对照 Go SDK。

### M2：编码媒体输入输出，再扩展 RTP/RTCP

- 新增建议类型 `EncodedVideoSource/EncodedAudioSource`、`EncodedMediaStream`，包含 codec/fmtp、采集时间/PTS、duration、关键帧标记和自有 buffer；不公开后端类型。
- 视频首批 H.264/VP8，音频首批 Opus；H.265 按当前需求和后端能力单独交付。明确 Annex-B/AVCC、SPS/PPS/VPS、access unit 边界、参数变化和错误恢复契约。
- 复用图内编码发送适配及原生 RTP packetizer/RTCP 反馈，验证当前 native buffer 透传的调度和丢帧行为；不能把内部透传链路直接承诺为无损外部编码输入。
- 接收侧在解码前增加受控编码帧输出节点；应用可选择解码、编码输出或同时输出。先隔离所有权和慢消费，不阻塞网络回调。
- 文件原码发送按单调时钟 pacing；实时源过载后丢弃应恢复到可解码边界，不能随机丢参考帧后继续发送依赖它的帧。
- RTP/RTCP 分两步：先 packet observer、RTCP 事件、关键帧请求；再做注入可行性验证。注入需要 SSRC/PT/扩展 ID 映射、序号时间戳与 RTX/NACK/拥塞控制边界，不能绕过 WebRTC 的安全传输直接发 UDP。
- 同批补齐 Go 已有的采集时间/用户时间戳/帧 ID 等公开元数据中业务需要的部分；其余字段明确 unsupported。

验收：C++↔Go 编码样本双向解码；原码输入不得经过本地解码/再编码；关键帧恢复、参数变化、时间戳回绕、EOS、拥塞、重新发布和 rejoin。原始 RTP 注入是独立交付门槛，不能由编码帧互通替代。

### M3：Simulcast、备用编码与同步

- 发布选项增加 `VideoEncoding` 列表（RID、缩放、码率、帧率、active），通过原生 send_encodings 与 AddTrack 上报真实层信息，先完成 VP8 三层。
- 扩展 GraphVideoSender 的实际编码输出和 codec metadata 路由；每层独立启停，码率反馈进入真实编码器，保留关键帧请求和重连配置。不能复制单路压缩包模拟三层。
- 增加 `BackupCodecOptions` 与策略。复用一个稳定 publication/source 身份，处理 SubscribedQualityUpdate 和需要的音频 codec 更新，按请求启动备用编码；测试 REGRESSION 与 SIMULCAST 不同策略。是否全体切换取决于配置和服务端协议，不能给出无条件承诺。
- 接收图按 participant/同步组映射 RTP/RTCP SR 到统一呈现时间，接入实际音频播放位置；无音频回退单调时钟。重连重置时间映射，隔离参与者时钟。

验收：三层真实独立解码、按质量订阅、带宽收缩、逐层 OFF/ON；H.265/H.264 混合能力订阅者及回退后重连；脉冲/闪光合成媒体的长时同步。先基线测量再固定 AV 偏差指标，设备实际播放同步另列人工验收。

### M4：DataTrack

- 新增 `LocalDataTrack/RemoteDataTrack/DataFrame`，实现发布/取消发布确认、订阅、subscriber handles、schema 与 frame encoding 元数据。
- 实现官方包格式、分片/重组、序列与用户时间戳、过期帧清理、发送拥塞时保留最新完整帧的策略。
- 维护队列/重组上限和 dropped/expired/error 统计。resume 与 rejoin 分开处理，重建后丢弃旧 handles 和旧帧。
- 可复用 M1 的资源限额、停止和调度基础，但 DataTrack 使用自己的传输状态，不能套用可靠文件流的交付假设。

验收：使用确认支持 DataTrack 的固定官方服务端，C++↔Go 双向收发、schema、重复名称、超时、缺片/乱序、慢消费、取消订阅、重连及跨代次隔离。环境不支持时报告未验证或 unsupported。

### M5：E2EE

- 新增 KeyProvider、密钥轮换和加密状态事件；密钥获取由调用方提供，不新增服务端管理或密钥分发服务。
- 先实现数据包 EncryptedPacket，再实现 Opus/H.264 媒体，随后 H.265；DataTrack cryptor 在 M4 之后加入。
- 加密位于编码后、RTP packetizer 前；解密位于组帧后、解码前。优先评估 M137 标准 FrameEncryptor/FrameDecryptor 与现有图路径的兼容性，保证每帧只经过一次 cryptor。
- 按 Go 的 wire 格式、key index、IV/nonce、AAD、ratchet、codec-specific 处理及服务端插入帧标识实现；复用成熟密码库，不自定义加密协议。
- 密钥缺失、认证失败拒绝输出；轮换、重连和重新发布不得重用 key/nonce 组合，密钥不写日志。

验收：固定 Go 测试向量、双向解密、错误密钥、篡改、轮换、乱序/旧帧、SIF 处理和清理。加密格式互通与目标 codec 实际可编解码分别验收。

### M6：连接模式、剩余策略与交付

- 给 PeerTransport 增加 single-PC 策略，补齐对应 Join、预发布、协商方向、媒体和数据复用；保留默认双 PC 兼容。
- 将首次连接故障处理从“收到 JoinResponse 前”扩展至初次 ICE/媒体就绪，统一总预算、候选切换、取消和状态回收。避免重复回调、重复发布和遗留会话。
- 补齐 ClientConfiguration 中需要支持的 codec/hardware 策略、IPv6 等用途配置和自有日志 sink；不支持的策略明确报告，不能静默假装生效。
- 按实际目标交付 Windows、Linux、macOS 构建与 consumer 验证。硬件、ARM64、移动端和预编译包分别定义范围，不以存在 CMake preset 证明支持。

验收：双/单 PC 下纯数据、媒体、多轨、重连、取消与关闭；首次信令成功但 ICE 失败的故障注入；真实 Cloud 区域/迁移专项；长期内存/线程/队列稳定性与平台矩阵。

## 5. 顺序与代码落点

默认顺序：M0 → M1 与 M2 分别交付 → M3；M4 在数据底座完成后推进，M5 按数据/媒体/DataTrack 的依赖分批推进，M6 的连接策略可在 M0 后单独交付。各批都有自己的功能开关和验收，不等待整套方案完成才发布。

如果近期目标是设备视频接入和 H.265/H.264 回退，M2 和 M3 应排在 M1 前；这是业务优先级选择，不影响总体架构。完整原始 RTP、SVC 和硬件零拷贝不应阻塞基础补齐。

| 文件/模块 | 建议职责 |
|---|---|
| `include/livekit/room.hpp`、`participant.hpp`、`media.hpp` | 增量入口、选项、兼容旧调用 |
| `include/livekit/streams.hpp`、`encoded_media.hpp`、`rtp.hpp`、`data_track.hpp`、`encryption.hpp`（建议新增） | 自有公共类型与生命周期契约 |
| `src/engines/rtc/` | DataRouter/Scheduler、流状态、DataTrack、publication、多 PC 策略；复用现有请求与恢复模块 |
| `src/media_nodes/`、`src/media_graph/`、`src/backends/webrtc/` | GraphEngine 媒体节点、编码样本、层/codec 路由、同步与 cryptor adapter |
| `protocol/`、`tests/protocol_contract.py` | 上游 schema 增量与字段合约 |
| `tests/go_interop/`、`tests/go_interop_integration.py` 及新增专项 | 双向互通、故障、背压、生命周期和负面用例 |

## 6. 验证要求

- 每批先做协议/状态机单测，再做原生无窗口测试与 C++↔Go 集成；服务端版本按能力固定，仅作为测试依赖。
- 本次新增文档不新增实现测试，也不把历史 CTest 或集成结果表述为当前工作树重新验证通过。
- 队列、取消和关闭必须验证边界；大数据、媒体、RPC 并存时必须测量时延与资源上限，不能只测空载 echo。
- 跨平台、真实 Cloud、硬件设备、音频播放/AEC 与实际音画同步单独登记状态。自动化和实际设备人工验收分开报告。
- 遵守仓库约定，不使用 computer-use、桌面自动化或 @oai/sky；采用编译、单元/集成测试、无窗口测试和程序内渲染截图。

## 7. 主要源码依据

- [C++ 公共能力声明](../../livekit-sdk-cpp/src/engines/rtc/sdk.cpp)：已支持项与明确 unsupported 项。
- [C++ Room](../../livekit-sdk-cpp/include/livekit/room.hpp)、[Participant](../../livekit-sdk-cpp/include/livekit/participant.hpp)、[MediaSpec](../../livekit-sdk-cpp/include/livekit/media.hpp)：公开契约、协议和传输设置、单层 Dynacast。
- [单层订阅质量处理](../../livekit-sdk-cpp/src/engines/rtc/subscribed_quality.hpp)、[DecoderAdapter](../../livekit-sdk-cpp/src/backends/webrtc/graph_video_decoder.cpp)、[接收图](../../livekit-sdk-cpp/src/engines/rtc/video_receive_graph.cpp)：当前编码、解码反馈和同步边界。
- [Go room.go](../../../server-sdk-go/room.go)、[localparticipant.go](../../../server-sdk-go/localparticipant.go)、[localtrack.go](../../../server-sdk-go/localtrack.go)、[publication.go](../../../server-sdk-go/publication.go)、[备用编码选项](../../../server-sdk-go/localtrackoptions.go)。
- [Go streams.go](../../../server-sdk-go/streams.go)、[DataTrack 公开类型](../../../server-sdk-go/datatrack/datatrack.go)、[DataTrack 发布](../../../server-sdk-go/localdatatrack.go)、[E2EE](../../../server-sdk-go/e2ee.go)、[PCM 接收限制](../../../server-sdk-go/pkg/media/pcmremotetrack.go)、[同步工具](../../../server-sdk-go/pkg/synchronizer/syncengine.go)。
- [原分阶段方案](cpp-sdk-client-parity-plan.md)、[历史实施记录](../../livekit-sdk-cpp/docs/client-parity-progress.md)、[2026-10-28 传输策略复测记录](../testing/uav-sfu-go-cpp-revalidation-20261028.md)：只按各自范围引用，不合并为整套 SDK 已验收。
