# Go LiveKit + C++ SDK：需求复测与严格传输策略

**验收口径已更新**：用户随后明确“模拟测试通过即可，不需要真机实测”。当前状态以 [模拟验收报告](uav-sfu-go-cpp-simulation-acceptance.md) 为准：5 项通过、14 项部分通过待补模拟、7 项未通过、8 项尚未模拟。下文“完整通过 0 项”保留为此前产品／设备完整验收口径的历史结论，不再作为本轮模拟验收结论。

日期：2026-10-28（北京时间）。依据 [Go 版需求评估](../architecture/uav-sfu-go-requirements-assessment.md) 和 V1.11 的全部 34 项需求。本文是本次复测记录；[历史验证报告](uav-sfu-go-cpp-validation-report.md) 中的失败记录继续保留。

## 结论与范围

**34 项完整需求尚未全部通过。** 本次使用 `D:/workspace/livekit` 当前 Go 源码构建服务端，所有媒体客户端使用本仓库原生 C++ SDK。验证为 Windows 本机无窗口自动化，未操作桌面或采集设备。合成 I420/PCM 的实际远端解码不等于目标设备显示、音频播放或 AEC 验收。

新增并实现 `RoomOptions::media_transport`：`automatic`、`udp_only`、`tcp_only`。严格模式约束两个 PeerConnection，禁用 TURN，拒绝冲突的 relay 策略，并用于初次连接、ICE 恢复和完整重新入房。实时与回放须用独立 Room；没有逐轨混用传输的承诺。原有 GraphEngine 媒体流水线继续使用。见 [SDK 使用说明](../../livekit-sdk-cpp/docs/media-transport-policy.md)。

## 本次执行证据

- 修改前基线：[6 个媒体场景全部通过](../../out/uav-sfu-go/20261028-revalidation-baseline/report.md)。它们采用本次开始时的 Go 源码和 C++ SDK，未拿历史服务端二进制替代。
- Go 扩展回归：[524 个测试／子测试通过](../../out/uav-20261028-current-go-regression.jsonl)，[退出码 0](../../out/uav-20261028-current-go-regression.exit)。包含 RTC、dynacast、SFU、pacer、buffer、connectionquality、rtpstats、selector、telemetry 和当前 `rtxconfig`。`streamallocator` 无独立测试文件。
- Go 重传部署配置：[16 个测试／子测试通过](../../out/uav-20261028-current-go-config.jsonl)，[退出码 0](../../out/uav-20261028-current-go-config.exit)。包括上下行参数及无效值拒绝。本轮没有修改这些进入任务前已存在的 Go 工作区改动，也不把它们列为本轮编写。
- C++ CTest **6/6 通过**：[SDK、严格传输策略、FFmpeg 编解码 3/3](../../out/uav-20261028-transport-ctest.log)，[core、media_graph、video_frames 3/3](../../out/uav-20261028-remaining-ctest.log)。所有这些目标已从当前源码构建，未执行桌面／设备测试。
- Python 报告判定：[11/11 通过](../../out/uav-20261028-transport-runner-tests.log)。新增缺失候选类型、负向用例意外选中连接、UDP 失败归因和已知实现缺口保留的测试。
- 扩展媒体与传输：[15/15 通过](../../out/uav-sfu-go/20261028-strict-transport/report.md)，Go 需求探针 **4/4 执行成功**。包括原六场景、H.265 TCP、两个协议拒绝场景、两个同时运行场景，以及 H.264/H.265 各两次追加 TCP 复测。实际选中协议均与策略一致且无 relay。两并行进程的执行窗口在北京时间 09:41:39—09:41:47 重叠，详细时间与媒体日志均已保留；不据此推断高负载容量。
- 严格协议恢复：[6/6 通过及执行命令](../../out/uav-20261028-strict-recovery.json)，包括 UDP/TCP 各自的 resume、rejoin、restart。服务端同时开放两种协议；客户端坚持指定协议，检查到的所有候选对均符合并拒绝 relay。恢复日志包含多次 ICE offer、同步状态、实际媒体恢复和完整重新入房的不同 SID。
- 媒体运行器退出 **1**，原因是 Q-06/Q-07 探针揭示缺口，不能改为全需求成功。之后用同一原始测量重新生成报告，补入源码核查的 V-12/Q-08/P-11/N-09 缺口；[生成前 JSON](../../out/uav-sfu-go/20261028-strict-transport/result-before-report-fix.json) 与原始场景结果保留，未重写媒体测量。
- 首轮恢复执行因系统 Python 缺少 `websockets` 而在启动服务前失败；[准备失败记录](../../out/uav-20261028-strict-recovery-missing-dependency.json) 保留。改用仓库现有 `client-parity-venv` 中的 `websockets==15.0.1` 后六项通过，未安装或替换用户全局依赖。

## 修复及新增验证

1. **客户端传输强约束。** UDP 模式禁止 TCP 候选及端口分配；TCP 模式禁止 UDP/STUN 端口分配并允许主动 ICE-TCP；两者禁止 relay 分配。`disable_turn` 原有选项也进一步禁用底层 relay 分配。默认自动模式不改变。服务端 `force_relay` 与严格直连冲突时明确报错。
2. **负向验证。** TCP-only 客户端连接 UDP-only 服务端，以及 UDP-only 客户端连接 TCP-only 服务端。必须已完成信令 JoinResponse，随后因媒体传输失败；若信令失败、出现任何已选中 ICE 对或意外连通，都不能算负向测试通过。
3. **H.265 TCP。** 新增与 H.264 相同的两源、两观看者、实际像素／MIME、独立退订、撤轨隔离和重发断言。TCP 的 source 仍是合成画面，不冒充原样转发录像。
4. **同时运行。** 两个 Go 实例共享本机：UDP 实例运行 H.265 两源四份视频解码及三方 Opus 六链路；TCP 实例同时运行 H.265 两源两观看者。UDP 视频在语音测试及单成员退出后继续解码。记录场景起止时间；不把这种低负载并行称为容量测试。
5. **恢复。** 扩展已有 resume/rejoin/restart 测试，可在同时开放 UDP/TCP 的服务端上指定客户端严格协议；校验实际 selected candidate pairs、重连身份代次及媒体恢复。测试使用 VP8/Opus，并不证明 H.265 回退恢复、物理网卡切换或断网后实际设备表现。
6. **报告判定。** 缺少候选类型不再被视为“非 relay”；UDP 场景失败映射回关联需求，负向失败按客户端策略归因；已知源码缺口与执行测量分开保存，基础媒体通过不能清除实现缺口。

## 全部 34 项当前状态与原因

“未测”指完整验收条件未覆盖；“未通过”指存在实现缺口或尚未关闭的失败。局部测试通过单列证据，不把它升级为完整需求通过。Q-02 当前已出现可部署配置并通过回归，因此相较历史报告改为完整需求“未测”，并非宣称丢包下重传预算达标。

| 编号 | 完整需求 | 本机证据／未通过或未测原因 |
| --- | --- | --- |
| V-01 | 未测 | 两独立源、内容区分和新 SID 重发已有测试；缺物理 deviceId/cameraId、枚举变化、热插拔及源代次业务验收 |
| V-02 | 未测 | 两源两观看者、独立退订恢复有实际解码；缺目标端、720p30/2 Mbps 和额定混合负载 |
| V-08 | 未测 | H.264/H.265 订阅数 0→1→2→1→0→1，源消费及 RTP 停止／恢复；缺机载真实硬编、多层及专项恢复 |
| V-11 | 未测 | 本轮客户端为 C++；没有 Web 多机业务、授权和浏览器并发解码验收条件 |
| V-12 | 未通过 | SDK 未实现首位能力决策、备用编码 REGRESSION 发布、所有旧新观看者统一切换及重连状态。独立 H.264/H.265 测试不能代替 |
| V-13 | 未测 | 已新增客户端 UDP-only、反向测试及并行验证；缺目标板和三端、跨网／物理网卡变化验收 |
| A-01 | 未测 | 三方六条有向 PCM 实际解码；缺设备混音播放、完整播放参考 AEC 和各链路采集到播放时延 |
| A-02 | 未测 | 多人发布订阅及单人退出隔离；缺业务授权、人数边界及容量提示 |
| B-01 | 未测 | TCP 上 H.264/H.265 合成视频实传；缺真实设备文件、原样编码接入和读取节奏 |
| B-03 | 未测 | TCP 多源独立生命周期有测试；缺 playbackSessionId、不同进度、seek 和倍速业务 |
| B-04 | 未测 | 同 TCP 源两观看者无需重复上传；缺慢 TCP 观看者、写入超时和积压隔离 |
| B-07 | 未通过 | 严格 TCP-only 与正反向测试已补；历史间歇 `WebRTC transport failed` 尚未查明根因，成功复测不等于已修复；真实回放及目标端也未验收 |
| N-02 | 未测 | 未做受控上下行限速、音频预算及主辅画面优先策略验收 |
| Q-01 | 未测 | SFU 回归及软件编码器基本控制有证据；缺受控弱网下 BWE→硬编目标／实际码率闭环 |
| Q-02 | 未测 | 当前 Go 工作区上下行重传参数、次数／寿命、缺包容量回归通过；缺 C++ 媒体两段独立丢包及聚合重传预算实测 |
| Q-03 | 未测 | buffer/SFU 回归和 IDR 编解码测试；缺多人同源丢关键帧、PLI 合并限频和实际媒体恢复 |
| Q-05 | 未测 | 独立退订恢复不影响其他观看者；缺弱端选层／暂停、主画面优先与慢 TCP 端隔离 |
| Q-06 | 未通过 | NoQueue 阻塞时仍保留 4096 包／4915200 payload 字节，PassThrough 不按目标码率 pacing；缺字节／时间硬边界、帧依赖恢复和 TCP 写入超时 |
| Q-07 | 未通过 | 视频 FEC 协商、生成、恢复及转发后重新保护无完整实现；需要协议和端侧共同开发，不能仅注册 codec 或以 RTX 代替 |
| Q-08 | 未通过 | 默认 1 s 节点／质量／telemetry 与 C++ stats 已有；缺业务标识关联、冻结／音频中断及重连增量基线 |
| N-01 | 未测 | 未测采集到显示／播放的 P95；收到媒体和 RTP RTT 不能代替 ≤500 ms／≤300 ms 验收 |
| N-06 | 未测 | 未做足够冷热加入样本的首帧／双向可听 P95；单次在超时内解码不足以证明 ≤2 s／≤3 s |
| P-02 | 未测 | 没有额定 H.265 720p30/2 Mbps 接入阶梯加压及瓶颈排除；低分辨率样本不是容量 |
| P-03 | 未测 | 没有固定源数递增订阅的 UDP/TCP/混合及回退峰值容量测试 |
| P-10 | 未测 | 尚未确定候选最高负载，也未运行该负载的连续 8 h；短测不能外推 |
| P-11 | 未通过 | 缺动态源／转发／连接／缓存原子准入；Windows CPU monitoring unsupported，不能认证生产过载保护 |
| V-04 | 未测 | 单轨撤下和重发不影响另一轨；缺真实拔插、硬编异常和无帧超时故障注入 |
| A-05 | 未测 | 正常音频退出保留视频和其他成员语音；缺外部授权到期、异常清理和迟到撤权闭环 |
| A-06 | 未测 | 旧 handle 和权限版本回归存在；缺业务 requestId/memberId/connectionEpoch 的幂等与代次隔离验收 |
| B-06 | 未测 | TCP 撤轨／新 SID 重发存在；缺实际 EOS／故障原因、稳定 streamId、进度和旧流隔离业务 |
| N-04 | 未测 | 新增严格传输恢复测试；缺物理切网／媒体黑洞、跨网以及语音到期重新授权 |
| N-05 | 未测 | 本机节点重启测试可验证部分重建；缺多节点路由、重新授权、幽灵成员及真实回放恢复 |
| N-08 | 未测 | 当前只有 Windows 软件编解码；缺 ARM64／手机 8 h、硬编通道、温度、功耗和资源回收 |
| N-09 | 未通过 | 保留房间／轨道／ICE／RTC／graph 证据；缺 deviceId/cameraId/playbackSessionId/epoch 全链路关联和终端看板 |

合计：完整通过 **0**，未通过 **7**，未测 **27**。其中 B-07 保留历史未关闭失败；执行器只据本轮结果生成矩阵，所以本轮成功时仍可能显示其完整状态“未测”。本文保留跨轮次问题状态，不自动关闭历史故障。

## 版本与复现

- Go 基线：`6b6a3e4c5a4cb3dd73b54758db599bc07d07a651`，包含进入本任务前已存在的重传配置工作区修改。
- C++ SDK 基线：`69e4f64af58ce6b79686d76b20e5702d993f99f0`，加本次严格传输及测试改动。未提交／推送。
- 本机原始证据在 `out/`，通常不随 Git 交付；分享或复现时需保留这些目录及匹配 FFmpeg DLL。二进制 SHA256 和源码状态见每轮 `result.json`。
- [交付源码／证据摘要](../../out/uav-20261028-revalidation-manifest.json) 记录当前文件和可执行文件 SHA256，并保留 Go、SDK 的受测工作区修改快照。未修改进入任务前的 `livekit-cpp` 工作区内容。

```powershell
Set-Location D:/workspace/av-platform
cmake --build livekit-sdk-cpp/out/windows-x64 --config Release `
  --target livekit_uav_requirements livekit_transport_policy_tests livekit_sdk_tests `
  livekit_reconnect_integration livekit_rejoin_integration --parallel 4
python livekit-sdk-cpp/tests/uav_requirements.py `
  --server-source D:/workspace/livekit --goproxy https://goproxy.cn,direct --tcp-repeats 3
python -m unittest discover -s livekit-sdk-cpp/tests -p test_uav_requirements_runner.py -v
```

运行器保留非零退出码表达需求缺口；不会通过放宽断言、跳过失败、换成 Go SDK 客户端或降低到 VP8 后宣称 H.265 验收完成。
