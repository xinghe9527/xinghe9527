# 手动隐藏技术文件脚本
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "    手动隐藏技术文件工具" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 需要管理员权限
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
{
    Write-Host "❌ 需要管理员权限！" -ForegroundColor Red
    Write-Host "请右键以管理员身份运行此脚本。" -ForegroundColor Yellow
    Write-Host ""
    pause
    exit 1
}

# 查找安装目录
$installPath = $null
$possiblePaths = @(
    "${env:ProgramFiles}\星河",
    "C:\Program Files\星河",
    "C:\Program Files (x86)\星河",
    "D:\星河",
    "D:\星河2",
    "D:\星河3"
)

foreach ($path in $possiblePaths) {
    if (Test-Path "$path\xinghe.exe") {
        $installPath = $path
        break
    }
}

if (-not $installPath) {
    Write-Host "❌ 未找到星河安装目录！" -ForegroundColor Red
    Write-Host ""
    Write-Host "请手动输入安装目录路径:" -ForegroundColor Yellow
    $installPath = Read-Host "路径"
    
    if (-not (Test-Path "$installPath\xinghe.exe")) {
        Write-Host "❌ 指定路径无效！" -ForegroundColor Red
        pause
        exit 1
    }
}

Write-Host "✅ 找到安装目录: $installPath" -ForegroundColor Green
Write-Host ""

# 要隐藏的文件列表
$filesToHide = @(
    "flutter_windows.dll",
    "app_links_plugin.dll",
    "file_selector_windows_plugin.dll",
    "url_launcher_windows_plugin.dll",
    "ffmpeg.exe",
    "data"
)

Write-Host "开始隐藏技术文件..." -ForegroundColor Green
Write-Host ""

$successCount = 0
$failCount = 0

foreach ($file in $filesToHide) {
    $fullPath = Join-Path $installPath $file
    
    if (Test-Path $fullPath) {
        try {
            $item = Get-Item $fullPath -Force
            $item.Attributes = $item.Attributes -bor [System.IO.FileAttributes]::Hidden
            
            Write-Host "  ✅ $file - 已隐藏" -ForegroundColor Green
            $successCount++
        } catch {
            Write-Host "  ❌ $file - 隐藏失败: $_" -ForegroundColor Red
            $failCount++
        }
    } else {
        Write-Host "  ⚠️  $file - 文件不存在" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "隐藏完成！" -ForegroundColor Green
Write-Host "  成功: $successCount 个" -ForegroundColor Green
Write-Host "  失败: $failCount 个" -ForegroundColor $(if ($failCount -gt 0) { "Red" } else { "Gray" })
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 验证结果
Write-Host "验证隐藏状态..." -ForegroundColor White
Write-Host ""

foreach ($file in $filesToHide) {
    $fullPath = Join-Path $installPath $file
    
    if (Test-Path $fullPath) {
        $item = Get-Item $fullPath -Force
        $isHidden = $item.Attributes -band [System.IO.FileAttributes]::Hidden
        
        if ($isHidden) {
            Write-Host "  ✅ $file" -ForegroundColor Green
        } else {
            Write-Host "  ❌ $file（仍然可见）" -ForegroundColor Red
        }
    }
}

Write-Host ""
Write-Host "提示：" -ForegroundColor Yellow
Write-Host "- 在文件资源管理器中，取消勾选'查看 > 显示 > 隐藏的项目'即可完全隐藏这些文件" -ForegroundColor Gray
Write-Host "- 即使勾选'显示隐藏文件'，这些文件也会以半透明图标显示" -ForegroundColor Gray
Write-Host ""
Write-Host "按任意键退出..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
