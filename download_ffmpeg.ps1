# FFmpeg 自动下载脚本
# 用途：自动下载并配置 FFmpeg 到项目中

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "      FFmpeg 自动下载和配置工具" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 配置
$ffmpegUrl = "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip"
$outputZip = ".\ffmpeg.zip"
$extractPath = ".\ffmpeg_temp"
$targetPath = ".\windows\ffmpeg"

# 检查目标目录
if (-not (Test-Path $targetPath)) {
    New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
    Write-Host "✅ 已创建目录: $targetPath" -ForegroundColor Green
}

# 检查是否已存在
if (Test-Path "$targetPath\ffmpeg.exe") {
    Write-Host "⚠️  FFmpeg 已存在于 $targetPath" -ForegroundColor Yellow
    $overwrite = Read-Host "是否重新下载? (Y/N)"
    if ($overwrite -ne "Y" -and $overwrite -ne "y") {
        Write-Host "已取消操作" -ForegroundColor Yellow
        exit 0
    }
}

# 步骤 1: 下载
Write-Host ""
Write-Host "[1/4] 正在下载 FFmpeg..." -ForegroundColor Green
Write-Host "URL: $ffmpegUrl" -ForegroundColor Gray
try {
    # 使用 .NET WebClient 以显示进度
    $webClient = New-Object System.Net.WebClient
    $webClient.DownloadFile($ffmpegUrl, $outputZip)
    Write-Host "✅ 下载完成！文件大小: $([math]::Round((Get-Item $outputZip).Length / 1MB, 2)) MB" -ForegroundColor Green
} catch {
    Write-Host "❌ 下载失败: $_" -ForegroundColor Red
    exit 1
}

# 步骤 2: 解压
Write-Host ""
Write-Host "[2/4] 正在解压..." -ForegroundColor Green
try {
    Expand-Archive -Path $outputZip -DestinationPath $extractPath -Force
    Write-Host "✅ 解压完成" -ForegroundColor Green
} catch {
    Write-Host "❌ 解压失败: $_" -ForegroundColor Red
    Remove-Item -Path $outputZip -Force -ErrorAction SilentlyContinue
    exit 1
}

# 步骤 3: 复制可执行文件
Write-Host ""
Write-Host "[3/4] 正在查找并复制 ffmpeg.exe..." -ForegroundColor Green
$ffmpegExe = Get-ChildItem -Path $extractPath -Recurse -Filter "ffmpeg.exe" | Select-Object -First 1

if ($ffmpegExe) {
    Copy-Item -Path $ffmpegExe.FullName -Destination "$targetPath\ffmpeg.exe" -Force
    $fileSize = [math]::Round((Get-Item "$targetPath\ffmpeg.exe").Length / 1MB, 2)
    Write-Host "✅ 已复制到: $targetPath\ffmpeg.exe" -ForegroundColor Green
    Write-Host "   文件大小: $fileSize MB" -ForegroundColor Gray
} else {
    Write-Host "❌ 未找到 ffmpeg.exe" -ForegroundColor Red
    Remove-Item -Path $outputZip -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $extractPath -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}

# 步骤 4: 清理临时文件
Write-Host ""
Write-Host "[4/4] 正在清理临时文件..." -ForegroundColor Green
Remove-Item -Path $outputZip -Force -ErrorAction SilentlyContinue
Remove-Item -Path $extractPath -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "✅ 临时文件已清理" -ForegroundColor Green

# 验证
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "✅ FFmpeg 配置完成！" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "位置: $targetPath\ffmpeg.exe" -ForegroundColor Gray
Write-Host ""
Write-Host "下一步操作:" -ForegroundColor Yellow
Write-Host "  1. 运行: flutter pub get" -ForegroundColor White
Write-Host "  2. 构建应用: flutter build windows --release" -ForegroundColor White
Write-Host ""

# 询问是否测试 FFmpeg
$test = Read-Host "是否测试 FFmpeg? (Y/N)"
if ($test -eq "Y" -or $test -eq "y") {
    Write-Host ""
    Write-Host "测试 FFmpeg..." -ForegroundColor Green
    & "$targetPath\ffmpeg.exe" -version
}

Write-Host ""
Write-Host "按任意键退出..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
