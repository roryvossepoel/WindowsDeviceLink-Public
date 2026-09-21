function Show-WindowsDeviceLink {
    <#
    .SYNOPSIS
    Opens the WindowsDeviceLink operator dashboard.

    .DESCRIPTION
    Opens a compact Windows 11 Settings-inspired WinForms dashboard on full Windows.

    The GUI focuses on inspecting Device Association state, onboarding, and offboarding.
    Lifecycle actions delegate to existing WindowsDeviceLink public cmdlets.

    Interactive authentication is the default. Use -Method and the corresponding authentication
    parameters to select another supported authentication flow.

    Use -Tenants to provide friendly tenant names for the tenant selector:

    @{'Management'='11111111-1111-1111-1111-111111111111'; 'Contoso'='22222222-2222-2222-2222-222222222222'}

    .EXAMPLE
    Show-WindowsDeviceLink

    .EXAMPLE
    Show-WindowsDeviceLink -Method DeviceCode

    .EXAMPLE
    Show-WindowsDeviceLink -Tenants @{
        'Management' = '11111111-1111-1111-1111-111111111111'
        'Contoso' = '22222222-2222-2222-2222-222222222222'
    }
    #>
    [CmdletBinding()]
    param(
        [ValidateSet(
            'DeviceCode','Interactive','ClientSecret','AccessToken','Certificate',
            'CertificateThumbprint','CertificateSubjectName','EnvironmentVariable','ManagedIdentity'
        )]
        [string]$Method = 'Interactive',

        [ValidateNotNullOrEmpty()]
        [string]$TenantId,

        [hashtable]$Tenants,

        [ValidateNotNullOrEmpty()]
        [string]$ClientId,

        [securestring]$AccessToken,

        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,

        [ValidateNotNullOrEmpty()]
        [string]$CertificateThumbprint,

        [ValidateNotNullOrEmpty()]
        [string]$CertificateSubjectName,

        [bool]$SendCertificateChain = $false,

        [securestring]$ClientSecret,

        [ValidateNotNullOrEmpty()]
        [string]$Environment = 'Global',

        [ValidateRange(1,600)]
        [double]$ClientTimeout = 100
    )

    if (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT') {
        throw 'Show-WindowsDeviceLink is not supported in Windows PE yet. Use the WindowsDeviceLink command-line cmdlets instead.'
    }

    $outerBoundParameters = @{}
    foreach ($key in $PSBoundParameters.Keys) {
        $outerBoundParameters[$key] = $PSBoundParameters[$key]
    }

    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    [System.Windows.Forms.Application]::EnableVisualStyles()

    $loadedModule = Get-Module WindowsDeviceLink | Select-Object -First 1
    $baseVersion = if ($loadedModule) { $loadedModule.Version.ToString() } else { 'unknown' }
    $prerelease = $null
    if ($loadedModule -and $loadedModule.PrivateData -and $loadedModule.PrivateData.PSData) {
        $prerelease = [string]$loadedModule.PrivateData.PSData.Prerelease
    }
    $displayVersion = if ([string]::IsNullOrWhiteSpace($prerelease)) { $baseVersion } else { "$baseVersion-$prerelease" }

    $workingArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $targetWidth = [Math]::Max(820,[Math]::Min(1080,$workingArea.Width - 32))
    $targetHeight = [Math]::Max(620,[Math]::Min(760,$workingArea.Height - 40))

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "WindowsDeviceLink $displayVersion (Preview)"
    $form.StartPosition = 'CenterScreen'
    $form.Size = [System.Drawing.Size]::new($targetWidth,$targetHeight)
    $form.MinimumSize = [System.Drawing.Size]::new(820,620)
    $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $form.BackColor = [System.Drawing.Color]::FromArgb(243,243,243)

    $content = New-Object System.Windows.Forms.Panel
    $content.Dock = [System.Windows.Forms.DockStyle]::Fill
    $content.AutoScroll = $false
    $content.BackColor = $form.BackColor
    $form.Controls.Add($content)


    function New-Card {
        param(
            [string]$Title,
            [int]$X,
            [int]$Y,
            [int]$Width,
            [int]$Height
        )

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
            $label.Location = [System.Drawing.Point]::new(14,9)
            $label.AutoSize = $true
            $panel.Controls.Add($label)
        }

        $panel
    }

    function New-ValuePair {
        param(
            [System.Windows.Forms.Control]$Parent,
            [string]$Caption,
            [int]$Y,
            [int]$CaptionWidth = 112
        )

        $captionLabel = New-Object System.Windows.Forms.Label
        $captionLabel.Text = $Caption
        $captionLabel.Font = New-Object System.Drawing.Font('Segoe UI',8.5)
        $captionLabel.ForeColor = [System.Drawing.Color]::FromArgb(102,102,102)
        $captionLabel.Location = [System.Drawing.Point]::new(14,$Y)
        $captionLabel.Size = [System.Drawing.Size]::new($CaptionWidth,20)
        $Parent.Controls.Add($captionLabel)

        $valueLabel = New-Object System.Windows.Forms.Label
        $valueLabel.Text = '-'
        $valueLabel.Font = New-Object System.Drawing.Font('Segoe UI',9,[System.Drawing.FontStyle]::Bold)
        $valueLabel.Location = [System.Drawing.Point]::new(($CaptionWidth + 20),($Y - 1))
        $valueLabel.Size = [System.Drawing.Size]::new(350,22)
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
            [string[]]$Buttons
        )

        $row = New-Object System.Windows.Forms.Panel
        $row.Location = [System.Drawing.Point]::new(0,$Y)
        $row.Size = [System.Drawing.Size]::new(900,46)
        $row.BackColor = [System.Drawing.Color]::White
        $Parent.Controls.Add($row)

        $titleLabel = New-Object System.Windows.Forms.Label
        $titleLabel.Text = $Title
        $titleLabel.Font = New-Object System.Drawing.Font('Segoe UI',8.3,[System.Drawing.FontStyle]::Bold)
        $titleLabel.Location = [System.Drawing.Point]::new(14,5)
        $titleLabel.AutoSize = $true
        $row.Controls.Add($titleLabel)

        $descriptionLabel = New-Object System.Windows.Forms.Label
        $descriptionLabel.Text = $Description
        $descriptionLabel.Font = New-Object System.Drawing.Font('Segoe UI',8.2)
        $descriptionLabel.ForeColor = [System.Drawing.Color]::FromArgb(108,108,108)
        $descriptionLabel.Location = [System.Drawing.Point]::new(14,23)
        $descriptionLabel.AutoSize = $true
        $row.Controls.Add($descriptionLabel)

        $buttonList = New-Object System.Collections.Generic.List[object]
        $count = $Buttons.Count
        $buttonWidth = if ($count -eq 1) { 118 } elseif ($count -eq 2) { 112 } else { 88 }
        $gap = 7
        $right = 884

        for ($i = $count - 1; $i -ge 0; $i--) {
            $button = New-Object System.Windows.Forms.Button
            $button.Text = $Buttons[$i]
            $button.Font = New-Object System.Drawing.Font('Segoe UI',8.6)
            $button.Size = [System.Drawing.Size]::new($buttonWidth,28)
            $right -= $buttonWidth
            $button.Location = [System.Drawing.Point]::new($right,9)
            $button.FlatStyle = [System.Windows.Forms.FlatStyle]::System
            $button.UseVisualStyleBackColor = $true
            $row.Controls.Add($button)
            $buttonList.Insert(0,$button)
            $right -= $gap
        }

        $separator = New-Object System.Windows.Forms.Panel
        $separator.BackColor = [System.Drawing.Color]::FromArgb(232,232,232)
        $separator.Location = [System.Drawing.Point]::new(14,45)
        $separator.Size = [System.Drawing.Size]::new(860,1)
        $row.Controls.Add($separator)

        [pscustomobject]@{
            Panel = $row
            Buttons = $buttonList.ToArray()
        }
    }

    $tenantChoiceLookup = @{}
    $tenantChoices = New-Object System.Collections.Generic.List[string]
    $autoLabel = if ($outerBoundParameters.ContainsKey('TenantId')) { 'Default tenant parameter' } else { 'Automatic / local context' }
    $tenantChoiceLookup[$autoLabel] = $null
    $tenantChoices.Add($autoLabel)

    if ($Tenants) {
        foreach ($name in @($Tenants.Keys | Sort-Object)) {
            $id = [string]$Tenants[$name]
            if ([string]::IsNullOrWhiteSpace($id)) { continue }
            $label = [string]$name
            if ($tenantChoiceLookup.ContainsKey($label)) {
                $label = "$label ($id)"
            }
            $tenantChoiceLookup[$label] = $id.Trim()
            $tenantChoices.Add($label)
        }
    }

    function Get-SelectedTenantId {
        if ($tenantSelector.SelectedItem) {
            $selected = [string]$tenantSelector.SelectedItem
            if ($tenantChoiceLookup.ContainsKey($selected) -and $tenantChoiceLookup[$selected]) {
                return [string]$tenantChoiceLookup[$selected]
            }
        }

        if ($outerBoundParameters.ContainsKey('TenantId')) {
            return [string]$TenantId
        }

        $null
    }

    function Get-GuiAuthParameters {
        $parameters = @{
            Method = $Method
            Environment = $Environment
            ClientTimeout = $ClientTimeout
        }

        foreach ($name in @(
            'ClientId','AccessToken','Certificate','CertificateThumbprint',
            'CertificateSubjectName','SendCertificateChain','ClientSecret'
        )) {
            if ($outerBoundParameters.ContainsKey($name)) {
                $parameters[$name] = $outerBoundParameters[$name]
            }
        }

        $selectedTenant = Get-SelectedTenantId
        if ($selectedTenant) {
            $parameters.TenantId = $selectedTenant
        }

        $parameters
    }

    $ui = @{}
    $script:WdlGuiBusy = $false
    $script:WdlGuiLocalAssociation = $null
    $script:WdlGuiCloudStatus = $null

    $deviceCard = New-Card -Title 'Device' -X 14 -Y 12 -Width 508 -Height 126
    $associationCard = New-Card -Title 'Association' -X 536 -Y 12 -Width 508 -Height 126

    $ui.DeviceName = New-ValuePair -Parent $deviceCard -Caption 'Device' -Y 34
    $ui.Serial     = New-ValuePair -Parent $deviceCard -Caption 'Serial number' -Y 56
    $ui.Environment = New-ValuePair -Parent $deviceCard -Caption 'Environment' -Y 78
    $ui.Auth       = New-ValuePair -Parent $deviceCard -Caption 'Authentication' -Y 100

    $ui.Firmware   = New-ValuePair -Parent $associationCard -Caption 'Firmware' -Y 34
    $ui.LocalState = New-ValuePair -Parent $associationCard -Caption 'Local state' -Y 56
    $ui.TenantId   = New-ValuePair -Parent $associationCard -Caption 'Tenant ID' -Y 78
    $ui.Source     = New-ValuePair -Parent $associationCard -Caption 'Source' -Y 100

    $cloudCard = New-Card -Title 'Cloud association' -X 14 -Y 150 -Width 1030 -Height 84
    $ui.CloudState  = New-ValuePair -Parent $cloudCard -Caption 'State' -Y 34 -CaptionWidth 80
    $ui.CloudTenant = New-ValuePair -Parent $cloudCard -Caption 'Tenant ID' -Y 56 -CaptionWidth 80

    $cloudIdCaption = New-Object System.Windows.Forms.Label
    $cloudIdCaption.Text = 'Association ID'
    $cloudIdCaption.Font = New-Object System.Drawing.Font('Segoe UI',8.5)
    $cloudIdCaption.ForeColor = [System.Drawing.Color]::FromArgb(102,102,102)
    $cloudIdCaption.Location = [System.Drawing.Point]::new(500,34)
    $cloudIdCaption.Size = [System.Drawing.Size]::new(96,20)
    $cloudCard.Controls.Add($cloudIdCaption)

    $ui.CloudId = New-Object System.Windows.Forms.Label
    $ui.CloudId.Text = '-'
    $ui.CloudId.Font = New-Object System.Drawing.Font('Segoe UI',8.3,[System.Drawing.FontStyle]::Bold)
    $ui.CloudId.Location = [System.Drawing.Point]::new(600,33)
    $ui.CloudId.Size = [System.Drawing.Size]::new(380,22)
    $ui.CloudId.AutoEllipsis = $true
    $cloudCard.Controls.Add($ui.CloudId)

    $tenantCaption = New-Object System.Windows.Forms.Label
    $tenantCaption.Text = 'Tenant'
    $tenantCaption.Font = New-Object System.Drawing.Font('Segoe UI',8.5)
    $tenantCaption.ForeColor = [System.Drawing.Color]::FromArgb(102,102,102)
    $tenantCaption.Location = [System.Drawing.Point]::new(500,56)
    $tenantCaption.Size = [System.Drawing.Size]::new(96,18)
    $cloudCard.Controls.Add($tenantCaption)

    $tenantSelector = New-Object System.Windows.Forms.ComboBox
    $tenantSelector.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $tenantSelector.Font = New-Object System.Drawing.Font('Segoe UI',8.5)
    $tenantSelector.Location = [System.Drawing.Point]::new(600,53)
    $tenantSelector.Size = [System.Drawing.Size]::new(380,24)
    foreach ($choice in $tenantChoices) {
        [void]$tenantSelector.Items.Add($choice)
    }
    $tenantSelector.SelectedIndex = 0
    $cloudCard.Controls.Add($tenantSelector)

    $actionsTitle = New-Object System.Windows.Forms.Label
    $actionsTitle.Text = 'Actions'
    $actionsTitle.Font = New-Object System.Drawing.Font('Segoe UI',11.5,[System.Drawing.FontStyle]::Bold)
    $actionsTitle.Location = [System.Drawing.Point]::new(16,246)
    $actionsTitle.AutoSize = $true
    $content.Controls.Add($actionsTitle)

    $actionsPanel = New-Card -Title '' -X 14 -Y 272 -Width 1030 -Height 232
    $rowRefresh = New-ActionRow -Parent $actionsPanel -Title 'Refresh' -Description 'Refresh local DeviceLink and firmware information.' -Y 0 -Buttons @('Refresh')
    $rowOnline  = New-ActionRow -Parent $actionsPanel -Title 'Check online' -Description 'Query the tenant-side Device Association using the selected tenant context.' -Y 46 -Buttons @('Check online')
    $rowExport  = New-ActionRow -Parent $actionsPanel -Title 'Export DeviceLink CSV' -Description 'Export the Microsoft-generated .devicelink.csv.' -Y 92 -Buttons @('Export CSV')
    $rowOnboard = New-ActionRow -Parent $actionsPanel -Title 'Onboarding' -Description 'Create only the pre-association, or perform the complete onboarding flow.' -Y 138 -Buttons @('Pre-associate','Full associate')
    $rowOffboard = New-ActionRow -Parent $actionsPanel -Title 'Offboarding' -Description 'Remove cloud state, local state, or both.' -Y 184 -Buttons @('Cloud','Local','Full')

    $activityTitle = New-Object System.Windows.Forms.Label
    $activityTitle.Text = 'Activity'
    $activityTitle.Font = New-Object System.Drawing.Font('Segoe UI',11,[System.Drawing.FontStyle]::Bold)
    $activityTitle.Location = [System.Drawing.Point]::new(16,518)
    $activityTitle.AutoSize = $true
    $content.Controls.Add($activityTitle)

    $activityCard = New-Card -Title '' -X 14 -Y 544 -Width 1030 -Height 118

    $consoleBox = New-Object System.Windows.Forms.TextBox
    $consoleBox.Location = [System.Drawing.Point]::new(12,10)
    $consoleBox.Size = [System.Drawing.Size]::new(1006,96)
    $consoleBox.Multiline = $true
    $consoleBox.ReadOnly = $true
    $consoleBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $consoleBox.WordWrap = $false
    $consoleBox.Font = New-Object System.Drawing.Font('Consolas',8)
    $consoleBox.BackColor = [System.Drawing.Color]::FromArgb(250,250,250)
    $consoleBox.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $activityCard.Controls.Add($consoleBox)

    $statusStrip = New-Object System.Windows.Forms.StatusStrip
    $statusStrip.Dock = [System.Windows.Forms.DockStyle]::Bottom

    $statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
    $statusLabel.Text = 'Ready'
    $statusLabel.Spring = $true
    $statusLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft

    $statusProgress = New-Object System.Windows.Forms.ToolStripProgressBar
    $statusProgress.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
    $statusProgress.MarqueeAnimationSpeed = 30
    $statusProgress.Size = [System.Drawing.Size]::new(140,16)
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
        param(
            [string]$Title,
            [string]$Message
        )

        $dialog = New-Object System.Windows.Forms.Form
        $dialog.Text = $Title
        $dialog.StartPosition = 'CenterParent'
        $dialog.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
        $dialog.MaximizeBox = $false
        $dialog.MinimizeBox = $false
        $dialog.ShowInTaskbar = $false
        $dialog.ClientSize = [System.Drawing.Size]::new(600,185)
        $dialog.BackColor = [System.Drawing.Color]::White

        $iconBox = New-Object System.Windows.Forms.PictureBox
        $iconBox.Location = [System.Drawing.Point]::new(24,28)
        $iconBox.Size = [System.Drawing.Size]::new(40,40)
        $iconBox.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::StretchImage
        $iconBox.Image = [System.Drawing.SystemIcons]::Warning.ToBitmap()
        $dialog.Controls.Add($iconBox)

        $messageLabel = New-Object System.Windows.Forms.Label
        $messageLabel.Text = $Message
        $messageLabel.Font = New-Object System.Drawing.Font('Segoe UI',9)
        $messageLabel.Location = [System.Drawing.Point]::new(82,24)
        $messageLabel.Size = [System.Drawing.Size]::new(490,95)
        $messageLabel.AutoEllipsis = $false
        $dialog.Controls.Add($messageLabel)

        $buttonPanel = New-Object System.Windows.Forms.Panel
        $buttonPanel.Dock = [System.Windows.Forms.DockStyle]::Bottom
        $buttonPanel.Height = 54
        $buttonPanel.BackColor = [System.Drawing.Color]::FromArgb(246,246,246)
        $dialog.Controls.Add($buttonPanel)

        $yesButton = New-Object System.Windows.Forms.Button
        $yesButton.Text = 'Yes'
        $yesButton.DialogResult = [System.Windows.Forms.DialogResult]::Yes
        $yesButton.Size = [System.Drawing.Size]::new(108,32)
        $yesButton.Location = [System.Drawing.Point]::new(356,11)
        $yesButton.Font = New-Object System.Drawing.Font('Segoe UI',9)
        $buttonPanel.Controls.Add($yesButton)

        $noButton = New-Object System.Windows.Forms.Button
        $noButton.Text = 'No'
        $noButton.DialogResult = [System.Windows.Forms.DialogResult]::No
        $noButton.Size = [System.Drawing.Size]::new(108,32)
        $noButton.Location = [System.Drawing.Point]::new(476,11)
        $noButton.Font = New-Object System.Drawing.Font('Segoe UI',9)
        $buttonPanel.Controls.Add($noButton)

        $dialog.AcceptButton = $yesButton
        $dialog.CancelButton = $noButton

        try {
            $result = $dialog.ShowDialog($form)
            return ($result -eq [System.Windows.Forms.DialogResult]::Yes)
        }
        finally {
            if ($iconBox.Image) { $iconBox.Image.Dispose() }
            $dialog.Dispose()
        }
    }

    function Set-GuiBusy {
        param(
            [Parameter(Mandatory)][bool]$Busy,
            [string]$StatusText
        )

        $script:WdlGuiBusy = $Busy
        $enabled = -not $Busy

        # Keep every action button in the native Windows visual style at all times.
        # Only Enabled changes, so rounded/themed button rendering is preserved while busy.
        $rowRefresh.Buttons[0].Enabled = $enabled
        $rowOnline.Buttons[0].Enabled = $enabled
        $rowExport.Buttons[0].Enabled = $enabled
        $rowOnboard.Buttons[0].Enabled = $enabled
        $rowOnboard.Buttons[1].Enabled = $enabled
        $rowOffboard.Buttons[0].Enabled = $enabled
        $rowOffboard.Buttons[1].Enabled = $enabled
        $rowOffboard.Buttons[2].Enabled = $enabled

        $tenantSelector.Enabled = $enabled
        $statusProgress.Visible = $Busy
        $form.UseWaitCursor = $Busy

        if (-not [string]::IsNullOrWhiteSpace($StatusText)) {
            Set-GuiStatus $StatusText
        }

        $rowRefresh.Buttons[0].Refresh()
        $rowOnline.Buttons[0].Refresh()
        $rowExport.Buttons[0].Refresh()
        $rowOnboard.Buttons[0].Refresh()
        $rowOnboard.Buttons[1].Refresh()
        $rowOffboard.Buttons[0].Refresh()
        $rowOffboard.Buttons[1].Refresh()
        $rowOffboard.Buttons[2].Refresh()
        $tenantSelector.Refresh()
        [System.Windows.Forms.Application]::DoEvents()
    }

    function Refresh-LocalView {
        Set-GuiStatus 'Refreshing local state...'
        Write-GuiConsole -Message 'Refresh local state' -Command

        $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
        $support = Test-WindowsDeviceLinkSupport
        $local = Get-WindowsDeviceLinkLocalAssociation

        $script:WdlGuiLocalAssociation = $local

        $ui.DeviceName.Text = "$($cs.Manufacturer) $($cs.Model)".Trim()
        $ui.Serial.Text = [string]$bios.SerialNumber

        if ($support.Environment -eq 'WindowsPE') {
            $environmentText = 'Windows PE'
        }
        elseif ($os -and [string]$os.Caption -match 'Windows 11') {
            $environmentText = 'Windows 11'
        }
        elseif ($os -and -not [string]::IsNullOrWhiteSpace([string]$os.Caption)) {
            $environmentText = ([string]$os.Caption).Replace('Microsoft ','')
        }
        else {
            $environmentText = [string]$support.Environment
        }

        if (-not $support.Supported) {
            $environmentText += " (unsupported: $($support.Reason))"
        }

        $ui.Environment.Text = $environmentText

        $selectedTenant = Get-SelectedTenantId
        $ui.Auth.Text = if ($selectedTenant) { "$Method | $selectedTenant" } else { $Method }

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
        try { Refresh-LocalView }
        catch { Show-GuiError $_.Exception.Message }
        finally { Set-GuiBusy -Busy $false }
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
        finally { Set-GuiBusy -Busy $false }
    }

    function Invoke-GuiExport {
        if ($script:WdlGuiBusy) { return }

        Set-GuiBusy -Busy $true -StatusText 'Choose export folder...'

        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = 'Choose a folder for the DeviceLink CSV'

        try {
            if ($dialog.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) {
                Set-GuiStatus 'Export cancelled'
                return
            }

            Set-GuiStatus 'Exporting DeviceLink CSV...'
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
        catch { Show-GuiError $_.Exception.Message }
        finally {
            Set-GuiBusy -Busy $false
            $dialog.Dispose()
        }
    }

    function Invoke-GuiPreassociate {
        if ($script:WdlGuiBusy) { return }

        if (-not (Confirm-GuiAction -Title 'Create pre-association' -Message 'Create or attempt the tenant-side Device Association pre-association for this device?')) {
            return
        }

        Set-GuiBusy -Busy $true -StatusText 'Creating pre-association...'
        try {
            Write-GuiConsole -Message 'Get-WindowsDeviceLink' -Command
            $identity = Get-WindowsDeviceLink

            $parameters = Get-GuiAuthParameters
            $parameters.InputObject = $identity
            $parameters.Confirm = $false

            Write-GuiConsole -Message "Get-WindowsDeviceLink | Register-WindowsDeviceLink -Method $Method" -Command
            $result = Register-WindowsDeviceLink @parameters
            Write-GuiObject $result

            $script:WdlGuiCloudStatus = $null
            Refresh-LocalView
            Set-GuiStatus 'Pre-association completed'
        }
        catch {
            Set-GuiStatus 'Pre-association failed'
            Show-GuiError $_.Exception.Message
        }
        finally { Set-GuiBusy -Busy $false }
    }

    function Invoke-GuiFullAssociate {
        if ($script:WdlGuiBusy) { return }

        if (-not (Confirm-GuiAction -Title 'Full association' -Message 'Ensure pre-association exists and complete Device Association on this device?')) {
            return
        }

        Set-GuiBusy -Busy $true -StatusText 'Completing onboarding...'
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
            Set-GuiStatus 'Full association completed'
        }
        catch {
            Set-GuiStatus 'Full association failed'
            Show-GuiError $_.Exception.Message
        }
        finally { Set-GuiBusy -Busy $false }
    }

    function Invoke-GuiCloudOffboard {
        if ($script:WdlGuiBusy) { return }

        if (-not (Confirm-GuiAction -Title 'Cloud offboarding' -Message 'Remove only the tenant-side Device Association record? Local DeviceLink firmware will remain unchanged.')) {
            return
        }

        Set-GuiBusy -Busy $true -StatusText 'Removing cloud association...'
        try {
            $parameters = Get-GuiAuthParameters
            $parameters.Confirm = $false

            Write-GuiConsole -Message "Remove-WindowsDeviceLinkAssociation -Method $Method" -Command
            $result = Remove-WindowsDeviceLinkAssociation @parameters
            Write-GuiObject $result

            $script:WdlGuiCloudStatus = $null
            $ui.CloudState.Text = 'Not checked'
            $ui.CloudTenant.Text = '-'
            $ui.CloudId.Text = '-'

            Refresh-LocalView
            Set-GuiStatus 'Cloud offboarding completed'
        }
        catch {
            Set-GuiStatus 'Cloud offboarding failed'
            Show-GuiError $_.Exception.Message
        }
        finally { Set-GuiBusy -Busy $false }
    }

    function Invoke-GuiLocalOffboard {
        if ($script:WdlGuiBusy) { return }

        if (-not (Confirm-GuiAction -Title 'Local offboarding' -Message 'Reset all known local DeviceLink UEFI variables? The tenant-side Device Association record will remain unchanged.')) {
            return
        }

        Set-GuiBusy -Busy $true -StatusText 'Resetting local DeviceLink state...'
        try {
            Write-GuiConsole -Message 'Reset-WindowsDeviceLinkFirmwareState' -Command
            $result = Reset-WindowsDeviceLinkFirmwareState -Confirm:$false
            Write-GuiObject $result

            $script:WdlGuiCloudStatus = $null
            Refresh-LocalView
            Set-GuiStatus 'Local offboarding completed'
        }
        catch {
            Set-GuiStatus 'Local offboarding failed'
            Show-GuiError $_.Exception.Message
        }
        finally { Set-GuiBusy -Busy $false }
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

        Set-GuiBusy -Busy $true -StatusText 'Performing full offboarding...'
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
            Set-GuiStatus 'Full offboarding completed'
        }
        catch {
            Set-GuiStatus 'Full offboarding failed'
            Show-GuiError $_.Exception.Message
        }
        finally { Set-GuiBusy -Busy $false }
    }

    $rowRefresh.Buttons[0].Add_Click({ Invoke-GuiRefresh })
    $rowOnline.Buttons[0].Add_Click({ Invoke-GuiOnline })
    $rowExport.Buttons[0].Add_Click({ Invoke-GuiExport })
    $rowOnboard.Buttons[0].Add_Click({ Invoke-GuiPreassociate })
    $rowOnboard.Buttons[1].Add_Click({ Invoke-GuiFullAssociate })
    $rowOffboard.Buttons[0].Add_Click({ Invoke-GuiCloudOffboard })
    $rowOffboard.Buttons[1].Add_Click({ Invoke-GuiLocalOffboard })
    $rowOffboard.Buttons[2].Add_Click({ Invoke-GuiFullOffboard })

    $tenantSelector.Add_SelectedIndexChanged({
        if (-not $script:WdlGuiBusy) {
            $selectedTenant = Get-SelectedTenantId
            $ui.Auth.Text = if ($selectedTenant) { "$Method | $selectedTenant" } else { $Method }
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
        Write-GuiConsole -Message "WindowsDeviceLink dashboard opened. Authentication method: $Method."
        Set-GuiBusy -Busy $true -StatusText 'Loading local state...'
        try { Refresh-LocalView }
        catch { Show-GuiError $_.Exception.Message }
        finally { Set-GuiBusy -Busy $false }
    })

    function Resize-GuiLayout {
        $fullWidth = [Math]::Max(760,$content.ClientSize.Width - 32)
        $gap = 14
        $halfWidth = [Math]::Floor(($fullWidth - $gap) / 2)

        if ($fullWidth -ge 900) {
            $deviceCard.Location = [System.Drawing.Point]::new(14,12)
            $deviceCard.Size = [System.Drawing.Size]::new([int]$halfWidth,126)
            $associationCard.Location = [System.Drawing.Point]::new((14 + $halfWidth + $gap),12)
            $associationCard.Size = [System.Drawing.Size]::new([int]$halfWidth,126)
            $cloudY = 150
        }
        else {
            $deviceCard.Location = [System.Drawing.Point]::new(14,12)
            $deviceCard.Size = [System.Drawing.Size]::new([int]$fullWidth,126)
            $associationCard.Location = [System.Drawing.Point]::new(14,150)
            $associationCard.Size = [System.Drawing.Size]::new([int]$fullWidth,126)
            $cloudY = 288
        }

        $cloudCard.Location = [System.Drawing.Point]::new(14,$cloudY)
        $cloudCard.Width = $fullWidth

        $actionsY = $cloudY + 96
        $actionsTitle.Location = [System.Drawing.Point]::new(16,$actionsY)
        $actionsPanel.Location = [System.Drawing.Point]::new(14,($actionsY + 26))
        $actionsPanel.Width = $fullWidth

        $activityY = $actionsY + 270
        $activityTitle.Location = [System.Drawing.Point]::new(16,$activityY)
        $activityCard.Location = [System.Drawing.Point]::new(14,($activityY + 26))
        $activityCard.Width = $fullWidth
        $consoleBox.Width = $fullWidth - 24


        foreach ($row in @($rowRefresh,$rowOnline,$rowExport,$rowOnboard,$rowOffboard)) {
            $row.Panel.Width = $fullWidth

            $buttons = @($row.Buttons)
            $right = $fullWidth - 16
            for ($i = $buttons.Count - 1; $i -ge 0; $i--) {
                $right -= $buttons[$i].Width
                $buttons[$i].Left = $right
                $right -= 7
            }

            $row.Panel.Controls |
                Where-Object { $_ -is [System.Windows.Forms.Panel] -and $_.Height -eq 1 } |
                ForEach-Object { $_.Width = [Math]::Max(480,$fullWidth - 28) }
        }

        $requiredHeight = $activityCard.Bottom + 2
        $availableHeight = [Math]::Max(0,$content.ClientSize.Height - 2)
        $scrollTolerance = 10

        if ($requiredHeight -gt ($availableHeight + $scrollTolerance)) {
            $content.AutoScroll = $true
            $content.HorizontalScroll.Enabled = $false
            $content.HorizontalScroll.Visible = $false
            $content.AutoScrollMinSize = [System.Drawing.Size]::new(1,$requiredHeight)
        }
        else {
            $content.AutoScrollMinSize = [System.Drawing.Size]::Empty
            $content.AutoScroll = $false
            $content.VerticalScroll.Value = 0
        }
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
