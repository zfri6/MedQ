MedQ V0.3 封面和医生轮播版 TF 卡

1. 使用 FAT32 格式的 TF 卡。将 SD_ROOT 内全部57个文件直接复制到卡的根目录，不要把 SD_ROOT 文件夹本身复制进去。
2. 根目录应有 COVER.BMP、DOC01.BMP、DOC02.BMP，以及 CLIP00.PCM 至 CLIP53.PCM。不要把 JPG、PNG、WAV 或 bit 位流当成运行素材复制进根目录。
3. 在 TD 下载配套 MEDIA_COVER 新版 bit；重新上电显示封面，K1..K4 任意键进入。进入键不会取号，全部松开后新的按键才启用诊室功能。
4. 系统内 K1=A初诊，K2=B初诊，K3=A回诊，K4=B回诊；SW1=A叫号，SW2=B叫号，SW3=A医生到位/离开，SW4=B医生到位/离开。SW1/2低有效。
5. 医生照片自动轮播。右下波形反映实际 HDMI 播报音频，静音时是平线。语音经 HDMI 输出。
6. 男医生选择较大的 PNG。运行 BMP 已离线高质量缩放并固定为640x480/24bit；替换图片请按工程 sim/build_media_assets.py 重新转换，不要直接改扩展名。
7. 本包完成本机仿真、原生时序与封包校验，尚未实板下载/验收。board_test: not_tested。
