function Show-WindowsDeviceLink {
    <#
    .SYNOPSIS
    Opens the WindowsDeviceLink operator dashboard.

    .DESCRIPTION
    Opens a compact Windows 11 Settings-inspired WinForms dashboard on full Windows.

    The dashboard reads local DeviceLink state without automatically materializing a new
    DeviceLink identity. Operator actions delegate to existing WindowsDeviceLink cmdlets.
    State-changing actions require an explicit GUI confirmation.

    The layout is intentionally compact and vertically scrollable so it remains usable on
    lower-resolution displays. WinPE remains a command-line workflow for now.

    .EXAMPLE
    Show-WindowsDeviceLink
    #>
    [CmdletBinding()]
    param()

    if (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT') {
        throw 'Show-WindowsDeviceLink is not supported in Windows PE yet. Use the WindowsDeviceLink command-line cmdlets instead.'
    }

    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop

    [System.Windows.Forms.Application]::EnableVisualStyles()

    $workingArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $targetWidth = [Math]::Max(820,[Math]::Min(1120,$workingArea.Width - 32))
    $targetHeight = [Math]::Max(620,[Math]::Min(860,$workingArea.Height - 48))

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'WindowsDeviceLink'
    $form.StartPosition = 'CenterScreen'
    $form.Size = [System.Drawing.Size]::new($targetWidth,$targetHeight)
    $form.MinimumSize = [System.Drawing.Size]::new(820,620)
    $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $form.BackColor = [System.Drawing.Color]::FromArgb(243,243,243)

    $content = New-Object System.Windows.Forms.Panel
    $content.Dock = [System.Windows.Forms.DockStyle]::Fill
    $content.AutoScroll = $true
    $content.BackColor = $form.BackColor
    $form.Controls.Add($content)

    $title = New-Object System.Windows.Forms.Label
    $title.Text = 'WindowsDeviceLink'
    $title.Font = New-Object System.Drawing.Font('Segoe UI',20,[System.Drawing.FontStyle]::Bold)
    $title.Location = [System.Drawing.Point]::new(28,18)
    $title.AutoSize = $true
    $content.Controls.Add($title)

    $subtitle = New-Object System.Windows.Forms.Label
    $subtitle.Text = 'Windows Autopilot Device Preparation - Device Association'
    $subtitle.Font = New-Object System.Drawing.Font('Segoe UI',9)
    $subtitle.ForeColor = [System.Drawing.Color]::FromArgb(96,96,96)
    $subtitle.Location = [System.Drawing.Point]::new(31,58)
    $subtitle.AutoSize = $true
    $content.Controls.Add($subtitle)

    function New-Card {
        param([string]$Title,[int]$X,[int]$Y,[int]$Width,[int]$Height)

        $panel = New-Object System.Windows.Forms.Panel
        $panel.Location = [System.Drawing.Point]::new([int]$X,[int]$Y)
        $panel.Size = [System.Drawing.Size]::new([int]$Width,[int]$Height)
        $panel.BackColor = [System.Drawing.Color]::White
        $panel.BorderStyle = [System.Windows.Forms.BorderStyle]::None
        $content.Controls.Add($panel)

        if (-not [string]::IsNullOrWhiteSpace($Title)) {
            $label = New-Object System.Windows.Forms.Label
            $label.Text = $Title
            $label.Font = New-Object System.Drawing.Font('Segoe UI',10,[System.Drawing.FontStyle]::Bold)
            $label.Location = [System.Drawing.Point]::new(18,14)
            $label.AutoSize = $true
            $panel.Controls.Add($label)
        }

        $panel
    }

    function New-ValuePair {
        param([System.Windows.Forms.Control]$Parent,[string]$Caption,[int]$Y)

        $captionLabel = New-Object System.Windows.Forms.Label
        $captionLabel.Text = $Caption
        $captionLabel.Font = New-Object System.Drawing.Font('Segoe UI',8.5)
        $captionLabel.ForeColor = [System.Drawing.Color]::FromArgb(96,96,96)
        $captionLabel.Location = [System.Drawing.Point]::new(18,$Y)
        $captionLabel.Size = [System.Drawing.Size]::new(135,20)
        $Parent.Controls.Add($captionLabel)

        $valueLabel = New-Object System.Windows.Forms.Label
        $valueLabel.Text = '-'
        $valueLabel.Font = New-Object System.Drawing.Font('Segoe UI',9,[System.Drawing.FontStyle]::Bold)
        $valueLabel.Location = [System.Drawing.Point]::new(155,([int]$Y - 1))
        $valueLabel.Size = [System.Drawing.Size]::new(330,34)
        $valueLabel.AutoEllipsis = $true
        $Parent.Controls.Add($valueLabel)

        $valueLabel
    }

    function New-ActionRow {
        param([System.Windows.Forms.Control]$Parent,[string]$Title,[string]$Description,[int]$Y,[string]$ButtonText)

        $row = New-Object System.Windows.Forms.Panel
        $row.Location = [System.Drawing.Point]::new(0,[int]$Y)
        $row.Size = [System.Drawing.Size]::new(900,50)
        $row.BackColor = [System.Drawing.Color]::White
        $Parent.Controls.Add($row)

        $titleLabel = New-Object System.Windows.Forms.Label
        $titleLabel.Text = $Title
        $titleLabel.Font = New-Object System.Drawing.Font('Segoe UI',9,[System.Drawing.FontStyle]::Bold)
        $titleLabel.Location = [System.Drawing.Point]::new(18,6)
        $titleLabel.AutoSize = $true
        $row.Controls.Add($titleLabel)

        $descriptionLabel = New-Object System.Windows.Forms.Label
        $descriptionLabel.Text = $Description
        $descriptionLabel.Font = New-Object System.Drawing.Font('Segoe UI',8)
        $descriptionLabel.ForeColor = [System.Drawing.Color]::FromArgb(110,110,110)
        $descriptionLabel.Location = [System.Drawing.Point]::new(18,25)
        $descriptionLabel.AutoSize = $true
        $row.Controls.Add($descriptionLabel)

        $button = New-Object System.Windows.Forms.Button
        $button.Text = $ButtonText
        $button.Font = New-Object System.Drawing.Font('Segoe UI',8.5)
        $button.Size = [System.Drawing.Size]::new(118,28)
        $button.Location = [System.Drawing.Point]::new(760,11)
        $button.FlatStyle = [System.Windows.Forms.FlatStyle]::System
        $row.Controls.Add($button)

        $separator = New-Object System.Windows.Forms.Panel
        $separator.BackColor = [System.Drawing.Color]::FromArgb(232,232,232)
        $separator.Location = [System.Drawing.Point]::new(18,49)
        $separator.Size = [System.Drawing.Size]::new(860,1)
        $row.Controls.Add($separator)

        [pscustomobject]@{
            Panel = $row
            Button = $button
            Title = $titleLabel
            Description = $descriptionLabel
        }
    }

    $ui = @{}
    $script:WdlGuiBusy = $false
    $script:WdlGuiLocalAssociation = $null
    $script:WdlGuiCloudStatus = $null

    $deviceCard = New-Card -Title 'Device' -X 28 -Y 92 -Width 500 -Height 176
    $localCard = New-Card -Title 'Local association' -X 544 -Y 92 -Width 500 -Height 176

    $ui.Manufacturer = New-ValuePair -Parent $deviceCard -Caption 'Manufacturer' -Y 48
    $ui.Model        = New-ValuePair -Parent $deviceCard -Caption 'Model' -Y 78
    $ui.Serial       = New-ValuePair -Parent $deviceCard -Caption 'Serial number' -Y 108
    $ui.Runtime      = New-ValuePair -Parent $deviceCard -Caption 'Runtime' -Y 138

    $ui.Firmware   = New-ValuePair -Parent $localCard -Caption 'Firmware state' -Y 48
    $ui.LocalState = New-ValuePair -Parent $localCard -Caption 'Local state' -Y 78
    $ui.TenantId   = New-ValuePair -Parent $localCard -Caption 'Tenant ID' -Y 108
    $ui.Trust      = New-ValuePair -Parent $localCard -Caption 'Trust / source' -Y 138

    $cloudCard = New-Card -Title 'Cloud association' -X 28 -Y 282 -Width 1016 -Height 112
    $ui.CloudState  = New-ValuePair -Parent $cloudCard -Caption 'Association state' -Y 48
    $ui.CloudTenant = New-ValuePair -Parent $cloudCard -Caption 'Tenant ID' -Y 78

    $cloudIdCaption = New-Object System.Windows.Forms.Label
    $cloudIdCaption.Text = 'Association ID'
    $cloudIdCaption.Font = New-Object System.Drawing.Font('Segoe UI',8.5)
    $cloudIdCaption.ForeColor = [System.Drawing.Color]::FromArgb(96,96,96)
    $cloudIdCaption.Location = [System.Drawing.Point]::new(520,48)
    $cloudIdCaption.Size = [System.Drawing.Size]::new(115,20)
    $cloudCard.Controls.Add($cloudIdCaption)

    $ui.CloudId = New-Object System.Windows.Forms.Label
    $ui.CloudId.Text = '-'
    $ui.CloudId.Font = New-Object System.Drawing.Font('Segoe UI',9,[System.Drawing.FontStyle]::Bold)
    $ui.CloudId.Location = [System.Drawing.Point]::new(638,47)
    $ui.CloudId.Size = [System.Drawing.Size]::new(350,28)
    $ui.CloudId.AutoEllipsis = $true
    $cloudCard.Controls.Add($ui.CloudId)

    $tenantCaption = New-Object System.Windows.Forms.Label
    $tenantCaption.Text = 'Tenant override'
    $tenantCaption.Font = New-Object System.Drawing.Font('Segoe UI',8.5)
    $tenantCaption.ForeColor = [System.Drawing.Color]::FromArgb(96,96,96)
    $tenantCaption.Location = [System.Drawing.Point]::new(520,78)
    $tenantCaption.Size = [System.Drawing.Size]::new(115,20)
    $cloudCard.Controls.Add($tenantCaption)

    $tenantBox = New-Object System.Windows.Forms.TextBox
    $tenantBox.Location = [System.Drawing.Point]::new(638,75)
    $tenantBox.Size = [System.Drawing.Size]::new(350,24)
    $tenantBox.Font = New-Object System.Drawing.Font('Consolas',8.5)
    $cloudCard.Controls.Add($tenantBox)

    $recommendedCard = New-Card -Title '' -X 28 -Y 408 -Width 1016 -Height 78

    $recommendedTag = New-Object System.Windows.Forms.Label
    $recommendedTag.Text = 'Recommended action'
    $recommendedTag.Font = New-Object System.Drawing.Font('Segoe UI',8,[System.Drawing.FontStyle]::Bold)
    $recommendedTag.ForeColor = [System.Drawing.SystemColors]::Highlight
    $recommendedTag.Location = [System.Drawing.Point]::new(18,12)
    $recommendedTag.AutoSize = $true
    $recommendedCard.Controls.Add($recommendedTag)

    $recommendedTitle = New-Object System.Windows.Forms.Label
    $recommendedTitle.Text = 'Check local state'
    $recommendedTitle.Font = New-Object System.Drawing.Font('Segoe UI',11,[System.Drawing.FontStyle]::Bold)
    $recommendedTitle.Location = [System.Drawing.Point]::new(18,34)
    $recommendedTitle.AutoSize = $true
    $recommendedCard.Controls.Add($recommendedTitle)

    $recommendedDescription = New-Object System.Windows.Forms.Label
    $recommendedDescription.Text = 'Refresh the device state to determine the next recommended step.'
    $recommendedDescription.Font = New-Object System.Drawing.Font('Segoe UI',8.5)
    $recommendedDescription.ForeColor = [System.Drawing.Color]::FromArgb(96,96,96)
    $recommendedDescription.Location = [System.Drawing.Point]::new(20,58)
    $recommendedDescription.AutoSize = $true
    $recommendedCard.Controls.Add($recommendedDescription)

    $recommendedButton = New-Object System.Windows.Forms.Button
    $recommendedButton.Text = 'Refresh'
    $recommendedButton.Font = New-Object System.Drawing.Font('Segoe UI',9,[System.Drawing.FontStyle]::Bold)
    $recommendedButton.Size = [System.Drawing.Size]::new(150,34)
    $recommendedButton.Location = [System.Drawing.Point]::new(840,26)
    $recommendedCard.Controls.Add($recommendedButton)

    $actionsTitle = New-Object System.Windows.Forms.Label
    $actionsTitle.Text = 'Actions'
    $actionsTitle.Font = New-Object System.Drawing.Font('Segoe UI',13,[System.Drawing.FontStyle]::Bold)
    $actionsTitle.Location = [System.Drawing.Point]::new(30,500)
    $actionsTitle.AutoSize = $true
    $content.Controls.Add($actionsTitle)

    $actionsPanel = New-Card -Title '' -X 28 -Y 532 -Width 1016 -Height 202
    $rowRefresh  = New-ActionRow -Parent $actionsPanel -Title 'Refresh local state' -Description 'Re-read firmware, runtime and local tenant correlation.' -Y 0 -ButtonText 'Refresh'
    $rowIdentity = New-ActionRow -Parent $actionsPanel -Title 'Load DeviceLink identity' -Description 'Generate/read the current DeviceLink identity if needed.' -Y 50 -ButtonText 'Load identity'
    $rowOnline   = New-ActionRow -Parent $actionsPanel -Title 'Check cloud association' -Description 'Query the tenant-side Device Association using Interactive authentication.' -Y 100 -ButtonText 'Check online'
    $rowExport   = New-ActionRow -Parent $actionsPanel -Title 'Export DeviceLink CSV' -Description 'Export the Microsoft-generated .devicelink.csv for this device.' -Y 150 -ButtonText 'Export CSV'

    $advancedTitle = New-Object System.Windows.Forms.Label
    $advancedTitle.Text = 'Advanced / lifecycle'
    $advancedTitle.Font = New-Object System.Drawing.Font('Segoe UI',13,[System.Drawing.FontStyle]::Bold)
    $advancedTitle.Location = [System.Drawing.Point]::new(30,750)
    $advancedTitle.AutoSize = $true
    $content.Controls.Add($advancedTitle)

    $advancedPanel = New-Card -Title '' -X 28 -Y 782 -Width 1016 -Height 152
    $rowRegister = New-ActionRow -Parent $advancedPanel -Title 'Create pre-association' -Description 'Create the tenant-side Device Association pre-association.' -Y 0 -ButtonText 'Pre-associate'
    $rowComplete = New-ActionRow -Parent $advancedPanel -Title 'Complete association' -Description 'Run native DeviceLink completion and verify the final local state.' -Y 50 -ButtonText 'Complete'
    $rowOffboard = New-ActionRow -Parent $advancedPanel -Title 'Offboarding' -Description 'Remove cloud association or reset local DeviceLink state.' -Y 100 -ButtonText 'Options...'

    $activityTitle = New-Object System.Windows.Forms.Label
    $activityTitle.Text = 'Activity'
    $activityTitle.Font = New-Object System.Drawing.Font('Segoe UI',13,[System.Drawing.FontStyle]::Bold)
    $activityTitle.Location = [System.Drawing.Point]::new(30,950)
    $activityTitle.AutoSize = $true
    $content.Controls.Add($activityTitle)

    $activityCard = New-Card -Title '' -X 28 -Y 982 -Width 1016 -Height 168

    $consoleBox = New-Object System.Windows.Forms.TextBox
    $consoleBox.Location = [System.Drawing.Point]::new(16,14)
    $consoleBox.Size = [System.Drawing.Size]::new(982,136)
    $consoleBox.Multiline = $true
    $consoleBox.ReadOnly = $true
    $consoleBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $consoleBox.WordWrap = $false
    $consoleBox.Font = New-Object System.Drawing.Font('Consolas',8.5)
    $consoleBox.BackColor = [System.Drawing.Color]::FromArgb(250,250,250)
    $consoleBox.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $activityCard.Controls.Add($consoleBox)

    $content.AutoScrollMinSize = [System.Drawing.Size]::new(0,1185)

    $statusStrip = New-Object System.Windows.Forms.StatusStrip
    $statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
    $statusLabel.Text = 'Ready'
    $statusLabel.Spring = $true
    $statusLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft

    $statusProgress = New-Object System.Windows.Forms.ToolStripProgressBar
    $statusProgress.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
    $statusProgress.MarqueeAnimationSpeed = 30
    $statusProgress.Size = [System.Drawing.Size]::new(150,16)
    $statusProgress.Visible = $false

    [void]$statusStrip.Items.Add($statusLabel)
    [void]$statusStrip.Items.Add($statusProgress)
    $form.Controls.Add($statusStrip)

    $offboardingMenu = New-Object System.Windows.Forms.ContextMenuStrip
    $menuRemoveCloud = $offboardingMenu.Items.Add('Remove cloud association')
    $menuResetLocal = $offboardingMenu.Items.Add('Reset local DeviceLink state')

    function Set-GuiStatus {
        param([string]$Text)
        $statusLabel.Text = $Text
        [System.Windows.Forms.Application]::DoEvents()
    }

    function Write-GuiConsole {
        param([AllowNull()][AllowEmptyString()][string]$Message,[switch]$Command,[switch]$ErrorMessage)

        if ([string]::IsNullOrWhiteSpace($Message)) { return }

        $timestamp = (Get-Date).ToString('HH:mm:ss')
        $prefix = if ($Command) { '>' } elseif ($ErrorMessage) { '!' } else { '-' }
        $line = "[$timestamp] $prefix $Message"

        $consoleBox.AppendText($line + [Environment]::NewLine)
        $consoleBox.SelectionStart = $consoleBox.TextLength
        $consoleBox.ScrollToCaret()
        [System.Windows.Forms.Application]::DoEvents()
        Write-Host $line
    }

    function Write-GuiObject {
        param($InputObject)
        if ($null -eq $InputObject) { return }

        $text = ($InputObject | Format-List * | Out-String).TrimEnd()
        if ([string]::IsNullOrWhiteSpace($text)) { return }

        foreach ($line in ($text -split '\r?\n')) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            Write-GuiConsole -Message $line
        }
    }

    function Show-GuiError {
        param([string]$Message)
        Write-GuiConsole -Message $Message -ErrorMessage
        [void][System.Windows.Forms.MessageBox]::Show(
            $form,$Message,'WindowsDeviceLink',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
    }

    function Confirm-GuiAction {
        param([string]$Title,[string]$Message)
        ([System.Windows.Forms.MessageBox]::Show(
            $form,$Message,$Title,
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) -eq [System.Windows.Forms.DialogResult]::Yes)
    }

    $actionControls = @(
        $rowRefresh.Button,$rowIdentity.Button,$rowOnline.Button,$rowExport.Button,
        $rowRegister.Button,$rowComplete.Button,$rowOffboard.Button,$recommendedButton,$tenantBox
    )

    function Set-GuiBusy {
        param([Parameter(Mandatory)][bool]$Busy,[string]$StatusText)

        $script:WdlGuiBusy = $Busy
        foreach ($control in $actionControls) { $control.Enabled = -not $Busy }

        $statusProgress.Visible = $Busy
        $form.UseWaitCursor = $Busy

        if (-not [string]::IsNullOrWhiteSpace($StatusText)) { Set-GuiStatus $StatusText }
        [System.Windows.Forms.Application]::DoEvents()
    }

    function Get-TenantOverride {
        $value = $tenantBox.Text.Trim()
        if ($value) { return $value }
        if ($script:WdlGuiLocalAssociation -and $script:WdlGuiLocalAssociation.TenantId) {
            return [string]$script:WdlGuiLocalAssociation.TenantId
        }
        $null
    }

    function Update-Recommendation {
        $local = $script:WdlGuiLocalAssociation
        $cloud = $script:WdlGuiCloudStatus

        if (-not $local) {
            $recommendedTitle.Text = 'Refresh local state'
            $recommendedDescription.Text = 'Read the current DeviceLink state before taking another action.'
            $recommendedButton.Text = 'Refresh'
            $recommendedButton.Tag = 'Refresh'
            return
        }

        if ($local.FirmwareState -eq '0/4') {
            $recommendedTitle.Text = 'Load DeviceLink identity'
            $recommendedDescription.Text = 'No current DeviceLink identity exists. Create/read the base identity first.'
            $recommendedButton.Text = 'Load identity'
            $recommendedButton.Tag = 'Identity'
            return
        }

        if (-not $cloud) {
            $recommendedTitle.Text = 'Check cloud association'
            $recommendedDescription.Text = 'Local state is available. Check tenant-side state before changing the lifecycle.'
            $recommendedButton.Text = 'Check online'
            $recommendedButton.Tag = 'Online'
            return
        }

        if ($cloud.AssociationPresent -and [string]$cloud.AssociationState -ieq 'preassociated' -and $local.FirmwareState -eq '2/4') {
            $recommendedTitle.Text = 'Complete Device Association'
            $recommendedDescription.Text = 'The device is pre-associated and local firmware is ready for native completion.'
            $recommendedButton.Text = 'Complete'
            $recommendedButton.Tag = 'Complete'
            return
        }

        if (-not $cloud.AssociationPresent -and $local.FirmwareState -eq '2/4') {
            $recommendedTitle.Text = 'Create pre-association'
            $recommendedDescription.Text = 'The local identity exists, but no tenant-side Device Association was found.'
            $recommendedButton.Text = 'Pre-associate'
            $recommendedButton.Tag = 'Register'
            return
        }

        if ($local.FirmwareState -eq '4/4') {
            $recommendedTitle.Text = 'Association locally complete'
            $recommendedDescription.Text = 'Local DeviceLink state is complete. Refresh or check online for verification.'
            $recommendedButton.Text = 'Refresh'
            $recommendedButton.Tag = 'Refresh'
            return
        }

        $recommendedTitle.Text = 'Review current state'
        $recommendedDescription.Text = 'The current lifecycle state does not map to a single recommended mutation.'
        $recommendedButton.Text = 'Refresh'
        $recommendedButton.Tag = 'Refresh'
    }

    function Refresh-LocalView {
        Set-GuiStatus 'Refreshing local state...'
        Write-GuiConsole -Message 'Refresh local state' -Command

        $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $support = Test-WindowsDeviceLinkSupport
        $local = Get-WindowsDeviceLinkLocalAssociation
        $script:WdlGuiLocalAssociation = $local

        $ui.Manufacturer.Text = [string]$cs.Manufacturer
        $ui.Model.Text = [string]$cs.Model
        $ui.Serial.Text = [string]$bios.SerialNumber

        if ($support.Supported) {
            $runtimeText = "$($support.Environment) | $($support.ActivationMode)"
            if ($support.DllVersion) { $runtimeText += " | $($support.DllVersion)" }
            $ui.Runtime.Text = $runtimeText
        }
        else {
            $ui.Runtime.Text = "Unsupported: $($support.Reason)"
        }

        $ui.Firmware.Text = [string]$local.FirmwareState
        $ui.LocalState.Text = [string]$local.LocalAssociationState
        $ui.TenantId.Text = if ($local.TenantId) { [string]$local.TenantId } else { 'Unavailable' }
        $ui.Trust.Text = "$($local.TrustLevel) | $($local.Source)"

        Set-GuiStatus "Local state refreshed | $($local.FirmwareState) | $($local.TrustLevel)"
        Write-GuiConsole -Message "Local state: $($local.FirmwareState), tenant source: $($local.Source), trust: $($local.TrustLevel)"
        Update-Recommendation
    }

    function Invoke-GuiRefresh {
        if ($script:WdlGuiBusy) { return }
        Set-GuiBusy -Busy $true -StatusText 'Refreshing local state...'
        try { Refresh-LocalView }
        catch { Show-GuiError $_.Exception.Message }
        finally { Set-GuiBusy -Busy $false }
    }

    function Invoke-GuiIdentity {
        if ($script:WdlGuiBusy) { return }
        Set-GuiBusy -Busy $true -StatusText 'Loading DeviceLink identity...'
        try {
            Write-GuiConsole -Message 'Get-WindowsDeviceLink' -Command
            $identity = Get-WindowsDeviceLink
            Write-GuiObject $identity
            Refresh-LocalView
        }
        catch { Show-GuiError $_.Exception.Message }
        finally { Set-GuiBusy -Busy $false }
    }

    function Invoke-GuiOnline {
        if ($script:WdlGuiBusy) { return }
        Set-GuiBusy -Busy $true -StatusText 'Checking tenant-side Device Association...'
        try {
            $parameters = @{ Online=$true; Method='Interactive' }
            $tenant = Get-TenantOverride
            if ($tenant) { $parameters.TenantId = $tenant }

            $displayTenant = if ($parameters.ContainsKey('TenantId')) { " -TenantId $($parameters.TenantId)" } else { '' }
            Write-GuiConsole -Message "Get-WindowsDeviceLinkStatus -Online -Method Interactive$displayTenant" -Command

            $cloud = Get-WindowsDeviceLinkStatus @parameters
            $script:WdlGuiCloudStatus = $cloud
            Write-GuiObject $cloud

            $ui.CloudState.Text = [string]$cloud.AssociationState
            $ui.CloudTenant.Text = if ($cloud.TenantId) { [string]$cloud.TenantId } else { '-' }
            $ui.CloudId.Text = if ($cloud.AssociationId) { [string]$cloud.AssociationId } else { '-' }

            Set-GuiStatus 'Cloud lookup completed'
            Update-Recommendation
        }
        catch {
            Set-GuiStatus 'Cloud lookup failed'
            Show-GuiError $_.Exception.Message
        }
        finally { Set-GuiBusy -Busy $false }
    }

    function Invoke-GuiExport {
        if ($script:WdlGuiBusy) { return }

        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = 'Choose a folder for the DeviceLink CSV'
        try {
            if ($dialog.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) { return }

            Set-GuiBusy -Busy $true -StatusText 'Exporting DeviceLink CSV...'
            Write-GuiConsole -Message "Get-WindowsDeviceLink -OutputDirectory '$($dialog.SelectedPath)'" -Command

            $file = Get-WindowsDeviceLink -OutputDirectory $dialog.SelectedPath
            Write-GuiObject $file
            Set-GuiStatus "CSV exported: $($file.FullName)"

            [void][System.Windows.Forms.MessageBox]::Show(
                $form,
                ('Exported to:' + [Environment]::NewLine + $file.FullName),
                'WindowsDeviceLink',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )

            Refresh-LocalView
        }
        catch { Show-GuiError $_.Exception.Message }
        finally {
            Set-GuiBusy -Busy $false
            $dialog.Dispose()
        }
    }

    function Invoke-GuiRegister {
        if ($script:WdlGuiBusy) { return }
        if (-not (Confirm-GuiAction -Title 'Create pre-association' -Message 'Create or attempt a tenant-side Device Association pre-association for this device?')) { return }

        Set-GuiBusy -Busy $true -StatusText 'Creating tenant-side pre-association...'
        try {
            $identity = Get-WindowsDeviceLink
            $parameters = @{ Method='Interactive'; Confirm=$false }
            $tenant = $tenantBox.Text.Trim()
            if ($tenant) { $parameters.TenantId = $tenant }

            $displayTenant = if ($parameters.ContainsKey('TenantId')) { " -TenantId $($parameters.TenantId)" } else { '' }
            Write-GuiConsole -Message "Get-WindowsDeviceLink | Register-WindowsDeviceLink -Method Interactive$displayTenant" -Command

            $result = $identity | Register-WindowsDeviceLink @parameters
            Write-GuiObject $result
            Set-GuiStatus "Pre-association completed: $($result.AssociationState)"
            $script:WdlGuiCloudStatus = $null
            Refresh-LocalView
        }
        catch { Show-GuiError $_.Exception.Message }
        finally { Set-GuiBusy -Busy $false }
    }

    function Invoke-GuiComplete {
        if ($script:WdlGuiBusy) { return }
        if (-not (Confirm-GuiAction -Title 'Complete association' -Message 'Run native DeviceLink association completion now? This can take one or more minutes and changes local DeviceLink state.')) { return }

        Set-GuiBusy -Busy $true -StatusText 'Completing DeviceLink association...'
        try {
            Write-GuiConsole -Message 'Complete-WindowsDeviceLinkAssociation -Confirm:$false' -Command
            $resultObjects = New-Object System.Collections.Generic.List[object]

            & {
                Complete-WindowsDeviceLinkAssociation -Confirm:$false
            } 6>&1 | ForEach-Object {
                if ($_ -is [System.Management.Automation.InformationRecord]) {
                    $message = [string]$_.MessageData
                    if (-not [string]::IsNullOrWhiteSpace($message)) {
                        Write-GuiConsole -Message $message
                    }
                }
                else {
                    $resultObjects.Add($_)
                }
                [System.Windows.Forms.Application]::DoEvents()
            }

            $result = @($resultObjects.ToArray()) | Select-Object -Last 1
            Write-GuiObject $result
            Set-GuiStatus 'Association completion finished'
            $script:WdlGuiCloudStatus = $null
            Refresh-LocalView
        }
        catch { Show-GuiError $_.Exception.Message }
        finally { Set-GuiBusy -Busy $false }
    }

    function Invoke-GuiRemoveCloud {
        if ($script:WdlGuiBusy) { return }
        if (-not (Confirm-GuiAction -Title 'Remove cloud association' -Message 'Delete the tenant-side Device Association record? Local DeviceLink firmware is not reset.')) { return }

        Set-GuiBusy -Busy $true -StatusText 'Removing tenant-side Device Association...'
        try {
            $parameters = @{ Method='Interactive'; Confirm=$false }
            $tenant = Get-TenantOverride
            if ($tenant) { $parameters.TenantId = $tenant }

            $displayTenant = if ($parameters.ContainsKey('TenantId')) { " -TenantId $($parameters.TenantId)" } else { '' }
            Write-GuiConsole -Message ("Remove-WindowsDeviceLinkAssociation -Method Interactive" + $displayTenant + " -Confirm:False") -Command

            $result = Remove-WindowsDeviceLinkAssociation @parameters
            Write-GuiObject $result
            $script:WdlGuiCloudStatus = $null
            $ui.CloudState.Text = 'Not checked'
            $ui.CloudTenant.Text = '-'
            $ui.CloudId.Text = '-'
            Refresh-LocalView
        }
        catch { Show-GuiError $_.Exception.Message }
        finally { Set-GuiBusy -Busy $false }
    }

    function Invoke-GuiResetLocal {
        if ($script:WdlGuiBusy) { return }
        if (-not (Confirm-GuiAction -Title 'Reset local DeviceLink state' -Message 'Remove all known local DeviceLink UEFI variables? This does not delete the cloud Device Association record.')) { return }

        Set-GuiBusy -Busy $true -StatusText 'Resetting local DeviceLink firmware state...'
        try {
            Write-GuiConsole -Message 'Reset-WindowsDeviceLinkFirmwareState -Confirm:$false' -Command
            $result = Reset-WindowsDeviceLinkFirmwareState -Confirm:$false
            Write-GuiObject $result
            $script:WdlGuiCloudStatus = $null
            Refresh-LocalView
        }
        catch { Show-GuiError $_.Exception.Message }
        finally { Set-GuiBusy -Busy $false }
    }

    $rowRefresh.Button.Add_Click({ Invoke-GuiRefresh })
    $rowIdentity.Button.Add_Click({ Invoke-GuiIdentity })
    $rowOnline.Button.Add_Click({ Invoke-GuiOnline })
    $rowExport.Button.Add_Click({ Invoke-GuiExport })
    $rowRegister.Button.Add_Click({ Invoke-GuiRegister })
    $rowComplete.Button.Add_Click({ Invoke-GuiComplete })

    $rowOffboard.Button.Add_Click({
        if ($script:WdlGuiBusy) { return }
        $offboardingMenu.Show($rowOffboard.Button,0,$rowOffboard.Button.Height)
    })

    $menuRemoveCloud.Add_Click({ Invoke-GuiRemoveCloud })
    $menuResetLocal.Add_Click({ Invoke-GuiResetLocal })

    $recommendedButton.Add_Click({
        if ($script:WdlGuiBusy) { return }
        switch ([string]$recommendedButton.Tag) {
            'Identity' { Invoke-GuiIdentity }
            'Online'   { Invoke-GuiOnline }
            'Register' { Invoke-GuiRegister }
            'Complete' { Invoke-GuiComplete }
            default    { Invoke-GuiRefresh }
        }
    })

    $form.Add_FormClosing({
        param($sender,$eventArgs)
        if ($script:WdlGuiBusy) {
            $eventArgs.Cancel = $true
            Write-GuiConsole -Message 'Close request ignored because an operation is still running.'
        }
    })

    $form.Add_Shown({
        Write-GuiConsole -Message 'WindowsDeviceLink operator dashboard opened.'
        Set-GuiBusy -Busy $true -StatusText 'Loading local state...'
        try { Refresh-LocalView }
        catch { Show-GuiError $_.Exception.Message }
        finally { Set-GuiBusy -Busy $false }
    })

    function Resize-GuiLayout {
        $viewportWidth = [Math]::Max(780,$content.ClientSize.Width - 56)
        $fullWidth = $viewportWidth
        $gap = 16
        $halfWidth = [Math]::Floor(($fullWidth - $gap) / 2)

        if ($fullWidth -ge 900) {
            $deviceCard.Location = [System.Drawing.Point]::new(28,92)
            $deviceCard.Size = [System.Drawing.Size]::new([int]$halfWidth,176)
            $localCard.Location = [System.Drawing.Point]::new((28 + $halfWidth + $gap),92)
            $localCard.Size = [System.Drawing.Size]::new([int]$halfWidth,176)
            $topBottom = 282
        }
        else {
            $deviceCard.Location = [System.Drawing.Point]::new(28,92)
            $deviceCard.Size = [System.Drawing.Size]::new([int]$fullWidth,176)
            $localCard.Location = [System.Drawing.Point]::new(28,282)
            $localCard.Size = [System.Drawing.Size]::new([int]$fullWidth,176)
            $topBottom = 472
        }

        $cloudCard.Location = [System.Drawing.Point]::new(28,$topBottom)
        $cloudCard.Width = $fullWidth

        $recommendedY = $topBottom + 124
        $recommendedCard.Location = [System.Drawing.Point]::new(28,$recommendedY)
        $recommendedCard.Width = $fullWidth
        $recommendedButton.Left = [Math]::Max(620,$fullWidth - 176)

        $actionsY = $recommendedY + 94
        $actionsTitle.Location = [System.Drawing.Point]::new(30,$actionsY)
        $actionsPanel.Location = [System.Drawing.Point]::new(28,($actionsY + 34))
        $actionsPanel.Width = $fullWidth

        $advancedY = $actionsY + 250
        $advancedTitle.Location = [System.Drawing.Point]::new(30,$advancedY)
        $advancedPanel.Location = [System.Drawing.Point]::new(28,($advancedY + 34))
        $advancedPanel.Width = $fullWidth

        $activityY = $advancedY + 200
        $activityTitle.Location = [System.Drawing.Point]::new(30,$activityY)
        $activityCard.Location = [System.Drawing.Point]::new(28,($activityY + 34))
        $activityCard.Width = $fullWidth
        $consoleBox.Width = $fullWidth - 34

        foreach ($row in @($rowRefresh,$rowIdentity,$rowOnline,$rowExport,$rowRegister,$rowComplete,$rowOffboard)) {
            $row.Panel.Width = $fullWidth - 2
            $row.Button.Left = [Math]::Max(600,$fullWidth - 140)
        }

        $content.AutoScrollMinSize = [System.Drawing.Size]::new(0,([int]$activityY + 230))
    }

    $form.Add_Resize({ Resize-GuiLayout })

    try {
        Resize-GuiLayout
        [void]$form.ShowDialog()
    }
    finally {
        $form.Dispose()
        Remove-Variable WdlGuiLocalAssociation -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable WdlGuiCloudStatus -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable WdlGuiBusy -Scope Script -ErrorAction SilentlyContinue
    }
}
