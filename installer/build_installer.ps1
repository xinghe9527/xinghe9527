# 星河安装程序构建脚本
# 使用 Inno Setup 创建专业的 Windows 安装包

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "    星河安装程序构建工具" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 检查 Inno Setup 是否已安装
$innoSetupPath = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"

if (-not (Test-Path $innoSetupPath)) {
    Write-Host "❌ 未找到 Inno Setup！" -ForegroundColor Red
    Write-Host ""
    Write-Host "请先安装 Inno Setup:" -ForegroundColor Yellow
    Write-Host "1. 访问: https://jrsoftware.org/isdl.php" -ForegroundColor White
    Write-Host "2. 下载并安装 Inno Setup 6" -ForegroundColor White
    Write-Host "3. 重新运行此脚本" -ForegroundColor White
    Write-Host ""
    
    $download = Read-Host "是否现在打开下载页面? (Y/N)"
    if ($download -eq "Y" -or $download -eq "y") {
        Start-Process "https://jrsoftware.org/isdl.php"
    }
    exit 1
}

Write-Host "✅ 找到 Inno Setup: $innoSetupPath" -ForegroundColor Green
Write-Host ""

# 检查 Release 构建是否存在
$releasePath = "..\build\windows\x64\runner\Release"
$exePath = "$releasePath\xinghe.exe"

if (-not (Test-Path $exePath)) {
    Write-Host "❌ 未找到 Release 构建！" -ForegroundColor Red
    Write-Host ""
    Write-Host "请先构建应用:" -ForegroundColor Yellow
    Write-Host "  flutter build windows --release" -ForegroundColor White
    Write-Host ""
    exit 1
}

Write-Host "✅ 找到 Release 构建: $exePath" -ForegroundColor Green
Write-Host ""

# 创建输出目录
$outputDir = ".\output"
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    Write-Host "✅ 创建输出目录: $outputDir" -ForegroundColor Green
}

# 编译安装程序
Write-Host ""
Write-Host "开始编译安装程序..." -ForegroundColor Green
Write-Host ""

try {
    & $innoSetupPath "xinghe-setup.iss"
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "✅ 安装程序创建成功！" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        
        # 查找生成的安装程序
        $setupFile = Get-ChildItem -Path $outputDir -Filter "xinghe-setup-*.exe" | Select-Object -First 1
        
        if ($setupFile) {
            $fileSize = [math]::Round($setupFile.Length / 1MB, 2)
            Write-Host "文件位置: $($setupFile.FullName)" -ForegroundColor Gray
            Write-Host "文件大小: $fileSize MB" -ForegroundColor Gray
            Write-Host ""
            
            # 询问是否测试安装
            $test = Read-Host "是否立即测试安装程序? (Y/N)"
            if ($test -eq "Y" -or $test -eq "y") {
                Write-Host ""
                Write-Host "启动安装程序..." -ForegroundColor Green
                Start-Process $setupFile.FullName
            }
            
            # 询问是否打开输出目录
            $open = Read-Host "是否打开输出目录? (Y/N)"
            if ($open -eq "Y" -or $open -eq "y") {
                explorer $outputDir
            }
        }
    } else {
        Write-Host ""
        Write-Host "❌ 编译失败！" -ForegroundColor Red
        Write-Host "请检查 xinghe-setup.iss 脚本是否正确。" -ForegroundColor Yellow
        exit 1
    }
} catch {
    Write-Host ""
    Write-Host "❌ 编译过程中发生错误: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "按任意键退出..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
