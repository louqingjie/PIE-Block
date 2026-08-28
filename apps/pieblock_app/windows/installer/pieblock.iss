; PIE-Block Flutter 桌面版 Windows 安装包脚本
; 由 tools/package_flutter_windows.ps1 调用：
;   ISCC.exe /DAppVersion=x.y.z pieblock.iss
; 所有源路径均相对本文件所在目录，构建产物来自
; apps/pieblock_app/build/windows/x64/runner/Release（完整目录，含
; data/pieblock_runtime 下的内置 SDCC 工具链与固件模板）。

#ifndef AppVersion
#define AppVersion "1.0.0"
#endif

#ifndef OutputBaseName
#define OutputBaseName "PIEBlock-" + AppVersion + "-windows-setup"
#endif

#define MyAppName "PIE-Block"
#define MyAppExeName "PIE-Block.exe"

[Setup]
AppId={{7E1A4C5B-9D2F-4A6E-8B3C-1F0D2A9E5C74}
AppName={#MyAppName}
AppVersion={#AppVersion}
AppVerName={#MyAppName} {#AppVersion}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=..\..\..\..\output
OutputBaseFilename={#OutputBaseName}
SetupIconFile=..\runner\resources\app_icon.ico
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
MinVersion=10.0
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
RestartApplications=no
UninstallDisplayIcon={app}\{#MyAppExeName}

[Languages]
Name: "chinese"; MessagesFile: "ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; \
    GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; \
    DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; \
    Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; \
    Flags: nowait postinstall skipifsilent
