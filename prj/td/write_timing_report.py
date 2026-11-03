"""Write the V0.3 report/README from current signed native evidence only."""
from pathlib import Path
import json,re,shutil
import medq_td,signoff_timing
ROOT=medq_td.ROOT
def read(p):return json.loads(p.read_text(encoding='utf-8'))
def main():
 signoff_timing.simulation_gate()
 pointer=read(ROOT/'prj/td/latest_timing_bitstream.json');bit=read(ROOT/pointer['result'])
 assert pointer['status']=='PASS' and bit['status']=='PASS'
 signoff_timing.check_hashes(bit['source_sha256'])
 signed=read(ROOT/bit['parent_signoff']);native=read(ROOT/signed['original_result'])
 assert native['meta']['name']=='MedQv03'
 regression=read(ROOT/'sim/regression_result.json');values=signed['timing']['values'];area=signed['physical_resources']
 run=(ROOT/signed['original_result']).parent
 qor=(run/'reports/MedQv03_route.qor').read_text(encoding='utf-8')
 utilization=float(re.search(r'slices percentage\s*\|\s*([\d.]+)%',qor)[1])
 destination=ROOT/'deliverables'/Path(bit['bitstream']).name
 if destination.exists():assert medq_td.sha(destination)==bit['bitstream_sha256']
 else:shutil.copy2(ROOT/bit['bitstream'],destination)
 destination.with_suffix('.sha256').write_text(bit['bitstream_sha256']+'  '+destination.name+'\n',encoding='ascii')
 lines=['# MedQ V0.3 事件字幕即时刷新修订本机验证与交付报告（2026-11-01）','',
  '**双诊室新业务仿真、真实控制器集成、原生TD时序签核和新位流生成分别通过。未上板。**','',
  f'ModelSim完整回归：{len(regression["results"])} / {len(regression["results"])} PASS；Verilog-2001门禁通过。',
  next(line.lstrip('# ') for line in (ROOT/'sim/tests/modelsim/tb_dual_service/sim.log').read_text(encoding='utf-8').splitlines() if 'PASS dual-room independent scoreboard' in line),
  '生产计时25MHz*30=750000000，30bit。单元终值用deposit加速，整机仅引脚驱动，未force内部状态。',
  '真实控制器：物理模型检查BL4/CL3、AC、刷新、掩码、边界、反压；真实PLL两帧带宽压力、真实顶层长PCM取消/暂停与双室语音均通过。',
  '语音链路仿真采用已知PCM测试向量；部署语音是本机Huihui生成的21段16000Hz s16le素材，语义/片段顺序与新RTL映射绑定。未声称实板声学测试。','',
  '视觉修订：生产8K同步ROM恢复2bit四级覆盖度；像素参考逐一比较，两个部分覆盖度等级、图集寻址范围和任一/两个叫号开关关闭后人数/字幕仍更新均纳入本轮ModelSim。',
  '行为规格按本轮双室开关/姓名占位要求修订；见doc/spec/marquee_events_20261101.md。本次新增8个操作提示sprite；原75个字形覆盖度和21段语音字节保持前版一致。','',
  '|原生指标|本版结果|','|---|---:|']
 for key,value in values.items():lines.append(f'|{key} / ns|{value:+.3f}|')
 for key,row in area.items():lines.append(f'|{key}|{row["used"]}/{row["available"]}|')
 lines += [f'|Slice利用率|{utilization:.2f}%|',f'|原生STA覆盖率|{signed["timing"]["coverage_percent"]}%|','',
  '两角slow/fast、max/min均分析；违例端点为0。没有全局false path、内部忽略/多周期或虚降频。',
  f'I/O最大延迟和{len(signed["implicit_local_io_hold_exclusions"])}项本地异步/无外部同步捕获hold边界沿用原适用合同，详见io_contract.md与新签核JSON。内部/SIP所有检查保留，55项SDRAM绑定与冻结基线一致。',
  f'原生构建：`{signed["original_result"]}`；签核：`{bit["parent_signoff"]}`。',
  f'新位流：`{destination.relative_to(ROOT).as_posix()}`；{bit["bitstream_bytes"]}字节。',
  f'SHA256：`{bit["bitstream_sha256"]}`。','',
  '## 证据与复现',
  '按README命令顺序复现；完整stdout和命令位于逐项compile.log/sim.log、原生td_run.log及JSON。',
  '行为规格：doc/spec/behavior_spec.md；操作：doc/spec/operation_v03.md；旧断言对应：doc/spec/regression_migration.md；首个不一致和修复：doc/compile/v03_repairs.md。',
  f'{len(regression["results"])}项ModelSim：sim/regression_result.json；实际顶层12连续帧PNG/GIF/APNG：sim/ui/v03_rtl/；只转换RTL输出PPM，不用软件重画界面。',
  '包SHA/内部清单/真实解压逐文件检查见deliverables/latest_v03.json与交付包DELIVERY_MANIFEST.json。','',
  'board_test: not_tested。没有下载，没有HDMI/SDRAM电气实测、实卡兼容认证或长时间实板运行。SW丝印编号仍以文档默认端口/引脚表为准。',
  '默认限制：A/B/C/D每类独立01..99不回卷，复位清空；每种队列16项；回诊新建票；本室开关关闭仅停止本室叫号，另一室和所有输入/显示保持实时；素材按空FAT32根目录顺序部署；无第二屏/持久化/热插拔恢复。']
 report='\n'.join(lines)+'\n';(ROOT/'doc/compile/v03_report.md').write_text(report,encoding='utf-8')
 readme=f"""# MedQ V0.3 — 独立双诊室叫号（事件字幕即时刷新修订）

**{len(regression['results'])}/{len(regression['results'])} ModelSim、真实加密SDRAM集成、原生双角setup/hold、新位流生成通过；未上板。**

Setup WNS {values['SWNS']:+.3f}ns，hold WNS {values['HWNS']:+.3f}ns；LUT {area['lut']['used']}/{area['lut']['available']}，BRAM9K {area['bram']['used']}/64，DSP {area['dsp']['used']}/29，Slice {utilization:.2f}%。

- 操作/输入映射/停止叫号约定：doc/spec/operation_v03.md、doc/spec/behavior_spec.md
- 逐操作字幕、下一帧左端刷新、独立滚动相位：doc/spec/marquee_events_20261101.md\n- 四级抗锯齿与视觉补充契约：doc/spec/visual_amendment_20261031.md；视觉设计交接：HANDOFF.md
- 当前验证结果/适用边界：doc/compile/v03_report.md、doc/compile/v03_status.json
- 实际RTL页面与连续帧：sim/ui/v03_rtl/（原生顶层PPM转换，非实板）
- 位流：{destination.relative_to(ROOT).as_posix()}；SHA256：`{bit['bitstream_sha256']}`
- 交付包/校验：deliverables/latest_v03.json；ZIP内有DELIVERY_MANIFEST.json，所有文件解压后逐个SHA256验证。
- V0.2原始891文件受baseline/v02_frozen/manifest.json保护；本目录继承的旧报告/旧位流均为历史材料，不能代替本版证据。

## 功能和素材

K1/K2/K3/K4=KEY[0]/[1]/[2]/[3]，分别A普通/B普通/A回诊/B回诊；SW1/SW2/SW3/SW4=SW[0]/[1]/[2]/[3]，分别低有效允许A叫号/低有效允许B叫号/A医生双边沿/B医生双边沿。候诊每种16项、A普通A01..A99/B普通B01..B99/A回诊C01..C99/B回诊D01..D99，四类独立编号，严格回诊优先且当前不被抢占。三次呼叫按实际接纳0/30/60秒，第三次再等30秒未到结束；共享音频争用可延后。本室开关关闭保存本室叫号计时并静音/安全排空本室音频，让另一室继续；重开为同一患者重播完整语句且不增加呼叫次数。按键取号、医生到位/离开、人数显示与两条字幕继续，恢复不重复取号。字幕请A01***到A诊室就诊/请B01***到B诊室就诊，C/D分别到A/B，三个星号为姓名占位。实际帧率59.5238Hz，字幕1px/2帧。每个操作刷新对应诊室提示：取号成功、回诊取号、拒绝、启停、叫号/重呼/恢复开播、到位、就诊结束、过号；下一帧从x24完整显字并重启独立相位，同室帧间多事件显示最新操作，另一室不复位。

assets/sd_root下21个.PCM（CLIP00..20，含C/D语音，与前版兼容）按编号顺序复制到空FAT32根目录（仅PCM，不要WAV或额外PCM）；格式16kHz/16bit有符号小端/单声道；目录枚举顺序即片段编号。可无BMP，地图和动态信息由RTL生成。素材脚本powershell -ExecutionPolicy Bypass -File sim/build_voice.ps1，本机需Microsoft Huihui Desktop；已生成的素材日常使用不需要TTS。字模已保存；仅重新生成时依次运行sim/build_font.py、sim/build_dual_font.py，需要本机字体/Pillow。

## 复现步骤（项目根目录，按顺序）

```powershell
python sim/run_regression.py --sim modelsim --timeout 600
python sim/run_vendor_sdram.py --system --timeout 600
python sim/run_vendor_sdram.py --system --system-tb tb_v03_top_audio --timeout 300
python sim/run_vendor_sdram.py --system --system-tb tb_basic_calling --timeout 180
python sim/run_vendor_sdram.py --timeout 300
python sim/run_vendor_sdram.py --real-pll --timeout 300
python sim/run_vendor_sdram.py --bandwidth --real-pll --timeout 600
python sim/run_vendor_pll.py
python sim/run_vendor_serdes.py
python prj/td/medq_td.py --name MedQv03 --mode implement --run --timeout 1800
# 如默认布局拥塞，可保留原run并复用同一gate.db，只改变布局种子：
# python prj/td/route_seed.py --parent-result <parent-result.json> --seed 61 --timeout 1800
# 实现后REVIEW_REQUIRED表示尚需严格审核；使用上一步新run的相对路径签核，禁止复用旧run。
python prj/td/signoff_timing.py --result <new-run-result.json> --bitgen
python sim/capture_v03.py --source <new-real-system-result-directory>
python prj/td/write_timing_report.py
python prj/td/finalize_marquee_events.py
python sim/package_release.py --timing
python prj/td/seal_timing_release.py
```

TD 6.2.168116，真实入口td_commands_prompt.exe，校准工具路径见doc/hw/toolchain.json。每次原生构建用唯一ASCII临时工程并把完整产物回存V0.3/prj/td/runs；所有正式证据在本版本内。签核脚本检查新源码/配置哈希、双角原生STA、约束、资源与新bitgen STA；不把综合/仿真/位流当作上板证据。

board_test: not_tested。本次未下载；SW丝印尚未独立实板核对。其他限制和I/O适用边界见验证报告。As of 2026-11-01。
"""
 (ROOT/'README.md').write_text(readme,encoding='utf-8')
 medq_td.dump(ROOT/'doc/compile/v03_status.json',{'version':'0.3','revision':'marquee_events_20261101','specification':'per_room_operation_messages_next_frame_left_reset_independent_scroll','visual_contract':'doc/spec/marquee_events_20261101.md','implementation':'complete','simulation':'PASS','modelsim_tests':len(regression['results']),'real_sdram':'PASS','sta':'PASS','bitstream':'PASS','release':'see_release_pointer','release_authority':'deliverables/latest_v03.json','board_test':'not_tested','signoff':bit['parent_signoff'],'bitstream_path':destination.relative_to(ROOT).as_posix(),'bitstream_sha256':bit['bitstream_sha256']})
 print('V03_REPORT_WRITTEN',values,'board_test: not_tested')
if __name__=='__main__':main()
