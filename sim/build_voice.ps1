$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Speech
$projectRoot = Split-Path -Parent $PSScriptRoot
$assetOutput = Join-Path $projectRoot 'assets\sd_root'
New-Item -ItemType Directory -Path $assetOutput -Force | Out-Null
$speaker = New-Object System.Speech.Synthesis.SpeechSynthesizer
$speaker.SelectVoice('Microsoft Huihui Desktop')
$speaker.Rate = 1
$format = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(16000, [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen, [System.Speech.AudioFormat.AudioChannel]::Mono)
$phrases = @('提示','请','A','零','一','二','三','四','五','六','七','八','九','号到','A诊室','B诊室','欢迎','B','就诊','C','D')
$patients = (Get-Content (Join-Path $projectRoot 'assets\patients.json') -Raw -Encoding UTF8 | ConvertFrom-Json).patients
$phrases += @($patients | ForEach-Object { $_.name }) + @('号','到','患者')
for ($voiceIndex=0; $voiceIndex -lt $phrases.Count; $voiceIndex++) {
    $wavePath = Join-Path $assetOutput ('CLIP{0:D2}.wav' -f $voiceIndex)
    $speaker.SetOutputToWaveFile($wavePath, $format)
    $speaker.Speak($phrases[$voiceIndex])
    $speaker.SetOutputToNull()
}
$speaker.Dispose()
python (Join-Path $PSScriptRoot 'voice_manifest.py')
