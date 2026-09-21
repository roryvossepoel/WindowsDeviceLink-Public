function Show-WindowsDeviceLink {
    <#
    .SYNOPSIS
    Opens the WindowsDeviceLink operator dashboard.

    .DESCRIPTION
    Opens a compact Windows 11 Settings-inspired WinForms dashboard on full Windows.

    The GUI focuses on inspecting Device Association state, onboarding the device, and fully
    offboarding DeviceLink state. All lifecycle actions delegate to existing WindowsDeviceLink
    public cmdlets.

    Interactive authentication is the default. Specify -Method and the corresponding
    authentication parameters when another supported authentication flow is required.

    .EXAMPLE
    Show-WindowsDeviceLink

    .EXAMPLE
    Show-WindowsDeviceLink -Method DeviceCode
    #>
    [CmdletBinding()]
    param(
        [ValidateSet(
            'DeviceCode','Interactive','ClientSecret','AccessToken','Certificate',
            'CertificateThumbprint','CertificateSubjectName','EnvironmentVariable','ManagedIdentity'
        )]
        [string]$Method = 'Interactive',

        [ValidateNotNullOrEmpty()][string]$TenantId,
        [ValidateNotNullOrEmpty()][string]$ClientId,
        [securestring]$AccessToken,
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
        [ValidateNotNullOrEmpty()][string]$CertificateThumbprint,
        [ValidateNotNullOrEmpty()][string]$CertificateSubjectName,
        [bool]$SendCertificateChain = $false,
        [securestring]$ClientSecret,
        [ValidateNotNullOrEmpty()][string]$Environment = 'Global',
        [ValidateRange(1,600)][double]$ClientTimeout = 100
    )

    if (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT') {
        throw 'Show-WindowsDeviceLink is not supported in Windows PE yet. Use the WindowsDeviceLink command-line cmdlets instead.'
    }

    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    [System.Windows.Forms.Application]::EnableVisualStyles()

    $workingArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $targetWidth = [Math]::Max(820,[Math]::Min(1080,$workingArea.Width - 32))
    $targetHeight = [Math]::Max(620,[Math]::Min(790,$workingArea.Height - 40))

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

    function New-Card {
        param([string]$Title,[int]$X,[int]$Y,[int]$Width,[int]$Height)

        $panel = New-Object System.Windows.Forms.Panel
        $panel.Location = [System.Drawing.Point]::new($X,$Y)
        $panel.Size = [System.Drawing.Size]::new($Width,$Height)
        $panel.BackColor = [System.Drawing.Color]::White
        $panel.BorderStyle = [System.Windows.Forms.BorderStyle]::None
        $content.Controls.Add($panel)

        if ($Title) {
            $label = New-Object System.Windows.Forms.Label
            $label.Text = $Title
            $label.Font = New-Object System.Drawing.Font('Segoe UI',10,[System.Drawing.FontStyle]::Bold)
            $label.Location = [System.Drawing.Point]::new(16,10)
            $label.AutoSize = $true
            $panel.Controls.Add($label)
        }

        $panel
    }

    function New-ValuePair {
        param([System.Windows.Forms.Control]$Parent,[string]$Caption,[int]$Y,[int]$CaptionWidth = 120)

        $captionLabel = New-Object System.Windows.Forms.Label
        $captionLabel.Text = $Caption
        $captionLabel.Font = New-Object System.Drawing.Font('Segoe UI',8)
        $captionLabel.ForeColor = [System.Drawing.Color]::FromArgb(105,105,105)
        $captionLabel.Location = [System.Drawing.Point]::new(16,$Y)
        $captionLabel.Size = [System.Drawing.Size]::new($CaptionWidth,18)
        $Parent.Controls.Add($captionLabel)

        $valueLabel = New-Object System.Windows.Forms.Label
        $valueLabel.Text = '-'
        $valueLabel.Font = New-Object System.Drawing.Font('Segoe UI',8.5,[System.Drawing.FontStyle]::Bold)
        $valueLabel.Location = [System.Drawing.Point]::new(($CaptionWidth + 22),($Y - 1))
        $valueLabel.Size = [System.Drawing.Size]::new(330,24)
        $valueLabel.AutoEllipsis = $true
        $Parent.Controls.Add($valueLabel)

        $valueLabel
    }

    function New-ActionRow {
        param(
            [System.Windows.Forms.Control]$Parent,
            [string]$Title,
            [string]$Description,
            [int]$Y,
            [string]$ButtonText
        )

        $row = New-Object System.Windows.Forms.Panel
        $row.Location = [System.Drawing.Point]::new(0,$Y)
        $row.Size = [System.Drawing.Size]::new(900,46)
        $row.BackColor = [System.Drawing.Color]::White
        $Parent.Controls.Add($row)

        $titleLabel = New-Object System.Windows.Forms.Label
        $titleLabel.Text = $Title
        $titleLabel.Font = New-Object System.Drawing.Font('Segoe UI',8.5,[System.Drawing.FontStyle]::Bold)
        $titleLabel.Location = [System.Drawing.Point]::new(16,5)
        $titleLabel.AutoSize = $true
        $row.Controls.Add($titleLabel)

        $descriptionLabel = New-Object System.Windows.Forms.Label
        $descriptionLabel.Text = $Description
        $descriptionLabel.Font = New-Object System.Drawing.Font('Segoe UI',7.8)
        $descriptionLabel.ForeColor = [System.Drawing.Color]::FromArgb(108,108,108)
        $descriptionLabel.Location = [System.Drawing.Point]::new(16,23)
        $descriptionLabel.AutoSize = $true
        $row.Controls.Add($descriptionLabel)

        $button = New-Object System.Windows.Forms.Button
        $button.Text = $ButtonText
        $button.Font = New-Object System.Drawing.Font('Segoe UI',8.3)
        $button.Size = [System.Drawing.Size]::new(118,28)
        $button.Location = [System.Drawing.Point]::new(760,9)
        $button.FlatStyle = [System.Windows.Forms.FlatStyle]::System
        $row.Controls.Add($button)

        $separator = New-Object System.Windows.Forms.Panel
        $separator.BackColor = [System.Drawing.Color]::FromArgb(232,232,232)
        $separator.Location = [System.Drawing.Point]::new(16,45)
        $separator.Size = [System.Drawing.Size]::new(860,1)
        $row.Controls.Add($separator)

        [pscustomobject]@{ Panel=$row; Button=$button }
    }

    function Get-GuiAuthParameters {
        $parameters = @{
            Method = $Method
            Environment = $Environment
            ClientTimeout = $ClientTimeout
        }

        foreach ($name in @(
            'TenantId','ClientId','AccessToken','Certificate','CertificateThumbprint',
            'CertificateSubjectName','SendCertificateChain','ClientSecret'
        )) {
            if ($PSBoundParameters.ContainsKey($name)) {
                $parameters[$name] = $PSBoundParameters[$name]
            }
        }

        $parameters
    }

    $ui = @{}
    $script:WdlGuiBusy = $false
    $script:WdlGuiLocalAssociation = $null
    $script:WdlGuiCloudStatus = $null

    $deviceCard = New-Card -Title 'Device' -X 18 -Y 16 -Width 500 -Height 138
    $associationCard = New-Card -Title 'Association' -X 534 -Y 16 -Width 500 -Height 138

    $ui.DeviceName = New-ValuePair -Parent $deviceCard -Caption 'Device' -Y 38
    $ui.Serial     = New-ValuePair -Parent $deviceCard -Caption 'Serial number' -Y 62
    $ui.Runtime    = New-ValuePair -Parent $deviceCard -Caption 'Runtime' -Y 86
    $ui.Auth       = New-ValuePair -Parent $deviceCard -Caption 'Authentication' -Y 110

    $ui.Firmware   = New-ValuePair -Parent $associationCard -Caption 'Firmware' -Y 38
    $ui.LocalState = New-ValuePair -Parent $associationCard -Caption 'Local state' -Y 62
    $ui.TenantId   = New-ValuePair -Parent $associationCard -Caption 'Tenant ID' -Y 86
    $ui.Source     = New-ValuePair -Parent $associationCard -Caption 'Source' -Y 110

    $cloudCard = New-Card -Title 'Cloud association' -X 18 -Y 168 -Width 1016 -Height 86
    $ui.CloudState  = New-ValuePair -Parent $cloudCard -Caption 'State' -Y 38 -CaptionWidth 95
    $ui.CloudTenant = New-ValuePair -Parent $cloudCard -Caption 'Tenant ID' -Y 62 -CaptionWidth 95

    $cloudIdCaption = New-Object System.Windows.Forms.Label
    $cloudIdCaption.Text = 'Association ID'
    $cloudIdCaption.Font = New-Object System.Drawing.Font('Segoe UI',8)
    $cloudIdCaption.ForeColor = [System.Drawing.Color]::FromArgb(105,105,105)
    $cloudIdCaption.Location = [System.Drawing.Point]::new(520,38)
    $cloudIdCaption.Size = [System.Drawing.Size]::new(105,18)
    $cloudCard.Controls.Add($cloudIdCaption)

    $ui.CloudId = New-Object System.Windows.Forms.Label
    $ui.CloudId.Text = '-'
    $ui.CloudId.Font = New-Object System.Drawing.Font('Segoe UI',8.5,[System.Drawing.FontStyle]::Bold)
    $ui.CloudId.Location = [System.Drawing.Point]::new(628,37)
    $ui.CloudId.Size = [System.Drawing.Size]::new(350,24)
    $ui.CloudId.AutoEllipsis = $true
    $cloudCard.Controls.Add($ui.CloudId)

    $actionsTitle = New-Object System.Windows.Forms.Label
    $actionsTitle.Text = 'Actions'
    $actionsTitle.Font = New-Object System.Drawing.Font('Segoe UI',12,[System.Drawing.FontStyle]::Bold)
    $actionsTitle.Location = [System.Drawing.Point]::new(20,270)
    $actionsTitle.AutoSize = $true
    $content.Controls.Add($actionsTitle)

    $actionsPanel = New-Card -Title '' -X 18 -Y 298 -Width 1016 -Height 232
    $rowRefresh = New-ActionRow -Parent $actionsPanel -Title 'Refresh' -Description 'Refresh local DeviceLink and firmware information.' -Y 0 -ButtonText 'Refresh'
    $rowOnline  = New-ActionRow -Parent $actionsPanel -Title 'Check online' -Description 'Query the current tenant-side Device Association.' -Y 46 -ButtonText 'Check online'
    $rowExport  = New-ActionRow -Parent $actionsPanel -Title 'Export DeviceLink CSV' -Description 'Export the Microsoft-generated .devicelink.csv.' -Y 92 -ButtonText 'Export CSV'
    $rowOnboard = New-ActionRow -Parent $actionsPanel -Title 'Onboard device' -Description 'Ensure pre-association and complete Device Association.' -Y 138 -ButtonText 'Onboard'
    $rowOffboard = New-ActionRow -Parent $actionsPanel -Title 'Full DeviceLink offboarding' -Description 'Remove cloud Device Association and reset local DeviceLink state.' -Y 184 -ButtonText 'Offboard'

    $activityTitle = New-Object System.Windows.Forms.Label
    $activityTitle.Text = 'Activity'
    $activityTitle.Font = New-Object System.Drawing.Font('Segoe UI',12,[System.Drawing.FontStyle]::Bold)
    $activityTitle.Location = [System.Drawing.Point]::new(20,546)
    $activityTitle.AutoSize = $true
    $content.Controls.Add($activityTitle)

    $activityCard = New-Card -Title '' -X 18 -Y 574 -Width 1016 -Height 154

    $consoleBox = New-Object System.Windows.Forms.TextBox
    $consoleBox.Location = [System.Drawing.Point]::new(14,12)
    $consoleBox.Size = [System.Drawing.Size]::new(988,128)
    $consoleBox.Multiline = $true
    $consoleBox.ReadOnly = $true
    $consoleBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $consoleBox.WordWrap = $false
    $consoleBox.Font = New-Object System.Drawing.Font('Consolas',8.3)
    $consoleBox.BackColor = [System.Drawing.Color]::FromArgb(250,250,250)
    $consoleBox.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $activityCard.Controls.Add($consoleBox)

    $content.AutoScrollMinSize = [System.Drawing.Size]::new(0,750)

    $statusStrip = New-Object System.Windows.Forms.StatusStrip
    $statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
    $statusLabel.Text = 'Ready'
    $statusLabel.Spring = $true
    $statusLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft

    $statusProgress = New-Object System.Windows.Forms.ToolStripProgressBar
    $statusProgress.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
    $statusProgress.MarqueeAnimationSpeed = 30
    $statusProgress.Size = [System.Drawing.Size]::new(145,16)
    $statusProgress.Visible = $false

    [void]$statusStrip.Items.Add($statusLabel)
    [void]$statusStrip.Items.Add($statusProgress)
    $form.Controls.Add($statusStrip)

    function Set-GuiStatus {
        param([string]$Text)
        $statusLabel.Text = $Text
        [System.Windows.Forms.Application]::DoEvents()
    }

    function Write-GuiConsole {
        param(
            [AllowNull()][AllowEmptyString()][string]$Message,
            [switch]$Command,
            [switch]$ErrorMessage
        )

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
        $rowRefresh.Button,
        $rowOnline.Button,
        $rowExport.Button,
        $rowOnboard.Button,
        $rowOffboard.Button
    )

    function Set-GuiBusy {
        param([Parameter(Mandatory)][bool]$Busy,[string]$StatusText)

        $script:WdlGuiBusy = $Busy

        foreach ($control in $actionControls) {
            $control.Enabled = -not $Busy
        }

        $statusProgress.Visible = $Busy
        $form.UseWaitCursor = $Busy

        if (-not [string]::IsNullOrWhiteSpace($StatusText)) {
            Set-GuiStatus $StatusText
        }

        [System.Windows.Forms.Application]::DoEvents()
    }

    function Refresh-LocalView {
        Set-GuiStatus 'Refreshing local state...'
        Write-GuiConsole -Message 'Refresh local state' -Command

        $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $support = Test-WindowsDeviceLinkSupport
        $local = Get-WindowsDeviceLinkLocalAssociation

        $script:WdlGuiLocalAssociation = $local

        $ui.DeviceName.Text = "$($cs.Manufacturer) $($cs.Model)".Trim()
        $ui.Serial.Text = [string]$bios.SerialNumber

        if ($support.Supported) {
            $runtimeText = "$($support.ActivationMode)"
            if ($support.DllVersion) { $runtimeText += " | $($support.DllVersion)" }
            $ui.Runtime.Text = $runtimeText
        }
        else {
            $ui.Runtime.Text = "Unsupported: $($support.Reason)"
        }

        $ui.Auth.Text = if ($TenantId) { "$Method | $TenantId" } else { $Method }
        $ui.Firmware.Text = [string]$local.FirmwareState
        $ui.LocalState.Text = [string]$local.LocalAssociationState
        $ui.TenantId.Text = if ($local.TenantId) { [string]$local.TenantId } else { 'Unavailable' }
        $ui.Source.Text = "$($local.TrustLevel) | $($local.Source)"

        Set-GuiStatus "Local state refreshed | $($local.FirmwareState)"
        Write-GuiConsole -Message "Local state: $($local.FirmwareState), tenant source: $($local.Source)"
    }

    function Invoke-GuiRefresh {
        if ($script:WdlGuiBusy) { return }

        Set-GuiBusy -Busy $true -StatusText 'Refreshing local state...'
        try {
            Refresh-LocalView
        }
        catch {
            Show-GuiError $_.Exception.Message
        }
        finally {
            Set-GuiBusy -Busy $false
        }
    }

    function Invoke-GuiOnline {
        if ($script:WdlGuiBusy) { return }

        Set-GuiBusy -Busy $true -StatusText 'Checking tenant-side Device Association...'
        try {
            $parameters = Get-GuiAuthParameters
            $parameters.Online = $true

            Write-GuiConsole -Message "Get-WindowsDeviceLinkStatus -Online -Method $Method" -Command
            $cloud = Get-WindowsDeviceLinkStatus @parameters
            $script:WdlGuiCloudStatus = $cloud
            Write-GuiObject $cloud

            $ui.CloudState.Text = [string]$cloud.AssociationState
            $ui.CloudTenant.Text = if ($cloud.TenantId) { [string]$cloud.TenantId } else { '-' }
            $ui.CloudId.Text = if ($cloud.AssociationId) { [string]$cloud.AssociationId } else { '-' }

            Set-GuiStatus 'Cloud lookup completed'
        }
        catch {
            Set-GuiStatus 'Cloud lookup failed'
            Show-GuiError $_.Exception.Message
        }
        finally {
            Set-GuiBusy -Busy $false
        }
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

            [void][System.Windows.Forms.MessageBox]::Show(
                $form,
                ('Exported to:' + [Environment]::NewLine + $file.FullName),
                'WindowsDeviceLink',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )

            Refresh-LocalView
        }
        catch {
            Show-GuiError $_.Exception.Message
        }
        finally {
            Set-GuiBusy -Busy $false
            $dialog.Dispose()
        }
    }

    function Invoke-GuiOnboard {
        if ($script:WdlGuiBusy) { return }

        if (-not (Confirm-GuiAction -Title 'Onboard device' -Message 'Ensure the tenant-side pre-association exists and complete Device Association on this device?')) {
            return
        }

        Set-GuiBusy -Busy $true -StatusText 'Onboarding device...'
        try {
            $parameters = Get-GuiAuthParameters
            $parameters.CompleteAssociation = $true
            $parameters.Confirm = $false

            Write-GuiConsole -Message "Initialize-WindowsDeviceLink -Method $Method -CompleteAssociation" -Command

            $resultObjects = New-Object System.Collections.Generic.List[object]

            & {
                Initialize-WindowsDeviceLink @parameters
            } 6>&1 | ForEach-Object {
                if ($_ -is [System.Management.Automation.InformationRecord]) {
                    $message = [string]$_.MessageData
                    if ($message) { Write-GuiConsole -Message $message }
                }
                else {
                    $resultObjects.Add($_)
                }
                [System.Windows.Forms.Application]::DoEvents()
            }

            $result = @($resultObjects.ToArray()) | Select-Object -Last 1
            Write-GuiObject $result
            $script:WdlGuiCloudStatus = $null
            Refresh-LocalView

            Set-GuiStatus 'Onboarding completed'
        }
        catch {
            Set-GuiStatus 'Onboarding failed'
            Show-GuiError $_.Exception.Message
        }
        finally {
            Set-GuiBusy -Busy $false
        }
    }

    function Invoke-GuiFullOffboard {
        if ($script:WdlGuiBusy) { return }

        $message = @(
            'This performs full DeviceLink offboarding:'
            ''
            '1. Verify tenant-side Device Association state'
            '2. Remove the cloud Device Association if present'
            '3. Reset all known local DeviceLink UEFI variables'
            ''
            'This does not remove the Entra device or MDM enrollment record.'
            ''
            'Continue?'
        ) -join [Environment]::NewLine

        if (-not (Confirm-GuiAction -Title 'Full DeviceLink offboarding' -Message $message)) {
            return
        }

        Set-GuiBusy -Busy $true -StatusText 'Offboarding DeviceLink...'
        try {
            $auth = Get-GuiAuthParameters
            $statusParameters = @{}
            foreach ($key in $auth.Keys) { $statusParameters[$key] = $auth[$key] }
            $statusParameters.Online = $true

            Write-GuiConsole -Message "Get-WindowsDeviceLinkStatus -Online -Method $Method" -Command
            $cloud = Get-WindowsDeviceLinkStatus @statusParameters
            Write-GuiObject $cloud

            if ($null -eq $cloud.AssociationPresent -or [string]$cloud.AssociationState -eq 'Unknown') {
                throw 'Cloud Device Association state is indeterminate. Local firmware was not reset.'
            }

            if ($cloud.AssociationPresent) {
                $removeParameters = @{}
                foreach ($key in $auth.Keys) { $removeParameters[$key] = $auth[$key] }
                $removeParameters.Confirm = $false

                Write-GuiConsole -Message "Remove-WindowsDeviceLinkAssociation -Method $Method" -Command
                $removed = Remove-WindowsDeviceLinkAssociation @removeParameters
                Write-GuiObject $removed
            }
            else {
                Write-GuiConsole -Message 'No tenant-side Device Association exists. Cloud removal skipped.'
            }

            Write-GuiConsole -Message 'Reset-WindowsDeviceLinkFirmwareState' -Command
            $reset = Reset-WindowsDeviceLinkFirmwareState -Confirm:$false
            Write-GuiObject $reset

            $script:WdlGuiCloudStatus = $null
            $ui.CloudState.Text = 'Not checked'
            $ui.CloudTenant.Text = '-'
            $ui.CloudId.Text = '-'

            Refresh-LocalView
            Set-GuiStatus 'Full DeviceLink offboarding completed'
        }
        catch {
            Set-GuiStatus 'Offboarding failed'
            Show-GuiError $_.Exception.Message
        }
        finally {
            Set-GuiBusy -Busy $false
        }
    }

    $rowRefresh.Button.Add_Click({ Invoke-GuiRefresh })
    $rowOnline.Button.Add_Click({ Invoke-GuiOnline })
    $rowExport.Button.Add_Click({ Invoke-GuiExport })
    $rowOnboard.Button.Add_Click({ Invoke-GuiOnboard })
    $rowOffboard.Button.Add_Click({ Invoke-GuiFullOffboard })

    $form.Add_FormClosing({
        param($sender,$eventArgs)

        if ($script:WdlGuiBusy) {
            $eventArgs.Cancel = $true
            Write-GuiConsole -Message 'Close request ignored because an operation is still running.'
        }
    })

    $form.Add_Shown({
        Write-GuiConsole -Message "WindowsDeviceLink dashboard opened. Authentication method: $Method."
        Set-GuiBusy -Busy $true -StatusText 'Loading local state...'
        try {
            Refresh-LocalView
        }
        catch {
            Show-GuiError $_.Exception.Message
        }
        finally {
            Set-GuiBusy -Busy $false
        }
    })

    function Resize-GuiLayout {
        $fullWidth = [Math]::Max(780,$content.ClientSize.Width - 36)
        $gap = 16
        $halfWidth = [Math]::Floor(($fullWidth - $gap) / 2)

        if ($fullWidth -ge 900) {
            $deviceCard.Location = [System.Drawing.Point]::new(18,16)
            $deviceCard.Size = [System.Drawing.Size]::new([int]$halfWidth,138)
            $associationCard.Location = [System.Drawing.Point]::new((18 + $halfWidth + $gap),16)
            $associationCard.Size = [System.Drawing.Size]::new([int]$halfWidth,138)
            $cloudY = 168
        }
        else {
            $deviceCard.Location = [System.Drawing.Point]::new(18,16)
            $deviceCard.Size = [System.Drawing.Size]::new([int]$fullWidth,138)
            $associationCard.Location = [System.Drawing.Point]::new(18,168)
            $associationCard.Size = [System.Drawing.Size]::new([int]$fullWidth,138)
            $cloudY = 320
        }

        $cloudCard.Location = [System.Drawing.Point]::new(18,$cloudY)
        $cloudCard.Width = $fullWidth

        $actionsY = $cloudY + 102
        $actionsTitle.Location = [System.Drawing.Point]::new(20,$actionsY)
        $actionsPanel.Location = [System.Drawing.Point]::new(18,($actionsY + 28))
        $actionsPanel.Width = $fullWidth

        $activityY = $actionsY + 276
        $activityTitle.Location = [System.Drawing.Point]::new(20,$activityY)
        $activityCard.Location = [System.Drawing.Point]::new(18,($activityY + 28))
        $activityCard.Width = $fullWidth
        $consoleBox.Width = $fullWidth - 28

        foreach ($row in @($rowRefresh,$rowOnline,$rowExport,$rowOnboard,$rowOffboard)) {
            $row.Panel.Width = $fullWidth
            $row.Button.Left = [Math]::Max(600,$fullWidth - 136)
            $row.Panel.Controls |
                Where-Object { $_ -is [System.Windows.Forms.Panel] -and $_.Height -eq 1 } |
                ForEach-Object { $_.Width = [Math]::Max(500,$fullWidth - 32) }
        }

        $content.AutoScrollMinSize = [System.Drawing.Size]::new(0,($activityY + 210))
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
