function Show-WindowsDeviceLink {
    <#
    .SYNOPSIS
    Opens a compact WindowsDeviceLink operator dashboard.

    .DESCRIPTION
    Opens a WinForms-based dashboard on full Windows. The dashboard presents local
    DeviceLink firmware and tenant-correlation state without automatically materializing
    a new DeviceLink identity.

    Operator actions delegate to the existing WindowsDeviceLink cmdlets. State-changing
    actions always require an explicit GUI confirmation before the underlying cmdlet is
    invoked.

    The GUI is a convenience layer only; lifecycle and safety logic remains in the
    existing public cmdlets.

    .EXAMPLE
    Show-WindowsDeviceLink

    Opens the WindowsDeviceLink dashboard.

    .NOTES
    The GUI is supported on full Windows only. WinPE remains a command-line workflow.
    #>
    [CmdletBinding()]
    param()

    if (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT') {
        throw 'Show-WindowsDeviceLink is not supported in Windows PE. Use the WindowsDeviceLink command-line cmdlets instead.'
    }

    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop

    [System.Windows.Forms.Application]::EnableVisualStyles()

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'WindowsDeviceLink'
    $form.StartPosition = 'CenterScreen'
    $form.Size = New-Object System.Drawing.Size(1020,720)
    $form.MinimumSize = New-Object System.Drawing.Size(980,680)
    $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi

    $title = New-Object System.Windows.Forms.Label
    $title.Text = 'WindowsDeviceLink'
    $title.Font = New-Object System.Drawing.Font('Segoe UI',18,[System.Drawing.FontStyle]::Bold)
    $title.Location = New-Object System.Drawing.Point(20,14)
    $title.AutoSize = $true
    $form.Controls.Add($title)

    $subtitle = New-Object System.Windows.Forms.Label
    $subtitle.Text = 'Windows Autopilot Device Preparation • Device Association'
    $subtitle.Font = New-Object System.Drawing.Font('Segoe UI',9)
    $subtitle.Location = New-Object System.Drawing.Point(24,50)
    $subtitle.AutoSize = $true
    $form.Controls.Add($subtitle)

    function New-ValueLabel {
        param(
            [System.Windows.Forms.Control]$Parent,
            [string]$Caption,
            [int]$Y
        )

        $captionLabel = New-Object System.Windows.Forms.Label
        $captionLabel.Text = $Caption
        $captionLabel.Location = New-Object System.Drawing.Point(14,$Y)
        $captionLabel.Size = New-Object System.Drawing.Size(150,22)
        $captionLabel.Font = New-Object System.Drawing.Font('Segoe UI',9)
        $Parent.Controls.Add($captionLabel)

        $valueLabel = New-Object System.Windows.Forms.Label
        $valueLabel.Text = '—'
        $valueLabel.Location = New-Object System.Drawing.Point(168,$Y)
        $valueLabel.Size = New-Object System.Drawing.Size(290,38)
        $valueLabel.Font = New-Object System.Drawing.Font('Segoe UI',9,[System.Drawing.FontStyle]::Bold)
        $valueLabel.AutoEllipsis = $true
        $Parent.Controls.Add($valueLabel)

        $valueLabel
    }

    function New-Group {
        param(
            [string]$Text,
            [int]$X,
            [int]$Y,
            [int]$Width,
            [int]$Height
        )

        $group = New-Object System.Windows.Forms.GroupBox
        $group.Text = $Text
        $group.Location = New-Object System.Drawing.Point($X,$Y)
        $group.Size = New-Object System.Drawing.Size($Width,$Height)
        $group.Font = New-Object System.Drawing.Font('Segoe UI',9,[System.Drawing.FontStyle]::Bold)
        $form.Controls.Add($group)
        $group
    }

    $deviceGroup = New-Group -Text 'Device' -X 20 -Y 82 -Width 470 -Height 220
    $localGroup  = New-Group -Text 'Local association' -X 510 -Y 82 -Width 470 -Height 220
    $cloudGroup  = New-Group -Text 'Cloud association' -X 20 -Y 316 -Width 470 -Height 190
    $actionGroup = New-Group -Text 'Actions' -X 510 -Y 316 -Width 470 -Height 270

    $ui = @{}
    $ui.Manufacturer = New-ValueLabel -Parent $deviceGroup -Caption 'Manufacturer' -Y 28
    $ui.Model        = New-ValueLabel -Parent $deviceGroup -Caption 'Model' -Y 62
    $ui.Serial       = New-ValueLabel -Parent $deviceGroup -Caption 'Serial number' -Y 96
    $ui.Runtime      = New-ValueLabel -Parent $deviceGroup -Caption 'Runtime' -Y 130
    $ui.LinkId       = New-ValueLabel -Parent $deviceGroup -Caption 'Link ID' -Y 164

    $ui.Firmware     = New-ValueLabel -Parent $localGroup -Caption 'Firmware state' -Y 28
    $ui.LocalState   = New-ValueLabel -Parent $localGroup -Caption 'Local state' -Y 62
    $ui.TenantId     = New-ValueLabel -Parent $localGroup -Caption 'Tenant ID' -Y 96
    $ui.Source       = New-ValueLabel -Parent $localGroup -Caption 'Source' -Y 130
    $ui.Trust        = New-ValueLabel -Parent $localGroup -Caption 'Trust' -Y 164

    $ui.CloudState   = New-ValueLabel -Parent $cloudGroup -Caption 'Association state' -Y 28
    $ui.CloudTenant  = New-ValueLabel -Parent $cloudGroup -Caption 'Tenant ID' -Y 62
    $ui.CloudId      = New-ValueLabel -Parent $cloudGroup -Caption 'Association ID' -Y 96
    $ui.CloudMessage = New-ValueLabel -Parent $cloudGroup -Caption 'Status' -Y 130

    $tenantCaption = New-Object System.Windows.Forms.Label
    $tenantCaption.Text = 'Tenant override (optional)'
    $tenantCaption.Location = New-Object System.Drawing.Point(14,30)
    $tenantCaption.Size = New-Object System.Drawing.Size(180,22)
    $tenantCaption.Font = New-Object System.Drawing.Font('Segoe UI',9)
    $actionGroup.Controls.Add($tenantCaption)

    $tenantBox = New-Object System.Windows.Forms.TextBox
    $tenantBox.Location = New-Object System.Drawing.Point(198,27)
    $tenantBox.Size = New-Object System.Drawing.Size(250,24)
    $tenantBox.Font = New-Object System.Drawing.Font('Consolas',9)
    $actionGroup.Controls.Add($tenantBox)

    function New-ActionButton {
        param(
            [string]$Text,
            [int]$X,
            [int]$Y,
            [int]$Width = 138
        )

        $button = New-Object System.Windows.Forms.Button
        $button.Text = $Text
        $button.Location = New-Object System.Drawing.Point($X,$Y)
        $button.Size = New-Object System.Drawing.Size($Width,34)
        $button.Font = New-Object System.Drawing.Font('Segoe UI',9)
        $actionGroup.Controls.Add($button)
        $button
    }

    $btnRefresh    = New-ActionButton -Text 'Refresh' -X 14 -Y 70
    $btnIdentity   = New-ActionButton -Text 'Load identity' -X 164 -Y 70
    $btnOnline     = New-ActionButton -Text 'Check online' -X 314 -Y 70

    $btnExport     = New-ActionButton -Text 'Export CSV' -X 14 -Y 114
    $btnRegister   = New-ActionButton -Text 'Pre-associate' -X 164 -Y 114
    $btnComplete   = New-ActionButton -Text 'Complete' -X 314 -Y 114

    $btnRemove     = New-ActionButton -Text 'Remove cloud' -X 14 -Y 158
    $btnReset      = New-ActionButton -Text 'Reset local' -X 164 -Y 158
    $btnClose      = New-ActionButton -Text 'Close' -X 314 -Y 158

    $actionNote = New-Object System.Windows.Forms.Label
    $actionNote.Text = 'State-changing actions call the existing cmdlets and require confirmation.'
    $actionNote.Location = New-Object System.Drawing.Point(16,208)
    $actionNote.Size = New-Object System.Drawing.Size(430,40)
    $actionNote.Font = New-Object System.Drawing.Font('Segoe UI',8)
    $actionGroup.Controls.Add($actionNote)

    $statusStrip = New-Object System.Windows.Forms.StatusStrip
    $statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
    $statusLabel.Text = 'Ready'
    [void]$statusStrip.Items.Add($statusLabel)
    $form.Controls.Add($statusStrip)

    $script:WdlGuiLocalAssociation = $null

    function Set-GuiStatus {
        param([string]$Text)
        $statusLabel.Text = $Text
        [System.Windows.Forms.Application]::DoEvents()
    }

    function Show-GuiError {
        param([string]$Message)
        [void][System.Windows.Forms.MessageBox]::Show(
            $form,
            $Message,
            'WindowsDeviceLink',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
    }

    function Confirm-GuiAction {
        param(
            [string]$Title,
            [string]$Message
        )

        $result = [System.Windows.Forms.MessageBox]::Show(
            $form,
            $Message,
            $Title,
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )

        $result -eq [System.Windows.Forms.DialogResult]::Yes
    }

    function Refresh-LocalView {
        Set-GuiStatus 'Refreshing local state...'
        try {
            $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop
            $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
            $support = Test-WindowsDeviceLinkSupport
            $local = Get-WindowsDeviceLinkLocalAssociation
            $script:WdlGuiLocalAssociation = $local

            $ui.Manufacturer.Text = [string]$cs.Manufacturer
            $ui.Model.Text = [string]$cs.Model
            $ui.Serial.Text = [string]$bios.SerialNumber

            if ($support.Supported) {
                $runtimeText = "$($support.Environment) • $($support.ActivationMode)"
                if ($support.DllVersion) { $runtimeText += " • $($support.DllVersion)" }
                $ui.Runtime.Text = $runtimeText
            }
            else {
                $ui.Runtime.Text = "Unsupported: $($support.Reason)"
            }

            $ui.LinkId.Text = if ($local.LinkId) { [string]$local.LinkId } else { 'Not materialized' }
            $ui.Firmware.Text = [string]$local.FirmwareState
            $ui.LocalState.Text = [string]$local.LocalAssociationState
            $ui.TenantId.Text = if ($local.TenantId) { [string]$local.TenantId } else { 'Unavailable' }
            $ui.Source.Text = [string]$local.Source
            $ui.Trust.Text = [string]$local.TrustLevel


            Set-GuiStatus "Local state refreshed • $($local.FirmwareState) • $($local.TrustLevel)"
        }
        catch {
            Set-GuiStatus 'Local refresh failed'
            Show-GuiError $_.Exception.Message
        }
    }

    function Get-TenantOverride {
        $value = $tenantBox.Text.Trim()
        if ($value) { return $value }
        if ($script:WdlGuiLocalAssociation -and $script:WdlGuiLocalAssociation.TenantId) {
            return [string]$script:WdlGuiLocalAssociation.TenantId
        }
        $null
    }

    $btnRefresh.Add_Click({
        Refresh-LocalView
    })

    $btnIdentity.Add_Click({
        Set-GuiStatus 'Loading DeviceLink identity...'
        try {
            $identity = Get-WindowsDeviceLink
            Set-GuiStatus "DeviceLink identity loaded: $($identity.LinkId)"
            Refresh-LocalView
        }
        catch {
            Set-GuiStatus 'Identity load failed'
            Show-GuiError $_.Exception.Message
        }
    })

    $btnOnline.Add_Click({
        Set-GuiStatus 'Checking tenant-side Device Association...'
        try {
            $parameters = @{ Online = $true; Method = 'Interactive' }
            $tenant = Get-TenantOverride
            if ($tenant) { $parameters.TenantId = $tenant }

            $cloud = Get-WindowsDeviceLinkStatus @parameters
            $ui.CloudState.Text = [string]$cloud.AssociationState
            $ui.CloudTenant.Text = if ($cloud.TenantId) { [string]$cloud.TenantId } else { '—' }
            $ui.CloudId.Text = if ($cloud.AssociationId) { [string]$cloud.AssociationId } else { '—' }
            $ui.CloudMessage.Text = if ($cloud.AssociationError) { [string]$cloud.AssociationError } else { 'Lookup completed' }
            Set-GuiStatus 'Cloud lookup completed'
        }
        catch {
            $ui.CloudMessage.Text = 'Lookup failed'
            Set-GuiStatus 'Cloud lookup failed'
            Show-GuiError $_.Exception.Message
        }
    })

    $btnExport.Add_Click({
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = 'Choose a folder for the DeviceLink CSV'
        if ($dialog.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) { return }

        Set-GuiStatus 'Exporting DeviceLink CSV...'
        try {
            $file = Get-WindowsDeviceLink -OutputDirectory $dialog.SelectedPath
            Set-GuiStatus "CSV exported: $($file.FullName)"
            [void][System.Windows.Forms.MessageBox]::Show(
                $form,
                "Exported to:
$($file.FullName)",
                'WindowsDeviceLink',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
            Refresh-LocalView
        }
        catch {
            Set-GuiStatus 'CSV export failed'
            Show-GuiError $_.Exception.Message
        }
        finally {
            $dialog.Dispose()
        }
    })

    $btnRegister.Add_Click({
        if (-not (Confirm-GuiAction -Title 'Create pre-association' -Message 'Create or attempt a tenant-side Device Association pre-association for this device?')) {
            return
        }

        Set-GuiStatus 'Creating tenant-side pre-association...'
        try {
            $identity = Get-WindowsDeviceLink
            $parameters = @{ Method = 'Interactive'; Confirm = $false }
            $tenant = $tenantBox.Text.Trim()
            if ($tenant) { $parameters.TenantId = $tenant }

            $result = $identity | Register-WindowsDeviceLink @parameters
            Set-GuiStatus "Pre-association completed: $($result.AssociationState)"
            Refresh-LocalView
        }
        catch {
            Set-GuiStatus 'Pre-association failed'
            Show-GuiError $_.Exception.Message
        }
    })

    $btnComplete.Add_Click({
        if (-not (Confirm-GuiAction -Title 'Complete association' -Message 'Run native DeviceLink association completion now? This can take one or more minutes and changes local DeviceLink state.')) {
            return
        }

        Set-GuiStatus 'Completing DeviceLink association...'
        try {
            $result = Complete-WindowsDeviceLinkAssociation -Confirm:$false
            Set-GuiStatus "Completion result: $($result.Result)"
            Refresh-LocalView
        }
        catch {
            Set-GuiStatus 'Association completion failed'
            Show-GuiError $_.Exception.Message
        }
    })

    $btnRemove.Add_Click({
        if (-not (Confirm-GuiAction -Title 'Remove cloud association' -Message 'Delete the tenant-side Device Association record for this device? Local DeviceLink firmware state will not be reset.')) {
            return
        }

        Set-GuiStatus 'Removing tenant-side Device Association...'
        try {
            $parameters = @{ Method = 'Interactive'; Confirm = $false }
            $tenant = Get-TenantOverride
            if ($tenant) { $parameters.TenantId = $tenant }

            $null = Remove-WindowsDeviceLinkAssociation @parameters
            $ui.CloudState.Text = 'Not checked'
            $ui.CloudTenant.Text = '—'
            $ui.CloudId.Text = '—'
            $ui.CloudMessage.Text = 'Cloud association removed; refresh/check online to verify.'
            Set-GuiStatus 'Tenant-side association removal completed'
            Refresh-LocalView
        }
        catch {
            Set-GuiStatus 'Cloud removal failed'
            Show-GuiError $_.Exception.Message
        }
    })

    $btnReset.Add_Click({
        if (-not (Confirm-GuiAction -Title 'Reset local DeviceLink state' -Message 'Remove all known local DeviceLink UEFI variables? This is destructive local cleanup and does not delete the cloud Device Association record.')) {
            return
        }

        Set-GuiStatus 'Resetting local DeviceLink firmware state...'
        try {
            $null = Reset-WindowsDeviceLinkFirmwareState -Confirm:$false
            Set-GuiStatus 'Local DeviceLink firmware state reset'
            Refresh-LocalView
        }
        catch {
            Set-GuiStatus 'Local reset failed'
            Show-GuiError $_.Exception.Message
        }
    })

    $btnClose.Add_Click({
        $form.Close()
    })

    $form.Add_Shown({
        Refresh-LocalView
    })

    try {
        [void]$form.ShowDialog()
    }
    finally {
        $form.Dispose()
        Remove-Variable WdlGuiLocalAssociation -Scope Script -ErrorAction SilentlyContinue
    }
}
