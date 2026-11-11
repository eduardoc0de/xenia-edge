# get_webcam_files.ps1 [[-Storage] XENIA_STORAGE_FOLDER]: sets up what a webcam
# needs to stand in for a Kinect, in the kinect folder of Xenia's storage
# folder (C:\Users\<you>\AppData\Local\Xenia by default, or the emulator's
# executable folder when portable.txt is next to it):
#   - pose_detector.onnx and pose_landmarks_detector.onnx: MediaPipe's pose
#     landmarker (Google, Apache License 2.0), converted to ONNX by
#     convert_pose_models.py in a temporary Python environment;
#   - onnxruntime.dll: ONNX Runtime (Microsoft, MIT).
# Needs curl.exe (built into Windows 10+) and, for the conversion, uv
# (winget install astral-sh.uv), or Python 3.10-3.13.
param([string]$Storage = "$env:LOCALAPPDATA\Xenia")

$ErrorActionPreference = "Stop"
$dest = Join-Path $Storage "kinect"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$taskUrl =
  "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_full/float16/latest/pose_landmarker_full.task"
$ortVersion = "1.22.0"
$ortUrl =
  "https://github.com/microsoft/onnxruntime/releases/download/v$ortVersion/onnxruntime-win-x64-$ortVersion.zip"

$work = Join-Path ([System.IO.Path]::GetTempPath()) `
  ("xenia-kinect-" + [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $dest | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $work "download") | Out-Null
try {
  Write-Host "Downloading MediaPipe's pose landmarker..."
  curl.exe -fL --progress-bar `
    -o (Join-Path $work "download\pose_landmarker_full.task") $taskUrl

  Write-Host "Converting it to ONNX..."
  $packages = @("tflite", "onnx", "onnxruntime", "ai-edge-litert", "numpy")
  $python = $null
  if (Get-Command uv -ErrorAction SilentlyContinue) {
    # uv fetches a suitable Python (3.13) itself if none is installed.
    uv venv --python 3.13 (Join-Path $work "venv")
    uv pip install --python (Join-Path $work "venv\Scripts\python.exe") $packages
    $python = Join-Path $work "venv\Scripts\python.exe"
  } else {
    $version = & python -c "import sys; print(f'{sys.version_info[0]}.{sys.version_info[1]}')" `
      2>$null
    if (-not $version -or $version -notmatch "^3\.(1[0-3])$") {
      throw "The conversion needs Python 3.10-3.13 (found: $(if ($version) { $version } else { 'none' })). Install uv (winget install astral-sh.uv) and run this again."
    }
    python -m venv (Join-Path $work "venv")
    & (Join-Path $work "venv\Scripts\python.exe") -m pip install --quiet $packages
    $python = Join-Path $work "venv\Scripts\python.exe"
  }
  & $python -I -W ignore (Join-Path $here "convert_pose_models.py") `
    (Join-Path $work "download\pose_landmarker_full.task") $dest

  if (Test-Path (Join-Path $dest "onnxruntime.dll")) {
    Write-Host "ONNX Runtime is already in $dest."
  } else {
    Write-Host "Downloading ONNX Runtime $ortVersion..."
    curl.exe -fL --progress-bar -o (Join-Path $work "download\ort.zip") $ortUrl
    Expand-Archive -Path (Join-Path $work "download\ort.zip") `
      -DestinationPath (Join-Path $work "download") -Force
    Copy-Item `
      (Join-Path $work "download\onnxruntime-win-x64-$ortVersion\lib\onnxruntime.dll") `
      (Join-Path $dest "onnxruntime.dll")
    Copy-Item `
      (Join-Path $work "download\onnxruntime-win-x64-$ortVersion\LICENSE") `
      (Join-Path $dest "onnxruntime-LICENSE")
  }
  Write-Host "Done: a webcam can stand in for a Kinect ($dest)."
} finally {
  Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}
