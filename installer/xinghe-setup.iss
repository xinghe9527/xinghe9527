; Xinghe 星河 - 专业安装脚本
; 使用 Inno Setup 创建 Windows 安装程序
; 隐藏 Flutter 框架和技术细节

#define MyAppName "星河"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Xinghe Studio"
#define MyAppExeName "xinghe.exe"
#define MyAppAssocName "Xinghe Project"
#define MyAppAssocExt ".xinghe"

[Setup]
; 应用基本信息
AppId={{A8F3D9E2-1B4C-4D7A-9F2E-5C8E6A3B7D1F}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
OutputDir=..\installer\output
OutputBaseFilename=xinghe-setup-{#MyAppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern

; 权限和兼容性
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=dialog
MinVersion=10.0.17763
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64

; 界面设置
DisableProgramGroupPage=yes
DisableWelcomePage=no
LicenseFile=..\LICENSE.txt
; InfoBeforeFile=..\README.txt

; 卸载设置
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加选项:"; Flags: unchecked
Name: "quicklaunchicon"; Description: "创建快速启动栏快捷方式"; GroupDescription: "附加选项:"; Flags: unchecked

[Files]
; 方案：所有文件放在同一目录（Flutter 要求），但通过快捷方式隐藏技术细节
; 用户只通过开始菜单/桌面快捷方式访问，不会直接看到文件夹

; 主程序
Source: "..\build\windows\x64\runner\Release\xinghe.exe"; DestDir: "{app}"; Flags: ignoreversion

; 运行时库（必须与 EXE 在同一目录）
Source: "..\build\windows\x64\runner\Release\flutter_windows.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\app_links_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\file_selector_windows_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\url_launcher_windows_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion

; FFmpeg（必须与 EXE 在同一目录，供程序调用）
Source: "..\build\windows\x64\runner\Release\ffmpeg.exe"; DestDir: "{app}"; Flags: ignoreversion

; 应用资源
Source: "..\build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; 开始菜单
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\卸载 {#MyAppName}"; Filename: "{uninstallexe}"

; 桌面快捷方式
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

; 快速启动栏
Name: "{userappdata}\Microsoft\Internet Explorer\Quick Launch\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: quicklaunchicon

[Run]
; 安装完成后启动应用
Filename: "{app}\{#MyAppExeName}"; Description: "启动 {#MyAppName}"; Flags: nowait postinstall skipifsilent

[Code]
// Windows API 声明
function SetFileAttributes(lpFileName: String; dwFileAttributes: DWORD): BOOL;
  external 'SetFileAttributesW@kernel32.dll stdcall';

function GetFileAttributes(lpFileName: String): DWORD;
  external 'GetFileAttributesW@kernel32.dll stdcall';

// 设置文件或文件夹为隐藏
procedure HideFileOrFolder(FileName: String);
var
  Attrs: DWORD;
begin
  Attrs := GetFileAttributes(FileName);
  if Attrs <> $FFFFFFFF then
  begin
    // 添加隐藏属性（$00000002），保留其他属性
    if SetFileAttributes(FileName, Attrs or $00000002) then
      Log('成功隐藏: ' + FileName)
    else
      Log('隐藏失败: ' + FileName);
  end
  else
    Log('获取文件属性失败: ' + FileName);
end;

// 安装完成后的处理
procedure CurStepChanged(CurStep: TSetupStep);
var
  AppPath: string;
begin
  if CurStep = ssPostInstall then
  begin
    AppPath := ExpandConstant('{app}');
    Log('开始隐藏技术文件...');
    
    // 隐藏所有 Flutter 和技术文件
    HideFileOrFolder(AppPath + '\flutter_windows.dll');
    HideFileOrFolder(AppPath + '\app_links_plugin.dll');
    HideFileOrFolder(AppPath + '\file_selector_windows_plugin.dll');
    HideFileOrFolder(AppPath + '\url_launcher_windows_plugin.dll');
    HideFileOrFolder(AppPath + '\ffmpeg.exe');
    HideFileOrFolder(AppPath + '\data');
    
    Log('文件隐藏完成！');
  end;
end;
