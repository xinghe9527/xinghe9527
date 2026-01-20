# 检查星河安装目录中的文件隐藏状态
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "    检查文件隐藏状态" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$installPath = "${env:ProgramFiles}\星河"

if (-not (Test-Path $installPath)) {
    Write-Host "❌ 未找到安装目录: $installPath" -ForegroundColor Red
    Write-Host ""
    Write-Host "请先安装星河应用。" -ForegroundColor Yellow
    exit 1
}

Write-Host "安装目录: $installPath" -ForegroundColor Green
Write-Host ""

# 要检查的文件列表
$filesToCheck = @(
    "flutter_windows.dll",
    "app_links_plugin.dll",
    "file_selector_windows_plugin.dll",
    "url_launcher_windows_plugin.dll",
    "ffmpeg.exe",
    "data"
)

Write-Host "检查技术文件隐藏状态:" -ForegroundColor White
Write-Host ""

$allHidden = $true

foreach ($file in $filesToCheck) {
    $fullPath = Join-Path $installPath $file
    
    if (Test-Path $fullPath) {
        $item = Get-Item $fullPath -Force
        $isHidden = $item.Attributes -band [System.IO.FileAttributes]::Hidden
        
        if ($isHidden) {
            Write-Host "  ✅ $file" -NoNewline
            Write-Host " - 已隐藏" -ForegroundColor Green
        } else {
            Write-Host "  ❌ $file" -NoNewline
            Write-Host " - 未隐藏" -ForegroundColor Red
            $allHidden = $false
        }
    } else {
        Write-Host "  ⚠️  $file" -NoNewline
        Write-Host " - 文件不存在" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan

if ($allHidden) {
    Write-Host "✅ 所有技术文件都已成功隐藏！" -ForegroundColor Green
} else {
    Write-Host "❌ 部分文件未隐藏" -ForegroundColor Red
    Write-Host ""
    Write-Host "提示：需要以管理员身份运行安装程序" -ForegroundColor Yellow
}

Write-Host ""

# 检查主程序
Write-Host "主程序检查:" -ForegroundColor White
$mainExe = Join-Path $installPath "xinghe.exe"
if (Test-Path $mainExe) {
    $exeItem = Get-Item $mainExe
    $isExeHidden = $exeItem.Attributes -band [System.IO.FileAttributes]::Hidden
    
    if ($isExeHidden) {
        Write-Host "  ⚠️  xinghe.exe 被隐藏了（不应该隐藏）" -ForegroundColor Yellow
    } else {
        Write-Host "  ✅ xinghe.exe 可见（正确）" -ForegroundColor Green
    }
    
    Write-Host "  文件大小: $([math]::Round($exeItem.Length/1KB,2)) KB" -ForegroundColor Gray
}

Write-Host ""
Write-Host "按任意键退出..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
