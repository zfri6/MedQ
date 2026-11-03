# V0.3 first-mismatch record

1. 初次ModelSim编译发现top前向引用fallback_tone/tone_sample被当成重复声明。将BUZZER连线移至声明后；不改业务预期。
2. 新TB使用SV保留字priority及混合net声明，编译拒绝；改标识符并拆声明。
3. basic TB在grant同拍采旧announcing=0，提前检查第二段tone结束；移至negedge观察新状态，仍要求有限tone后真实静音。
4. top_audio观察器在A新grant同拍错误使用旧active_room=B，误计B第8段；改为grant有效时以新grant元数据判房间，未改B应为7段的预期。旧失败日志保留sim/v03/failures/pin_audio_observer_before_fix。
5. 两个独立SDRAM runner同秒并发触发新目录exist_ok=False保护，第二个没有启动仿真；稍后以独立新目录执行，不覆盖旧目录。正式复现命令顺序运行各SDRAM profile。
6. 生产素材Windows PowerShell5按ANSI误读无BOM中文；build_voice.ps1加UTF8 BOM后19段16kHz/s16le素材实际生成。RTL保持无BOM ASCII注释。
7. WAIT_BUSY极短片段done分支补齐最后一步完成处理，与正常WAIT_DONE规则一致；全部受影响音频/整机回归重跑。
8. 完成新仲裁延迟用例时，首轮全回归已启动；其结果只能标SOURCES_CHANGED。最终重新执行包含全部38项的全回归，不拼接旧PASS。

9. 首轮TD原生门级LUT11570、DSP21，但BRAM84/64，阻止物理实现。层次报告定位font_rom57块（旧版29块）；虚拟字模地址未被综合器证明限域，保留了完整16K×32 ROM。生产路径显式改为3584..7679的4K连续窗口，仍使用同一个font_rom和同步读口，不改字形/像素延迟；新增4096字逐字等价测试，并对12完整RTL帧做修改前后SHA256对照。原失败run prj/td/runs/20261030T123307Z_5f90ba19完整保留。修复后重跑全部受影响仿真和全新TD，不放宽资源门禁。

10. 规格hash侧车初值计算了内存字符串而非Windows落盘CRLF字节。规格正文未变，侧车改为真实read_bytes SHA256，与输入审计一致；位流/原生源码/ZIP哈希始终按落盘字节计算。

11. 发布前边界审查：暂停期间开始、恢复后才完成消抖的KEY/医生变化不能补发。原门控仅看采纳当拍running，存在漏测边界。加入逐输入armed：暂停立即撤销；恢复后等待4拍同步余量且raw/candidate/stable相同才重新武装；未完成变化先静默收为基线。新增定向TB先在running仍低时启动候选变化，再在running高后确认稳定，要求零补发并能受理随后新变化。保持R08预期不变，重跑完整回归/真实顶层/新TD，旧39项/位流结果只作修复前证据。
