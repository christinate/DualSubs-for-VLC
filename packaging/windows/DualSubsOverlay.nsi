Unicode true
ManifestDPIAware true
SetCompressor /SOLID lzma
CRCCheck on

!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "FileFunc.nsh"
!include "x64.nsh"

!include "build\installer-config.nsh"

Name "DualSubs for VLC ${VLC_VERSION}"
OutFile "${INSTALLER_OUTPUT}"
InstallDir "$PROGRAMFILES64\VideoLAN\VLC"
RequestExecutionLevel admin
BrandingText "DualSubs for VLC"
ShowInstDetails show
ShowUninstDetails show
XPStyle on

Icon "${BRANDING_ICON}"
UninstallIcon "${BRANDING_ICON}"

!define MUI_ABORTWARNING
!define MUI_ICON "${BRANDING_ICON}"
!define MUI_UNICON "${BRANDING_ICON}"

!insertmacro MUI_PAGE_WELCOME
!define MUI_PAGE_CUSTOMFUNCTION_LEAVE DualSubsDirectoryLeave
!insertmacro MUI_PAGE_DIRECTORY
!undef MUI_PAGE_CUSTOMFUNCTION_LEAVE
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_UNPAGE_FINISH

!insertmacro MUI_LANGUAGE "English"

!define UNINSTALL_REG_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\DualSubs for VLC"

Var PowerShellPath
Var InstallExitCode
Var VlcInstallDir
Var DetectedVlcDir
Var InstallErrorText

Function FindDetectedVlcDir
  StrCpy $DetectedVlcDir ""

  ReadRegStr $0 HKLM "SOFTWARE\VideoLAN\VLC" "InstallDir"
  ${If} $0 == ""
    ReadRegStr $0 HKLM "SOFTWARE\WOW6432Node\VideoLAN\VLC" "InstallDir"
  ${EndIf}
  ${If} $0 == ""
    ReadRegStr $0 HKCU "SOFTWARE\VideoLAN\VLC" "InstallDir"
  ${EndIf}

  ${If} $0 != ""
    IfFileExists "$0\vlc.exe" 0 +2
      StrCpy $DetectedVlcDir $0
  ${EndIf}

  ${If} $DetectedVlcDir == ""
    IfFileExists "$PROGRAMFILES64\VideoLAN\VLC\vlc.exe" 0 +2
      StrCpy $DetectedVlcDir "$PROGRAMFILES64\VideoLAN\VLC"
  ${EndIf}

  ${If} $DetectedVlcDir == ""
    IfFileExists "$PROGRAMFILES32\VideoLAN\VLC\vlc.exe" 0 +2
      StrCpy $DetectedVlcDir "$PROGRAMFILES32\VideoLAN\VLC"
  ${EndIf}
FunctionEnd

Function .onInit
  SetShellVarContext all

  ${If} ${RunningX64}
    SetRegView 64
  ${Else}
    SetRegView 32
  ${EndIf}

  StrCpy $PowerShellPath "$SYSDIR\WindowsPowerShell\v1.0\powershell.exe"
  StrCpy $INSTDIR "$PROGRAMFILES64\VideoLAN\VLC"
  Call FindDetectedVlcDir
  ${If} $DetectedVlcDir != ""
    StrCpy $INSTDIR $DetectedVlcDir
  ${EndIf}
FunctionEnd

Function ValidateSelectedVlcDir
  IfFileExists "$INSTDIR\vlc.exe" 0 +2
    Return

  Call FindDetectedVlcDir
  ${If} $DetectedVlcDir != ""
    MessageBox MB_ICONEXCLAMATION|MB_OK "The selected folder does not contain vlc.exe.$\r$\n$\r$\nDualSubs found VLC at:$\r$\n$DetectedVlcDir$\r$\n$\r$\nThe installer will use that folder instead."
    StrCpy $INSTDIR $DetectedVlcDir
    Return
  ${EndIf}

  MessageBox MB_ICONEXCLAMATION|MB_YESNO "VLC was not found.$\r$\n$\r$\nClick Yes to exit and install VLC first.$\r$\nClick No if you already have VLC in a custom folder and want to browse to the folder that contains vlc.exe." IDYES exitInstaller
  Abort

exitInstaller:
  Quit
FunctionEnd

Function DualSubsDirectoryLeave
  Call ValidateSelectedVlcDir
FunctionEnd

Function LoadInstallErrorText
  StrCpy $InstallErrorText ""
  IfFileExists "$PLUGINSDIR\Install-DualSubs-error.txt" 0 done
  ClearErrors
  FileOpen $0 "$PLUGINSDIR\Install-DualSubs-error.txt" r
  IfErrors done
  FileRead $0 $InstallErrorText
  FileClose $0
done:
FunctionEnd

Section "DualSubs Overlay" SecInstall
  Call ValidateSelectedVlcDir

  SetOutPath "$PLUGINSDIR"
  File "/oname=DualSubs-Payload.zip" "${STAGE_ROOT}\DualSubs-Payload.zip"
  File "/oname=payload-manifest.json" "${STAGE_ROOT}\payload-manifest.json"
  File "/oname=Install-DualSubs.ps1" "${STAGE_ROOT}\Install-DualSubs.ps1"
  File "/oname=Install DualSubs.cmd" "${STAGE_ROOT}\Install DualSubs.cmd"
  File "/oname=Uninstall-DualSubs.ps1" "${STAGE_ROOT}\Uninstall-DualSubs.ps1"
  File "/oname=Uninstall DualSubs.cmd" "${STAGE_ROOT}\Uninstall DualSubs.cmd"
  File "/oname=dualsubs-icon.ico" "${BRANDING_ICON}"

  Delete "$PLUGINSDIR\Install-DualSubs-error.txt"
  DetailPrint "Validating VLC install state at $INSTDIR"
  nsExec::ExecToStack '"$PowerShellPath" -NoProfile -ExecutionPolicy Bypass -File "$PLUGINSDIR\Install-DualSubs.ps1" -InstallDir "$INSTDIR" -PayloadZip "$PLUGINSDIR\DualSubs-Payload.zip" -PayloadManifestPath "$PLUGINSDIR\payload-manifest.json" -SkipRegistry -SkipCacheRefresh -PreflightOnly -Quiet'
  Pop $InstallExitCode
  Pop $0
  ${If} $InstallExitCode != 0
    ${If} $0 == ""
      Call LoadInstallErrorText
      StrCpy $0 $InstallErrorText
    ${EndIf}
    ${If} $0 == ""
      StrCpy $0 "DualSubs validation failed with exit code $InstallExitCode."
    ${EndIf}
    MessageBox MB_ICONSTOP|MB_OK "$0"
    Abort
  ${EndIf}
  ${If} $0 != ""
    DetailPrint $0
  ${EndIf}

  Delete "$PLUGINSDIR\Install-DualSubs-error.txt"
  DetailPrint "Patching existing VLC install at $INSTDIR"
  nsExec::ExecToLog '"$PowerShellPath" -NoProfile -ExecutionPolicy Bypass -File "$PLUGINSDIR\Install-DualSubs.ps1" -InstallDir "$INSTDIR" -PayloadZip "$PLUGINSDIR\DualSubs-Payload.zip" -PayloadManifestPath "$PLUGINSDIR\payload-manifest.json" -SkipRegistry'
  Pop $InstallExitCode
  ${If} $InstallExitCode != 0
    Call LoadInstallErrorText
    ${If} $InstallErrorText == ""
      StrCpy $InstallErrorText "DualSubs installation failed with exit code $InstallExitCode."
    ${EndIf}
    MessageBox MB_ICONSTOP|MB_OK "$InstallErrorText"
    Abort
  ${EndIf}

  WriteUninstaller "$INSTDIR\Uninstall DualSubs.exe"

  WriteRegStr HKLM "${UNINSTALL_REG_KEY}" "DisplayName" "DualSubs for VLC"
  WriteRegStr HKLM "${UNINSTALL_REG_KEY}" "DisplayVersion" "${DUALSUBS_VERSION}"
  WriteRegStr HKLM "${UNINSTALL_REG_KEY}" "Publisher" "DualSubs Open Source Contributors"
  WriteRegStr HKLM "${UNINSTALL_REG_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "${UNINSTALL_REG_KEY}" "DisplayIcon" "$INSTDIR\Uninstall DualSubs.exe"
  WriteRegStr HKLM "${UNINSTALL_REG_KEY}" "UninstallString" '"$INSTDIR\Uninstall DualSubs.exe"'
  WriteRegStr HKLM "${UNINSTALL_REG_KEY}" "QuietUninstallString" '"$INSTDIR\Uninstall DualSubs.exe" /S'
  WriteRegDWORD HKLM "${UNINSTALL_REG_KEY}" "NoModify" 1
  WriteRegDWORD HKLM "${UNINSTALL_REG_KEY}" "NoRepair" 1
SectionEnd

Section "Uninstall"
  StrCpy $VlcInstallDir $INSTDIR
  IfFileExists "$VlcInstallDir\DualSubs\install-manifest.json" +3 0
    MessageBox MB_ICONEXCLAMATION|MB_YESNO "DualSubs state files were not found in $VlcInstallDir. Remove only the installer registration and uninstaller?" IDYES cleanup
    Abort

  DetailPrint "Restoring original VLC files in $VlcInstallDir"
  ExecWait '"$PowerShellPath" -NoProfile -ExecutionPolicy Bypass -File "$VlcInstallDir\DualSubs\Uninstall-DualSubs.ps1" -InstallDir "$VlcInstallDir" -SkipRegistry' $InstallExitCode
  ${If} $InstallExitCode != 0
    MessageBox MB_ICONSTOP|MB_OK "DualSubs uninstall failed with exit code $InstallExitCode."
    Abort
  ${EndIf}

cleanup:
  Delete "$VlcInstallDir\Uninstall DualSubs.exe"
  DeleteRegKey HKLM "${UNINSTALL_REG_KEY}"
SectionEnd
