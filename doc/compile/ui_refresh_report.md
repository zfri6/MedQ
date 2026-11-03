> TD 接续后当前源码为 80 项哈希，ModelSim 18/18 重新通过；此处 78 项为界面交付时的冻结快照。当前硬件适配见 td_report.md。

# MedQ 字体、画面与动画优化验收

2026-10-26：已完成 FPGA 实际 OSD 像素通路的显示优化。当前源码 ModelSim **18/18 PASS**，
包含新增 `tb_medq_ui` 和整机；Icarus 的原 OSD 配置及视频时序两项补充检查通过。
Verilog-2001 门禁退出 0。78 个源码/测试数据哈希在全套回归期间不变，两个安路 wrapper 保持原字节。

## 可见变化

- 浅灰蓝背景、白色圆角分区、青绿色医疗十字、清晰的标题和信息层次。
- 票号与诊室使用原生尺寸大字，中文标题、小字和数字采用四档覆盖度抗锯齿。
- 候诊人数、普通/优先、人工/自动、重呼状态均取自实际 QSTATE；空闲显示横线，不伪造号码。
- 叫号提示以 16 帧 cubic ease-out 推进，包含轻微位移、淡入和指示线展开；重呼重新触发。
  主号码保持稳定，状态点使用 120 帧呼吸变化。全部可见业务状态仅在帧边界提交。
- 保持 800×525 扫描、25 MHz 像素时钟、两拍 OSD 延迟。实际扫描率 59.5238 Hz，动画约 268.8 ms。
  字体 ROM 声明仍为 16384×32 bit，利用地址 8192..16383 的空闲区放置 256×512、2 bit 图集。

默认面板为不透明业务界面，覆盖原素材背景。cfg_addr=768 bit0 写 0 可关闭面板、恢复原透明文字层用法；
原 16 个可配置文字域继续支持，PARAM[40] 关闭整个 OSD 后可显示原 SDRAM 图像。顶层 UART 暂不提供任意 cfg 写入口。

## 真实画面与动画

- [整机板级输入仿真捕获](../../sim/ui/medq_top.png)
- [稳定叫号界面](../../sim/ui/medq_dashboard.png)、[重呼](../../sim/ui/medq_recall.png)、[优先号/自动模式](../../sim/ui/medq_priority.png)
- [叫号动画 GIF](../../sim/ui/medq_call_animation.gif)：来自 20 张未重绘的 RTL 原始帧，含 17 张连续动画状态。
  GIF 以 20 ms 量化帧间隔播放，实际 RTL 每帧 16.8 ms；静态 PNG 保留原始像素，GIF 有调色板量化。
- [预览原始帧哈希与颜色检查](../../sim/ui/preview_verification.json)、[整机帧检查](../../sim/frame_verification.json)

## 验证内容

`tb_medq_ui` 验证帧内快照保持、16 帧 easing 单调与终值、重呼重新触发、120 帧呼吸循环、
0/85/170/255 四档覆盖度的精确颜色、字模读口相位和 20 张 640×480 完整画面。
四档颜色另由 Pillow 对真实截图核对，未用 Python 重绘界面。

全套保留 SD SPI/FAT32/BMP/缩放/队列/CDC/音频/HDMI/串化/整机测试。
整机在 39.6255 ms 仿真时间内完成三次跨域叫号/重呼、27 段 PCM，7620 次存储突发，1902 个音频样本选通，
无板级未知值、显示欠载或 PCM 欠载；捕获完整一帧。

最初将捕获从 11 张扩展到 20 张时，测试平台 180 ms 看门狗不足，发生一次 TIMEOUT；
已保留该失败证据在 `sim/ui/attempts/`，将测试预算按 20×640×480×40 ns 调整到 300 ms 后，完整回归通过。
这次失败是捕获测试时限问题，不作为 RTL 运行失败隐藏或计入通过数。

## 复现与改动位置

```powershell
python sim/run_regression.py --sim modelsim --timeout 240
python sim/make_ui_preview.py
```

只检查界面：

```powershell
python sim/run_sim.py --sim modelsim --run --tb-top tb_medq_ui --output-dir sim/tests/modelsim/tb_medq_ui
python sim/make_ui_preview.py
```

界面布局/色板/动画在 `rtl/medq_ui_scene.v`；同步字模混合在 `rtl/osd_renderer.v`；字体图集由 `sim/build_font.py` 生成。
日常仿真直接使用保存的 HEX/VH，不需要 Pillow 或本机字体；重新生成/预览导出需要 Pillow。
ModelSim 的 ASCII 镜像已补齐 `.vh` 复制，回归哈希也覆盖 `.vh`。

修改前快照：`sim/baseline/ui_20261026/sources.zip` 与 `sha256.json`。
源码差异：[source_changes.patch](../../sim/ui/source_changes.patch)；[改动清单](../../sim/ui/change_manifest.json)；
当前 [回归凭据](../../sim/ui/regression_result.json) 和 `sim/tests/modelsim/<tb>/` 下逐项日志可追溯到同一源码哈希。

## 边界

本次闭环是门诊主界面及其叫号动画，不代表原 `transition_engine` 的全部素材转场、完整诊断页面、双屏已验收。
新面板没有新增帧缓存或 SDRAM 读取，ROM 声明容量保持不变，但实际 LUT/BRAM/DSP 映射和时序必须以 TD 综合/布局布线报告为准。
安路真实 IP、约束、位流和实板流畅度尚未验证。
