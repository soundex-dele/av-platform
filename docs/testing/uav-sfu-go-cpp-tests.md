# Go SFU + C++ SDK 无人机需求测试用例

对应 [Go 版本需求评估](../architecture/uav-sfu-go-requirements-assessment.md)，基线为 V1.11 的 34 项需求。

**最新口径：以模拟测试验收，不要求真机。** 运行器按具体断言判定模拟通过，区分“部分通过待补模拟”和“尚未模拟”；缺失软件能力和性能模拟证据仍保留。当前 [模拟结果与复现入口](uav-sfu-go-cpp-simulation-acceptance.md) 优先于下文历史设备验收条件。

2026-10-28 本次扩展：客户端严格 `MediaTransport`、H.265/TCP、反向协议拒绝、两实例并行视频／语音、可选 TCP 重复轮次和 UDP/TCP 恢复测试。见 [本次复测与完整矩阵](uav-sfu-go-cpp-revalidation-20261028.md) 及 [SDK 策略说明](../../livekit-sdk-cpp/docs/media-transport-policy.md)。下文早期六场景说明保留作为基线；当前运行器默认 11 场景，`--tcp-repeats 3` 运行 15 场景，回归测试中的媒体客户端仍全部为 C++。

本文件描述测试代码和验收用例。用户已授权执行并尝试修复，并确认本轮范围为本机无窗口验证；实机条件不在本轮。执行结果与剩余缺口见 [验证与修复报告](uav-sfu-go-cpp-validation-report.md)，不能仅因用例存在就视为验收通过。

## 1. 测试对象和边界

- 服务端固定从 `D:/workspace/livekit` 的 Go 源码构建；不使用 C++ SFU，也不替换成历史 Go 二进制。报告记录提交、工作区状态、go.mod/go.sum 摘要和二进制 SHA256。
- 所有媒体客户端使用 `D:/workspace/av-platform/livekit-sdk-cpp` 的原生 C++ SDK。Python 只负责启动、清理和整理证据，不发布媒体；没有 Go SDK 客户端。
- 不访问摄像头、麦克风、扬声器或桌面。C++ 用例生成两种 I420 画面和三个频率的 PCM，检查远端真实解码输出。
- UDP-only、TCP-only 每个基础场景各启一个回环地址上的独立 Go 实例，禁用 TURN 与协议自动回退。新增 `simultaneous` 组同时运行 UDP H.265＋多人语音及 TCP H.265 两实例，验证本机低负载并行；不等于额定容量或完整业务隔离验收。
- 实例使用 `rtc.ips.includes: [127.0.0.1/32]`，避免将不同物理接口都公告为回环地址后造成 TCP mux 地址不一致。TCP 已有成功记录，但完整复跑仍出现间歇 `WebRTC transport failed`，详见修复报告；单次重试成功不关闭问题。
- 默认视频样本为 320×180 的 H.264，用于基础互通和内容识别；不是要求的 H.265 720p30、2 Mbps 容量负载。合成视频也不是实际设备回放文件。
- 只认 Go 服务端日志中已经选中的 ICE 候选对。验证发布端上行与每个观看端下行的 `localProtocol`、`remoteProtocol`，拒绝 relay；不以 WSS/信令 TCP、监听端口或 SDP 候选出现代替媒体协议证明。

## 2. 文件和执行入口

| 文件 | 内容 |
| --- | --- |
| `livekit-sdk-cpp/tests/uav_requirements.cpp` | 原生媒体测试客户端，CMake 目标 `livekit_uav_requirements` |
| `livekit-sdk-cpp/tests/uav_requirements.py` | 构建 Go 源码、启动隔离实例、执行场景、输出 34 项矩阵 |
| `livekit-sdk-cpp/tests/go_requirements/config_test.go` | 默认 codec、视频 FEC 注册、BWE 和节点统计间隔取证 |
| `livekit-sdk-cpp/tests/go_requirements/pacer_test.go` | PassThrough 突发发送和 NoQueue 阻塞写入后的队列增长取证 |
| `livekit-sdk-cpp/tests/go_requirements/dynacast_test.go` | H.265→H.264 的聚合控制状态迁移测试 |
| `livekit-sdk-cpp/tests/test_uav_requirements_runner.py` | 6 个报告判定测试：缺证据、协议错误、relay、构建失败、H.265 拒绝、TCP 媒体失败及 dynacast 失败归因 |
| `livekit-sdk-cpp/tests/subscribed_quality_contract.hpp` | 上游 wire field 14、当前/外来 codec、ON/OFF、未知质量、旧格式及不支持源类型的契约 |

取证用 Go 用例通过 `go test -overlay` 注入对应 package，测试实际 Go 实现。另有本轮修复及回归用例直接位于 `D:/workspace/livekit`；详见修复报告。依赖版本保持锁定，运行结束保留 overlay 和原始日志以便追溯。

复现命令如下。H.264/H.265 需要先按 [可选 FFmpeg RTC 后端说明](../../livekit-sdk-cpp/docs/rtc-ffmpeg-codecs.md) 配置匹配的编解码依赖：

```powershell
Set-Location D:/workspace/av-platform

# 使用本仓库已经配置好的 C++ SDK 构建目录。
cmake --build livekit-sdk-cpp/out/windows-x64 --config Release `
  --target livekit_uav_requirements --parallel 4

# 构建当前 Go 源码并执行测试。模块镜像仅对这次子进程生效。
python livekit-sdk-cpp/tests/uav_requirements.py `
  --server-source D:/workspace/livekit `
  --go D:/workspace/av-platform/out/tools/go/bin/go.exe `
  --client D:/workspace/av-platform/livekit-sdk-cpp/out/windows-x64/Release/livekit_uav_requirements.exe `
  --goproxy https://goproxy.cn,direct

# 单独检查报告判定逻辑，不启动媒体服务。
python -m unittest discover -s livekit-sdk-cpp/tests `
  -p test_uav_requirements_runner.py -v
```

首次配置 SDK 构建环境请参照 SDK 的 CMake 配置；不能把旧客户端可执行文件当作新用例。H.264 编解码后端必须实际存在于当前 WebRTC 构建中；没有后端时用例应报 `Video codec not available: h264`。H.265 同样必须得到 SDK API 和后端支持，不允许偷偷降到 VP8 后宣称通过。

输出位置为 `out/uav-sfu-go/<北京时间戳>/`，包含 `report.md`、`result.json`、服务端构建信息、Go 测试 JSONL、每个场景的配置/服务端日志/客户端日志/选中协议证据。测试 API key 仅供回环隔离实例使用。

需要排查原生 ICE 时，可在独立测试进程设置 `LIVEKIT_UAV_NATIVE_LOG=1`；默认关闭。该选项会增加原生传输诊断，日志只在本地测试证据目录保存，分享前需检查其中的网络地址和 ICE 信息。

退出码：`0` 表示已执行子项无失败且未检测到已知缺口；`1` 表示子项失败、Go 探针失败或发现需求缺口；`2` 表示全局准备失败。**任何退出码都不能代替 34 项完整验收**，完整状态仍以矩阵和剩余验收条件为准。

## 3. 已编写的可运行场景

| 场景/断言 | 操作与成功标准 | 关联需求 | 不能据此推断 |
| --- | --- | --- | --- |
| `udp-video-h264` / `two_sources_two_viewers` | 一个 C++ 发布者发布两轨不同亮度画面，两名 C++ 观看者各解码至少 10 帧；核对尺寸、亮度误差 ≤8、H.264 MIME、发布端仍只有两轨 | V-01、V-02 | H.265、实机摄像头身份、额定码率和容量 |
| `independent_unsubscribe_resubscribe` | A 退订第一轨，等待残留帧耗尽后计数不再增长；A 的第二轨和 B 的第一轨继续解码；A 重新订阅恢复 | V-02、Q-05 | BWE 弱网优先级和低质量层切换 |
| `unpublish_isolation` | 撤下第一轨，其消费者停止且源释放；第二轨继续解码 | V-04 | 硬件拔插或编码器崩溃隔离 |
| `republish_new_sid` | 第一源按 epoch-2 名称重新发布，SID 不同，两个观看者恢复解码 | V-01、B-06 的生命周期子项 | 业务代次授权、迟到请求隔离和设备 EOS |
| `tcp-video-h264` | 在 ForceTCP 实例重复上述多源多订阅/撤轨/重发场景，检查两个媒体方向及两个观看者均为直连 TCP | B-01、B-03、B-04、B-07 的基础子项 | 实际文件回放、seek、倍速、TCP 慢端与实时共存 |
| `udp-audio-h264` / `three_way_audio_six_links` | 无人机、用户 A、用户 B 同时发 440/660/880 Hz PCM；三端分别解码其他两端，每条有向链路至少 48000 样本，峰值 >500，频率误差 <6%；禁止把本端音频算成远端音频 | A-01、A-02 | 扬声器播放、混音参考 AEC、音质主观验收、P95 |
| `voice_leave_preserves_video_and_other_voice` | B 保持视频发布但撤掉音频；B 仍连接，视频继续解码，A 与无人机两方向音频各继续收到 >20 块；B 音频不得继续输出 | A-05 的正常退出子项 | 授权到期、异常断连、服务端迟到清理 |
| `selected_ice_protocol` | 解析选中候选对；视频要求 drone/PUBLISHER、A/SUBSCRIBER、B/SUBSCRIBER；三方音频要求每端 publisher/subscriber，全部符合指定协议且非 relay | V-13、B-07 | 真实三端平台、跨网络、重连坚持协议 |
| `udp-video-h265` | 请求 H.265 执行真实多轨场景；SDK 拒绝该编码或后端缺失必须失败 | V-12 的前置条件 | 该场景本身不执行 H.265→H.264 动态切换 |
| `udp-dynacast-h264` / `udp-dynacast-h265` | 开启 `MediaSpec::dynacast`；0→1→2→1→0→1 观看者；单人离开后等待 6 s 仍持续解码，无人观看时源消费和保留的 RTP 字节统计停止增长，重新订阅同 SID 恢复解码 | V-08 的本机单层实时源控制 | 首次 bootstrap 流量、硬编实机启停、质量层选择、全体编码回退及专项重连 |
| `TestUAVH265H264Regression` | 先聚合 H.265 观看需求，再调用真实 dynacast regression，等待 H.265 停用、H.264 启用 | V-08、V-12 的服务端控制子项 | 机载真正换编码、原观看者重新协商/解码 |

超时作为失败保留日志。单个场景失败不阻止后续场景执行。全体回退尚缺业务端编码控制接口，不能用两次独立发布或静态 codec 参数伪造完整通过。

## 4. 缺口取证和判定规则

`TestUAVNoQueueEvidence` 使用受控阻塞的 RTP writer，向真实 NoQueue 追加 4096 个 1200 字节包并读取队列长度。这里的 512 是实现的初始容量，**不是需求约定的队列上限**；有限样本只能证明它不是 512 包硬边界，不能仅靠样本数学证明无限增长。结合评估中的无上限/TTL 实现核对，该结果用于暴露 Q-06 缺口，不写成有界队列通过。若实现改变，测试要求重新评估结论。

`TestUAVPassThroughEvidence` 设置 8000 bps 后同步提交十个 1000 字节包，记录全部发完耗时。该探针用于显示目标码率是否实际影响发送路径；不把同进程调度耗时当 P95 媒体时延。

`TestUAVDefaultsEvidence` 读取编译后的实际默认配置和 protocol codec 集合，记录视频 FEC 是否注册、节点采样间隔、默认 send-side BWE。默认缺少视频 FEC 或统计间隔大于 1 s 会记录对应配置缺口；探针不宣称验证了 PLC/FEC 丢包恢复、全部统计链路或任意自定义部署。

完整需求状态只使用“通过／未通过／未测／不适用”。当前自动化范围仅能证明局部媒体与控制行为，因此即使全部基础媒体场景成功，尚需真实设备和完整业务闭环的需求仍为“未测”；已有直接反例的需求为“未通过”。场景内部另列 `PASS/FAIL`，防止混淆。

## 5. 34 项验收补充用例

运行器中维护全部 34 个编号及剩余验收步骤；每次报告均输出，不因环境失败或某个用例跳过而遗漏编号。下列为尚未自动化的专项测试，**当前未运行**。

| 需求 | 测试操作 | 必须留存的判定证据 |
| --- | --- | --- |
| V-01、V-04 | 两摄像头同时发布；改变枚举顺序、拔插其中一个、模拟硬编无帧；重连后恢复 | deviceId/cameraId 不混淆，发布代次更新，另一摄像头/音频不中断 |
| V-08 | 观看者数量 0→1→2→1→0，分别请求不同质量，再恢复订阅 | 聚合指令、机载编码器启停与真实上行字节，而非仅 SFU 下行停止 |
| V-11 | Web 同时加入多架设备的 Room，独立选轨与取消授权 | 实际渲染、来源标识、跨设备无越权和浏览器资源 |
| V-12 | 首位 H.264-only；先 H.265 后加入 H.264-only；回退期间重连；迟到旧代次回调 | REGRESSION 策略、机载 H.265 停止/H.264 启动、所有旧新观看者解码，回放不套用回退 |
| V-13、B-07、N-04 | 目标板与 Android/iOS/Web 分开实时/回放连接；断网/切网恢复 | 两段选中协议始终满足 UDP/TCP、无 TURN；失败有明确提示，不能自动跨协议 |
| A-01、A-02 | 三方同时发言、用户互听、扬声器外放，加入/移除第四成员 | 六条有向链路解码/播放、最终混音参考 AEC、授权与独立成员行为 |
| A-05、A-06 | 音频授权到期、异常掉线、重复 requestId、同 identity 新会话、旧 epoch 迟到移除 | 只撤合法目标的音频，视频保留，新代次不被旧清理影响 |
| B-01、B-03、B-04、B-06 | 两个真实设备回放会话不同进度；同源两观看者；seek/倍速/EOS/重发；限制一个观看者读取速率 | streamId/sessionId/epoch、原样编码、实际解码，其他回放/实时/语音连续且慢端队列有界 |
| N-02、Q-01、Q-05 | 独立限制上/下行带宽，让一个观看者慢于另一个，配置主辅画面 | BWE、编码器目标/实际码率、分配/暂停、音频可用性，健康观看者不随弱端降级 |
| Q-02、Q-03、Q-07 | 对上下行分别注入随机/突发丢包和关键帧丢失，多人订阅同源 | NACK/RTX 次数与寿命、PLI 合并/限频、实际 FEC 恢复包和解码；不能以 RTX 替代视频 FEC |
| Q-06 | 设置发送目标码率，突发帧、阻塞 TCP writer、慢观看者和恢复 | 实际发送时间线、队列字节/时长上限、完整帧/依赖丢弃、写入超时、同源其他订阅无阻塞 |
| Q-08、N-09 | 运行、暂停、丢包、冻结、重连后采样 | 1 s 时间戳，设备/源代次/成员/方向关联，恢复前后丢包口径、冻结/中断及增量基线 |
| N-01、N-06 | 统一时钟或可追溯采集/呈现标记，反复冷热加入、回退和 TCP 建连 | 视频实时/回放 P95 ≤500 ms；每条音频链路 P95 ≤300 ms；首帧 ≤2 s、双向可听 ≤3 s；记录样本数 |
| P-02、P-03 | 固定 H.265 720p30/2 Mbps、Opus 32 kbps；分别固定扇出增加源、固定源增加订阅；两实例共用硬件 | UDP/TCP/混合和 H.264 回退峰值，安全/QoS 开启，音频扇出、PC/TCP 数；未触边界只报告已验证下限 |
| P-11 | 已入房成员并发动态发布/订阅直至各配额边界，再撤轨/断连重试 | 源/转发/连接/缓存独立原子准入和释放、拒绝原因，不能只测入房限制 |
| N-05 | 测试节点故障后在可用节点重新入房 | 重新授权、发布/订阅重建、旧成员清理与回放进度；不要求媒体无缝迁移 |
| P-10、N-08 | 候选最高负载持续 8 h，同时覆盖 ARM64 板与手机 | 单核/线程、内存趋势、pps、队列、TCP 积压/重传、硬编通道、温度、功耗与资源回收 |

这些用例需要设备、网络注入、端侧业务和采集证据，当前不会用本地单元测试替代。
