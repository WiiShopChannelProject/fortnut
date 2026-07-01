#Requires -RunAsAdministrator
<#
    BekoTweaks.ps1  -  Windows Tweak & Setup Utility
    Two tabs: Tweaks | App Installer
    Run:  powershell -ExecutionPolicy Bypass -File ".\BekoTweaks.ps1"
#>

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

# ===========================================================================
# Helpers
# ===========================================================================

function Set-RegistryValue {
    param([string]$Path,[string]$Name,[string]$Value,[string]$Type)
    try {
        if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
    } catch { Write-Output "  [FAIL] $Path -> $Name : $_" }
}

function Set-ServiceState {
    param([string]$Name,[string]$StartupType)
    try {
        if (Get-Service -Name $Name -ErrorAction SilentlyContinue) {
            Set-Service -Name $Name -StartupType $StartupType -ErrorAction Stop
        }
    } catch { Write-Output "  [FAIL] Service $Name : $_" }
}

function Remove-AppxApps {
    param([string[]]$Names)
    foreach ($n in $Names) {
        try {
            Get-AppxPackage -Name $n -AllUsers -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
            Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object DisplayName -like $n | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Out-Null
        } catch { Write-Output "  [FAIL] Appx $n : $_" }
    }
}

function Test-WingetAvailable { return [bool](Get-Command winget -ErrorAction SilentlyContinue) }

# ===========================================================================
# Tweak functions
# ===========================================================================

function Invoke-ActivityHistory {
    Set-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "EnableActivityFeed" "0" DWord
    Set-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "PublishUserActivities" "0" DWord
    Set-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "UploadUserActivities" "0" DWord
}

function Invoke-Hibernation {
    Set-RegistryValue "HKLM:\System\CurrentControlSet\Control\Session Manager\Power" "HibernateEnabled" "0" DWord
    Set-RegistryValue "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings" "ShowHibernateOption" "0" DWord
    try { powercfg.exe /hibernate off } catch {}
}

function Invoke-WidgetsRemove {
    try {
        Get-Process *Widget* -ErrorAction SilentlyContinue | Stop-Process -ErrorAction SilentlyContinue
        Get-AppxPackage Microsoft.WidgetsPlatformRuntime -AllUsers -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
        Get-AppxPackage MicrosoftWindows.Client.WebExperience -AllUsers -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    } catch { Write-Output "  [FAIL] Widgets: $_" }
}

function Invoke-RevertStartMenu {
    Set-RegistryValue "HKLM:\SYSTEM\ControlSet001\Control\FeatureManagement\Overrides\8\3036241548" "EnabledState" "1" DWord
}

function Invoke-DisableStoreSearch {
    try { icacls "$Env:LocalAppData\Packages\Microsoft.WindowsStore_8wekyb3d8bbwe\LocalState\store.db" /deny Everyone:F 2>$null }
    catch { Write-Output "  [FAIL] store.db: $_" }
}

function Invoke-LocationTracking {
    Set-ServiceState "lfsvc" Disabled
    Set-RegistryValue "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" "Value" "Deny" String
    Set-RegistryValue "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Sensor\Overrides\{BFA794E4-F964-4FDB-90F6-51056BFE4B44}" "SensorPermissionState" "0" DWord
    Set-RegistryValue "HKLM:\SYSTEM\Maps" "AutoUpdateEnabled" "0" DWord
}

function Invoke-ServicesToManual {
    Set-ServiceState "CscService" Disabled
    Set-ServiceState "DiagTrack" Disabled
    Set-ServiceState "MapsBroker" Manual
    Set-ServiceState "StorSvc" Manual
    Set-ServiceState "SharedAccess" Disabled
    try {
        $mem = (Get-CimInstance Win32_PhysicalMemory | Measure-Object Capacity -Sum).Sum / 1KB
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control" -Name SvcHostSplitThresholdInKB -Value $mem
    } catch {}
}

function Invoke-ConsumerFeatures {
    Set-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableWindowsConsumerFeatures" "1" DWord
}

function Invoke-Telemetry {
    Set-RegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" "Enabled" "0" DWord
    Set-RegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy" "TailoredExperiencesWithDiagnosticDataEnabled" "0" DWord
    Set-RegistryValue "HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy" "HasAccepted" "0" DWord
    Set-RegistryValue "HKCU:\Software\Microsoft\Input\TIPC" "Enabled" "0" DWord
    Set-RegistryValue "HKCU:\Software\Microsoft\InputPersonalization" "RestrictImplicitInkCollection" "1" DWord
    Set-RegistryValue "HKCU:\Software\Microsoft\InputPersonalization" "RestrictImplicitTextCollection" "1" DWord
    Set-RegistryValue "HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore" "HarvestContacts" "0" DWord
    Set-RegistryValue "HKCU:\Software\Microsoft\Personalization\Settings" "AcceptedPrivacyPolicy" "0" DWord
    Set-RegistryValue "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" "AllowTelemetry" "0" DWord
    Set-RegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "Start_TrackProgs" "0" DWord
    Set-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "PublishUserActivities" "0" DWord
    Set-RegistryValue "HKCU:\Software\Microsoft\Siuf\Rules" "NumberOfSIUFInPeriod" "0" DWord
    try {
        Set-MpPreference -SubmitSamplesConsent 2
        Set-Service -Name diagtrack -StartupType Disabled
        Set-Service -Name wermgr -StartupType Disabled
        [Environment]::SetEnvironmentVariable('POWERSHELL_TELEMETRY_OPTOUT','1','Machine')
        Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Siuf\Rules" -Name PeriodInNanoSeconds -ErrorAction SilentlyContinue
    } catch {}
}

function Invoke-DeliveryOptimization {
    Set-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" "DODownloadMode" "0" DWord
}

function Invoke-DisableBitLocker {
    try { Disable-BitLocker -MountPoint $Env:SystemDrive } catch { Write-Output "  [FAIL] BitLocker: $_" }
}

function Invoke-DeBloat {
    Remove-AppxApps @(
        "Microsoft.WindowsFeedbackHub","Microsoft.BingNews","Microsoft.BingSearch","Microsoft.BingWeather",
        "Clipchamp.Clipchamp","Microsoft.Todos","Microsoft.PowerAutomateDesktop","Microsoft.MicrosoftSolitaireCollection",
        "Microsoft.WindowsSoundRecorder","Microsoft.MicrosoftStickyNotes","Microsoft.WindowsDevHome","Microsoft.Paint",
        "Microsoft.OutlookForWindows","Microsoft.WindowsAlarms","Microsoft.StartExperiencesApp","Microsoft.GetHelp",
        "Microsoft.ZuneMusic","MicrosoftCorporationII.QuickAssist","MSTeams"
    )
    try {
        $tp = "$Env:LocalAppData\Microsoft\Teams\Update.exe"
        if (Test-Path $tp) { Start-Process $tp -ArgumentList -uninstall -Wait; Remove-Item $tp -Recurse -Force }
    } catch {}
}

function Invoke-WPBT {
    Set-RegistryValue "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" "DisableWpbtExecution" "1" DWord
}

function Invoke-DiskCleanup {
    try { cleanmgr.exe /d C: /VERYLOWDISK; Dism.exe /online /Cleanup-Image /StartComponentCleanup /ResetBase } catch {}
}

function Invoke-DeleteTempFiles {
    Remove-Item -Path "$Env:Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$Env:SystemRoot\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
}

function Invoke-DisableExplorerAutoDiscovery {
    try {
        $bags   = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags"
        $bagMRU = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\BagMRU"
        Remove-Item $bags   -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $bagMRU -Recurse -Force -ErrorAction SilentlyContinue
        $af = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders\Shell"
        if (!(Test-Path $af)) { New-Item $af -Force | Out-Null }
        New-ItemProperty $af -Name FolderType -Value NotSpecified -PropertyType String -Force | Out-Null
    } catch {}
}

function Invoke-RestorePoint {
    Set-RegistryValue "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" "SystemRestorePointCreationFrequency" "0" DWord
    try {
        if (-not (Get-ComputerRestorePoint)) { Enable-ComputerRestore -Drive $Env:SystemDrive }
        Checkpoint-Computer -Description "Beko Tweaks Restore Point" -RestorePointType MODIFY_SETTINGS
    } catch {}
}

function Invoke-EndTaskOnTaskbar {
    Set-RegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings" "TaskbarEndTask" "1" DWord
}

function Invoke-BraveDebloat {
    $p = "HKLM:\SOFTWARE\Policies\BraveSoftware\Brave"
    Set-RegistryValue $p "BraveRewardsDisabled" "1" DWord
    Set-RegistryValue $p "BraveWalletDisabled" "1" DWord
    Set-RegistryValue $p "BraveVPNDisabled" "1" DWord
    Set-RegistryValue $p "BraveAIChatEnabled" "0" DWord
    Set-RegistryValue $p "BraveStatsPingEnabled" "0" DWord
    Set-RegistryValue $p "BraveNewsDisabled" "1" DWord
    Set-RegistryValue $p "BraveTalkDisabled" "1" DWord
    Set-RegistryValue $p "TorDisabled" "1" DWord
    Set-RegistryValue $p "BraveP3AEnabled" "0" DWord
    Set-RegistryValue $p "UrlKeyedAnonymizedDataCollectionEnabled" "0" DWord
    Set-RegistryValue $p "SafeBrowsingExtendedReportingEnabled" "0" DWord
    Set-RegistryValue $p "MetricsReportingEnabled" "0" DWord
}

function Invoke-DisableWarningForUnsignedRdp {
    Set-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services\Client" "RedirectionWarningDialogVersion" "1" DWord
    Set-RegistryValue "HKCU:\SOFTWARE\Microsoft\Terminal Server Client" "RdpLaunchConsentAccepted" "1" DWord
}

function Invoke-EdgeDebloat {
    $p = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
    Set-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate" "CreateDesktopShortcutDefault" "0" DWord
    Set-RegistryValue $p "PersonalizationReportingEnabled" "0" DWord
    Set-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Edge\ExtensionInstallBlocklist" "1" "ofefcgjbeghpigppfmkologfjadafddi" String
    Set-RegistryValue $p "ShowRecommendationsEnabled" "0" DWord
    Set-RegistryValue $p "HideFirstRunExperience" "1" DWord
    Set-RegistryValue $p "UserFeedbackAllowed" "0" DWord
    Set-RegistryValue $p "ConfigureDoNotTrack" "1" DWord
    Set-RegistryValue $p "AlternateErrorPagesEnabled" "0" DWord
    Set-RegistryValue $p "EdgeCollectionsEnabled" "0" DWord
    Set-RegistryValue $p "EdgeShoppingAssistantEnabled" "0" DWord
    Set-RegistryValue $p "MicrosoftEdgeInsiderPromotionEnabled" "0" DWord
    Set-RegistryValue $p "ShowMicrosoftRewards" "0" DWord
    Set-RegistryValue $p "WebWidgetAllowed" "0" DWord
    Set-RegistryValue $p "DiagnosticData" "0" DWord
    Set-RegistryValue $p "EdgeAssetDeliveryServiceEnabled" "0" DWord
    Set-RegistryValue $p "WalletDonationEnabled" "0" DWord
    Set-RegistryValue $p "DefaultBrowserSettingsCampaignEnabled" "0" DWord
}

function Invoke-RemoveEdge {
    try {
        Get-Process -Name "msedge","MicrosoftEdgeUpdate","msedgewebview2","msedgewebview","MicrosoftEdge" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2

        Get-ScheduledTask -TaskName "MicrosoftEdgeUpdateTask*" -ErrorAction SilentlyContinue | Disable-ScheduledTask -ErrorAction SilentlyContinue
        Get-ScheduledTask -TaskName "MicrosoftEdgeUpdateTask*" -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue
        Set-Service -Name "edgeupdate"  -StartupType Disabled -ErrorAction SilentlyContinue
        Set-Service -Name "edgeupdatem" -StartupType Disabled -ErrorAction SilentlyContinue
        Stop-Service -Name "edgeupdate"  -Force -ErrorAction SilentlyContinue
        Stop-Service -Name "edgeupdatem" -Force -ErrorAction SilentlyContinue

        $edgePaths = @(
            "${Env:ProgramFiles(x86)}\Microsoft\Edge",
            "${Env:ProgramFiles(x86)}\Microsoft\EdgeUpdate",
            "${Env:ProgramFiles(x86)}\Microsoft\EdgeCore",
            "${Env:ProgramFiles(x86)}\Microsoft\EdgeWebView",
            "$Env:ProgramFiles\Microsoft\Edge",
            "$Env:ProgramFiles\Microsoft\EdgeUpdate"
        )

        foreach ($path in $edgePaths) {
            if (Test-Path $path) {
                Write-Output "  Taking ownership of $path ..."
                & takeown /F "$path" /R /A /D Y 2>$null
                & icacls "$path" /grant ($Env:USERNAME + ":(OI)(CI)F") /T /C /Q 2>$null
            }
        }

        foreach ($path in $edgePaths) {
            if (Test-Path $path) {
                Write-Output "  Deleting $path ..."
                Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        $Sid = (New-Object System.Security.Principal.NTAccount($Env:USERNAME)).Translate([System.Security.Principal.SecurityIdentifier]).Value
        $appxStore = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore"

        Get-AppxPackage -AllUsers | Where-Object { $_.PackageFullName -like "*microsoftedge*" } | ForEach-Object {
            $pkg = $_.PackageFullName
            Write-Output "  Marking AppX EndOfLife: $pkg"
            New-Item -Path "$appxStore\EndOfLife\$Sid\$pkg"     -Force -ErrorAction SilentlyContinue | Out-Null
            New-Item -Path "$appxStore\EndOfLife\S-1-5-18\$pkg" -Force -ErrorAction SilentlyContinue | Out-Null
            New-Item -Path "$appxStore\Deprovisioned\$pkg"       -Force -ErrorAction SilentlyContinue | Out-Null
            Remove-AppxPackage -Package $pkg -AllUsers -ErrorAction SilentlyContinue
        }

        @(
            "HKLM:\SOFTWARE\Microsoft\EdgeUpdate",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate",
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge",
            "HKCU:\SOFTWARE\Microsoft\Edge",
            "HKCU:\SOFTWARE\WOW6432Node\Microsoft\Edge"
        ) | ForEach-Object {
            if (Test-Path $_) { Remove-Item $_ -Recurse -Force -ErrorAction SilentlyContinue }
        }

        Set-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate" "DoNotUpdateToEdgeWithChromium" "1" DWord
        Set-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate" "UpdateDefault" "0" DWord
        Set-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate" "InstallDefault" "0" DWord

        Remove-Item "$Env:PUBLIC\Desktop\Microsoft Edge.lnk" -Force -ErrorAction SilentlyContinue
        Remove-Item "$Env:UserProfile\Desktop\Microsoft Edge.lnk" -Force -ErrorAction SilentlyContinue
        Remove-Item "$Env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\Microsoft Edge.lnk" -Force -ErrorAction SilentlyContinue

        Write-Output "  [OK] Edge removed via ownership takeover. Restart recommended."
    } catch { Write-Output "  [FAIL] Edge removal: $_" }
}

function Invoke-UTC {
    Set-RegistryValue "HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation" "RealTimeIsUniversal" "1" QWord
}

function Invoke-RemoveOneDrive {
    try {
        $od = $Env:OneDrive
        Start-Process icacls -ArgumentList ("`"$od`" /deny `"Administrators:(D,DC)`"") -Wait -WindowStyle Hidden
        Start-Process 'C:\Windows\System32\OneDriveSetup.exe' -ArgumentList '/uninstall' -Wait
        Stop-Process -Name FileCoAuth,Explorer -ErrorAction SilentlyContinue
        Remove-Item "$Env:LocalAppData\Microsoft\OneDrive" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item "C:\ProgramData\Microsoft OneDrive" -Recurse -Force -ErrorAction SilentlyContinue
        Start-Process icacls -ArgumentList ("`"$od`" /grant `"Administrators:(D,DC)`"") -Wait -WindowStyle Hidden
        if (-not (Get-ChildItem -Path $od -ErrorAction SilentlyContinue)) {
            Remove-Item -Path $od -Recurse -ErrorAction SilentlyContinue
            [Environment]::SetEnvironmentVariable('OneDrive',$null,'User')
        }
        Set-Service -Name OneSyncSvc -StartupType Disabled -ErrorAction SilentlyContinue
    } catch { Write-Output "  [FAIL] OneDrive: $_" }
}

function Invoke-RemoveHomeAndGallery {
    Set-RegistryValue "HKCU:\Software\Classes\CLSID\{f874310e-b6b7-47dc-bc84-b9e6b38f5903}" "System.IsPinnedToNameSpaceTree" "0" DWord
    Set-RegistryValue "HKCU:\Software\Classes\CLSID\{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}" "System.IsPinnedToNameSpaceTree" "0" DWord
    Set-RegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "LaunchTo" "1" DWord
}

function Invoke-DisplayBestPerformance {
    Set-RegistryValue "HKCU:\Control Panel\Desktop" "DragFullWindows" "0" String
    Set-RegistryValue "HKCU:\Control Panel\Desktop" "MenuShowDelay" "200" String
    Set-RegistryValue "HKCU:\Control Panel\Desktop\WindowMetrics" "MinAnimate" "0" String
    Set-RegistryValue "HKCU:\Control Panel\Keyboard" "KeyboardDelay" "0" DWord
    Set-RegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ListviewAlphaSelect" "0" DWord
    Set-RegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ListviewShadow" "0" DWord
    Set-RegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarAnimations" "0" DWord
    Set-RegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" "VisualFXSetting" "3" DWord
    Set-RegistryValue "HKCU:\Software\Microsoft\Windows\DWM" "EnableAeroPeek" "0" DWord
    Set-RegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarMn" "0" DWord
    Set-RegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowTaskViewButton" "0" DWord
    Set-RegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" "SearchboxTaskbarMode" "0" DWord
    try { Set-ItemProperty "HKCU:\Control Panel\Desktop" "UserPreferencesMask" -Type Binary -Value ([byte[]](144,18,3,128,16,0,0,0)) } catch {}
}

function Invoke-XboxRemoval {
    Set-RegistryValue "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR" "AppCaptureEnabled" "0" DWord
    Remove-AppxApps @("Microsoft.XboxIdentityProvider","Microsoft.XboxSpeechToTextOverlay","Microsoft.GamingApp","Microsoft.Xbox.TCUI","Microsoft.XboxGamingOverlay")
}

function Invoke-ReservedStorage {
    try { DISM /Online /Set-ReservedStorageState /State:Disabled } catch {}
}

function Invoke-StorageSenseDisable {
    Set-RegistryValue "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy" "01" "0" DWord
}

function Invoke-WindowsAIRemove {
    Set-RegistryValue "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" "SettingsPageVisibility" "hide:aicomponents" String
    Set-RegistryValue "HKLM:\SOFTWARE\Policies\WindowsNotepad" "DisableAIFeatures" "1" DWord
    try {
        $appx = (Get-AppxPackage MicrosoftWindows.Client.CoreAI -ErrorAction SilentlyContinue).PackageFullName
        $sid  = (Get-LocalUser $Env:UserName).Sid.Value
        if ($appx) { New-Item "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\EndOfLife\$sid\$appx" -Force | Out-Null }
        Get-AppxPackage -AllUsers "*Copilot*" -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
        Get-AppxPackage -AllUsers Microsoft.MicrosoftOfficeHub -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
        if ($appx) { Remove-AppxPackage $appx -ErrorAction SilentlyContinue }
        Set-Service -Name WSAIFabricSvc -StartupType Disabled -ErrorAction SilentlyContinue
        Disable-WindowsOptionalFeature -FeatureName Recall -Online -NoRestart -ErrorAction SilentlyContinue
    } catch {}
}

function Invoke-RazerBlock {
    Set-RegistryValue "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching" "SearchOrderConfig" "0" DWord
    Set-RegistryValue "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Installer" "DisableCoInstallers" "1" DWord
    try {
        $rp = "C:\Windows\Installer\Razer"
        if (Test-Path $rp) { Remove-Item "$rp\*" -Recurse -Force } else { New-Item $rp -ItemType Directory | Out-Null }
        & icacls "$rp" /deny "Everyone:(W)" 2>$null
    } catch {}
}

function Invoke-DisableNotifications {
    Set-RegistryValue "HKCU:\Software\Policies\Microsoft\Windows\Explorer" "DisableNotificationCenter" "1" DWord
    Set-RegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications" "ToastEnabled" "0" DWord
}

function Invoke-BlockAdobeNet {
    try {
        $h = Invoke-RestMethod -Uri "https://github.com/Ruddernation-Designs/Adobe-URL-Block-List/raw/refs/heads/master/hosts"
        Add-Content -Path "$Env:SystemRoot\System32\drivers\etc\hosts" -Value $h
        ipconfig /flushdns
    } catch {}
}

function Invoke-RightClickMenuLegacy {
    try {
        New-Item -Path "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}" -Name InprocServer32 -Value "" -Force | Out-Null
        Stop-Process -Name explorer -ErrorAction SilentlyContinue
    } catch {}
}

function Invoke-IPv4Preferred {
    Set-RegistryValue "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters" "DisabledComponents" "32" DWord
}

function Invoke-TeredoDisable {
    Set-RegistryValue "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters" "DisabledComponents" "1" DWord
    try { netsh interface teredo set state disabled } catch {}
}

function Invoke-DisableIPv6 {
    Set-RegistryValue "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters" "DisabledComponents" "255" DWord
    try { Disable-NetAdapterBinding -Name * -ComponentID ms_tcpip6 } catch {}
}

function Invoke-DisableBackgroundApps {
    Set-RegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" "GlobalUserDisabled" "1" DWord
}

function Invoke-DisableFSO {
    Set-RegistryValue "HKCU:\System\GameConfigStore" "GameDVR_DXGIHonorFSEWindowsCompatible" "1" DWord
}

function Invoke-OOShutUp {
    try {
        $d = "$Env:Temp\OOSU10.exe"
        Invoke-WebRequest -Uri "https://dl5.oo-software.com/files/ooshutup10/OOSU10.exe" -OutFile $d -UseBasicParsing
        Start-Process $d
    } catch { Write-Output "  [FAIL] O`&O ShutUp10++: $_" }
}

function Invoke-UltimatePerformance {
    try { powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 } catch {}
}

function Invoke-RemoveUltimatePerformance {
    try {
        $guids = powercfg -list | Select-String "Ultimate Performance" | ForEach-Object { ($_ -split "\s+")[3] }
        if ($guids) { $guids | ForEach-Object { powercfg -delete $_ } }
    } catch {}
}

function Invoke-SetDNS {
    param([string]$Provider)
    $map = @{
        "Google"                            = @("8.8.8.8","8.8.4.4")
        "Cloudflare"                         = @("1.1.1.1","1.0.0.1")
        "Cloudflare_Malware"                 = @("1.1.1.2","1.0.0.2")
        "Cloudflare_Malware_Adult"           = @("1.1.1.3","1.0.0.3")
        "Open_DNS"                           = @("208.67.222.222","208.67.220.220")
        "Quad9"                              = @("9.9.9.9","149.112.112.112")
        "AdGuard_Ads_Trackers"               = @("94.140.14.14","94.140.15.15")
        "AdGuard_Ads_Trackers_Malware_Adult" = @("94.140.14.15","94.140.15.16")
    }
    try {
        $adapters = Get-DnsClient | Where-Object { $_.InterfaceAlias -notmatch "Loopback" }
        if ($Provider -eq "DHCP") {
            $adapters | ForEach-Object { Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ResetServerAddresses }
        } elseif ($map.ContainsKey($Provider)) {
            $adapters | ForEach-Object { Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ServerAddresses $map[$Provider] }
        }
    } catch {}
}

function Invoke-DetailedBSoD {
    Set-RegistryValue "HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl" "DisplayParameters" "1" DWord
    Set-RegistryValue "HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl" "DisableEmoticon" "1" DWord
}
function Invoke-BatteryPercentage {
    Set-RegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "IsBatteryPercentageEnabled" "1" DWord
}
function Invoke-DarkMode {
    Set-RegistryValue "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" "AppsUseLightTheme" "0" DWord
    Set-RegistryValue "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" "SystemUsesLightTheme" "0" DWord
}
function Invoke-ShowFileExtensions {
    Set-RegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "HideFileExt" "0" DWord
}
function Invoke-ShowHiddenFiles {
    Set-RegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "Hidden" "1" DWord
}
function Invoke-VerboseLogon {
    Set-RegistryValue "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" "VerboseStatus" "1" DWord
}
function Invoke-NewOutlookToggle {
    Set-RegistryValue "HKCU:\SOFTWARE\Microsoft\Office\16.0\Outlook\Preferences" "UseNewOutlook" "1" DWord
    Set-RegistryValue "HKCU:\Software\Microsoft\Office\16.0\Outlook\Options\General" "HideNewOutlookToggle" "0" DWord
    Set-RegistryValue "HKCU:\Software\Policies\Microsoft\Office\16.0\Outlook\Options\General" "DoNewOutlookAutoMigration" "0" DWord
    Set-RegistryValue "HKCU:\Software\Policies\Microsoft\Office\16.0\Outlook\Preferences" "NewOutlookMigrationUserSetting" "0" DWord
}
function Invoke-ScrollbarsAlwaysVisible {
    Set-RegistryValue "HKCU:\Control Panel\Accessibility" "DynamicScrollbars" "0" DWord
}
function Invoke-MultiplaneOverlay {
    Set-RegistryValue "HKLM:\SOFTWARE\Microsoft\Windows\Dwm" "OverlayTestMode" "0" DWord
    Set-RegistryValue "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "DisableOverlays" "1" DWord
}
function Invoke-MouseAcceleration {
    Set-RegistryValue "HKCU:\Control Panel\Mouse" "MouseSpeed" "1" DWord
    Set-RegistryValue "HKCU:\Control Panel\Mouse" "MouseThreshold1" "6" DWord
    Set-RegistryValue "HKCU:\Control Panel\Mouse" "MouseThreshold2" "10" DWord
}
function Invoke-NumLockOnStartup {
    Set-RegistryValue "HKU:\.Default\Control Panel\Keyboard" "InitialKeyboardIndicators" "2" String
    Set-RegistryValue "HKCU:\Control Panel\Keyboard" "InitialKeyboardIndicators" "2" String
}
function Invoke-StandbyFix {
    Set-RegistryValue "HKCU:\SOFTWARE\Policies\Microsoft\Power\PowerSettings\f15576e8-98b7-4186-b944-eafa664402d9" "ACSettingIndex" "1" DWord
}
function Invoke-S3Sleep {
    Set-RegistryValue "HKLM:\SYSTEM\CurrentControlSet\Control\Power" "PlatformAoAcOverride" "0" DWord
}
function Invoke-HideSettingsHome {
    Set-RegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" "SettingsPageVisibility" "show:home" String
}
function Invoke-BingSearchToggle {
    Set-RegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" "BingSearchEnabled" "1" DWord
}
function Invoke-LoginScreenBlur {
    Set-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "DisableAcrylicBackgroundOnLogon" "0" DWord
}
function Invoke-DisableLockscreen {
    Set-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" "NoLockScreen" "1" DWord
}
function Invoke-StartMenuRecommendations {
    Set-RegistryValue "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Start" "HideRecommendedSection" "0" DWord
    Set-RegistryValue "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Education" "IsEducationEnvironment" "0" DWord
    Set-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" "HideRecommendedSection" "0" DWord
}
function Invoke-StickyKeysToggle {
    Set-RegistryValue "HKCU:\Control Panel\Accessibility\StickyKeys" "Flags" "506" DWord
}
function Invoke-TaskbarCentered {
    Set-RegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarAl" "1" DWord
}
function Invoke-TaskbarSearchIcon {
    Set-RegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" "SearchboxTaskbarMode" "1" DWord
}
function Invoke-TaskViewButton {
    Set-RegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowTaskViewButton" "1" DWord
}
function Invoke-GameModeToggle {
    Set-RegistryValue "HKCU:\Software\Microsoft\GameBar" "AllowAutoGameMode" "1" DWord
    Set-RegistryValue "HKCU:\Software\Microsoft\GameBar" "AutoGameModeEnabled" "1" DWord
}
function Invoke-LongPathsToggle {
    Set-RegistryValue "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" "LongPathsEnabled" "1" DWord
}

# ===========================================================================
# Debloat and Cleanup functions
# ===========================================================================

function Invoke-DeletePrefetch {
    try { Remove-Item -Path "$Env:SystemRoot\Prefetch\*" -Recurse -Force -ErrorAction SilentlyContinue } catch {}
}

function Invoke-EmptyRecycleBin {
    try { Clear-RecycleBin -Force -ErrorAction SilentlyContinue } catch {}
}

function Invoke-ClearWindowsUpdateCache {
    try {
        Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "$Env:SystemRoot\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue
        Start-Service -Name wuauserv -ErrorAction SilentlyContinue
    } catch {}
}

function Invoke-ClearEventLogs {
    try { wevtutil el | ForEach-Object { wevtutil cl "$_" 2>$null } } catch {}
}

# ===========================================================================
# CPU Tweak functions
# ===========================================================================

function Invoke-DisableCoreParking {
    try {
        powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 0cc5b647-c1df-4637-891a-dec35c318583 100
        powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 0cc5b647-c1df-4637-891a-dec35c318583 100
        powercfg /setactive SCHEME_CURRENT
    } catch { Write-Output "  [FAIL] Core parking: $_" }
}

function Invoke-SetMinMaxProcessorState {
    try {
        powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 100
        powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 100
        powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100
        powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100
        powercfg /setactive SCHEME_CURRENT
    } catch { Write-Output "  [FAIL] Min/Max processor state: $_" }
}

function Invoke-SetEnergyPerformancePreference {
    try {
        powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFEPP 0
        powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFEPP 0
        powercfg /setactive SCHEME_CURRENT
    } catch { Write-Output "  [FAIL] Energy performance preference: $_" }
}

function Invoke-DisableCpuPowerThrottling {
    Set-RegistryValue "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" "PowerThrottlingOff" "1" DWord
}

function Invoke-DisableModernStandby {
    Set-RegistryValue "HKLM:\SYSTEM\CurrentControlSet\Control\Power" "PlatformAoAcOverride" "0" DWord
}

# ===========================================================================
# GPU Tweak functions
# ===========================================================================

function Invoke-OptimizeNvidiaFrameScheduling {
    Set-RegistryValue "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "HwSchMode" "2" DWord
}

function Invoke-DisableHDCP {
    Set-RegistryValue "HKLM:\SOFTWARE\NVIDIA Corporation\Global\NVTweak" "EnableHDCP" "0" DWord
    Set-RegistryValue "HKLM:\SOFTWARE\WOW6432Node\NVIDIA Corporation\Global\NVTweak" "EnableHDCP" "0" DWord
}

# ===========================================================================
# Memory Tweak functions
# ===========================================================================

function Invoke-DisableMemoryCompression {
    try { Disable-MMAgent -mc -ErrorAction SilentlyContinue } catch { Write-Output "  [FAIL] Memory compression: $_" }
}

function Invoke-DisablePrefetcher {
    Set-RegistryValue "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" "EnablePrefetcher" "0" DWord
    Set-RegistryValue "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" "EnableSuperfetch" "0" DWord
}

function Invoke-DisableRamDiagnostics {
    try {
        Get-ScheduledTask -TaskName "MemoryDiagnostic" -ErrorAction SilentlyContinue | Disable-ScheduledTask -ErrorAction SilentlyContinue
        Get-ScheduledTask -TaskPath "\Microsoft\Windows\MemoryDiagnostic\" -ErrorAction SilentlyContinue | Disable-ScheduledTask -ErrorAction SilentlyContinue
    } catch {}
}

# ===========================================================================
# Tweak metadata
# ===========================================================================

$Tweaks = @(
    @{ Id="ActivityHistory";       Name="Activity History - Disable";                        Category="Essential Tweaks";          Action={Invoke-ActivityHistory} }
    @{ Id="Hiber";                 Name="Hibernation - Disable";                              Category="Essential Tweaks";          Action={Invoke-Hibernation} }
    @{ Id="Widget";                Name="Widgets - Remove";                                   Category="Essential Tweaks";          Action={Invoke-WidgetsRemove} }
    @{ Id="RevertStartMenu";       Name="Start Menu Previous Layout - Enable";                Category="Essential Tweaks";          Action={Invoke-RevertStartMenu} }
    @{ Id="DisableStoreSearch";    Name="MS Store Recommended Search Results - Disable";      Category="Essential Tweaks";          Action={Invoke-DisableStoreSearch} }
    @{ Id="Location";              Name="Location Tracking - Disable";                        Category="Essential Tweaks";          Action={Invoke-LocationTracking} }
    @{ Id="Services";              Name="Services - Set to Manual";                           Category="Essential Tweaks";          Action={Invoke-ServicesToManual} }
    @{ Id="ConsumerFeatures";      Name="ConsumerFeatures - Disable";                          Category="Essential Tweaks";          Action={Invoke-ConsumerFeatures} }
    @{ Id="Telemetry";             Name="Telemetry - Disable";                                Category="Essential Tweaks";          Action={Invoke-Telemetry} }
    @{ Id="DeliveryOptimization";  Name="Delivery Optimization - Disable";                    Category="Essential Tweaks";          Action={Invoke-DeliveryOptimization} }
    @{ Id="DisableBitLocker";      Name="BitLocker - Disable";                                Category="Essential Tweaks";          Action={Invoke-DisableBitLocker} }
    @{ Id="DeBloat";               Name="Unwanted Pre-Installed Apps - Remove";               Category="Essential Tweaks";          Action={Invoke-DeBloat} }
    @{ Id="WPBT";                  Name="Windows Platform Binary Table - Disable";            Category="Essential Tweaks";          Action={Invoke-WPBT} }
    @{ Id="DiskCleanup";           Name="Disk Cleanup - Run";                                 Category="Essential Tweaks";          Action={Invoke-DiskCleanup} }
    @{ Id="DeleteTempFiles";       Name="Temporary Files - Remove";                           Category="Essential Tweaks";          Action={Invoke-DeleteTempFiles} }
    @{ Id="ExplorerAutoDiscovery"; Name="File Explorer Auto Folder Discovery - Disable";      Category="Essential Tweaks";          Action={Invoke-DisableExplorerAutoDiscovery} }
    @{ Id="RestorePoint";          Name="Restore Point - Create";                             Category="Essential Tweaks";          Action={Invoke-RestorePoint} }
    @{ Id="EndTaskOnTaskbar";      Name="End Task With Right Click - Enable";                 Category="Essential Tweaks";          Action={Invoke-EndTaskOnTaskbar} }

    @{ Id="BraveDebloat";          Name="Brave Browser - Debloat";                            Category="Advanced Tweaks - CAUTION"; Action={Invoke-BraveDebloat} }
    @{ Id="DisableRdpWarning";     Name="RDP Unsigned File Warnings - Disable";               Category="Advanced Tweaks - CAUTION"; Action={Invoke-DisableWarningForUnsignedRdp} }
    @{ Id="EdgeDebloat";           Name="Microsoft Edge - Debloat";                           Category="Advanced Tweaks - CAUTION"; Action={Invoke-EdgeDebloat} }
    @{ Id="RemoveEdge";            Name="Microsoft Edge - Remove";                            Category="Advanced Tweaks - CAUTION"; Action={Invoke-RemoveEdge} }
    @{ Id="UTC";                   Name="Date and Time - Set to UTC";                         Category="Advanced Tweaks - CAUTION"; Action={Invoke-UTC} }
    @{ Id="RemoveOneDrive";        Name="Microsoft OneDrive - Remove";                        Category="Advanced Tweaks - CAUTION"; Action={Invoke-RemoveOneDrive} }
    @{ Id="RemoveHomeGallery";     Name="File Explorer Home and Gallery - Disable";           Category="Advanced Tweaks - CAUTION"; Action={Invoke-RemoveHomeAndGallery} }
    @{ Id="DisplayPerf";           Name="Visual Effects - Best Performance";                  Category="Advanced Tweaks - CAUTION"; Action={Invoke-DisplayBestPerformance} }
    @{ Id="XboxRemoval";           Name="Xbox and Gaming Components - Remove";                Category="Advanced Tweaks - CAUTION"; Action={Invoke-XboxRemoval} }
    @{ Id="ReservedStorage";       Name="Disable Reserved Storage";                           Category="Advanced Tweaks - CAUTION"; Action={Invoke-ReservedStorage} }
    @{ Id="StorageSense";          Name="Storage Sense - Disable";                            Category="Advanced Tweaks - CAUTION"; Action={Invoke-StorageSenseDisable} }
    @{ Id="WindowsAI";             Name="Windows AI - Disable and Remove";                    Category="Advanced Tweaks - CAUTION"; Action={Invoke-WindowsAIRemove} }
    @{ Id="RazerBlock";            Name="Razer Software Auto-Install - Disable";              Category="Advanced Tweaks - CAUTION"; Action={Invoke-RazerBlock} }
    @{ Id="DisableNotifications";  Name="System Tray Notifications and Calendar - Disable";   Category="Advanced Tweaks - CAUTION"; Action={Invoke-DisableNotifications} }
    @{ Id="BlockAdobeNet";         Name="Adobe URL Block List - Enable";                      Category="Advanced Tweaks - CAUTION"; Action={Invoke-BlockAdobeNet} }
    @{ Id="RightClickMenu";        Name="Right-Click Menu Previous Layout - Enable";          Category="Advanced Tweaks - CAUTION"; Action={Invoke-RightClickMenuLegacy} }
    @{ Id="IPv46";                 Name="IPv6 - Set IPv4 as Preferred";                       Category="Advanced Tweaks - CAUTION"; Action={Invoke-IPv4Preferred} }
    @{ Id="Teredo";                Name="Teredo - Disable";                                   Category="Advanced Tweaks - CAUTION"; Action={Invoke-TeredoDisable} }
    @{ Id="DisableIPv6";           Name="IPv6 - Disable";                                     Category="Advanced Tweaks - CAUTION"; Action={Invoke-DisableIPv6} }
    @{ Id="DisableBGapps";         Name="Background Apps - Disable";                          Category="Advanced Tweaks - CAUTION"; Action={Invoke-DisableBackgroundApps} }
    @{ Id="DisableFSO";            Name="Fullscreen Optimizations - Disable";                 Category="Advanced Tweaks - CAUTION"; Action={Invoke-DisableFSO} }
    @{ Id="OOSU";                  Name="OandO ShutUp10++ - Download and Run";                Category="Advanced Tweaks - CAUTION"; Action={Invoke-OOShutUp} }

    @{ Id="DetailedBSoD";          Name="BSoD Verbose Mode";                                  Category="Customize Preferences";     Action={Invoke-DetailedBSoD} }
    @{ Id="BatteryPercentage";     Name="System Tray Battery Percentage";                     Category="Customize Preferences";     Action={Invoke-BatteryPercentage} }
    @{ Id="DarkMode";              Name="Dark Theme for Windows";                             Category="Customize Preferences";     Action={Invoke-DarkMode} }
    @{ Id="ShowExt";               Name="File Explorer File Extensions - Show";               Category="Customize Preferences";     Action={Invoke-ShowFileExtensions} }
    @{ Id="HiddenFiles";           Name="File Explorer Hidden Files - Show";                  Category="Customize Preferences";     Action={Invoke-ShowHiddenFiles} }
    @{ Id="VerboseLogon";          Name="Logon Verbose Mode";                                 Category="Customize Preferences";     Action={Invoke-VerboseLogon} }
    @{ Id="NewOutlook";            Name="Microsoft Outlook New Version";                      Category="Customize Preferences";     Action={Invoke-NewOutlookToggle} }
    @{ Id="Scrollbars";            Name="Scrollbars Always Visible";                          Category="Customize Preferences";     Action={Invoke-ScrollbarsAlwaysVisible} }
    @{ Id="MultiplaneOverlay";     Name="Disable Multiplane Overlay";                         Category="Customize Preferences";     Action={Invoke-MultiplaneOverlay} }
    @{ Id="MouseAcceleration";     Name="Disable Mouse Acceleration";                         Category="Customize Preferences";     Action={Invoke-MouseAcceleration} }
    @{ Id="NumLock";               Name="Num Lock on Startup";                                Category="Customize Preferences";     Action={Invoke-NumLockOnStartup} }
    @{ Id="StandbyFix";            Name="S0 Sleep Network Connectivity";                      Category="Customize Preferences";     Action={Invoke-StandbyFix} }
    @{ Id="S3Sleep";               Name="Enable S3 Sleep";                                    Category="Customize Preferences";     Action={Invoke-S3Sleep} }
    @{ Id="HideSettingsHome";      Name="Settings Home Page - Show";                          Category="Customize Preferences";     Action={Invoke-HideSettingsHome} }
    @{ Id="BingSearch";            Name="Start Menu Bing Search - Enable";                    Category="Customize Preferences";     Action={Invoke-BingSearchToggle} }
    @{ Id="LoginBlur";             Name="Logon Screen Acrylic Blur - Enable";                 Category="Customize Preferences";     Action={Invoke-LoginScreenBlur} }
    @{ Id="DisableLockscreen";     Name="Lock Screen - Disable";                              Category="Customize Preferences";     Action={Invoke-DisableLockscreen} }
    @{ Id="StartMenuRecs";         Name="Start Menu Recommendations - Disable";               Category="Customize Preferences";     Action={Invoke-StartMenuRecommendations} }
    @{ Id="StickyKeys";            Name="Disable Sticky Keys";                                Category="Customize Preferences";     Action={Invoke-StickyKeysToggle} }
    @{ Id="TaskbarCentered";       Name="Taskbar Centered Icons";                             Category="Customize Preferences";     Action={Invoke-TaskbarCentered} }
    @{ Id="TaskbarSearch";         Name="Taskbar Search Icon - Show";                         Category="Customize Preferences";     Action={Invoke-TaskbarSearchIcon} }
    @{ Id="TaskView";              Name="Taskbar Task View Icon - Show";                      Category="Customize Preferences";     Action={Invoke-TaskViewButton} }
    @{ Id="GameMode";              Name="Enable Game Mode";                                   Category="Customize Preferences";     Action={Invoke-GameModeToggle} }
    @{ Id="LongPaths";             Name="Enable Long Paths";                                  Category="Customize Preferences";     Action={Invoke-LongPathsToggle} }

    @{ Id="AddUltPerf";            Name="Ultimate Performance Power Plan - Enable";           Category="Performance Plans";         Action={Invoke-UltimatePerformance} }
    @{ Id="RemoveUltPerf";         Name="Ultimate Performance Power Plan - Disable";          Category="Performance Plans";         Action={Invoke-RemoveUltimatePerformance} }

    @{ Id="DeletePrefetch";        Name="Prefetch Files - Remove";                            Category="Debloat and Cleanup";       Action={Invoke-DeletePrefetch} }
    @{ Id="EmptyRecycleBin";       Name="Recycle Bin - Empty";                                Category="Debloat and Cleanup";       Action={Invoke-EmptyRecycleBin} }
    @{ Id="ClearWUCache";          Name="Windows Update Cache - Clear";                       Category="Debloat and Cleanup";       Action={Invoke-ClearWindowsUpdateCache} }
    @{ Id="ClearEventLogs";        Name="Event Logs - Clear All";                             Category="Debloat and Cleanup";       Action={Invoke-ClearEventLogs} }

    @{ Id="DisableCoreParking";    Name="Disable CPU Core Parking";                           Category="CPU Tweaks";                Action={Invoke-DisableCoreParking} }
    @{ Id="MinMaxProcState";       Name="Set Min/Max Processor State to 100%";                Category="CPU Tweaks";                Action={Invoke-SetMinMaxProcessorState} }
    @{ Id="EnergyPerfPref";        Name="Set Energy Performance Preference to Max";           Category="CPU Tweaks";                Action={Invoke-SetEnergyPerformancePreference} }
    @{ Id="DisableCpuThrottling";  Name="Disable CPU Power Throttling";                       Category="CPU Tweaks";                Action={Invoke-DisableCpuPowerThrottling} }
    @{ Id="DisableModernStandby";  Name="Disable Modern Standby";                             Category="CPU Tweaks";                Action={Invoke-DisableModernStandby} }

    @{ Id="OptimizeNvidiaFrame";   Name="Optimize Nvidia Frame Scheduling (HAGS)";            Category="GPU Tweaks";                Action={Invoke-OptimizeNvidiaFrameScheduling} }
    @{ Id="DisableHDCP";           Name="Disable HDCP";                                       Category="GPU Tweaks";                Action={Invoke-DisableHDCP} }

    @{ Id="DisableMemCompression"; Name="Disable Memory Compression";                         Category="Memory Tweaks";             Action={Invoke-DisableMemoryCompression} }
    @{ Id="DisablePrefetcher";     Name="Disable Prefetcher and Superfetch";                  Category="Memory Tweaks";             Action={Invoke-DisablePrefetcher} }
    @{ Id="DisableRamDiagnostics"; Name="Disable RAM Diagnostics Task";                       Category="Memory Tweaks";             Action={Invoke-DisableRamDiagnostics} }
)

$DnsOptions = @("Default DHCP","Google","Cloudflare")

$Apps = @(
    # System and Diagnostic Tools
    @{ Id="hwinfo";       Name="HWiNFO";                    Category="System and Diagnostic Tools"; WingetId="REALiX.HWiNFO" }
    @{ Id="cpuz";         Name="CPU-Z";                     Category="System and Diagnostic Tools"; WingetId="CPUID.CPU-Z" }
    @{ Id="gpuz";         Name="GPU-Z";                     Category="System and Diagnostic Tools"; WingetId="TechPowerUp.GPU-Z" }
    @{ Id="crystaldisk";  Name="CrystalDiskInfo";           Category="System and Diagnostic Tools"; WingetId="CrystalDewWorld.CrystalDiskInfo" }
    @{ Id="revouninst";   Name="Revo Uninstaller";          Category="System and Diagnostic Tools"; WingetId="RevoUninstaller.RevoUninstaller" }
    @{ Id="balenaetcher"; Name="balenaEtcher";              Category="System and Diagnostic Tools"; WingetId="Balena.Etcher" }
    @{ Id="rufus";        Name="Rufus";                     Category="System and Diagnostic Tools"; WingetId="Rufus.Rufus" }
    @{ Id="virtualbox";   Name="Oracle VirtualBox";         Category="System and Diagnostic Tools"; WingetId="Oracle.VirtualBox" }
    @{ Id="wireshark";    Name="Wireshark";                 Category="System and Diagnostic Tools"; WingetId="WiresharkFoundation.Wireshark" }
    @{ Id="logitechhub";  Name="Logitech G HUB";            Category="System and Diagnostic Tools"; WingetId="Logitech.GHUB" }

    # Utilities
    @{ Id="7zip";            Name="7-Zip";                   Category="Utilities";      WingetId="7zip.7zip" }
    @{ Id="winrar";          Name="WinRAR";                  Category="Utilities";      WingetId="RARLab.WinRAR" }
    @{ Id="notepadpp";       Name="Notepad++";                Category="Utilities";      WingetId="Notepad++.Notepad++" }
    @{ Id="powertoys";       Name="Microsoft PowerToys";      Category="Utilities";      WingetId="Microsoft.PowerToys" }
    @{ Id="everything";      Name="Everything (search)";      Category="Utilities";      WingetId="voidtools.Everything" }
    @{ Id="ccleaner";        Name="CCleaner";                 Category="Utilities";      WingetId="Piriform.CCleaner" }

    # Remote Access and Streaming
    @{ Id="anydesk";      Name="AnyDesk";                   Category="Remote Access and Streaming"; WingetId="AnyDeskSoftwareGmbH.AnyDesk" }
    @{ Id="teamviewer";   Name="TeamViewer";                Category="Remote Access and Streaming"; WingetId="TeamViewer.TeamViewer" }
    @{ Id="parsec";       Name="Parsec";                    Category="Remote Access and Streaming"; WingetId="Parsec.Parsec" }
    @{ Id="sunshine";     Name="Sunshine";                  Category="Remote Access and Streaming"; WingetId="LizardByte.Sunshine" }
    @{ Id="moonlight";    Name="Moonlight";                 Category="Remote Access and Streaming"; WingetId="MoonlightGameStreamingProject.Moonlight" }

    # Browsers
    @{ Id="chrome";       Name="Google Chrome";             Category="Browsers";       WingetId="Google.Chrome" }
    @{ Id="operagx";      Name="Opera GX";                  Category="Browsers";       WingetId="Opera.OperaGX" }
    @{ Id="firefox";      Name="Mozilla Firefox";           Category="Browsers";       WingetId="Mozilla.Firefox" }
    @{ Id="brave";        Name="Brave Browser";             Category="Browsers";       WingetId="Brave.Brave" }
    @{ Id="tor";          Name="Tor Browser";                Category="Browsers";       WingetId="TorProject.TorBrowser" }

    # Developer Tools
    @{ Id="vscode";          Name="Visual Studio Code";     Category="Developer";      WingetId="Microsoft.VisualStudioCode" }
    @{ Id="git";             Name="Git";                    Category="Developer";      WingetId="Git.Git" }
    @{ Id="python";          Name="Python 3";               Category="Developer";      WingetId="Python.Python.3.12" }
    @{ Id="nodejs";          Name="Node.js LTS";             Category="Developer";      WingetId="OpenJS.NodeJS.LTS" }
    @{ Id="windowsterminal"; Name="Windows Terminal";       Category="Developer";      WingetId="Microsoft.WindowsTerminal" }

    # Communication
    @{ Id="discord";      Name="Discord";                   Category="Communication";  WingetId="Discord.Discord" }
    @{ Id="teams";        Name="Microsoft Teams";           Category="Communication";  WingetId="Microsoft.Teams" }
    @{ Id="zoom";         Name="Zoom";                      Category="Communication";  WingetId="Zoom.Zoom" }
    @{ Id="whatsapp";     Name="WhatsApp";                  Category="Communication";  WingetId="WhatsApp.WhatsApp" }
    @{ Id="telegram";     Name="Telegram";                  Category="Communication";  WingetId="Telegram.TelegramDesktop" }
    @{ Id="signal";       Name="Signal";                    Category="Communication";  WingetId="OpenWhisperSystems.Signal" }
    @{ Id="viber";        Name="Viber";                     Category="Communication";  WingetId="Viber.Viber" }

    # Media and Creative
    @{ Id="vlc";          Name="VLC Media Player";          Category="Media";          WingetId="VideoLAN.VLC" }
    @{ Id="spotify";      Name="Spotify";                   Category="Media";          WingetId="Spotify.Spotify" }
    @{ Id="obs";          Name="OBS Studio";                Category="Media";          WingetId="OBSProject.OBSStudio" }
    @{ Id="audacity";     Name="Audacity";                  Category="Media";          WingetId="Audacity.Audacity" }
    @{ Id="acrobat";      Name="Adobe Acrobat Reader";      Category="Media";          WingetId="Adobe.Acrobat.Reader.64-bit" }

    # Game Launchers
    @{ Id="steam";        Name="Steam";                     Category="Game Launchers"; WingetId="Valve.Steam" }
    @{ Id="epicgames";    Name="Epic Games Launcher";       Category="Game Launchers"; WingetId="EpicGames.EpicGamesLauncher" }
    @{ Id="gog";          Name="GOG Galaxy";                 Category="Game Launchers"; WingetId="GOG.Galaxy" }
    @{ Id="battlenet";    Name="Battle.net";                 Category="Game Launchers"; WingetId="Blizzard.BattleNet" }
    @{ Id="ea";           Name="EA App";                     Category="Game Launchers"; WingetId="ElectronicArts.EADesktop" }
    @{ Id="ubisoft";      Name="Ubisoft Connect";            Category="Game Launchers"; WingetId="Ubisoft.Connect" }
    @{ Id="heroic";       Name="Heroic Games Launcher";      Category="Game Launchers"; WingetId="HeroicGamesLauncher.HeroicGamesLauncher" }
    @{ Id="playnite";     Name="Playnite";                   Category="Game Launchers"; WingetId="Playnite.Playnite" }
    @{ Id="rockstar";     Name="Rockstar Games Launcher";    Category="Game Launchers"; WingetId="RockstarGames.Launcher" }
    @{ Id="curseforge";   Name="CurseForge";                 Category="Game Launchers"; WingetId="Overwolf.CurseForge" }

    # Emulators
    @{ Id="dolphin";      Name="Dolphin Emulator";           Category="Emulators"; WingetId="DolphinEmulator.DolphinEmulator" }
    @{ Id="rpcs3";        Name="RPCS3";                      Category="Emulators"; WingetId="RPCS3.RPCS3" }
)

# ===========================================================================
# XAML
# ===========================================================================

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Beko Tweaks" Height="820" Width="1020"
        Background="#1e1e1e" WindowStartupLocation="CenterScreen">
    <Window.Resources>
        <Style TargetType="CheckBox">
            <Setter Property="Foreground" Value="#e6e6e6"/>
            <Setter Property="Margin" Value="4,3,4,3"/>
            <Setter Property="FontSize" Value="13"/>
        </Style>
        <Style TargetType="TextBlock">
            <Setter Property="Foreground" Value="#5dade2"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="FontSize" Value="16"/>
            <Setter Property="Margin" Value="0,14,0,4"/>
        </Style>
        <Style TargetType="Button">
            <Setter Property="Background" Value="#2d2d30"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="Padding" Value="14,6"/>
            <Setter Property="Margin" Value="6,0,0,0"/>
            <Setter Property="BorderBrush" Value="#5dade2"/>
            <Setter Property="BorderThickness" Value="1"/>
        </Style>
        <Style TargetType="ComboBox">
            <Setter Property="Margin" Value="6,0,0,0"/>
            <Setter Property="Width" Value="220"/>
        </Style>
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="#2d2d30"/>
            <Setter Property="Foreground" Value="#e6e6e6"/>
            <Setter Property="Padding" Value="4"/>
            <Setter Property="BorderBrush" Value="#5dade2"/>
        </Style>
    </Window.Resources>
    <Grid Margin="10">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
        </Grid.RowDefinitions>
        
        <!-- Header Section with Slanted Retro-Modern Logo Wrapper -->
        <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="5,0,0,15" VerticalAlignment="Center">
            <Grid Width="45" Height="50" Margin="0,0,12,0">
                <Grid.RenderTransform>
                    <SkewTransform AngleX="-15"/>
                </Grid.RenderTransform>
                <!-- Retro dark ambient drop shadow text layers -->
                <TextBlock Text="B" FontFamily="Arial Black" FontSize="44" FontWeight="Black" Foreground="#2e1065" Margin="4,4,0,0" VerticalAlignment="Center" HorizontalAlignment="Center"/>
                <TextBlock Text="B" FontFamily="Arial Black" FontSize="44" FontWeight="Black" Foreground="#3b0764" Margin="2,2,0,0" VerticalAlignment="Center" HorizontalAlignment="Center"/>
                <!-- Main Neon Purple Gradient Text -->
                <TextBlock Text="B" FontFamily="Arial Black" FontSize="44" FontWeight="Black" VerticalAlignment="Center" HorizontalAlignment="Center">
                    <TextBlock.Foreground>
                        <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                            <GradientStop Color="#a855f7" Offset="0.0"/>
                            <GradientStop Color="#6b21a8" Offset="1.0"/>
                        </LinearGradientBrush>
                    </TextBlock.Foreground>
                </TextBlock>
                <!-- Retro-Modern Accent Line Base -->
                <Rectangle Height="4" VerticalAlignment="Bottom" RadiusX="2" RadiusY="2" Margin="2,0,2,0">
                    <Rectangle.Fill>
                        <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
                            <GradientStop Color="#ec4899" Offset="0.0"/>
                            <GradientStop Color="#8b5cf6" Offset="1.0"/>
                        </LinearGradientBrush>
                    </Rectangle.Fill>
                </Rectangle>
            </Grid>
            
            <StackPanel Orientation="Vertical" VerticalAlignment="Center">
                <TextBlock Text="BEKO TWEAKS" FontSize="22" Foreground="#5dade2" FontWeight="Bold" Margin="0"/>
                <TextBlock Text="Windows Tweak &amp; Setup Utility" FontSize="11" Foreground="#888888" Margin="0,-2,0,0" FontWeight="Normal"/>
            </StackPanel>
        </StackPanel>
        
        <TabControl Grid.Row="1" Background="#1e1e1e" BorderThickness="0" Name="MainTabs">

            <TabItem Header="Tweaks">
                <Grid Margin="6">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="130"/>
                    </Grid.RowDefinitions>
                    <ScrollViewer Grid.Row="0" VerticalScrollBarVisibility="Auto">
                        <StackPanel Name="TweakPanel"/>
                    </ScrollViewer>
                    <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,10,0,0">
                        <Button Name="BtnSelectAll" Content="Select All"/>
                        <Button Name="BtnSelectNone" Content="Select None"/>
                        <Button Name="BtnApply" Content="Apply Selected Tweaks" Background="#2e7d32"/>
                        <TextBlock Text="DNS:" Foreground="#e6e6e6" FontWeight="Normal" VerticalAlignment="Center" Margin="20,0,0,0"/>
                        <ComboBox Name="DnsCombo"/>
                        <Button Name="BtnSetDns" Content="Set DNS"/>
                    </StackPanel>
                    <Border Grid.Row="2" Background="#111111" BorderBrush="#333333" BorderThickness="1" Margin="0,10,0,0">
                        <ScrollViewer VerticalScrollBarVisibility="Auto">
                            <TextBox Name="LogBox" Background="#111111" Foreground="#90ee90" BorderThickness="0"
                                     FontFamily="Consolas" FontSize="12" IsReadOnly="True" TextWrapping="Wrap"/>
                        </ScrollViewer>
                    </Border>
                </Grid>
            </TabItem>

            <TabItem Header="App Installer">
                <Grid Margin="6">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="130"/>
                    </Grid.RowDefinitions>
                    <ScrollViewer Grid.Row="0" VerticalScrollBarVisibility="Auto">
                        <StackPanel Name="AppPanel"/>
                    </ScrollViewer>
                    <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,10,0,0">
                        <Button Name="BtnAppSelectAll" Content="Select All"/>
                        <Button Name="BtnAppSelectNone" Content="Select None"/>
                        <Button Name="BtnInstallApps" Content="Install Selected Apps" Background="#2e7d32"/>
                    </StackPanel>
                    <Border Grid.Row="2" Background="#111111" BorderBrush="#333333" BorderThickness="1" Margin="0,10,0,0">
                        <ScrollViewer VerticalScrollBarVisibility="Auto">
                            <TextBox Name="AppLogBox" Background="#111111" Foreground="#90ee90" BorderThickness="0"
                                     FontFamily="Consolas" FontSize="12" IsReadOnly="True" TextWrapping="Wrap"/>
                        </ScrollViewer>
                    </Border>
                </Grid>
            </TabItem>

        </TabControl>
    </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

$TweakPanel       = $window.FindName("TweakPanel")
$LogBox           = $window.FindName("LogBox")
$DnsCombo         = $window.FindName("DnsCombo")
$BtnSelectAll     = $window.FindName("BtnSelectAll")
$BtnSelectNone    = $window.FindName("BtnSelectNone")
$BtnApply         = $window.FindName("BtnApply")
$BtnSetDns        = $window.FindName("BtnSetDns")
$AppPanel         = $window.FindName("AppPanel")
$BtnAppSelectAll  = $window.FindName("BtnAppSelectAll")
$BtnAppSelectNone = $window.FindName("BtnAppSelectNone")
$BtnInstallApps   = $window.FindName("BtnInstallApps")
$AppLogBox        = $window.FindName("AppLogBox")

function Write-Log {
    param([string]$Text)
    $window.Dispatcher.Invoke([action]{ $LogBox.AppendText("$Text`r`n"); $LogBox.ScrollToEnd() })
}
function Write-AppLog {
    param([string]$Text)
    $window.Dispatcher.Invoke([action]{ $AppLogBox.AppendText("$Text`r`n"); $AppLogBox.ScrollToEnd() })
}

# Populate DNS combo
foreach ($opt in $DnsOptions) { $DnsCombo.Items.Add($opt) | Out-Null }
$DnsCombo.SelectedIndex = 0

# Build tweak checkboxes
$checkboxMap = @{}
foreach ($cat in @("Essential Tweaks","Debloat and Cleanup","CPU Tweaks","GPU Tweaks","Memory Tweaks","Advanced Tweaks - CAUTION","Customize Preferences","Performance Plans")) {
    $h = New-Object System.Windows.Controls.TextBlock; $h.Text = $cat
    $TweakPanel.Children.Add($h) | Out-Null
    $wrap = New-Object System.Windows.Controls.WrapPanel
    foreach ($t in ($Tweaks | Where-Object { $_.Category -eq $cat })) {
        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.Content = $t.Name; $cb.Width = 440; $cb.Tag = $t.Id
        $wrap.Children.Add($cb) | Out-Null
        $checkboxMap[$t.Id] = $cb
    }
    $TweakPanel.Children.Add($wrap) | Out-Null
}

# Build app checkboxes
$appCheckboxMap = @{}
foreach ($cat in @("System and Diagnostic Tools","Utilities","Remote Access and Streaming","Browsers","Developer","Communication","Media","Game Launchers","Emulators")) {
    $h = New-Object System.Windows.Controls.TextBlock; $h.Text = $cat
    $AppPanel.Children.Add($h) | Out-Null
    $wrap = New-Object System.Windows.Controls.WrapPanel
    foreach ($a in ($Apps | Where-Object { $_.Category -eq $cat })) {
        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.Content = $a.Name; $cb.Width = 320; $cb.Tag = $a.Id
        $wrap.Children.Add($cb) | Out-Null
        $appCheckboxMap[$a.Id] = $cb
    }
    $AppPanel.Children.Add($wrap) | Out-Null
}

# Tweaks tab events
$BtnSelectAll.Add_Click({  foreach ($cb in $checkboxMap.Values)    { $cb.IsChecked = $true }  })
$BtnSelectNone.Add_Click({ foreach ($cb in $checkboxMap.Values)    { $cb.IsChecked = $false } })

$BtnSetDns.Add_Click({
    $p = ($DnsCombo.SelectedItem -replace " ","_")
    if ($p -eq "Default_DHCP") { $p = "DHCP" }
    Write-Log ">>> Setting DNS to $($DnsCombo.SelectedItem)"
    $BtnSetDns.IsEnabled = $false
    try { Invoke-SetDNS -Provider $p; Write-Log "    Done." } catch { Write-Log "    [FAIL] $_" }
    $BtnSetDns.IsEnabled = $true
})

$BtnApply.Add_Click({
    $BtnApply.IsEnabled = $false
    $sel = $Tweaks | Where-Object { $checkboxMap[$_.Id].IsChecked -eq $true }
    if ($sel.Count -eq 0) { Write-Log "No tweaks selected."; $BtnApply.IsEnabled = $true; return }
    Write-Log "=== Applying $($sel.Count) tweak(s) ==="
    foreach ($t in $sel) {
        Write-Log "-> $($t.Name)"
        try { & $t.Action; Write-Log "   [OK]" } catch { Write-Log "   [ERROR] $_" }
    }
    Write-Log "=== Done. Restart recommended. ==="
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Process explorer.exe
    $BtnApply.IsEnabled = $true
})

# App installer tab events
$BtnAppSelectAll.Add_Click({  foreach ($cb in $appCheckboxMap.Values) { $cb.IsChecked = $true }  })
$BtnAppSelectNone.Add_Click({ foreach ($cb in $appCheckboxMap.Values) { $cb.IsChecked = $false } })

$BtnInstallApps.Add_Click({
    $BtnInstallApps.IsEnabled = $false
    if (-not (Test-WingetAvailable)) {
        Write-AppLog "[FAIL] winget not found. Install 'App Installer' from the Microsoft Store first."
        $BtnInstallApps.IsEnabled = $true; return
    }
    $sel = $Apps | Where-Object { $appCheckboxMap[$_.Id].IsChecked -eq $true }
    if ($sel.Count -eq 0) { Write-AppLog "No apps selected."; $BtnInstallApps.IsEnabled = $true; return }
    Write-AppLog "=== Installing $($sel.Count) app(s) via winget ==="
    foreach ($a in $sel) {
        Write-AppLog "-> $($a.Name) ($($a.WingetId))"
        try {
            $out = & winget install --id $a.WingetId --silent --accept-source-agreements --accept-package-agreements -e 2>&1
            $out | ForEach-Object { Write-AppLog "   $_" }
            Write-AppLog "   [DONE]"
        } catch { Write-AppLog "   [ERROR] $_" }
    }
    Write-AppLog "=== Installation complete. ==="
    $BtnInstallApps.IsEnabled = $true
})

Write-Log "Beko Tweaks ready. Running as Administrator: $([bool]([Security.Principal.WindowsIdentity]::GetCurrent().Groups -match 'S-1-5-32-544'))"
Write-AppLog "winget available: $(Test-WingetAvailable)"

$window.ShowDialog() | Out-Null