$url = "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip"
$zip = "ffmpeg.zip"
$temp = "ffmpeg_temp"
$target = "windows\ffmpeg"

Write-Host "Downloading FFmpeg..." -ForegroundColor Green
Invoke-WebRequest -Uri $url -OutFile $zip

Write-Host "Extracting..." -ForegroundColor Green
Expand-Archive -Path $zip -DestinationPath $temp -Force

Write-Host "Copying ffmpeg.exe..." -ForegroundColor Green
$exe = Get-ChildItem -Path $temp -Recurse -Filter "ffmpeg.exe" | Select-Object -First 1
Copy-Item -Path $exe.FullName -Destination "$target\ffmpeg.exe" -Force

Write-Host "Cleaning up..." -ForegroundColor Green
Remove-Item -Path $zip -Force
Remove-Item -Path $temp -Recurse -Force

Write-Host "Done! FFmpeg installed to $target\ffmpeg.exe" -ForegroundColor Green
