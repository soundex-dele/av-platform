# Go LiveKit SFU + C++ SDK：本机需求验证与修复报告

**当前结果按模拟验收**：用户已明确无需真机，见 [模拟验收报告](uav-sfu-go-cpp-simulation-acceptance.md)。下文完整产品／设备验收结论作为历史记录保留。

**最新复测与新增实现**：见 [2026-10-28 严格传输策略及 34 项当前状态](uav-sfu-go-cpp-revalidation-20261028.md)。下文保留此前执行记录；最新报告单独区分本机子项与完整需求验收。

更新日期：2026-10-28（含 2026-10-27 历史记录）。基线：[V1.11 需求评估](../architecture/uav-sfu-go-requirements-assessment.md)，共 34 项。用户已授权执行、修复，并将本轮范围明确为本机验证；未进行 ARM64、Android、iOS、Web 实机验收。

## 1. 结论

**本机验证及部分修复已完成；34 项需求尚未完整满足。** 2026-10-28 当前源码完整运行的六个媒体场景全部通过，新增 H.264/H.265 发布端聚合订阅启停验证。历史 TCP 间歇连接失败尚未定位根因，仍保持未关闭。不能将这些结果扩展为机载交付、真实回放、全体编码回退、视频 FEC、弱网 QoS、容量或 8 h 长稳通过。

本轮交付：可运行的原生 C++ 示例、Go 探针与修复回归用例、34 项验收矩阵、可选 FFmpeg RTC 编解码后端、Go 服务端修复，以及原始测试记录。所有验证无窗口，不操作桌面，不使用摄像头/麦克风/扬声器。

仍需优先实现：H.265→H.264 REGRESSION 闭环、真正 pacing/有界队列、视频 FEC、业务成员/回放生命周期、完整质量关联及严格动态资源准入。

### 2026-10-28 增量实现与验证

新增可选 `MediaSpec::dynacast`，接入 Go 服务端 `SubscribedQualityUpdate`，通过现有 GraphEngine 停止/恢复单层实时视频源与编码，同时设置 RTP sender active。保留发布 SID；支持应用 I420、生成画面和捕获源，拒绝音频及文件/网络回放。详见 [SDK 使用说明与边界](../../livekit-sdk-cpp/docs/live-video-dynacast.md)。

- [本次完整媒体结果](../../out/uav-sfu-go/20261028-local-dynacast/report.md)：H.264 UDP/TCP、三方 Opus、H.265 UDP、两种编码的 dynacast，共 **6/6 通过**。运行器仍返回 `1`，原因是 Q-06/Q-07 已知缺口，不能解释成全部需求通过。
- 两个 dynacast 场景覆盖观看人数 0→1→2→1→0→1；一人退出后等待 6 s（超过服务端默认 5 s OFF 防抖），其余观看者继续解码；无人观看时源消费与保留的 outbound RTP 字节统计停止增长，重新订阅后同 SID 恢复解码。首次发布仍有建立接收器所需的 bootstrap 帧；不是零观看从第一帧起绝不上传的保证。
- [C++ CTest](../../out/uav-20261028-ctest.log) **5/5 通过**，包含新增信令字段及聚合策略契约；[Python 判定测试](../../out/uav-20261028-runner-tests.log) **6/6 通过**。当前 Go 源码重建及四个需求探针通过执行；下文 518 项 Go 扩展回归是 10 月 27 日记录，本次没有重跑该批测试。
- [扩展集成记录](../../out/uav-20261028-regression-integrations.json) 中 sdk、resume、rejoin、restart、operations、video-source 通过。audio-source 首次因服务端 UDP bind 被 Windows 拒绝而准备失败，未进入客户端测试；测试夹具改为按 UDP 探测端口并限定回环网卡后，[audio-source 复测通过](../../out/uav-20261028-audio-source-recheck.log)。扩展集成使用 VP8/Opus，不证明 H.265 回退或 dynacast 故障恢复。
- [TCP 历史二进制排查](../../out/uav-tcp-investigation/20261028-baseline/results.json) 连续 10 次通过，本次源码完整运行 TCP 也通过；未复现不等于已修复历史间歇故障。
- 端口夹具修改后，使用本次源码构建的 Go 服务再次执行 resume、restart、video-source，均通过；见 [复核退出码](../../out/uav-20261028-harness-recheck.json)。原始 audio-source 准备失败记录保留，不覆盖。

V-08 本机单层源控制已实现并验证；真实硬编启停、多质量层以及 dynacast 专项重连故障注入仍待验收。V-12 全体编码回退没有在本次实现。以下历史执行记录保留，逐项矩阵更新 V-08 的当前状态。

## 2. 执行结果及证据

2026-10-27 历史完整媒体证据目录：[20261027-195306-985708](../../out/uav-sfu-go/20261027-195306-985708/report.md)。目录内 `result.json` 记录源代码提交/工作区状态、二进制 SHA256、Go 版本和各项检查；`report.md` 是运行器生成的完整需求索引。下表为当日结果，当前增量结果见上一节。

| 检查 | 结果 | 实际证明的内容 |
| --- | --- | --- |
| H.264 / UDP | 通过 | 两个独立画面、两名观看者、四份实际解码；独立退订/恢复、撤轨隔离及新 SID 重发 |
| H.264 / TCP | 间歇失败，未关闭 | 完整运行在 viewer-b 加入时出现 `WebRTC transport failed`；独立复测三次均完成多源/多观看解码及双段 TCP 检查。不能判为可靠通过 |
| H.265 / UDP | 通过 | 实际 HEVC 编码、原生 WebRTC RTP、Go SFU 转发、两观看端实际解码和轨道隔离 |
| 三方 Opus / UDP | 通过 | 440/660/880 Hz 的六条有向链路；每条至少 48000 样本，频率误差 <6%；退出语音保留视频及其他双向语音 |
| Go 扩展回归 | 518 个测试/子测试通过 | RTC、dynacast、SFU、pacer、buffer、connectionquality、rtpstats、selector、telemetry；无失败 |
| Go 需求探针 | 4 个探针通过执行 | 实际默认配置、NoQueue 增长、PassThrough 突发、H.265→H.264 dynacast 状态迁移；探针执行成功不代表需求通过 |
| C++ CTest | 5/5 通过 | core、sdk、media_graph、video_frames、ffmpeg_rtc_codecs |
| SDK 扩展集成 | 7/7 通过 | sdk、resume、rejoin、restart、operations、video-source、audio-source |
| 报告判定单测 | 5/5 通过 | 缺协议证据、错误协议、relay、准备失败、不支持编码及 TCP 场景失败不能误报通过 |
| Go 模块完整性 | 通过 | `go mod verify`：all modules verified |

证据索引：

- [Go 518 项 JSONL](../../out/uav-go-regression.jsonl)、[退出码](../../out/uav-go-regression.exit)。`streamallocator` 包没有独立测试文件，不能把它列为其自身单测通过；相关 SFU 测试只是组件证据。
- [C++ 最终 CTest](../../out/uav-sdk-ctest-final.log)、[报告单测](../../out/uav-runner-tests-final.log)、[模块完整性](../../out/uav-go-mod-verify.log)。
- [本轮交付文件与二进制摘要](../../out/uav-delivery-manifest.json)，记录测试源码、实现修复和最终可执行文件的 SHA256。
- [七个 SDK 场景命令与退出码](../../out/uav-regression-integrations.json)；逐项日志：[SDK](../../out/uav-regression-sdk.log)、[resume](../../out/uav-regression-resume.log)、[rejoin](../../out/uav-regression-rejoin.log)、[restart](../../out/uav-regression-restart.log)、[operations](../../out/uav-regression-operations.log)、[video-source](../../out/uav-regression-video-source.log)、[audio-source](../../out/uav-regression-audio-source.log)。这些既有场景采用默认 VP8/Opus，作为控制/生命周期回归；不是 H.265 回退、UDP/TCP 重连强约束或跨节点迁移验收。

媒体运行器最终返回 `1`，同时存在 TCP 场景失败及 Q-06、Q-07 缺口，不应改成 `0` 隐藏问题。场景结果与完整需求状态分别保存。报告判定增加 B-07 失败归因后，使用保留的原始结果重新生成需求索引，未修改场景结果。

TCP 补充证据：[回环配置修正后首次成功](../../out/uav-tcp-loopback/tcp-video-h264/result.json)，以及随后 [复测 1](../../out/uav-tcp-repeat-0/tcp-video-h264/result.json)、[复测 2](../../out/uav-tcp-repeat-1/tcp-video-h264/result.json)、[复测 3](../../out/uav-tcp-repeat-2/tcp-video-h264/result.json)。成功时均检查双方实际候选协议；间歇失败的根因尚未证实，后续需采集失败轮次原生 ICE/TCP 日志与连接时序，不能把已修复的两个问题当作所有失败的唯一原因。

## 3. 发现的问题和实现修复

| 问题与复现 | 修改 | 验证及边界 |
| --- | --- | --- |
| C++ 原构建无 H.264 编码器，API 拒绝 H.265 | 新增可选 `LIVEKIT_RTC_FFMPEG_CODECS`，用 libavcodec 的 x264/x265 编解码；开放 H.265 API 校验 | H.264/H.265 本地编码解码、IDR 请求、暂停、码率变化、释放及真实 SFU 多轨场景通过。默认 OFF；未实现机载硬编或全体动态回退 |
| 30 fps 源被 WebRTC 默认按最高 60 fps 初始化，后端拒绝，源已消费却无编码输出 | `room.cpp` 将 `MediaSpec.fps` 写入 `RtpEncodingParameters.max_framerate` | H.264/H.265 真实解码恢复；保留源及 graph 统计，不能只看发布成功 |
| 最后一条有效 ICE 候选带 `final=true`，SDK 当作空结束标记丢弃 | 只忽略空 candidateInit；非空 final 候选照常加入 | 已能建立 TCP 通路，但整体仍有间歇失败；空 candidate 内容仍可安全忽略 |
| 本机 TCP 配置将多个物理网卡映射到 127.0.0.1，mux 的接口和公告地址不对应 | 测试实例增加 `rtc.ips.includes: [127.0.0.1/32]` | 修改后出现双段直连 TCP 成功证据，后续仍有间歇失败；这是回环部署修复，不是公网 NAT 兼容性结论 |
| 音频示例每次写 10 ms，Windows 的 2 ms sleep 可延长到一个定时器 tick，产生欠供给 | 示例改为每次写 20 ms，遇背压仍保持采样位置；记录源 silence/skipped 和原始 PCM | 六链路频率检查通过，未放宽误差阈值；不能据此宣称实际设备音质/AEC 通过 |
| Go 迁移后的权限版本领先本地时钟，本地撤权未增加版本，迟到授权可能覆盖撤权 | `uptrackmanager.go` 的本地版本取本地生成值与当前版本下一值的较大者 | 原 `update_versions` 用例与新增确定性“100→本地101→迟到100→本地102”测试通过 |
| NoQueue 停止时残留待发包及停止后的 Enqueue 未释放 | 抽取 `releasePacket`；停止时清理待发队列，停止后交付的包立即归还池 | `TestNoQueueStopReleasesPendingAndLatePackets` 及 pacer 回归通过；正在阻塞的 writer、运行中的队列上限/TTL 与 pacing 仍未解决 |
| Go 默认统计周期分别为 2 s / 5 s / 30 s | 节点采样、连接质量更新、telemetry 汇总默认改为 1 s | 新增三周期回归用例。客户端业务 ID、冻结和中断指标链路仍未闭环；更高采样频率的容量开销未验收 |

主要源码：

- C++：[FFmpeg 后端](../../livekit-sdk-cpp/src/backends/webrtc/ffmpeg_video_codecs.cpp)、[工厂接入](../../livekit-sdk-cpp/src/backends/webrtc/codec_factories.cpp)、[RTC 房间](../../livekit-sdk-cpp/src/engines/rtc/room.cpp)、[编解码回归](../../livekit-sdk-cpp/tests/ffmpeg_codec_tests.cpp)、[无人机示例](../../livekit-sdk-cpp/tests/uav_requirements.cpp)。
- Go：[权限版本](../../../livekit/pkg/rtc/uptrackmanager.go)、[权限回归](../../../livekit/pkg/rtc/uptrackmanager_uav_test.go)、[pacer 停止](../../../livekit/pkg/sfu/pacer/no_queue.go)、[停止回归](../../../livekit/pkg/sfu/pacer/no_queue_shutdown_test.go)、[统计回归](../../../livekit/pkg/telemetry/uav_interval_test.go)。Go 代码修改在 **D:/workspace/livekit**，交付时需要一并保留。

后端范围：单层 L1T1、8-bit I420、偶数尺寸、最高 1280×720 / 30 fps，解码上限 1920×1080；不宣称硬件加速或 SVC。H.264 constrained baseline / level 3.1 / packetization-mode 1；H.265 Main / level 3.1 / SRST。编码器无 B 帧/重排、重复参数集、关键帧为 IDR；较大码率变化通过重开编码器生效，可能增加关键帧突发，尚未经弱网和满载验证。

## 4. 全部 34 项逐项判定

“未测”指**完整需求未完成验收**，不代表本行没有任何子项证据；“未通过”表示存在已取证或源码确认的实现缺口。本轮没有任何一项能据本机自动化替代完整产品/设备验收。

| 编号 | 本机证据与修改 | 完整需求 | 剩余条件 |
| --- | --- | --- | --- |
| V-01 多摄像头识别 | H.264/H.265 两源内容区分、新 SID 重发；源重连稳定 ID 回归 | 未测 | 物理 deviceId/cameraId 映射、枚举变化、热插拔及源代次业务 |
| V-02 多用户独立观看 | 一发布者两轨、两观看者各解码，独立退订恢复通过 | 未测 | 额定 H.265 720p30/2 Mbps 与混合负载及目标端 |
| V-08 聚合订阅控制源 | SDK 已接 SubscribedQualityUpdate；H.264/H.265 的 0→1→2→1→0→1、源消费/RTP 停止及同 SID 恢复解码通过 | 未测 | 真实机载硬编启停、多质量层及 dynacast 专项故障恢复；首次发布有 bootstrap 流量 |
| V-11 Web 多机观看 | 本轮为 C++ 客户端，无 Web 产品验收 | 未测 | 多 Room、多机标识、授权、并发浏览器解码 |
| V-12 H.265→H.264 全体回退 | 两种编码分别实传通过，Go 控制状态迁移通过；未接备用编码发布和机载执行 | 未通过 | 首位能力决策、REGRESSION、全体新旧观看者解码、重连保持 H.264 |
| V-13 实时两段 UDP | 发布和两个观看端选中 UDP，禁 TURN，通过 | 未测 | 与回放同时运行，跨网/重连始终 UDP，ARM64 与三端 |
| A-01 多人全双工 | 三方同时发布、六条有向 PCM 解码及频率通过 | 未测 | 实际扬声器混音、完整播放参考 AEC、各链路时延 |
| A-02 独立成员管理 | 三方发布/订阅与单成员音频退出隔离通过 | 未测 | 业务授权、容量提示、人数边界及异常成员隔离 |
| B-01 回放接入 | 合成 H.264 经 TCP 实传通过 | 未测 | 真实设备文件、原样编码、时间戳和读取节奏；合成源不等于回放 |
| B-03 多回放会话 | TCP 两源独立生命周期通过 | 未测 | playbackSessionId、不同进度、seek/倍速与实时/语音共存 |
| B-04 同源多人分发 | TCP 两名观看者共享每条源，未重复发布 | 未测 | 慢 TCP 观看者、写入截止时间及其他订阅无阻塞 |
| B-07 回放两段 TCP | 成功轮次发布/两观看端均 TCP、非 relay；完整复跑仍出现 transport failed | 未通过 | 先修复间歇建连失败，再验证真实回放、目标端及重连不跨协议 |
| N-02 弱网优先音频/主画面 | SFU 组件回归通过，未执行带宽故障注入 | 未测 | 主辅画面业务映射、分别限制上下行并核对音频和视频预算 |
| Q-01 BWE/拥塞控制 | SFU 回归；软件编码器暂停/码率变化回归 | 未测 | BWE→机载目标/实际码率闭环、反馈时序及受控弱网 |
| Q-02 有界 NACK/RTX | buffer/RTP 回归通过；重试次数/窗口部分仍硬编码 | 未通过 | 补可部署参数，分别注入上下行丢包，验证预算及过期淘汰 |
| Q-03 PLI/关键帧恢复 | Go 相关回归、两种编码器强制 IDR 的解码回归通过 | 未测 | 多人同源丢关键帧、PLI 合并限频及真实媒体恢复 |
| Q-05 独立订阅质量 | UDP/TCP 独立退订恢复、不影响其他轨道通过 | 未测 | 弱端选层/暂停、音频主画面优先、慢 TCP 端隔离 |
| Q-06 pacing/有界队列 | 阻塞时保留 4096 包 / 4915200 payload 字节；8000 bps 下同步发出 10000 字节；仅修复 Stop 清理 | 未通过 | BWE 驱动发送节奏、字节/时长边界、帧依赖丢弃、RTX 预算和 TCP 截止时间 |
| Q-07 音视频 FEC | Opus 有基础；默认视频 codec 集合无 FEC，未发现端到端生成/恢复实现 | 未通过 | 视频 FEC 协商、SSRC/PT 关联、上行恢复、下行重写后再保护；丢包实测 |
| Q-08 默认 1 s 质量 | Go 三周期已修为 1 s；C++ 1 s 原生 stats/graph 记录 | 未通过 | 全链路业务 ID、冻结/中断、恢复前后丢包口径及重连基线 |
| N-01 P95 时延 | 只检查在超时内收到媒体，未测呈现时延 | 未测 | 同步采集/呈现时间，视频 ≤500 ms、每条音频链路 ≤300 ms |
| N-06 首帧/加入语音 | 基础加入成功，无冷热加入 P95 分布 | 未测 | 首帧 P95 ≤2 s、双向可听 P95 ≤3 s，足够样本与目标端 |
| P-02 接入容量 | 两源下限样本，非额定压力负载 | 未测 | 固定扇出逐增 H.265 720p30/2 Mbps 源及 Opus 32 kbps 负载 |
| P-03 转发容量 | 四份视频解码、六条音频链路样本 | 未测 | 固定源数逐增订阅，UDP/TCP/混合、回退峰值与完整资源记录 |
| P-10 最高负载 8 h | 未运行 8 h，未找到容量边界 | 未测 | 在候选最高稳定负载连续 8 h；不能外推短测 |
| P-11 配额/过载保护 | selector 回归；Windows 日志明确 CPU monitoring unsupported、capacity management disabled | 未通过 | Linux 部署验证、动态源/转发/连接/缓存原子准入与释放；不得据本机认证过载保护 |
| V-04 单摄像头隔离 | 撤下/重发一个源时另一个源持续解码 | 未测 | 真实拔插、捕获/硬编崩溃、无帧超时不能拖垮设备 |
| A-05 退出/异常清理 | 音频退出保留视频与其他语音通过；权限版本问题已修复 | 未测 | 授权过期主动撤权、异常断连和迟到清理 |
| A-06 幂等/代次隔离 | SDK 重连旧 handle 拒绝、取消/超时请求不重放、迟到 ACK 忽略；Go 旧权限版本拒绝 | 未测 | 业务 requestId/memberId/connectionEpoch 的加入和移除闭环 |
| B-06 中断/结束/重发 | TCP 新 SID 重发、旧轨停止通过 | 未测 | 真实 EOS/故障原因、稳定 streamId、回放进度及旧流隔离 |
| N-04 网络变化恢复 | 信令断连 resume/rejoin 与源恢复通过 | 未测 | 实际网卡切换、媒体黑洞、UDP/TCP 强约束保持及语音重新授权 |
| N-05 节点故障重建 | 独立本机服务终止/重启、源重发和旧 handle 拒绝通过 | 未测 | 多节点调度/重新授权、幽灵成员清理及真实回放恢复 |
| N-08 机载资源长稳 | Windows 软件编解码短测 | 未测 | ARM64 硬编、手机 8 h、温度/功耗/通道与资源回收 |
| N-09 可观测追溯 | 按房间/轨道保留 ICE、RTC、graph、PCM 证据；业务关联尚缺 | 未通过 | deviceId/cameraId/playbackSessionId/epoch 全链路及终端看板 |

## 5. 版本、依赖和复现

- Go SFU：`D:/workspace/livekit`，基线提交 `a390d03d28c895742d9b13c0894880ee67733801`，加本轮工作区修复；源码版本 1.13.10。构建工具 `go1.27.3 windows/amd64`。未降级或修改 go.mod/go.sum。
- C++ SDK：`D:/workspace/av-platform/livekit-sdk-cpp`，基线提交 `99488d51ee595405d3a7cf787eac5ec52d832f9b`，加本轮工作区修复；WebRTC 提交 `bed339dae011617e02bcd02828df95ac759cfa09`。未改动并行任务的 studio 文件。
- Windows x64 / Release / localhost；视频 320×180 的合成色块，非真实摄像头/录像，也非 2 Mbps 压力负载。三路 48 kHz mono PCM，音频发送上限 64 kbps；不是需求容量基准的固定 Opus 32 kbps。
- FFmpeg 8.1 GPL shared（BtbN，含 x264/x265），归档 SHA256 `88cda345c479dd3e18b8e33fa4835d350b1084b1f8008617a396531b05f5c851`。原有 FFmpeg 7.1 包的 x265 在独立命令行也崩溃，故采用独立目录的新包，未覆盖用户旧安装。部署需匹配头文件/import libs/DLL，并保留 GPL 等依赖许可要求。
- 配置、构建及依赖路径见 [可选 RTC 编解码说明](../../livekit-sdk-cpp/docs/rtc-ffmpeg-codecs.md)；全部场景说明见 [测试入口](uav-sfu-go-cpp-tests.md)。

```powershell
# 在 D:/workspace/av-platform，已配置匹配的 FFmpeg 后：
cmake --build livekit-sdk-cpp/out/windows-x64 --config Release `
  --target livekit_uav_requirements livekit_ffmpeg_codec_tests --parallel 4
python livekit-sdk-cpp/tests/uav_requirements.py --goproxy https://goproxy.cn,direct
ctest --test-dir livekit-sdk-cpp/out/windows-x64 -C Release `
  -R '^(core|sdk|media_graph|video_frames|ffmpeg_rtc_codecs)$' --output-on-failure
python -m unittest discover -s livekit-sdk-cpp/tests -p test_uav_requirements_runner.py

# 在 D:/workspace/livekit，镜像仅影响当前进程：
$env:GOPROXY='https://goproxy.cn,direct'
& D:/workspace/av-platform/out/tools/go/bin/go.exe test -mod=readonly -json -count=1 `
  -timeout=180s ./pkg/rtc ./pkg/rtc/dynacast ./pkg/sfu ./pkg/sfu/pacer `
  ./pkg/sfu/buffer ./pkg/sfu/streamallocator ./pkg/sfu/connectionquality `
  ./pkg/sfu/rtpstats ./pkg/routing/selector ./pkg/telemetry
```

## 6. 失败记录和未完成项处理

- 修复前媒体基线：[20261027-191447-337409](../../out/uav-sfu-go/20261027-191447-337409/report.md)。H.264 缺编码器、H.265 API 拒绝、音频示例欠供给均如实保留。
- 中间版本：[20261027-193058-397319](../../out/uav-sfu-go/20261027-193058-397319/report.md)、[20261027-194338-694258](../../out/uav-sfu-go/20261027-194338-694258/report.md)、[20261027-194803-244056](../../out/uav-sfu-go/20261027-194803-244056/report.md)。后两次 TCP 入房超时仍失败，不被后续成功记录覆盖；最后完整运行的间歇失败也保留。
- 早期 Go config 全包测试在 Windows 的 POSIX 凭据权限断言失败；没有删除安全检查。最终运行的是明确列出的 Go 包及 config 需求 overlay，不能表述为 Go 全仓库测试通过。
- 最初额外调用 operations/video-source/audio-source 使用了不接受相应参数的 rejoin 可执行文件，得到 usage 失败；改用正确的 reconnect 可执行文件后通过，随后对最终 SDK 重跑七场景通过。这是测试调用纠正，不是产品修复。
- 未实现的完整 pacing、视频 FEC、业务回退和严格准入都涉及协议/帧依赖/预算或业务契约。本轮已定位、取证并尝试补齐相关基础，未以随机丢 RTP、仅注册 FEC codec 或两次独立发布冒充需求实现；剩余开发和验收条件逐项列在第 4 节。
- 本轮不含 Linux/ARM64 构建与实际板卡、移动端/Web、受控丢包、主观音质/AEC、P95、额定容量和 8 h。验证阶段未提交 Git，也未部署生产环境。

## 7. 代码提交记录

2026-10-28 按用户要求提交本轮代码：C++ SDK 提交 `8cd421e`；独立 Go 仓库 `D:/workspace/livekit` 提交 `6b6a3e4c`。主仓库同步记录 SDK 子模块指针及本报告。原始测试证据和摘要对应提交前的受测工作区，未因提交重新运行媒体测试；未推送远端。

同日增量按用户要求提交：C++ SDK `69e4f64`，基于已合并其他任务的 `55ece05`，包含实时视频 dynacast、契约/媒体用例和重连夹具修复。主仓库同步子模块指针、测试说明及当前报告；Go 仓库本次无新增修改，仍为 `6b6a3e4c`。当前源码媒体证据记录的是 SDK 提交前工作区；测试输出位于本机 `out/`，不随 Git 提交归档。完整需求缺口继续保留，未推送远端。
