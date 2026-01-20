# 星河完整清理脚本 - 移除所有残留
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "    星河完整清理工具" -ForegroundColor Cyan
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

Write-Host "开始清理星河相关文件..." -ForegroundColor Green
Write-Host ""

# 1. 查找并删除所有可能的安装目录
$possiblePaths = @(
    "${env:ProgramFiles}\星河",
    "C:\Program Files\星河",
    "C:\Program Files (x86)\星河",
    "D:\星河",
    "D:\星河2",
    "D:\星河3",
    "D:\本地磁盘(D:)\星河",
    "D:\本地磁盘(D:)\星河2",
    "D:\本地磁盘(D:)\星河3"
)

foreach ($path in $possiblePaths) {
    if (Test-Path $path) {
        Write-Host "发现安装目录: $path" -ForegroundColor Yellow
        
        try {
            # 先取消所有文件的隐藏和只读属性
            Get-ChildItem $path -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
                $_.Attributes = 'Normal'
            }
            
            # 删除目录
            Remove-Item $path -Recurse -Force -ErrorAction Stop
            Write-Host "  ✅ 已删除: $path" -ForegroundColor Green
        } catch {
            Write-Host "  ❌ 删除失败: $_" -ForegroundColor Red
        }
    }
}

Write-Host ""

# 2. 清理注册表
Write-Host "清理注册表..." -ForegroundColor Green

$regPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{A8F3D9E2-1B4C-4D7A-9F2E-5C8E6A3B7D1F}_is1",
    "HKCU:\SOFTWARE\Xinghe Studio",
    "HKLM:\SOFTWARE\Xinghe Studio"
)

foreach ($regPath in $regPaths) {
    if (Test-Path $regPath) {
        try {
            Remove-Item $regPath -Recurse -Force -ErrorAction Stop
            Write-Host "  ✅ 已删除注册表: $regPath" -ForegroundColor Green
        } catch {
            Write-Host "  ❌ 删除失败: $_" -ForegroundColor Red
        }
    }
}

Write-Host ""

# 3. 清理开始菜单快捷方式
Write-Host "清理开始菜单快捷方式..." -ForegroundColor Green

$startMenuPaths = @(
    "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\星河",
    "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\星河"
)

foreach ($smPath in $startMenuPaths) {
    if (Test-Path $smPath) {
        try {
            Remove-Item $smPath -Recurse -Force -ErrorAction Stop
            Write-Host "  ✅ 已删除: $smPath" -ForegroundColor Green
        } catch {
            Write-Host "  ❌ 删除失败: $_" -ForegroundColor Red
        }
    }
}

Write-Host ""

# 4. 清理桌面快捷方式
Write-Host "清理桌面快捷方式..." -ForegroundColor Green

$desktopShortcuts = @(
    "$env:PUBLIC\Desktop\星河.lnk",
    "$env:USERPROFILE\Desktop\星河.lnk"
)

foreach ($shortcut in $desktopShortcuts) {
    if (Test-Path $shortcut) {
        try {
            Remove-Item $shortcut -Force -ErrorAction Stop
            Write-Host "  ✅ 已删除: $shortcut" -ForegroundColor Green
        } catch {
            Write-Host "  ❌ 删除失败: $_" -ForegroundColor Red
        }
    }
}

Write-Host ""

# 5. 清理应用数据
Write-Host "清理应用数据..." -ForegroundColor Green

$appDataPaths = @(
    "$env:APPDATA\xinghe",
    "$env:LOCALAPPDATA\xinghe"
)

foreach ($appData in $appDataPaths) {
    if (Test-Path $appData) {
        try {
            Remove-Item $appData -Recurse -Force -ErrorAction Stop
            Write-Host "  ✅ 已删除: $appData" -ForegroundColor Green
        } catch {
            Write-Host "  ❌ 删除失败: $_" -ForegroundColor Red
        }
    }
}

Write-Host ""

# 6. 停止所有运行中的 xinghe 进程
Write-Host "停止运行中的进程..." -ForegroundColor Green

$processes = Get-Process -Name xinghe -ErrorAction SilentlyContinue
if ($processes) {
    foreach ($proc in $processes) {
        try {
            Stop-Process -Id $proc.Id -Force
            Write-Host "  ✅ 已停止进程: PID $($proc.Id)" -ForegroundColor Green
        } catch {
            Write-Host "  ❌ 停止失败: $_" -ForegroundColor Red
        }
    }
} else {
    Write-Host "  ℹ️  没有运行中的进程" -ForegroundColor Gray
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "✅ 清理完成！" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "现在可以重新安装星河了。" -ForegroundColor White
Write-Host "建议使用默认安装路径: C:\Program Files\星河" -ForegroundColor Yellow
Write-Host ""
Write-Host "按任意键退出..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
