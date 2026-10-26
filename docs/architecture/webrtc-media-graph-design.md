> 2026-10-26 更新：采集、视频编码、解码、渲染和录制已拆为独立节点，通过 GraphEngine::loadFromNodes 和强类型事件边创建实际媒体图。视频发送采用图侧真实编码 + 标准 Custom VideoTrackSource/native buffer + EncoderFactory 透传适配，不修改 WebRTC 源码。WebRTC 仍调度透传触发帧；音频编解码保留原生调度。视频接收通过自定义 DecoderFactory 在 Decode 入口送入每轨完整接收图，解码像素不回交 WebRTC；呈现由图负责，原生解码后统计和音画同步反馈不再自动保留。当前实现和边界见 [实现说明](../../livekit-sdk-cpp/docs/media-graph-webrtc.md)。

# WebRTC 节点化接入 Media Graph 方案

日期：2026-10-26。状态：设计基线，首版实施情况见下方链接。目录重构后的归属见 [仓库结构](repository-layout.md)。本文类型、接口、目录和执行模式描述原设计目标，实际支持范围以实现说明为准。

后续实施记录：同日已落地 RTC 节点与四类 Factory 的首版闭环，实际接口、验证和未覆盖范围见 [实现说明](../../livekit-sdk-cpp/docs/media-graph-webrtc.md)。下文保留设计基线，不将全部后续目标标记为已实现。

目标：基于 [SDK 新架构](sdk-architecture.md)，将采集、编码、解码、渲染拆为独立节点，通过 WebRTC EncoderFactory / DecoderFactory 接入 RTC。首发建议 Windows x64、CPU I420、VP8 + Opus；其他格式与平台按能力扩展。

## 1. 核心决策

采用“图管理节点与资源，WebRTC 驱动 RTC 编解码”的方式：

- 采集、编码、解码、渲染分别拥有配置、状态、资源和指标，可单独替换与复用。
- 自定义 Factory 返回 WebRTC 接口适配器；适配器把真正的编解码交给 Media Graph 中的 codec 节点执行。
- WebRTC 继续负责 SDP/ICE/DTLS/SRTP、RTP/RTCP、拥塞控制、码率分配、pacing、接收组帧、抖动缓冲、视频解码前调度、NetEq 和音频播放；视频解码后的呈现由媒体图接管。
- GraphFlow 承担图组织与控制；逐帧数据和高频码控走专用媒体连接及 codec 调用接口。
- 普通 RTC 发布仍从原始帧进入 WebRTC，由 WebRTC 在合适时机调用编码节点。第一版不提供任意预编码包直接注入 PeerConnection 的能力。

这细化了原架构中“WebRTC 编解码保留在 RTC 后端”的描述：编解码操作成为独立媒体节点，但 RTC 场景下的调用时机及网络控制权仍归 WebRTC。视频接收只保留图内呈现出口，不同时运行 WebRTC 原生视频播放出口。

## 2. 当前源码与需要补齐的部分

| 依据 | 当前实现 | 接入工作 |
| --- | --- | --- |
| `livekit-sdk-cpp/src/engines/rtc/room.cpp` 中 `lk::Runtime` | `EnableMediaWithDefaults(deps)` + `CreateModularPeerConnectionFactory`；默认 codec factories | 注入自定义 factories，抽出 RTC runtime 与 codec host |
| `src/internal/lk/media.hpp`、`src/media.cpp` | `VideoSource`、`MediaPump`、`TrackSink`；文件输入、回调、录制与输出存在耦合 | 拆源适配、订阅出口、渲染及录制分支 |
| `src/media_graph/playback_graph.*` | 固定单个 FFmpeg 复合节点，Player 线程串行访问 | 抽取通用图支持，增加 RTC graph 与后端驱动节点 |
| `src/media_graph/channel.hpp` | 有界队列、满时拒绝、按时间和 generation 取帧；调用者负责串行化 | 保留播放器语义，增加 RTC 跨线程有界通道，禁止直接并发复用 |
| `include/livekit/media_core/frame.hpp` | 文件时间线上的 RGBA8、float32 PCM、自有只读 Buffer | 增加 I420/NV12、多平面存储、编码帧、时钟域；保留现有 Player 契约 |
| `player/CMakeLists.txt` | 已有 `LiveKit::MediaCore` / `LiveKit::MediaGraph`；图目标依赖 FFmpeg 节点 | 抽到公共构建入口，解除通用 graph 对 FFmpeg 的依赖 |
| `graphflow-cpp/core/graph_node.h` | GraphNode、生命周期与事件边 | SDK 内部适配媒体端口、执行器和后端托管节点，不向 GraphFlow 加入 WebRTC 类型 |

当前播放器代码比部分总体文档更新，不能以“media_graph 尚不存在”为前提重新建一套。现有工作区修改作为基线保留。

## 3. 节点划分

下表名称为设计名，公共 API 不暴露 `webrtc::*` 或 GraphFlow 类型。

| 节点 | 输入 → 输出 | 职责及执行方式 |
| --- | --- | --- |
| `CameraCaptureNode` | 设备 → VideoFrame | 摄像头采集；后端回调驱动 |
| `ScreenCaptureNode` | 屏幕/窗口 → VideoFrame | 桌面采集；显式设置 screencast/content type |
| `AudioCaptureNode` | 设备 → AudioFrame | 麦克风/可用系统音频；共享设备服务驱动 |
| `VideoConvertNode` / `AudioConvertNode` | Frame → Frame | 尺寸、像素格式、采样格式和采样率转换 |
| `VideoEncoderNode` | VideoFrame + EncodeControl → EncodedVideoFrame | 独立编码实例；RTC 下由编码器适配器驱动 |
| `VideoDecoderNode` | EncodedVideoFrame + DecodeControl → VideoFrame | 独立解码实例；RTC 下由解码器适配器驱动 |
| `AudioEncoderNode` / `AudioDecoderNode` | PCM ↔ 编码音频 | 同步 codec 操作；保留 Opus/NetEq 所需语义 |
| `RtcPublishNode` | 原始音视频 → 本地轨道 | 轨道源适配、发布控制、源适应；无独立编码实现 |
| `RtcEncodedSourceNode` | DecoderAdapter → 待解码请求 | 按已注册的接收 SSRC 路由，保留目标呈现时间 |
| `RtcSubscribeNode` | 远端音频轨道 → PCM | 音频 sink/录制出口；视频已改走编码帧入口 |
| `VideoPresentNode` | 解码帧 → 到期画面 | 本地时钟、有界队列、迟到丢帧；实际音频主时钟待接入 |
| `VideoRenderNode` | VideoFrame → RenderTarget | 应用渲染线程执行；支持预览与远端输出 |
| `AudioOutputNode` | PCM/播放拉取 → 设备 | 与 ADM/共享音频服务协调，处理实际输出与设备时钟 |

首期采集后端优先评估当前 WebRTC 构建中的 video capture / desktop capture 模块；未编入或平台能力不足时使用独立 OS 后端。渲染复用现有 SDL 能力抽取实现，窗口创建和 UI 事件继续由应用管理。

`RtcRuntime`、`CodecRegistry`、`DeviceService`、`MediaClock` 是共享服务，不为了节点化而强行变成节点。信令、成员和发布订阅状态继续由 RTC 场景引擎管理。

## 4. 实际数据链路

### 4.1 视频发送

```text
CameraCapture / ScreenCapture
    ├─ MediaChannel → VideoRender                         本地预览
    └─ MediaChannel → RtcPublish / TrackSource
                         ↓
                    WebRTC 源适应、发送调度与码率控制
                         ↓ VideoEncoderAdapter::Encode
                    VideoEncoderNode → CodecBackend
                         ↓ EncodedImageCallback
                    WebRTC RTP / pacing / SRTP → 网络
```

`VideoEncoderNode` 是图中的真实可观测执行节点，由 Factory 建立执行绑定；不是在采集与 RtcPublish 之间额外串一个普通异步编码器。RTC 子图的内部调用边需要标注为后端驱动边，不能用普通的线性原始帧流水线替代这一过程。

源适应应响应 sink wants，按 WebRTC 的要求丢帧/缩放或调用显式转换节点。当前 `VideoSource::push()` 只调用 `OnFrame()`，不能假定继承 `AdaptedVideoTrackSource` 就完成全部适应逻辑。缩放和帧率决策采用单一执行路径，避免与外部处理重复。

### 4.2 视频接收

```text
网络 → WebRTC SRTP / RTP / 重排组帧 / 抖动缓冲 / 解码调度
                         ↓ VideoDecoderAdapter::Decode
                    RtcEncodedSourceNode
                         ↓
                    VideoDecoderNode → CodecBackend
                         ↓ 内部解码回调，像素留在图内
                    VideoPresentNode → VideoRender
                    解码输出另分流到 RecordingNode
```

按当前确定的边界，解码后的像素不回交 WebRTC。自定义 DecoderFactory 返回入口适配器，Decode 通过同步图事件调用真实 codec，并把真实返回码交回 WebRTC；无需修改 WebRTC 源码。解码输出进入同一张接收图的呈现/渲染/录制节点。目标呈现时间随请求保留，呈现队列有界。原生解码耗时估计、解码后统计和音画同步反馈不会自动保留；当前没有接入音频设备主时钟，完整同步仍是待实现能力。

### 4.3 音频

```text
设备输入 → AudioCapture → GraphAudioDeviceBridge(ADM)
         → WebRTC APM / 发送音频处理
         → AudioEncoderAdapter → AudioEncoderNode → WebRTC RTP

WebRTC 接收 / NetEq → AudioDecoderAdapter → AudioDecoderNode
         → 返回 NetEq（PLC/FEC/时间伸缩等）→ WebRTC 混音
         → GraphAudioDeviceBridge(ADM) → AudioOutput → 设备
```

PCM 最终播放必须保留 NetEq、混音、设备拉取和 AEC 参考链路。音频设备由同一个服务/ADM 桥管理，采集节点和输出节点表示独立操作，不表示各自重复打开一套硬件。

每轨音频 sink 可提供处理/录制分支，但与 ADM 混音播放路径只能选择明确的路由，避免同一声音重复播放。Player 与会议共享设备时，最终实际播放的混合音频需纳入 AEC 参考；首期共享混音尚未实现时，明确设备互斥能力，不能宣称已支持并行。

自定义 PCM/文件输入可保留 AudioSource 适配，但必须单独标明其 APM 路径，不能假定当前 `AudioSource::push()` 与麦克风 ADM 路径具有相同回声消除行为。

## 5. Factory、适配器与节点后端

### 5.1 两类注册分别承担不同职责

1. GraphFlow/Media Graph 的节点注册表：注册 `VideoEncoderNode` 等节点类型，管理图内实例与资源。
2. WebRTC 的 factories：注册可协商格式，并按需返回 `webrtc::VideoEncoder` / `VideoDecoder` 适配器。

连接关系：

```text
GraphVideoEncoderFactory::Create(env, format)
    → CodecNodeHost 创建并登记独立 VideoEncoderNode
    → 节点从 CodecRegistry 取得 Backend 实例
    → 返回 GraphVideoEncoderAdapter，持有节点执行租约

WebRTC → Adapter → Node → Backend
编码输出：WebRTC ← Adapter ← Node ← Backend callback
视频解码输出：Backend callback → Node → Present → Render / Recording
```

初版 Backend 包装 `CreateBuiltinVideoEncoderFactory()` / `CreateBuiltinVideoDecoderFactory()` 创建的 codec，随后可替换系统硬件或 FFmpeg 实现。后台 factory 必须是独立 delegate，不能调用外层 Graph factory，避免递归创建。

编码器 Backend 若使用 builtin encoder factory，需持有该 factory 至其全部 encoder 销毁后：当前 builtin 的 simulcast adapter 引用了内部 factory。一个节点可以封装该 adapter 管理的多个层，不要求“一节点等于一 SSRC”。

### 5.2 注册位置

在当前 `lk::Runtime` 创建 PeerConnectionFactory 的位置注入。以下代码只是目标接口示意：

```cpp
// deps 的 network / worker / signaling / task_queue / adm 已设置。
deps.video_encoder_factory =
    std::make_unique<GraphVideoEncoderFactory>(codec_host, codec_registry);
deps.video_decoder_factory =
    std::make_unique<GraphVideoDecoderFactory>(codec_host, codec_registry);

// 音频 factory 在本仓库 WebRTC 中采用 scoped_refptr / RefCountInterface。
deps.audio_encoder_factory =
    webrtc::make_ref_counted<GraphAudioEncoderFactory>(codec_host, codec_registry);
deps.audio_decoder_factory =
    webrtc::make_ref_counted<GraphAudioDecoderFactory>(codec_host, codec_registry);

webrtc::EnableMediaWithDefaults(deps);
factory = webrtc::CreateModularPeerConnectionFactory(std::move(deps));
```

已核对当前 `enable_media_with_defaults.cc`：只填充空缺 factory，随后调用 `EnableMedia(deps)`。因此必须先注入，再调用该 helper 完成媒体引擎装配；不能在媒体引擎已经创建后仅覆盖 deps 字段。

### 5.3 视频接口映射

| WebRTC 接口 | 节点行为 |
| --- | --- |
| Factory `GetSupportedFormats` / `QueryCodecSupport` | 从实际可创建的 Backend 能力生成 SDP formats；正确报告 profile、packetization 和 scalability 支持 |
| Factory `Create(const Environment&, const SdpVideoFormat&)` | 新建独立 codec 会话及执行租约 |
| Encoder `InitEncode` | 配置尺寸、帧率、层、码率及内容类型 |
| `Encode(frame, frame_types)` | 帧引用与逐次关键帧请求进入节点，按契约返回提交状态 |
| `SetRates` | 保留完整分层 bitrate allocation、framerate、bandwidth allocation |
| loss / RTT / loss notification / FEC override | 按 Backend 能力准确转发，不能因包装丢失默认实现的行为 |
| `RegisterEncodeCompleteCallback` | 管理回调租约；完整转发 EncodedImage、CodecSpecificInfo、返回值及丢帧通知 |
| `GetEncoderInfo` | 返回真实 alignment、native handle、simulcast、硬件加速等能力 |
| Decoder `Configure` / `Decode` | 转发配置、编码帧与 render time；返回解码状态 |
| `RegisterDecodeCompleteCallback` | 仅控制内部 codec 回调启停；解码像素进入图，不调用 WebRTC 注册的回调 |
| `Release` | 在所属执行序列关闭当前 codec 会话并等待其回调静默；允许后续重新初始化 |

`SetRates` 等高频命令与 Encode 必须有明确的先后顺序，不能交给无序 EventBus；图配置只提供上限/偏好，最终 RTC 实时目标由 WebRTC 决定。关键帧请求通过 WebRTC 传入的 `frame_types` 到达节点。

### 5.4 音频接口不能照搬视频异步队列

音频工厂同样包装 `AudioEncoderFactory` / `AudioDecoderFactory`，复用 builtin Opus 实现。`AudioEncoder::Encode` 同步返回编码结果，节点在 WebRTC 调用序列内完成 `EncodeImpl`；不能 enqueue 后返回一个空结果作为异步占位。

音频 decoder 需完整覆盖 `ParsePayload`、返回的 `EncodedAudioFrame::Decode` 及其生命周期，以及冗余解码、PLC、packet duration、FEC、Reset 等契约。仅包装旧的 `DecodeInternal` 会漏掉实际调用路径。音频网络自适应、DTX、码率与丢包反馈也须透传。输入按 codec 要求组织 10 ms 块，实际输出包长允许是多块聚合。

## 6. 图内实例、轨道关联与调度

### 6.1 解决 Factory 没有 track ID 的限制

视频接收当前实现：OnTrack 从接收器参数登记 SSRC → 接收图；Factory 适配器在 Decode 读取 PacketInfos 的 SSRC 路由，未知或冲突值拒绝。每轨 GraphEngine 统一拥有编码帧入口、解码、呈现、渲染与可选录制节点；codec 的 Configure/Release 仍由适配器管理，不在图停止线程调用原生 codec Release。以下 Host 描述保留为进一步通用化设计。

当前视频 `Create(env, format)` 没有 MID、SSRC、track ID，音频 codec pair ID 也不是业务 track ID。因此不按 codec 名、创建顺序或线程局部变量猜测归属。

- RTC 场景引擎持有会话级 `CodecNodeHost`，与该会话的 factory scope 一起注入。
- 每次 Create 生成独立 `codec_instance_id`，在会话 RTC 子图中登记一个实际节点，保存执行状态与统计。
- 静态图描述 codec policy/节点模板；实际实例由协商与 WebRTC 重建行为产生，属于后端托管子图。
- Factory 快速创建节点与租约，不从 WebRTC codec 线程同步调用 GraphEngine 改拓扑。Host 的并发实例表是执行事实来源，GraphFlow 的状态展示在控制线程串行更新。
- 第一版明确支持 session + codec instance 级指标；业务 track 关联只采用可验证信息。不完整映射显示为 unknown。
- 如需“每条轨道选择不同 Backend”或精确 codec→MID/SSRC 关联，另设带 stream context 的后端创建扩展点；评估局部 WebRTC 补丁或连接范围隔离后实施。基础工厂方案不虚构已有能力。

所有重建、并发相同格式、多 PeerConnection 和 simulcast 测试均按独立实例执行。graph stop 必须覆盖 host 中尚未投影到展示拓扑的实例。

### 6.2 两种执行模式

新增 `GraphDriven` 和 `BackendDriven` 执行契约：前者由播放器/图执行器驱动，后者由 WebRTC 回调调用。两者共享节点操作与 Backend 能力，但不共享同一个活动 codec 实例。

RTC 编解码节点不再由普通图 worker 额外调度。初版保留 delegate 的调用序列和回调语义，尽量不增加 codec 前后排队；未来异步硬编节点必须自行提供有界在途请求、取消及回调静默契约。

GraphFlow NodeBase 生命周期只在图控制序列串行执行；codec 的 Init/Configure/Release 是另一个独立会话状态机。不能让图 stop 和 WebRTC Release 同时释放 Backend。`CodecNodeHost` 负责两者之间的停止协议。

媒体连接分为普通有界 `MediaChannel` 与后端调用/回调边。后者传递持有所有权的帧引用并遵循 WebRTC 契约，不强制经过通用工作线程或队列。

## 7. 数据契约、线程与生命周期

### 7.1 数据模型

在保留已有 Player RGBA/PCM API 的基础上逐步引入通用 Buffer/格式描述，通过适配转换迁移，避免直接改变现有 `rgba`、`pcm` 字段语义。

- VideoFrame：多平面地址/stride、I420/NV12/RGBA、尺寸、rotation、color space、时间戳、clock domain、generation；GPU 存储预留设备与同步信息。
- AudioFrame：采样格式、采样率、声道布局、samples-per-channel、时钟域；显式支持 float32 与 PCM16 转换。
- EncodedVideoFrame：共享编码缓冲、codec/format、RTP timestamp、capture time、关键帧、层信息和依赖元数据。
- 编码包的文件 PTS/DTS 与 RTP timestamp 分别建模；RTP 32 位回绕由 RTC 适配层处理，不能把 RTP ticks 当作微秒或直接当作文件 DTS。
- WebRTC codec-specific/timing/packet metadata 先在私有适配层无损保留；公共字段尚不能表达时，不允许压缩成“字节数组+关键帧”后丢失信息。

通过内部 Buffer holder 保持 `webrtc::VideoFrameBuffer` / encoded buffer 引用计数，可行时零拷贝。callback 参数或临时 codec info 不能以裸指针逃逸；异步分支必须持有内容或复制小型元数据。GPU 路径以后按能力验证。

### 7.2 线程与背压

- 保留 WebRTC network / worker / signaling / codec queues；图控制与 UI 各自有明确执行序列。
- 采集入口、预览、track sink 输出采用跨线程有界队列；预览和发送分支独立，不因慢 UI 阻塞采集或网络。
- 第一版可从视频最多 2 帧、额外限制字节数与帧龄的策略起步，最终值通过测量确定。只对允许丢弃的原始/已解码视频使用 latest-wins。
- 编码帧不能普遍使用 drop-oldest，特别是带参考依赖的视频；接收侧由 WebRTC 调度，codec 错误或丢弃需按原生返回码/通知反馈，使其恢复关键帧。
- 音频回调采用预分配缓冲与有界环形队列，禁止等待 UI、磁盘 I/O 和大块分配；欠载补静音、过载记录 discontinuity 并按明确策略处理，不套用视频丢帧规则。
- 录制与应用视频回调从现有 TrackSink 分离到独立分支；延续旧 API 的兼容投递时也必须限制排队，不能按每帧无限投递到 Room 会话队列。

### 7.3 停止与重建

启动顺序：准备输出/资源与 host → 创建 factories / PC → 完成轨道绑定与媒体协商 → 激活输入。Codec 实例可在协商过程中延迟创建，不能要求启动采集前所有 codec 必然存在。

停止顺序：

1. 场景进入 stopping，host 禁止新 codec 会话，停止输入；提升 generation，拒绝迟到工作。
2. 在所属线程解除 source/sink/observer 绑定并关闭 PC，让 WebRTC 完成 codec Release。
3. Host 等待在途 codec 操作与回调静默；执行队列此时仍存活。禁止在 callback 内等待自身完成。
4. 清空 RTC 输出队列，结束节点执行租约；其他非 RTC 文件分支按自身 drain/cancel 规则关闭。
5. 释放 factories、codec delegates 和图资源，再停止 WebRTC 线程；共享设备只释放当前会话租约。

若用户要求关闭某个活动 codec 节点，先由场景引擎撤销对应媒体使用或重建相关后端，不能直接销毁仍被 WebRTC 持有的节点。关闭超时报告失败并保留仍被引用的清理状态，不能用强制 free 伪装成功。

重协商/编码器重建采用新 codec instance；同一对象 Release 后 Init 使用新 codec generation。停止完成后不再向应用投递该代次回调。

## 8. 代码与构建组织

建议继续放在 `livekit-sdk-cpp`，不新建平行 SDK：

```text
include/livekit/media_core/           通用帧、Buffer、格式、时钟与能力
src/media_graph/
  media_node.* / ports.*             SDK 内部 GraphFlow 适配
  channel.hpp / realtime_channel.*   保留播放队列，增加跨线程通道
  codec_node_host.*                  后端托管实例、租约、关闭协调
  playback_graph.* / rtc_graph.*     场景构图
src/media_nodes/
  capture/                          相机、桌面、音频源
  codecs/                           音视频 Encoder/DecoderNode
  render/                           视频渲染、音频输出
  rtc/                              发布/订阅节点
src/backends/webrtc/
  runtime.* / codec_factories.*      WebRTC runtime 与四类 factories
  codec_adapters.* / codec_backend.* 适配器与 builtin delegate
  frame_bridge.* / audio_device.*   帧和 ADM 桥接
```

构建依赖目标：

```text
MediaCore ← MediaGraph（只依赖 GraphFlow 等通用基础）
MediaGraph + MediaCore ← MediaNodesWebRTC ← RTC / LiveKit::SDK
MediaGraph + MediaNodesFFmpeg ← Player
MediaCore + 渲染后端 ← MediaNodesRender
```

把 MediaCore/MediaGraph 定义从 player 专用 CMake 提升到公共模块入口；`PlaybackGraph` 中的 FFmpeg 组装归 Player，避免通用 graph 反向依赖 FFmpeg。WebRTC 节点按选项构建，Player-only 继续不链接 RTC。公共头文件保持无 WebRTC/GraphFlow 类型。

## 9. 实施顺序与验收

| 阶段 | 交付 | 验收条件 |
| --- | --- | --- |
| P0 公共底座 | 公共构建入口、兼容帧适配、RTC 通道、BackendDriven 契约、codec host | Player-only / RTC-only / 同时启用都可构建；现有 Player 功能保持 |
| P1 视频 Factory 闭环 | GraphVideoEncoder/DecoderFactory、独立视频 codec 节点、VP8 builtin Backend；先接现有合成源 | 发送/接收实际调用图节点；每个 codec instance 对每个输入提交只调用一次 Backend，无重复编码/解码 |
| P2 视频采集与输出 | Camera/Screen、TrackSource/TrackSink 桥、独立 Renderer、旧回调兼容 | 一路采集预览与发送；慢预览不阻塞 RTC；远端从正常输出时序呈现 |
| P3 音频拆分 | Audio factories/nodes、ADM 桥、采集输出设备协调 | Opus 双向通话，DTX/FEC/PLC 行为与基线一致，静音/切换/欠载恢复正确；真实设备验证回声与同步 |
| P4 健壮性与扩展 | 多轨、重建、能力选择、可选硬编/硬解 | 并发同格式实例隔离、停止无悬空回调、模拟弱网、硬件失败回退、分层能力按实际验证开放 |

P1/P2 是视频里程碑，P3 完成后才算音视频四类操作都节点化。硬件编解码与分层发布不作为初版已支持能力。

重点测试：

- 工厂能力列表与实际创建一致；codec-specific 元数据、时间戳、关键帧请求、SetRates 顺序完整透传。
- 默认 delegate 调用轨迹与包装后等价；允许 WebRTC 合理丢帧及多层输出，不能要求采集帧数等于编码帧数。
- 不支持格式、初始化失败、codec 回调失败、Release/重建、并发 Create 均有确定状态和错误。
- 慢 UI/录制、队列溢出、分辨率变化、源切换、RTP 回绕、旧 generation 回调不会破坏其他分支。
- 多 Room、多轨同 codec、双 PC、重复入退房无状态串扰；轨道映射未知时不误标。
- 音频实际 `ParsePayload → EncodedAudioFrame::Decode`、PLC/FEC 路径经过节点且不丢语义。
- 实际 SDK→SFU→SDK 媒体回归，并与改造前基线比较 CPU、内存、排队、编码/解码/呈现时延。端到端延迟预算待实测确定，不把排队配置当作性能承诺。

现有 RTC 文件四轨和跨系统回归仍有已记录失败，应先保留可重复基线以区分新增回归。此次仅评审方案，未运行构建或媒体验收。

## 10. 本方案的首期边界

首期采用 Windows x64、VP8/Opus 软件后端、视频 I420、固定 RTC 子图加动态 codec 实例；保留旧 Room 与 Player API。通用高级图 API、无缝热换图、外部预编码媒体发布、逐轨硬件策略、GPU 零拷贝和完整 simulcast/SVC 发布分别作为后续能力验收。

其中 Factory 驱动独立 codec 节点、采集与渲染拆分、WebRTC 媒体控制闭环、跨线程生命周期是本次实现必须完成的架构部分，不作为可选优化。
