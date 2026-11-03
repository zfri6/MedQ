# MedQ V0.3 SD封面、医生轮播和音频波形版（2026-11-03）

上电从TF卡读取用户提供的封面；K1..K4任意键进入诊室系统。进入键被单独消费，全部按键稳定松开后才重新初始化诊室按键/开关，封面操作不会取号或触发医生事件。SW1/SW2独立A/B叫号、SW3/SW4医生、四路初诊/回诊取号及所有原队列规则保留。

右侧地图缩为152x100区域；下方显示一名医生，男/女两张照片自动轮播。照片显示152x128，保持约4秒，采用逐帧smoothstep淡出/淡入（每方向约0.55秒），零透明度换图，隐藏3帧等待现有读取FIFO和CDC稳定；不会同时叠放两位医生。男医生选用较大PNG，另一张男医生原图完整保留。

右下角波形取最终HDMI有符号音频，做32点帧快照、线性插值及边缘覆盖度；静音平线，封面隐藏。独立测试发现旧混音器将负采样零扩展且未正确做Q0.8缩放，负1000/音量128错误输出32767；本版修正为-500，4105项数值对照通过。全部54段PCM、全名语音提速、名单、屏幕张*民隐私遮罩、四级抗锯齿字体和居中连续循环字幕素材保持原字节。

## 直接部署

- 位流：deliverables/MedQ_v0.3_MEDIA_COVER_20261103T063042Z.bit
- SHA256：a1392a908f4533d4cdcd7019dabec5a65c87a96945e0e0033ee2fcedc7298567
- TF卡：deliverables/TF_CARD_MEDIA_20261103/SD_ROOT，共57个文件。把里面的文件直接复制到FAT32根目录。包含3张BMP和原54段PCM，按文件名定位，不依赖复制顺序。
- BMP是电脑端Lanczos缩放的640x480/24bit无压缩文件；JPG/PNG原图放assets/media_source，运行时不使用JPEG/PNG解码或片内图片ROM。
- 旧TF卡必须增加3张BMP；建议使用本包完整SD_ROOT。声音仍经HDMI屏幕/接收设备输出。

## 本机证据

ModelSim完整55/55通过，另2项命名PCM/396整句语音链路专项通过；Verilog-2001检查通过。SD卡多簇读取与跨时钟/反压写入对照921600个实际图片像素；独立封面307200像素、18种照片混合350208像素、4320000个原叫号/字幕区像素对照通过。原14042240点字幕全环回归继续通过。

整机使用原加密SDRAM控制器及独立物理器件模型：图片未全加载前封面已先显示；进入键不误取号；3张图片、54段PCM加载完整；A/B并发18段播放；最终307200封面像素和19456照片像素逐一一致；无显示/音频欠载。原整机业务、长语音取消/暂停、无卡降级和PLL/串行器/带宽证据也通过当前源码哈希核验。36项工具/负向签核测试通过。

实际RTL预览：sim/ui/media_real_system（整机实际SD读取）、sim/ui/media_rtl（独立像素对照）。sim/ui/media_assets是输入素材转换预览，不是RTL或实板证据。

## 时序与资源

原生slow/fast所有setup/hold组通过：WNS +0.225/+0.021ns，TNS0，违例端点0；fresh bitgen重新导入同一路由库并检查STA。
LUT 15268/19600，REG 5927/19600，BRAM 56/64（上一版62），DSP 17/29（上一版20）。板级管脚、PLL频率、SDRAM相位和所有约束保持字节一致，没有增加false path或放宽时序。

签核：doc/compile/timing_closure/20261103T061423Z_c18a20e8/signoff.json。版本权威为deliverables/latest_v03.json，详细结果doc/compile/media_carousel_delivery.json。旧封包、位流、V0.2及修改前源码快照保留。

## 复现

    python sim/build_media_assets.py
    python sim/build_media_fixtures.py
    python sim/run_regression.py --sim modelsim --timeout 1200
    python prj/td/verify_patient_paths.py tb_named_pcm tb_patient_pcm_path
    python sim/run_vendor_sdram.py --system --system-tb tb_media_top --timeout 1200
    python sim/run_vendor_sdram.py --system --timeout 400
    python sim/run_vendor_sdram.py --system --system-tb tb_v03_top_audio --timeout 400
    python sim/run_vendor_sdram.py --system --system-tb tb_basic_calling --timeout 120
    python prj/td/medq_td.py --mode synth --run
    python prj/td/route_seed.py --parent-result <new-synth-result.json> --seed 23
    python prj/td/signoff_timing.py --result <new-route-result.json> --bitgen
    python prj/td/finalize_media_release.py
    python prj/td/package_media_release.py
    python prj/td/seal_timing_release.py

board_test: not_tested。未进行实板下载、HDMI屏幕/扬声器验收或真实TF卡速度测量。
