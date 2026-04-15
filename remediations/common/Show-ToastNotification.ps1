<#
.SYNOPSIS
    Utility - Show a Windows Toast Notification (PS 5.1 and 7+ compatible)
.DESCRIPTION
    Loads WinRT assemblies correctly for both PowerShell 5.1 (.NET Framework)
    and PowerShell 7+ (.NET Core). Run in USER context.
#>

function Show-ToastNotification {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Message,
        [string]$Scenario = "reminder",
        [array]$Buttons = @(),
        [string]$AppId = "{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe"
    )

    # Load WinRT types - different method for PS 5.1 vs 7+
    if ($PSVersionTable.PSVersion.Major -le 5) {
        # PS 5.1: direct WinRT type loading works
        [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        [void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
    } else {
        # PS 7+: need to load via Add-Type from WinMD files
        $null = [System.Runtime.InteropServices.WindowsRuntime.WindowsRuntimeSystemExtensions]
        Add-Type -AssemblyName 'Windows.UI.Notifications' -ErrorAction SilentlyContinue
        $winmdPath = "$env:SystemRoot\System32\WinMetadata\Windows.UI.winmd"
        if (Test-Path $winmdPath) {
            Add-Type -Path $winmdPath -ErrorAction SilentlyContinue
        }
        # If still not loaded, fall back to .NET approach
        try {
            [void][Windows.UI.Notifications.ToastNotificationManager]
        } catch {
            throw "Toast notifications require PowerShell 5.1 (powershell.exe) on this system. PS 7+ WinRT support not available."
        }
    }

    # Build actions XML
    $actionsXml = ""
    if ($Buttons.Count -gt 0) {
        $btnXml = ($Buttons | ForEach-Object {
            $activationType = if ($_.Arguments -match '^https?://') { 'protocol' } else { 'foreground' }
            "<action content=`"$($_.Content)`" arguments=`"$($_.Arguments)`" activationType=`"$activationType`"/>"
        }) -join "`n    "
        $actionsXml = "<actions>$btnXml</actions>"
    }

    $toastXml = @"
<toast scenario="$Scenario" activationType="foreground">
  <visual>
    <binding template="ToastGeneric">
      <text>$Title</text>
      <text>$Message</text>
    </binding>
  </visual>
  $actionsXml
</toast>
"@

    $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
    $xml.LoadXml($toastXml)
    $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
    $notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($AppId)
    $notifier.Show($toast)
}