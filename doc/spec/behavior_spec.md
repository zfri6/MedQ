> 当前姓名遮罩与语音节奏以masked_smooth_20261102.md为准。

> 2026-11-02姓名与语音修订以 patient_names_20261102.md 为准。

> 2026-11-01字幕行为以 marquee_events_20261101.md 为准：每个操作对应提示，下一帧从x24重启独立滚动。

# MedQ V0.3 行为契约（2026-10-31 双室独立开关/姓名占位修订）

状态：implementation contract。验收结果另见 doc/compile/v03_status.json，旧V0.2报告不能作为本版证据。

## 用户明确要求
|规则|触发/观测|合格标准|
|R01 输入|KEY/SW引脚到事件|两级同步后消抖；按下一次一人，长按不重复；医生双边沿；初始化不制造事件|
|R02 独立|A/B FIFO/状态/计时|每室独立普通/回诊FIFO及各类独立分配器，禁止跨室修改|
|R03 严格优先|首次有效叫号grant|回诊先于全部普通；未grant普通可被新回诊延后；当前患者不被抢占|
|R04 人数|grant/recall|首次grant一次出队；重呼保持票和等待数；当前不算等待|
|R05 状态|doctor_event|IDLE忽略；WAIT_ARRIVAL到IN_VISIT；IN_VISIT到IDLE。电平不是业务状态|
|R06 呼叫|start/grant和elapsed|0/30/60秒最多三次；医生事件同拍优先于grant/最终超时|
|R07 到位|任意WAIT时刻|持续监控；取消本室尚未开播/在播，另一室不受影响|
|R08 停止叫号|本室run=0|仅禁止本室首次/重呼grant及计时；本室播放静音并安全排空，重开为同患者重播完整语句且不增加呼叫次数；另一室继续；普通/回诊取号和医生事件继续受理；计数/服务状态/两字幕每帧更新|
|R09 仲裁|A/B同时请求|轮转公平；保持请求至实际接纳，busy不计次；以每次grant作为本室30秒起点|
|R10 音频|素材就绪|普通请 A01/B01，回诊请 C01 到 A诊室/D01 到 B诊室就诊；无卡明确基础叫号及有限提示音|
|R11 显示|实际640x480像素|两字幕、两卡片、示例地图；原同步ROM及两拍像素流水；号码/状态/计数/字幕同帧快照|
|R12 底层|真实控制器|保护刷新、显示低水位、PCM预充、真实欠载、PLL、HDMI；存储不因pause停钟|
|R13 守恒|每周期|成功入队=普通等待+回诊等待+当前有效+完成+过号；拒绝及重呼不改变成功数|
|R14 签核|源码/日志/STA/bit|最终同源完整ModelSim、真实控制器、原生双角setup/hold、资源、fresh bitgen和ZIP校验|

## 默认补充约定
D01 第三次grant后再等待30秒，约90秒过号，不重新入队。
D02 四类独立票号：A普通A01..A99、B普通B01..B99、A回诊C01..C99、B回诊D01..D99；各自从01递增，互不消耗号段，不回卷，单类号尽不阻止另一类。每种队列16项，AW=4；回诊严格优先，当前不被新取号抢占。每室最大成功取号198，accepted/completed/missed为8bit；室号+回诊类别+BCD共同标识事务。
D03 CLK_BUSINESS_HZ=25000000，来自已校准25MHz像素PLL；INTERVAL_CYCLES=750000000，30位计数足够，表达式用64位计算后推导宽度。每室计时为业务有效周期，停止叫号不消耗；仲裁延迟只延后实际呼叫，不提前。
D04 医生开关初始位置只作基线；SW1=SW[0]控制A，SW2=SW[1]控制B，均低有效叫号、高有效停止；SW3=SW[2]为A医生，SW4=SW[3]为B医生。所有KEY和医生事件在初始化后始终按消抖正常受理，SW1/SW2切换不清除或重放输入；停止叫号仍可办理到位/离开，且安全取消对应音频。
D05 共享语音按完整语句串行。开始接纳定义为首段非零PCM请求被播放器接纳；无卡时有限提示音被接纳。当前患者在该拍才建立，票号只出队一次。取消先安全结束已发存储突发并清除旧PCM，再服务另一室；不复用旧事务。每类票号在复位生命周期唯一，room+return_class+ticket唯一标识事务。
D06 每个frame_start都更新同帧快照、两卡片人数、服务状态、字幕与动画，任一/全部叫号开关关闭不冻结画面。两字幕仍按1像素/2帧连续移动；时钟、存储刷新、在途事务继续。
D07 字幕1像素/2帧=29.7619px/s（25MHz/800/525）；在x24..615的各自20像素高窗口内循环。示例地图不代表真实医院。
D08 UART旧队列控制不接入新业务，命令5参数设置及协议ACK/NAK回归保留；四个SW均有明确业务功能。

## 状态转移与同拍优先级
reset > doctor_event >（仅叫号开启时 final_timeout > start_grant > elapsed++）；普通/回诊入队始终独立受理，用净变化更新计数。
|当前|条件|下一状态|动作|
|IDLE|doctor_event|IDLE|无派号|
|IDLE|queue request & grant|WAIT_ARRIVAL|回诊优先选队首，出队，count=1，elapsed=0|
|WAIT_ARRIVAL|doctor_event|IN_VISIT|elapsed保持，取消本患者语音|
|WAIT_ARRIVAL|elapsed终值且count<3|WAIT_ARRIVAL|保持请求，等grant；grant才加次数且elapsed清0|
|WAIT_ARRIVAL|elapsed终值且count=3|IDLE|过号+1，清当前并取消语音|
|IN_VISIT|doctor_event|IDLE|完成+1，清当前|
医生到位/离开不受SW1/SW2限制；新叫号、重呼、计时和过号仅在本室run有效时推进。胶囊显示空闲/呼叫中/就诊中。

## 输入映射与硬件事实
沿用已校准HX4S20C / EG4S20BG256、50MHz@R7、25/125MHz视频、50MHz/+8ns SDRAM。原ADC/IP字节保护。
|操作|端口|引脚|电气/语义|
|K1|KEY[0]|A2|低有效，A普通|
|K2|KEY[1]|B2|低有效，B普通|
|K3|KEY[2]|B1|低有效，A回诊|
|K4|KEY[3]|C1|低有效，B回诊|
|SW1|SW[0]|C8|低有效允许A叫号，高仅停止A叫号|
|SW2|SW[1]|C7|低有效允许B叫号，高仅停止B叫号|
|SW3|SW[2]|C6|稳定双边沿A医生|
|SW4|SW[3]|C5|稳定双边沿B医生|
依据：doc/hw/extracted_facts.json及原DEMO a.adc、6_cnt10/cnt10.adc、8_key_sw/key_sw.adc。KEY1..4别名有资料证据；SW物理编号丝印未独立实板核对，采用用户指定SW[0..3]，操作说明同时标端口/引脚；不宣称实板确认。
消抖/初始化默认250000个25MHz周期=10ms，先等待4拍同步稳定再采初值。参数化供真实抖动和加速仿真。

## 资源预算（实现前估计，不是测量）
V0.2物理LUT13584/19600、BRAM58/64、DSP25/29。新队列4x16x8=512bit，优先寄存器/分布式；业务/输入/仲裁预计<1800LUT、<1000FF、0DSP；复用已有font_rom低地址空白区5504..8191存中文单色字模，复用大字，不复制字库；字幕几何无整帧缓存。整体目标BRAM<=58、DSP<=25、LUT<19600；最终只认TD实测。该段为历史预估，当前4K二位图集包含A/B/C/D，格式见visual_amendment_20261031.md。
新业务使用像素域，输入在该域同步/消抖，避免快速语音事件过CDC邮箱丢失。QSTATE向sys走现有宽总线握手，只供数码管/指示；素材ready及状态保持现有sys->pix握手。播放器pix->mem描述符/取消握手须等待已发突发排空。

## 验证契约
独立scoreboard以事件/规则建模，不能读取DUT队列替代期望。每拍检查双室状态/票号/FIFO顺序/计数/守恒；定向同拍、参数边界、随机长序列。生产默认750000000及计数终值独立检查；加速TB只缩参数。
顶层只注入外部引脚/SD模型/UART，不force内部状态。真实控制器和独立物理模型、PLL/串行器回归全部保留。旧队列/旧UI作为legacy单元契约保留；顶层旧四室业务断言映射到新双室用例，不删除有效外设/欠载断言。
board_test: not_tested；仿真/STA/bitgen/实板分别报告。

当前补充契约：doc/spec/independent_switch_name_20261031.md。叫号字幕请A01***到A诊室就诊 / 请B01***到B诊室就诊；C/D仍分别到A/B。QSTATE64为any_run、65为ready、66/67为A/B_run。


最新字幕契约：seamless_marquee_20261102.md。两字幕按整句实际宽度居中刷新，592像素环连续左移，左出右入同一步，无整句退场空档；覆盖此前x24左端刷新与912步旧环规则。

## media_carousel_20261103

Authoritative additional requirements, timings, fallback rules and acceptance gates: `doc/spec/media_carousel_20261103.md`. All existing room, queue, switch, patient, speech and seamless subtitle behavior remains in force after clinic entry. Cover entry is a separately consumed action. Additional audio correction: both16bit tone/PCM inputs are sign-extended, mixed in17bits, multiplied by unsigned Q0.8 volume, shifted arithmetically8bits, saturated to signed16bit. Independent integer reference must cover silence, both signs, saturation, volume0/1/128/255 and strobe holds. PCM files and phrase order are unchanged.
