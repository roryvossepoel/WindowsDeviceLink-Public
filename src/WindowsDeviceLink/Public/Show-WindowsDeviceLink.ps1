function Show-WindowsDeviceLink {
    <#
    .SYNOPSIS
    Opens the WindowsDeviceLink operator dashboard.

    .DESCRIPTION
    Opens a compact Windows 11 Settings-inspired WinForms dashboard on Windows 11 and supported Windows PE environments.

    The GUI focuses on inspecting Device Association state, onboarding, and offboarding.
    Lifecycle actions delegate to existing WindowsDeviceLink public cmdlets.

    Interactive authentication is the default on full Windows. Windows PE defaults to DeviceCode because Interactive browser authentication is unavailable there. Use -Method and the corresponding authentication parameters to select another supported authentication flow.

    Use -Tenants to provide friendly tenant names for the tenant selector:

    @{'Tenant Alpha'='11111111-1111-1111-1111-111111111111'; 'Tenant Beta'='22222222-2222-2222-2222-222222222222'}

    Use -TenantsUri to load the same friendly-name-to-tenant-ID mapping from a trusted HTTPS JSON endpoint.
    Use -TenantsPath to load the same JSON format from a local file.
    Precedence is: TenantsUri, then TenantsPath, then explicit -Tenants values.

    Backend mode retrieves its authoritative tenant catalog from the Function App.
    The dashboard presents device, local-association, and cloud-association state in
    one view. Register performs the complete guarded assignment workflow; diagnostic,
    export, recovery, and offboarding actions remain available below it.

    .EXAMPLE
    Show-WindowsDeviceLink

    .EXAMPLE
    Show-WindowsDeviceLink -Method DeviceCode

    .EXAMPLE
    Show-WindowsDeviceLink -Tenants @{
        'Tenant Alpha' = '11111111-1111-1111-1111-111111111111'
        'Tenant Beta' = '22222222-2222-2222-2222-222222222222'
    }

    .EXAMPLE
    Show-WindowsDeviceLink -TenantsUri 'https://config.example.com/windowsdevicelink/tenants.json'

    .EXAMPLE
    Show-WindowsDeviceLink -TenantsPath 'E:\Config\tenants.json'
    #>
    [CmdletBinding()]
    param(
        [ValidateSet(
            'DeviceCode','Interactive','ClientSecret','AccessToken','Certificate',
            'CertificateThumbprint','CertificateSubjectName','EnvironmentVariable','ManagedIdentity'
        )]
        [string]$Method,

        [ValidateNotNullOrEmpty()]
        [string]$TenantId,

        [hashtable]$Tenants,

        [ValidateNotNull()]
        [uri]$TenantsUri,

        [ValidateNotNullOrEmpty()]
        [string]$TenantsPath,

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
        [double]$ClientTimeout = 100,

        [ValidateNotNullOrEmpty()]
        [string]$WindowsManagementServicePath

        ,[ValidateNotNull()]
        [uri]$BackendUri

        ,[ValidateNotNull()]
        [securestring]$BackendApiKey

        ,[ValidateSet('Simple','Advanced')]
        [string]$ViewMode = 'Simple'
    )

    $outerBoundParameters = @{}
    foreach ($key in $PSBoundParameters.Keys) {
        $outerBoundParameters[$key] = $PSBoundParameters[$key]
    }

    $isWinPE = Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT'
    $backendMode = $outerBoundParameters.ContainsKey('BackendUri') -or $outerBoundParameters.ContainsKey('BackendApiKey')
    if ($backendMode -and (-not $outerBoundParameters.ContainsKey('BackendUri') -or -not $outerBoundParameters.ContainsKey('BackendApiKey'))) {
        throw '-BackendUri and -BackendApiKey must be supplied together.'
    }
    if ($backendMode -and ($Tenants -or $outerBoundParameters.ContainsKey('TenantsUri') -or $outerBoundParameters.ContainsKey('TenantsPath'))) {
        throw 'Backend mode obtains its tenant catalog from the Function App; do not combine it with -Tenants, -TenantsUri, or -TenantsPath.'
    }
    if (-not $backendMode -and $outerBoundParameters.ContainsKey('TenantId') -and ($Tenants -or $outerBoundParameters.ContainsKey('TenantsUri') -or $outerBoundParameters.ContainsKey('TenantsPath'))) {
        throw 'Direct mode uses either one explicit -TenantId or a tenant catalog; do not combine them.'
    }

    if ($backendMode -and $outerBoundParameters.ContainsKey('Method')) {
        throw 'Backend mode performs Graph operations through the Function App; do not combine it with -Method.'
    }
    if (-not $backendMode -and -not $outerBoundParameters.ContainsKey('Method')) {
        $Method = if ($isWinPE) { 'DeviceCode' } else { 'Interactive' }
    }

    if ($isWinPE -and $Method -eq 'Interactive') {
        throw 'Interactive authentication is not available in Windows PE. Use -Method DeviceCode or a supported app-only authentication method.'
    }
    $usesInteractiveUserAuthentication = -not $backendMode -and $Method -in @('Interactive','DeviceCode')

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

    $formIcon = $null
    if ($loadedModule -and -not [string]::IsNullOrWhiteSpace([string]$loadedModule.ModuleBase)) {
        $iconPath = Join-Path ([string]$loadedModule.ModuleBase) 'Assets\WindowsDeviceLink.ico'
        if (Test-Path -LiteralPath $iconPath) {
            try {
                $formIcon = [System.Drawing.Icon]::new($iconPath)
                $form.Icon = $formIcon
            }
            catch {
                # An icon is cosmetic and must never block the operator workflow.
                $formIcon = $null
            }
        }
    }

    $content = New-Object System.Windows.Forms.Panel
    $content.Dock = [System.Windows.Forms.DockStyle]::Fill
    $content.AutoScroll = $false
    $content.BackColor = $form.BackColor
    $form.Controls.Add($content)

    $toolTip = New-Object System.Windows.Forms.ToolTip
    $toolTip.AutoPopDelay = 10000
    $toolTip.InitialDelay = 400
    $toolTip.ReshowDelay = 200
    $toolTip.ShowAlways = $true

    $colorCardAccent = [System.Drawing.Color]::FromArgb(86,94,102)
    $colorCardTint = [System.Drawing.Color]::FromArgb(248,249,250)

    function New-GuiFont {
        param(
            [string]$Family,
            [float]$Size = 9,
            [System.Drawing.FontStyle]$Style = [System.Drawing.FontStyle]::Regular
        )

        $resolvedFamily = if (-not [string]::IsNullOrWhiteSpace($Family)) {
            $Family
        }
        elseif ($Style -eq [System.Drawing.FontStyle]::Regular) {
            'Tahoma'
        }
        else {
            'Segoe UI'
        }

        return [System.Drawing.Font]::new(
            $resolvedFamily,$Size,$Style,[System.Drawing.GraphicsUnit]::Point
        )
    }


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
            $label.Font = New-GuiFont -Size 10 -Style Bold
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
            [int]$CaptionWidth = 112,
            [int]$X = 14,
            [int]$ValueWidth = 350
        )

        $captionLabel = New-Object System.Windows.Forms.Label
        $captionLabel.Text = $Caption
        $captionLabel.Font = New-GuiFont -Size 8.5 -Style Regular
        $captionLabel.ForeColor = [System.Drawing.Color]::FromArgb(102,102,102)
        $captionLabel.Location = [System.Drawing.Point]::new($X,$Y)
        $captionLabel.Size = [System.Drawing.Size]::new($CaptionWidth,20)
        $captionLabel.Tag = "Caption:$Caption"
        $Parent.Controls.Add($captionLabel)

        $valueLabel = New-Object System.Windows.Forms.Label
        $valueLabel.Text = '-'
        $valueLabel.Font = New-GuiFont -Size 9 -Style Bold
        $valueLabel.Location = [System.Drawing.Point]::new(($X + $CaptionWidth + 6),($Y - 1))
        $valueLabel.Size = [System.Drawing.Size]::new($ValueWidth,22)
        $valueLabel.AutoEllipsis = $true
        $valueLabel.Tag = "Value:$Caption"
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
        $titleLabel.Font = New-GuiFont -Size 8.3 -Style Bold
        $titleLabel.Location = [System.Drawing.Point]::new(14,5)
        $titleLabel.AutoSize = $true
        $row.Controls.Add($titleLabel)

        $descriptionLabel = New-Object System.Windows.Forms.Label
        $descriptionLabel.Text = $Description
        $descriptionLabel.Font = New-GuiFont -Size 8.2 -Style Regular
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
            $button.Font = New-GuiFont -Size 8.6 -Style Regular
            $button.Size = [System.Drawing.Size]::new($buttonWidth,28)
            $right -= $buttonWidth
            $button.Location = [System.Drawing.Point]::new($right,9)
            $button.FlatStyle = [System.Windows.Forms.FlatStyle]::Standard
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
            Description = $descriptionLabel
        }
    }

    $effectiveTenants = @{}

    if ($backendMode) {
        $backendTenants = @(Get-WindowsDeviceLinkBackendTenant -BackendUri $BackendUri -BackendApiKey $BackendApiKey)
        if ($backendTenants.Count -eq 0) { throw 'The Function backend returned no allowed tenants.' }
        foreach ($tenant in $backendTenants) {
            $effectiveTenants[[string]$tenant.Name] = [string]$tenant.TenantId
        }
    }

    if ($outerBoundParameters.ContainsKey('TenantsUri')) {
        foreach ($tenant in @(Get-WindowsDeviceLinkTenantCatalog -Uri $TenantsUri)) {
            $effectiveTenants[[string]$tenant.Name] = [string]$tenant.TenantId
        }
    }

    if ($outerBoundParameters.ContainsKey('TenantsPath')) {
        foreach ($tenant in @(Get-WindowsDeviceLinkTenantCatalog -Path $TenantsPath)) {
            $effectiveTenants[[string]$tenant.Name] = [string]$tenant.TenantId
        }
    }

    if ($Tenants) {
        foreach ($tenant in @(Get-WindowsDeviceLinkTenantCatalog -TenantMap $Tenants)) {
            $effectiveTenants[[string]$tenant.Name] = [string]$tenant.TenantId
        }
    }

    $tenantChoiceLookup = @{}
    $tenantChoices = New-Object System.Collections.Generic.List[string]
    $hasDirectTenantCatalog = -not $backendMode -and $effectiveTenants.Count -gt 0
    $autoLabel = if ($backendMode -or $hasDirectTenantCatalog) { 'Select target tenant...' } elseif ($outerBoundParameters.ContainsKey('TenantId')) { 'Explicit tenant parameter' } else { 'Tenant determined by sign-in' }
    $tenantChoiceLookup[$autoLabel] = $null
    $tenantChoices.Add($autoLabel)

    if ($effectiveTenants.Count -gt 0) {
        foreach ($name in @($effectiveTenants.Keys | Sort-Object)) {
            $id = [string]$effectiveTenants[$name]
            $label = [string]$name
            if ($tenantChoiceLookup.ContainsKey($label)) {
                $label = "$label ($id)"
            }
            $tenantChoiceLookup[$label] = $id
            $tenantChoices.Add($label)
        }
    }

    # A true Direct single-tenant workflow has no choice to present. The
    # authenticated sign-in context (or explicit TenantId) remains authoritative.
    $showTenantSelector = $backendMode -or $effectiveTenants.Count -gt 0

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

    function Get-TenantDisplayName {
        param([string]$TenantId)

        if ([string]::IsNullOrWhiteSpace($TenantId)) { return 'Unavailable' }
        foreach ($name in $effectiveTenants.Keys) {
            if ([string]$effectiveTenants[$name] -ieq $TenantId) {
                return [string]$name
            }
        }

        return $TenantId
    }

    function Get-GuiAuthParameters {
        $selectedTenant = Get-SelectedTenantId

        if ($hasDirectTenantCatalog -and [string]::IsNullOrWhiteSpace($selectedTenant)) {
            throw 'Select a target tenant before signing in or performing a cloud action.'
        }

        if (-not $backendMode -and $Method -eq 'DeviceCode') {
            $cacheTenantMatches = -not $selectedTenant -or
                ([string]$script:WdlGuiSessionTenantId -ieq [string]$selectedTenant)
            $cacheValid = $script:WdlGuiSessionAccessToken -and
                $script:WdlGuiSessionExpiresUtc -and
                ([DateTime]::UtcNow -lt $script:WdlGuiSessionExpiresUtc) -and
                $cacheTenantMatches

            if (-not $cacheValid) {
                Clear-GuiSessionAuthentication
                Write-GuiConsole -Message 'Authenticating once for this Direct-mode UI session.' -Command

                $tokenParameters = @{}
                if ($selectedTenant) { $tokenParameters.TenantId = $selectedTenant }
                if ($outerBoundParameters.ContainsKey('ClientId')) { $tokenParameters.ClientId = $ClientId }
                $tokenResults = @(Invoke-GuiInformationCommand -ScriptBlock {
                    Get-WindowsDeviceLinkDeviceCodeToken @tokenParameters
                })
                $token = $tokenResults | Select-Object -Last 1
                if (-not $token -or [string]::IsNullOrWhiteSpace([string]$token.AccessToken)) {
                    throw 'Device code authentication did not return an access token.'
                }

                $script:WdlGuiSessionAccessToken = ConvertTo-SecureString ([string]$token.AccessToken) -AsPlainText -Force
                $script:WdlGuiSessionTenantId = [string]$token.TenantId
                $expiresIn = if ($token.ExpiresIn) { [int]$token.ExpiresIn } else { 3600 }
                $script:WdlGuiSessionExpiresUtc = [DateTime]::UtcNow.AddSeconds([Math]::Max(60,$expiresIn - 120))
                $script:WdlGuiSessionAuthenticated = $true
                $token = $null
                $ui.Authentication.Text = "$Method - Signed in"
                if ($btnSignIn) { $btnSignIn.Text = 'Switch account' }
                Write-GuiConsole -Message 'Direct-mode session authenticated; the in-memory token will be reused for cloud actions.'
            }

            return @{
                Method = 'AccessToken'
                AccessToken = $script:WdlGuiSessionAccessToken
                TenantId = $script:WdlGuiSessionTenantId
                Environment = $Environment
                ClientTimeout = $ClientTimeout
            }
        }

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

        if ($selectedTenant) {
            $parameters.TenantId = $selectedTenant
        }

        $parameters
    }

    function Clear-GuiSessionAuthentication {
        if ($script:WdlGuiSessionAccessToken -is [System.IDisposable]) {
            try { $script:WdlGuiSessionAccessToken.Dispose() } catch {}
        }
        $script:WdlGuiSessionAccessToken = $null
        $script:WdlGuiSessionTenantId = $null
        $script:WdlGuiSessionExpiresUtc = $null
        $script:WdlGuiSessionAuthenticated = $false
        if ($ui -and $ui.Authentication -and -not $backendMode) {
            $ui.Authentication.Text = if ($usesInteractiveUserAuthentication) { "$Method - Signed out" } else { "$Method - Non-interactive" }
        }
        if ($btnSignIn) { $btnSignIn.Text = 'Sign in' }
    }

    function Get-GuiBackendParameters {
        if (-not $backendMode) { throw 'This action requires -BackendUri and -BackendApiKey.' }
        @{ BackendUri=$BackendUri; BackendApiKey=$BackendApiKey }
    }


    function Get-GuiRuntimeParameters {
        $parameters = @{}
        if ($outerBoundParameters.ContainsKey('WindowsManagementServicePath')) {
            $parameters.WindowsManagementServicePath = $WindowsManagementServicePath
        }
        $parameters
    }

    $ui = @{}
    $script:WdlGuiBusy = $false
    $script:WdlGuiLocalAssociation = $null
    $script:WdlGuiCloudStatus = $null
    $script:WdlGuiSupport = $null
    $script:WdlGuiSessionAccessToken = $null
    $script:WdlGuiSessionTenantId = $null
    $script:WdlGuiSessionExpiresUtc = $null
    $script:WdlGuiSessionAuthenticated = $false

    $deviceCard = New-Card -Title 'Device' -X 14 -Y 12 -Width 508 -Height 126
    $connectionCard = New-Card -Title 'Connection' -X 536 -Y 12 -Width 508 -Height 126
    $associationCard = New-Card -Title 'Local association' -X 14 -Y 150 -Width 508 -Height 126
    $cloudCard = New-Card -Title 'Cloud association' -X 536 -Y 150 -Width 508 -Height 126
    $deviceCard.BackColor = $colorCardTint
    $connectionCard.BackColor = $colorCardTint
    $associationCard.BackColor = $colorCardTint
    $cloudCard.BackColor = $colorCardTint

    $deviceAccent = New-Object System.Windows.Forms.Panel
    $deviceAccent.BackColor = $colorCardAccent
    $deviceAccent.Location = [System.Drawing.Point]::new(0,0)
    $deviceAccent.Size = [System.Drawing.Size]::new(4,126)
    $deviceCard.Controls.Add($deviceAccent)

    $connectionAccent = New-Object System.Windows.Forms.Panel
    $connectionAccent.BackColor = $colorCardAccent
    $connectionAccent.Location = [System.Drawing.Point]::new(0,0)
    $connectionAccent.Size = [System.Drawing.Size]::new(4,126)
    $connectionCard.Controls.Add($connectionAccent)

    $localAccent = New-Object System.Windows.Forms.Panel
    $localAccent.BackColor = $colorCardAccent
    $localAccent.Location = [System.Drawing.Point]::new(0,0)
    $localAccent.Size = [System.Drawing.Size]::new(4,126)
    $associationCard.Controls.Add($localAccent)

    $ui.CloudAccent = New-Object System.Windows.Forms.Panel
    $ui.CloudAccent.BackColor = $colorCardAccent
    $ui.CloudAccent.Location = [System.Drawing.Point]::new(0,0)
    $ui.CloudAccent.Size = [System.Drawing.Size]::new(4,126)
    $cloudCard.Controls.Add($ui.CloudAccent)

    $ui.Manufacturer = New-ValuePair -Parent $deviceCard -Caption 'Manufacturer' -Y 34 -CaptionWidth 105 -ValueWidth 335
    $ui.Model        = New-ValuePair -Parent $deviceCard -Caption 'Model' -Y 56 -CaptionWidth 105 -ValueWidth 335
    $ui.Serial       = New-ValuePair -Parent $deviceCard -Caption 'Serial number' -Y 78 -CaptionWidth 105 -ValueWidth 335
    $ui.OperatingSystem = New-ValuePair -Parent $deviceCard -Caption 'Operating system' -Y 100 -CaptionWidth 105 -ValueWidth 335

    $ui.ConnectionMode = New-ValuePair -Parent $connectionCard -Caption 'Mode' -Y 34 -CaptionWidth 105 -ValueWidth 335
    $ui.Authentication = New-ValuePair -Parent $connectionCard -Caption 'Authentication' -Y 56 -CaptionWidth 105 -ValueWidth 335
    $ui.Endpoint       = New-ValuePair -Parent $connectionCard -Caption 'Endpoint' -Y 78 -CaptionWidth 105 -ValueWidth 335
    $ui.TenantScope    = New-ValuePair -Parent $connectionCard -Caption 'Tenant scope' -Y 100 -CaptionWidth 105 -ValueWidth 335

    $ui.LocalState = New-ValuePair -Parent $associationCard -Caption 'State' -Y 34 -CaptionWidth 105 -ValueWidth 335
    $ui.LocalState.Text = 'Not checked'
    $ui.Firmware   = New-ValuePair -Parent $associationCard -Caption 'Firmware' -Y 56 -CaptionWidth 105 -ValueWidth 335
    $ui.Firmware.Text = 'Not checked'
    $ui.LinkId     = New-ValuePair -Parent $associationCard -Caption 'Link ID' -Y 78 -CaptionWidth 105 -ValueWidth 335
    $ui.LinkId.Text = 'Not checked'
    $ui.LocalCreated = New-ValuePair -Parent $associationCard -Caption 'Created' -Y 100 -CaptionWidth 105 -ValueWidth 335
    $ui.LocalCreated.Text = 'Not checked'

    $ui.CloudState  = New-ValuePair -Parent $cloudCard -Caption 'State' -Y 34 -CaptionWidth 105 -ValueWidth 335
    $ui.CloudState.Text = 'Not checked'
    $ui.CloudTenant = New-ValuePair -Parent $cloudCard -Caption 'Tenant' -Y 56 -CaptionWidth 105 -ValueWidth 335
    $ui.CloudTenant.Text = 'Not checked'
    $ui.CloudId = New-ValuePair -Parent $cloudCard -Caption 'Association ID' -Y 78 -CaptionWidth 105 -ValueWidth 335
    $ui.CloudId.Text = 'Not checked'
    $ui.CloudChecked = New-ValuePair -Parent $cloudCard -Caption 'Last checked' -Y 100 -CaptionWidth 105 -ValueWidth 335
    $ui.CloudChecked.Text = 'Not checked'

    $actionsTitle = New-Object System.Windows.Forms.Label
    $actionsTitle.Text = 'Actions'
    $actionsTitle.Font = New-GuiFont -Size 11.5 -Style Bold
    $actionsTitle.Location = [System.Drawing.Point]::new(16,150)
    $actionsTitle.AutoSize = $true
    $content.Controls.Add($actionsTitle)

    $actionsPanel = New-Card -Title '' -X 14 -Y 176 -Width 1030 -Height 196

    $assignmentRow = New-Object System.Windows.Forms.Panel
    $assignmentRow.Location = [System.Drawing.Point]::new(0,0)
    $assignmentRow.Size = [System.Drawing.Size]::new(1030,46)
    $assignmentRow.BackColor = [System.Drawing.Color]::White
    $actionsPanel.Controls.Add($assignmentRow)

    $assignmentTitle = New-Object System.Windows.Forms.Label
    $assignmentTitle.Text = 'Tenant assignment'
    $assignmentTitle.Font = New-GuiFont -Size 8.5 -Style Bold
    $assignmentTitle.Location = [System.Drawing.Point]::new(14,5)
    $assignmentTitle.AutoSize = $true
    $assignmentRow.Controls.Add($assignmentTitle)

    $assignmentDescription = New-Object System.Windows.Forms.Label
    $assignmentDescription.Text = 'Select the destination and choose pre-registration or full registration.'
    $assignmentDescription.Font = New-GuiFont -Size 8.2 -Style Regular
    $assignmentDescription.ForeColor = [System.Drawing.Color]::FromArgb(108,108,108)
    $assignmentDescription.Location = [System.Drawing.Point]::new(14,23)
    $assignmentDescription.AutoSize = $true
    $assignmentRow.Controls.Add($assignmentDescription)

    $tenantCaption = New-Object System.Windows.Forms.Label
    $tenantCaption.Text = 'Target tenant'
    $tenantCaption.Font = New-GuiFont -Size 8.5 -Style Regular
    $tenantCaption.ForeColor = [System.Drawing.Color]::FromArgb(102,102,102)
    $tenantCaption.Location = [System.Drawing.Point]::new(500,14)
    $tenantCaption.Size = [System.Drawing.Size]::new(88,18)
    $assignmentRow.Controls.Add($tenantCaption)

    $tenantSelector = New-Object System.Windows.Forms.ComboBox
    $tenantSelector.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $tenantSelector.Font = New-GuiFont -Size 8.5 -Style Regular
    $tenantSelector.Location = [System.Drawing.Point]::new(588,9)
    $tenantSelector.ItemHeight = 22
    $tenantSelector.Size = [System.Drawing.Size]::new(220,28)
    foreach ($choice in $tenantChoices) {
        [void]$tenantSelector.Items.Add($choice)
    }
    $tenantSelector.SelectedIndex = 0
    $tenantCaption.Visible = $showTenantSelector
    $tenantSelector.Visible = $showTenantSelector
    if (-not $showTenantSelector) {
        $assignmentDescription.Text = if ($outerBoundParameters.ContainsKey('TenantId')) {
            'The destination tenant is fixed by the supplied tenant ID. Choose pre-registration or full registration.'
        }
        else {
            'The destination tenant is determined by sign-in. Choose pre-registration or full registration.'
        }
    }
    $assignmentRow.Controls.Add($tenantSelector)

    $btnAssign = New-Object System.Windows.Forms.Button
    $btnAssign.Text = 'Pre-register'
    $btnAssign.Font = New-GuiFont -Size 8.6 -Style Regular
    $btnAssign.Size = [System.Drawing.Size]::new(94,28)
    $btnAssign.Location = [System.Drawing.Point]::new(816,9)
    $btnAssign.FlatStyle = [System.Windows.Forms.FlatStyle]::Standard
    $btnAssign.UseVisualStyleBackColor = $true
    $assignmentRow.Controls.Add($btnAssign)

    $btnFullAssociate = New-Object System.Windows.Forms.Button
    $btnFullAssociate.Text = 'Full register'
    $btnFullAssociate.Font = New-GuiFont -Size 8.6 -Style Regular
    $btnFullAssociate.Size = [System.Drawing.Size]::new(96,28)
    $btnFullAssociate.Location = [System.Drawing.Point]::new(918,9)
    $btnFullAssociate.FlatStyle = [System.Windows.Forms.FlatStyle]::Standard
    $btnFullAssociate.UseVisualStyleBackColor = $true
    $assignmentRow.Controls.Add($btnFullAssociate)

    $assignmentSeparator = New-Object System.Windows.Forms.Panel
    $assignmentSeparator.BackColor = [System.Drawing.Color]::FromArgb(232,232,232)
    $assignmentSeparator.Location = [System.Drawing.Point]::new(14,45)
    $assignmentSeparator.Size = [System.Drawing.Size]::new(1002,1)
    $assignmentRow.Controls.Add($assignmentSeparator)

    $rowTools = New-ActionRow -Parent $actionsPanel -Title 'Status' -Description 'Sign in for cloud actions, or refresh local or cloud state.' -Y 46 -Buttons @('Sign in','Refresh cloud','Refresh local')
    $rowExport = New-ActionRow -Parent $actionsPanel -Title 'Export' -Description 'Export DeviceLink CSV for manual import in Intune.' -Y 92 -Buttons @('Export CSV')
    $rowOffboard = New-ActionRow -Parent $actionsPanel -Title 'Offboarding' -Description 'Remove the cloud association, local state, or both.' -Y 138 -Buttons @('Remove cloud','Remove local','Remove both')

    $offboardSeparator = @(
        $rowOffboard.Panel.Controls |
            Where-Object { $_ -is [System.Windows.Forms.Panel] -and $_.Height -eq 1 }
    ) | Select-Object -First 1
    if ($offboardSeparator) {
        $rowOffboard.Panel.Controls.Remove($offboardSeparator)
        $offboardSeparator.Dispose()
    }

    function Get-ActionButtonByText {
        param(
            [Parameter(Mandatory)][System.Windows.Forms.Control]$Row,
            [Parameter(Mandatory)][string]$Text
        )

        $button = @(
            $Row.Controls |
                Where-Object { $_ -is [System.Windows.Forms.Button] -and $_.Text -eq $Text }
        ) | Select-Object -First 1

        if (-not $button) {
            throw "GUI action button '$Text' could not be resolved."
        }

        $button
    }

    $btnSignIn = Get-ActionButtonByText -Row $rowTools.Panel -Text 'Sign in'
    $btnRefresh = Get-ActionButtonByText -Row $rowTools.Panel -Text 'Refresh local'
    $btnOnline = Get-ActionButtonByText -Row $rowTools.Panel -Text 'Refresh cloud'
    $btnExport = Get-ActionButtonByText -Row $rowExport.Panel -Text 'Export CSV'
    $btnCloudOffboard = Get-ActionButtonByText -Row $rowOffboard.Panel -Text 'Remove cloud'
    $btnLocalOffboard = Get-ActionButtonByText -Row $rowOffboard.Panel -Text 'Remove local'
    $btnFullOffboard = Get-ActionButtonByText -Row $rowOffboard.Panel -Text 'Remove both'

    $allActionButtons = @(
        $btnAssign,
        $btnSignIn,
        $btnRefresh,
        $btnOnline,
        $btnExport,
        $btnFullAssociate,
        $btnCloudOffboard,
        $btnLocalOffboard,
        $btnFullOffboard
    )

    $btnSignIn.Visible = $usesInteractiveUserAuthentication
    if (-not $usesInteractiveUserAuthentication) {
        $rowTools.Description.Text = 'Refresh local or cloud state.'
    }
    $actionsPanel.Height = 184

    $activityTitle = New-Object System.Windows.Forms.Label
    $activityTitle.Text = 'Activity'
    $activityTitle.Font = New-GuiFont -Size 11 -Style Bold
    $activityTitle.Location = [System.Drawing.Point]::new(16,564)
    $activityTitle.AutoSize = $true
    $content.Controls.Add($activityTitle)

    $btnClearActivity = New-Object System.Windows.Forms.Button
    $btnClearActivity.Text = 'Clear'
    $btnClearActivity.Font = New-GuiFont -Size 8.3 -Style Regular
    $btnClearActivity.Size = [System.Drawing.Size]::new(64,24)
    $btnClearActivity.FlatStyle = [System.Windows.Forms.FlatStyle]::Standard
    $content.Controls.Add($btnClearActivity)

    $activityCard = New-Card -Title '' -X 14 -Y 590 -Width 1030 -Height 118

    $consoleBox = New-Object System.Windows.Forms.TextBox
    $consoleBox.Location = [System.Drawing.Point]::new(12,10)
    $consoleBox.Size = [System.Drawing.Size]::new(1006,96)
    $consoleBox.Multiline = $true
    $consoleBox.ReadOnly = $true
    $consoleBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $consoleBox.WordWrap = $false
    $consoleBox.Font = New-GuiFont -Family 'Consolas' -Size 8 -Style Regular
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
    $statusProgress.Size = [System.Drawing.Size]::new(220,16)
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

        foreach ($item in @($InputObject)) {
            if ($null -eq $item) { continue }

            $properties = @($item.PSObject.Properties)
            if ($properties.Count -eq 0) {
                $text = [string]$item
                if (-not [string]::IsNullOrWhiteSpace($text)) {
                    Write-GuiConsole -Message $text
                }
                continue
            }

            $rows = New-Object System.Collections.Generic.List[object]
            $compactHiddenProperties = @(
                'RegistrationResult',
                'BeforeStatus',
                'AfterStatus',
                'FullAssociationDetails'
            )

            foreach ($property in $properties) {
                if ([string]$property.Name -in $compactHiddenProperties) { continue }

                $value = $property.Value
                if ($null -eq $value) { continue }

                if ($value -is [string] -and [string]::IsNullOrWhiteSpace($value)) { continue }

                if ($value -is [datetime]) {
                    $displayValue = $value.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                }
                elseif ($value -is [datetimeoffset]) {
                    $displayValue = $value.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                }
                elseif ($value -is [System.Collections.IEnumerable] -and -not ($value -is [string])) {
                    $items = @($value)
                    if ($items.Count -eq 0) { continue }
                    $displayValue = ($items | ForEach-Object { [string]$_ }) -join ', '
                }
                else {
                    $displayValue = [string]$value
                }

                if ([string]::IsNullOrWhiteSpace($displayValue)) { continue }

                $rows.Add([pscustomobject]@{
                    Name = [string]$property.Name
                    Value = $displayValue
                })
            }

            if ($rows.Count -eq 0) { continue }

            $nameWidth = [Math]::Min(
                34,
                [Math]::Max(
                    8,
                    (@($rows | ForEach-Object { $_.Name.Length }) | Measure-Object -Maximum).Maximum
                )
            )

            foreach ($row in $rows) {
                $name = $row.Name
                if ($name.Length -gt $nameWidth) {
                    $name = $name.Substring(0,$nameWidth)
                }
                Write-GuiConsole -Message (("{0,-$nameWidth} : {1}" -f $name,$row.Value))
            }
        }
    }

    function Invoke-GuiInformationCommand {
        param(
            [Parameter(Mandatory)]
            [scriptblock]$ScriptBlock
        )

        $resultObjects = New-Object System.Collections.Generic.List[object]

        & $ScriptBlock 6>&1 | ForEach-Object {
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

        return @($resultObjects.ToArray())
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

        $result = [System.Windows.Forms.MessageBox]::Show(
            $form,
            $Message,
            $Title,
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )

        return ($result -eq [System.Windows.Forms.DialogResult]::Yes)
    }

    function Set-GuiCapabilities {
        $support = $script:WdlGuiSupport
        $local = $script:WdlGuiLocalAssociation
        $cloud = $script:WdlGuiCloudStatus

        $runtimeReady = $support -and [bool]$support.Supported
        $canFullAssociation = $runtimeReady -and [string]$support.Environment -ne 'WindowsPE'

        $cloudState = if ($cloud) { ([string]$cloud.AssociationState).Trim().ToLowerInvariant() } else { '' }
        $cloudKnownAbsent = $cloud -and (
            $cloud.AssociationPresent -eq $false -or
            $cloudState -eq 'notassociated'
        )
        $cloudPresent = $cloud -and $cloud.AssociationPresent -eq $true
        $localFullyAssociated = $local -and [string]$local.FirmwareState -eq '4/4'
        $selectedTenantId = Get-SelectedTenantId
        $selectedMatchesCloud = $cloudPresent -and -not [string]::IsNullOrWhiteSpace($selectedTenantId) -and
            [string]$cloud.TenantId -ieq $selectedTenantId
        $alreadyRegisteredInTarget = $selectedMatchesCloud -and $cloudState -in @('associated','preassociated')
        $alreadyFullyAssociatedInTarget = $localFullyAssociated -and $selectedMatchesCloud -and $cloudState -eq 'associated'

        $btnRefresh.Enabled = $true
        $directTenantReady = -not $hasDirectTenantCatalog -or -not [string]::IsNullOrWhiteSpace((Get-SelectedTenantId))
        $btnSignIn.Enabled = $usesInteractiveUserAuthentication -and $directTenantReady
        $btnOnline.Enabled = $runtimeReady -and ($backendMode -or $directTenantReady)
        $btnExport.Enabled = $runtimeReady
        $targetReadyToRegister = if ($backendMode -or $hasDirectTenantCatalog) { -not [string]::IsNullOrWhiteSpace((Get-SelectedTenantId)) } else { $true }
        $btnAssign.Enabled = $runtimeReady -and $targetReadyToRegister -and -not $alreadyRegisteredInTarget
        $btnFullAssociate.Enabled = $canFullAssociation -and $targetReadyToRegister -and -not $alreadyFullyAssociatedInTarget
        $btnCloudOffboard.Enabled = $runtimeReady -and -not $cloudKnownAbsent -and ($backendMode -or $directTenantReady)
        $btnLocalOffboard.Enabled = -not $backendMode -or $cloudKnownAbsent
        $btnFullOffboard.Enabled = $runtimeReady -and ($backendMode -or $directTenantReady)

        $toolTip.SetToolTip($btnCloudOffboard, 'Remove only the tenant-side Device Association record.')
        $toolTip.SetToolTip($btnLocalOffboard, $(if ($backendMode -and -not $cloudKnownAbsent) { 'Backend mode blocks standalone local removal while a cloud association exists. Use registration or move workflows to keep both states consistent.' } else { 'Remove only the local DeviceLink firmware state.' }))
        $toolTip.SetToolTip($btnFullOffboard, 'Remove the cloud association and reset the local DeviceLink firmware state.')
        $toolTip.SetToolTip($btnFullAssociate, 'Register in the selected tenant and complete Device Association on this Windows device.')
        $toolTip.SetToolTip($btnAssign, 'Pre-register the device in the selected target tenant. Backend mode safely applies New, no-op, or Move.')
        $toolTip.SetToolTip($btnSignIn, 'Authenticate once for this Direct-mode UI session and load the cloud association.')
        if ($hasDirectTenantCatalog -and -not $directTenantReady) {
            $toolTip.SetToolTip($btnSignIn, 'Select a target tenant first. Sign-in will be scoped to that tenant.')
            $toolTip.SetToolTip($btnAssign, 'Select a target tenant first. Direct mode applies New or no-op only in that selected tenant.')
            $toolTip.SetToolTip($btnFullAssociate, 'Select a target tenant first, then sign in to perform full registration.')
        }
        elseif (-not $backendMode) { $toolTip.SetToolTip($btnAssign, 'Direct mode applies New or no-op in the selected tenant, or in the tenant determined by sign-in when no catalog is configured.') }
        elseif (-not $cloud) { $toolTip.SetToolTip($btnAssign, 'Check all configured tenants, renew the local identity when required, and register the device in the selected target tenant.') }

        if ($alreadyFullyAssociatedInTarget) {
            $toolTip.SetToolTip($btnFullAssociate, 'The device is already fully registered.')
        }
        if ($alreadyRegisteredInTarget) {
            $toolTip.SetToolTip($btnAssign, 'The device is already registered in the selected tenant. Select another tenant to move it.')
        }

        if ($cloudKnownAbsent) {
            $toolTip.SetToolTip($btnCloudOffboard, 'Cloud state is already known to be Not associated; there is nothing to remove.')
        }

        if ($support -and [string]$support.Environment -eq 'WindowsPE') {
            $toolTip.SetToolTip(
                $btnFullAssociate,
                'Full registration is not available in Windows PE. Pre-register the device now; full registration is completed automatically during Windows OOBE.'
            )
            $onlineToolTip = if ($backendMode) {
                'Windows PE online operations are performed through the configured Function backend.'
            }
            else {
                "Windows PE online operations use authentication method '$Method'. Interactive browser authentication is not supported in WinPE."
            }
            $toolTip.SetToolTip($btnOnline,$onlineToolTip)
        }

        if (-not $runtimeReady -and $support) {
            $runtimeReason = if ([string]::IsNullOrWhiteSpace([string]$support.Reason)) {
                'The local DeviceLink runtime is unavailable.'
            }
            else {
                [string]$support.Reason
            }

            foreach ($button in @($btnAssign,$btnFullAssociate,$btnOnline,$btnExport,$btnFullOffboard)) {
                $toolTip.SetToolTip($button,$runtimeReason)
            }
        }
    }

    function Set-GuiBusy {
        param(
            [Parameter(Mandatory)][bool]$Busy,
            [string]$StatusText
        )

        $script:WdlGuiBusy = $Busy

        if ($Busy) {
            foreach ($button in $allActionButtons) {
                $button.Enabled = $false
            }
            $actionsPanel.Enabled = $false
            $tenantSelector.Enabled = $false
        }
        else {
            $actionsPanel.Enabled = $true
            $tenantSelector.Enabled = $showTenantSelector
            Set-GuiCapabilities
        }

        $btnClearActivity.Enabled = -not $Busy
        $statusProgress.Visible = $Busy
        $form.UseWaitCursor = $Busy

        if (-not [string]::IsNullOrWhiteSpace($StatusText)) {
            Set-GuiStatus $StatusText
        }

        foreach ($button in $allActionButtons) {
            $button.Invalidate()
            $button.Update()
        }

        $actionsPanel.Invalidate($true)
        $actionsPanel.Update()
        $tenantSelector.Invalidate()
        $tenantSelector.Update()
        [System.Windows.Forms.Application]::DoEvents()
    }

    function Refresh-LocalView {
        Set-GuiStatus 'Refreshing local state...'
        Write-GuiConsole -Message 'Refresh local state' -Command

        $ui.LocalState.Text = 'Checking...'
        $ui.Firmware.Text = 'Checking...'
        $ui.LinkId.Text = 'Checking...'
        $ui.LocalCreated.Text = 'Checking...'
        [System.Windows.Forms.Application]::DoEvents()

        $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
        $runtimeParameters = Get-GuiRuntimeParameters
        $support = Test-WindowsDeviceLinkSupport @runtimeParameters
        $local = Get-WindowsDeviceLinkLocalAssociation

        $script:WdlGuiSupport = $support
        $script:WdlGuiLocalAssociation = $local

        $ui.Manufacturer.Text = [string]$cs.Manufacturer
        $ui.Model.Text = [string]$cs.Model
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

        $ui.OperatingSystem.Text = $environmentText

        $environmentToolTip = if ($support.Supported) {
            @(
                $environmentText
                "Activation: $($support.ActivationMode)"
                "Runtime: $($support.DllVersion)"
            ) -join [Environment]::NewLine
        }
        else {
            @(
                $environmentText
                "Runtime unavailable: $($support.Reason)"
            ) -join [Environment]::NewLine
        }
        $toolTip.SetToolTip($ui.OperatingSystem,$environmentToolTip)

        if (-not $support.Supported) {
            Write-GuiConsole -Message "DeviceLink runtime unavailable: $($support.Reason)"
        }

        $selectedTenant = Get-SelectedTenantId
        if ($backendMode) {
            $ui.ConnectionMode.Text = 'Backend'
            $ui.Authentication.Text = 'Function API key'
            $ui.Endpoint.Text = [string]$BackendUri.Host
            $ui.TenantScope.Text = "$($effectiveTenants.Count) available tenants"
            $toolTip.SetToolTip($ui.Endpoint,[string]$BackendUri.AbsoluteUri)
        }
        else {
            $ui.ConnectionMode.Text = 'Direct'
            if ($usesInteractiveUserAuthentication) {
                $sessionState = if ($script:WdlGuiSessionAuthenticated) { 'Signed in' } else { 'Signed out' }
                $ui.Authentication.Text = "$Method - $sessionState"
            }
            else {
                $ui.Authentication.Text = "$Method - Non-interactive"
            }
            $ui.Endpoint.Text = 'Microsoft Graph'
            $ui.TenantScope.Text = if ($selectedTenant) { Get-TenantDisplayName -TenantId $selectedTenant } else { 'Determined by sign-in' }
        }

        $ui.Firmware.Text = [string]$local.FirmwareState

        $friendlyLocalState = switch ([string]$local.LocalAssociationState) {
            'CompleteAssociationFirmwareState' { 'Full association' }
            'BaseIdentity' { 'Base identity' }
            'NoFirmwareState' { 'No firmware state' }
            'IncompleteFirmwareState' { 'Incomplete firmware state' }
            default { [string]$local.LocalAssociationState }
        }
        $ui.LocalState.Text = $friendlyLocalState
        $localLinkId = if ($local.LinkId) { [string]$local.LinkId } else { $null }
        $ui.LinkId.Text = if ($localLinkId) { $localLinkId } else { 'Unavailable' }
        $ui.LocalCreated.Text = if ($local.FirmwareCreationTimeUtc) {
            try { ([datetime]$local.FirmwareCreationTimeUtc).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss UTC') }
            catch { [string]$local.FirmwareCreationTimeUtc }
        }
        else { 'Unavailable' }
        $toolTip.SetToolTip($ui.LinkId, $(if ($localLinkId) { $localLinkId } else { 'Unavailable' }))
        $toolTip.SetToolTip($ui.LocalCreated, [string]$ui.LocalCreated.Text)

        Set-GuiCapabilities
        Set-GuiStatus "Local state refreshed | $($local.FirmwareState)"
        Write-GuiConsole -Message "Local state: $($local.FirmwareState), tenant source: $($local.Source)"
    }

    function Get-GuiCloudStateText {
        param([AllowNull()][object]$State)

        switch (([string]$State).Trim().ToLowerInvariant()) {
            'associated'    { return 'Associated' }
            'preassociated' { return 'Pre-associated' }
            'notassociated' { return 'Not associated' }
            default {
                if ([string]::IsNullOrWhiteSpace([string]$State)) {
                    return 'Not checked'
                }
                return [string]$State
            }
        }
    }

    function Refresh-CloudView {
        param(
            [switch]$WriteCommand
        )

        $ui.CloudState.Text = 'Checking...'
        $ui.CloudTenant.Text = 'Checking...'
        $ui.CloudId.Text = 'Checking...'
        $ui.CloudChecked.Text = 'Checking...'
        [System.Windows.Forms.Application]::DoEvents()

        if ($backendMode) {
            $credential = New-Object System.Management.Automation.PSCredential('api-key',$BackendApiKey)
            $plainKey = $null
            try {
                $plainKey = $credential.GetNetworkCredential().Password
                $parameters = @{ BackendUri=$BackendUri; BackendApiKey=$plainKey }
                $runtimeParameters = Get-GuiRuntimeParameters
                foreach ($key in $runtimeParameters.Keys) { $parameters[$key]=$runtimeParameters[$key] }
                if ($WriteCommand) { Write-GuiConsole -Message 'Get-WindowsDeviceLinkStatus through Backend mode' -Command }
                $cloud = Get-WindowsDeviceLinkBackendStatus @parameters
            }
            finally { $plainKey=$null; $credential=$null }
        }
        else {
            $parameters = Get-GuiAuthParameters
            $runtimeParameters = Get-GuiRuntimeParameters
            foreach ($key in $runtimeParameters.Keys) { $parameters[$key]=$runtimeParameters[$key] }
            $parameters.Online = $true
            if ($WriteCommand) { Write-GuiConsole -Message "Get-WindowsDeviceLinkStatus -Online -Method $Method" -Command }
            $cloudResults = @(Invoke-GuiInformationCommand -ScriptBlock { Get-WindowsDeviceLinkStatus @parameters })
            $cloud = $cloudResults | Select-Object -Last 1
        }
        $script:WdlGuiCloudStatus = $cloud

        if ($usesInteractiveUserAuthentication) {
            $script:WdlGuiSessionAuthenticated = $true
            $ui.Authentication.Text = "$Method - Signed in"
            $btnSignIn.Text = 'Switch account'
        }

        $ui.CloudState.Text = Get-GuiCloudStateText -State $cloud.AssociationState
        $ui.CloudTenant.Text = if ($cloud.TenantId) { Get-TenantDisplayName -TenantId ([string]$cloud.TenantId) } else { 'None' }
        $cloudAssociationId = if ($cloud.AssociationId) { [string]$cloud.AssociationId } else { $null }
        $ui.CloudId.Text = if ($cloudAssociationId) { $cloudAssociationId } else { 'None' }
        $ui.CloudChecked.Text = (Get-Date).ToString('HH:mm:ss')
        $ui.CloudAccent.BackColor = $colorCardAccent
        $cloudCard.BackColor = $colorCardTint

        $cloudTenantIdText = if ($cloud.TenantId) { [string]$cloud.TenantId } else { 'Unavailable' }
        $toolTip.SetToolTip($ui.CloudTenant,$cloudTenantIdText)
        $toolTip.SetToolTip($ui.CloudId, $(if ($cloudAssociationId) { $cloudAssociationId } else { 'None' }))

        return $cloud
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
            $cloud = Refresh-CloudView -WriteCommand
            Write-GuiObject $cloud

            Set-GuiStatus 'Cloud lookup completed'
        }
        catch {
            Set-GuiStatus 'Cloud lookup failed'
            Show-GuiError $_.Exception.Message
        }
        finally { Set-GuiBusy -Busy $false }
    }

    function Invoke-GuiSignIn {
        if ($script:WdlGuiBusy -or $backendMode) { return }

        Clear-GuiSessionAuthentication
        Set-GuiBusy -Busy $true -StatusText 'Signing in...'
        try {
            [void](Get-GuiAuthParameters)
            $cloud = Refresh-CloudView -WriteCommand
            Write-GuiObject $cloud
            Set-GuiStatus 'Signed in; cloud association loaded'
        }
        catch {
            Clear-GuiSessionAuthentication
            Set-GuiStatus 'Sign-in failed'
            Show-GuiError $_.Exception.Message
        }
        finally { Set-GuiBusy -Busy $false }
    }

    function Invoke-GuiTenantAssignment {
        if ($script:WdlGuiBusy) { return }
        $targetId = Get-SelectedTenantId
        if ($backendMode -and [string]::IsNullOrWhiteSpace($targetId)) { Show-GuiError 'Select a target tenant first.'; return }
        if ($hasDirectTenantCatalog -and [string]::IsNullOrWhiteSpace($targetId)) { Show-GuiError 'Select a target tenant first. Direct-mode sign-in and registration will use that tenant.'; return }
        $targetLabel = if ($targetId) { [string]$tenantSelector.SelectedItem } else { 'Tenant determined by sign-in' }
        $sourceText = if ($script:WdlGuiCloudStatus -and $script:WdlGuiCloudStatus.TenantId) { [string]$script:WdlGuiCloudStatus.TenantId } else { 'determined automatically' }
        $modeText = if ($backendMode) {
            'Backend mode can perform a verified Move when another configured tenant currently contains the device.'
        } else {
            'Direct mode checks only the chosen sign-in tenant and can perform New or no-op; it cannot prove absence from other tenants.'
        }
        $message = @("Current cloud tenant: $sourceText","Target tenant: $targetLabel",'',$modeText,'','Continue?') -join [Environment]::NewLine
        if (-not $backendMode -and -not (Confirm-GuiAction -Title 'Register tenant assignment' -Message $message)) { return }

        Set-GuiBusy -Busy $true -StatusText $(if ($backendMode) { 'Checking cloud state and registering device...' } else { 'Applying tenant assignment...' })
        try {
            $parameters = if ($backendMode) { Get-GuiBackendParameters } else { Get-GuiAuthParameters }
            if ($backendMode) { $parameters.TargetTenantId = [guid]$targetId }
            $parameters.Confirm = $false
            $runtimeParameters = Get-GuiRuntimeParameters
            foreach ($key in $runtimeParameters.Keys) { $parameters[$key]=$runtimeParameters[$key] }
            $commandText = if ($backendMode) { "Set-WindowsDeviceLinkTenant -BackendUri <configured> -TargetTenantId $targetId" } elseif ($targetId) { "Set-WindowsDeviceLinkTenant -Method $Method -TenantId $targetId" } else { "Set-WindowsDeviceLinkTenant -Method $Method" }
            Write-GuiConsole -Message $commandText -Command
            $results = @(Invoke-GuiInformationCommand -ScriptBlock { Set-WindowsDeviceLinkTenant @parameters })
            $result = $results | Select-Object -Last 1
            Write-GuiObject $result
            Refresh-LocalView
            if ($backendMode) {
                $cloud = Refresh-CloudView
            }
            else {
                $cloud = $result.Details.AfterStatus
                $script:WdlGuiCloudStatus = $cloud
                $ui.CloudState.Text = Get-GuiCloudStateText -State $cloud.AssociationState
                $ui.CloudTenant.Text = if ($cloud.TenantId) { Get-TenantDisplayName -TenantId ([string]$cloud.TenantId) } else { 'None' }
                $ui.CloudId.Text = if ($cloud.AssociationId) { [string]$cloud.AssociationId } else { 'None' }
                $ui.CloudChecked.Text = (Get-Date).ToString('HH:mm:ss')
                $ui.CloudAccent.BackColor = $colorCardAccent
                $cloudCard.BackColor = $colorCardTint
            }
            Write-GuiObject $cloud
            Set-GuiStatus ([string]$result.Message)
        }
        catch {
            Set-GuiStatus 'Tenant assignment failed or requires verification'
            if ($backendMode) { try { $cloud = Refresh-CloudView; Write-GuiObject $cloud } catch {} }
            Show-GuiError $_.Exception.Message
        }
        finally { Set-GuiBusy -Busy $false }
    }

    function Select-GuiExportDirectory {
        if (-not $isWinPE) {
            $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
            $dialog.Description = 'Choose a folder for the DeviceLink CSV'
            try {
                if ($dialog.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) {
                    return $null
                }
                return [string]$dialog.SelectedPath
            }
            finally {
                $dialog.Dispose()
            }
        }

        $defaultPath = $null
        if ($outerBoundParameters.ContainsKey('WindowsManagementServicePath')) {
            try {
                $defaultPath = Split-Path -Parent $WindowsManagementServicePath
            }
            catch {}
        }
        if ([string]::IsNullOrWhiteSpace($defaultPath)) {
            try { $defaultPath = (Get-Location).Path } catch {}
        }
        if ([string]::IsNullOrWhiteSpace($defaultPath)) {
            $defaultPath = 'X:\'
        }

        $pathForm = New-Object System.Windows.Forms.Form
        $pathForm.Text = 'Export DeviceLink CSV'
        $pathForm.StartPosition = 'CenterParent'
        $pathForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
        $pathForm.MinimizeBox = $false
        $pathForm.MaximizeBox = $false
        $pathForm.ShowInTaskbar = $false
        $pathForm.Size = [System.Drawing.Size]::new(520,155)

        $pathLabel = New-Object System.Windows.Forms.Label
        $pathLabel.Text = 'Output folder'
        $pathLabel.Font = New-GuiFont -Size 9 -Style Regular
        $pathLabel.Location = [System.Drawing.Point]::new(14,14)
        $pathLabel.AutoSize = $true
        $pathForm.Controls.Add($pathLabel)

        $pathBox = New-Object System.Windows.Forms.TextBox
        $pathBox.Text = $defaultPath
        $pathBox.Font = New-GuiFont -Family 'Consolas' -Size 9 -Style Regular
        $pathBox.Location = [System.Drawing.Point]::new(16,40)
        $pathBox.Size = [System.Drawing.Size]::new(472,24)
        $pathForm.Controls.Add($pathBox)

        $okButton = New-Object System.Windows.Forms.Button
        $okButton.Text = 'Export'
        $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $okButton.Location = [System.Drawing.Point]::new(308,78)
        $okButton.Size = [System.Drawing.Size]::new(86,30)
        $pathForm.Controls.Add($okButton)

        $cancelButton = New-Object System.Windows.Forms.Button
        $cancelButton.Text = 'Cancel'
        $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $cancelButton.Location = [System.Drawing.Point]::new(402,78)
        $cancelButton.Size = [System.Drawing.Size]::new(86,30)
        $pathForm.Controls.Add($cancelButton)

        $pathForm.AcceptButton = $okButton
        $pathForm.CancelButton = $cancelButton

        try {
            while ($true) {
                if ($pathForm.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) {
                    return $null
                }

                $selectedPath = [string]$pathBox.Text
                if (-not [string]::IsNullOrWhiteSpace($selectedPath)) {
                    $selectedPath = $selectedPath.Trim()
                }

                if (-not [string]::IsNullOrWhiteSpace($selectedPath) -and [System.IO.Directory]::Exists($selectedPath)) {
                    return $selectedPath
                }

                [void][System.Windows.Forms.MessageBox]::Show(
                    $pathForm,
                    'The specified output folder does not exist. Enter an existing folder path.',
                    'WindowsDeviceLink',
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                )
            }
        }
        finally {
            $pathForm.Dispose()
        }
    }

    function Invoke-GuiExport {
        if ($script:WdlGuiBusy) { return }

        Set-GuiBusy -Busy $true -StatusText 'Choose export folder...'

        try {
            $selectedPath = Select-GuiExportDirectory
            if ([string]::IsNullOrWhiteSpace($selectedPath)) {
                Set-GuiStatus 'Export cancelled'
                return
            }

            Set-GuiStatus 'Exporting DeviceLink CSV...'
            Write-GuiConsole -Message "Get-WindowsDeviceLink -OutputDirectory '$selectedPath'" -Command

            $deviceLinkParameters = Get-GuiRuntimeParameters
            $deviceLinkParameters.OutputDirectory = $selectedPath
            $file = Get-WindowsDeviceLink @deviceLinkParameters
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
        }
    }

    function Invoke-GuiFullAssociate {
        if ($script:WdlGuiBusy) { return }

        if ($isWinPE) {
            Show-GuiError 'Full registration is not available in Windows PE. Pre-register the device now; full registration is completed automatically during Windows OOBE.'
            return
        }

        $targetId = Get-SelectedTenantId
        if (($backendMode -or $hasDirectTenantCatalog) -and [string]::IsNullOrWhiteSpace($targetId)) {
            Show-GuiError 'Select a target tenant first.'
            return
        }

        Set-GuiBusy -Busy $true -StatusText 'Performing full registration...'
        try {
            if ($backendMode) {
                $assignmentParameters = Get-GuiBackendParameters
                $assignmentParameters.TargetTenantId = [guid]$targetId
                $assignmentParameters.Confirm = $false
                $runtimeParameters = Get-GuiRuntimeParameters
                foreach ($key in $runtimeParameters.Keys) { $assignmentParameters[$key] = $runtimeParameters[$key] }

                $cloudState = if ($script:WdlGuiCloudStatus) { ([string]$script:WdlGuiCloudStatus.AssociationState).Trim().ToLowerInvariant() } else { '' }
                $cloudTenantId = if ($script:WdlGuiCloudStatus) { [string]$script:WdlGuiCloudStatus.TenantId } else { '' }
                if ($script:WdlGuiLocalAssociation -and [string]$script:WdlGuiLocalAssociation.FirmwareState -eq '2/4' -and
                    $cloudState -eq 'associated' -and $cloudTenantId -ieq $targetId) {
                    $assignmentParameters.RepairExistingAssociation = $true
                    Write-GuiConsole -Message 'Same-tenant repair required: replacing the stale cloud association with the current local identity.'
                }

                Write-GuiConsole -Message "Set-WindowsDeviceLinkTenant -BackendUri <configured> -TargetTenantId $targetId" -Command
                $assignmentResults = @(Invoke-GuiInformationCommand -ScriptBlock {
                    Set-WindowsDeviceLinkTenant @assignmentParameters
                })
                $assignment = $assignmentResults | Select-Object -Last 1
                Write-GuiObject $assignment

                Write-GuiConsole -Message 'Complete-WindowsDeviceLinkAssociation' -Command
                $completionResults = @(Invoke-GuiInformationCommand -ScriptBlock {
                    Complete-WindowsDeviceLinkAssociation -Confirm:$false
                })
                $result = $completionResults | Select-Object -Last 1
            }
            else {
                $parameters = Get-GuiAuthParameters
                $runtimeParameters = Get-GuiRuntimeParameters
                foreach ($key in $runtimeParameters.Keys) { $parameters[$key] = $runtimeParameters[$key] }
                $parameters.FullAssociation = $true
                $parameters.Confirm = $false

                Write-GuiConsole -Message "Initialize-WindowsDeviceLink -Method $Method -FullAssociation" -Command
                $resultObjects = New-Object System.Collections.Generic.List[object]
                & {
                    Initialize-WindowsDeviceLink @parameters
                } 6>&1 | ForEach-Object {
                    if ($_ -is [System.Management.Automation.InformationRecord]) {
                        $message = [string]$_.MessageData
                        if ($message) { Write-GuiConsole -Message $message }
                    }
                    else { $resultObjects.Add($_) }
                    [System.Windows.Forms.Application]::DoEvents()
                }
                $result = @($resultObjects.ToArray()) | Select-Object -Last 1
            }

            Write-GuiObject $result

            $script:WdlGuiCloudStatus = $null
            Refresh-LocalView
            $verifiedCloud = Refresh-CloudView -WriteCommand
            Write-GuiObject $verifiedCloud
            Set-GuiStatus 'Full registration completed and verified'
        }
        catch {
            Set-GuiStatus 'Full registration failed or requires verification'
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
            if ($backendMode) {
                $serialNumber = ([string](Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop).SerialNumber).Trim()
                $sourceTenantId = if ($script:WdlGuiCloudStatus) { [string]$script:WdlGuiCloudStatus.TenantId } else { $null }
                $credential = New-Object System.Management.Automation.PSCredential('api-key',$BackendApiKey)
                $plainKey = $null
                try {
                    $plainKey = $credential.GetNetworkCredential().Password
                    Write-GuiConsole -Message 'Invoke backend cloud offboarding' -Command
                    $result = Invoke-WindowsDeviceLinkBackendOffboard -BackendUri $BackendUri -BackendApiKey $plainKey -SerialNumber $serialNumber -SourceTenantId $sourceTenantId
                }
                finally { $plainKey=$null; $credential=$null }

                Write-GuiObject $result
                Refresh-LocalView
                $verifiedCloud = Refresh-CloudView -WriteCommand
                Write-GuiObject $verifiedCloud
                Set-GuiStatus 'Cloud offboarding completed and verified'
                return
            }

            $parameters = Get-GuiAuthParameters
            $parameters.Confirm = $false

            Write-GuiConsole -Message "Remove-WindowsDeviceLinkAssociation -Method $Method" -Command
            $removalResults = @(Invoke-GuiInformationCommand -ScriptBlock {
                Remove-WindowsDeviceLinkAssociation @parameters
            })
            $result = $removalResults | Select-Object -Last 1
            Write-GuiObject $result

            $script:WdlGuiCloudStatus = $null
            $ui.CloudState.Text = 'Not checked'
            $ui.CloudTenant.Text = 'Not checked'
            $ui.CloudId.Text = 'Not checked'
            $ui.CloudChecked.Text = 'Not checked'
            $ui.CloudAccent.BackColor = $colorCardAccent
            $cloudCard.BackColor = $colorCardTint

            Refresh-LocalView
            Set-GuiStatus 'Cloud offboarding completed'
        }
        catch {
            $message = [string]$_.Exception.Message
            if ($message -like "No Device Association record was found for serial number *") {
                $noChangeMessage = 'No cloud association was found. Nothing was removed.'
                Write-GuiConsole -Message $noChangeMessage
                $script:WdlGuiCloudStatus = $null
                $ui.CloudState.Text = 'Not associated'
                $ui.CloudTenant.Text = 'None'
                $ui.CloudId.Text = 'None'
                $ui.CloudChecked.Text = (Get-Date).ToString('HH:mm:ss')
                $ui.CloudAccent.BackColor = $colorCardAccent
                $cloudCard.BackColor = $colorCardTint
                Refresh-LocalView
                Set-GuiStatus $noChangeMessage
                [void][System.Windows.Forms.MessageBox]::Show(
                    $form,
                    $noChangeMessage,
                    'WindowsDeviceLink',
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                )
            }
            else {
                Set-GuiStatus 'Cloud offboarding failed'
                Show-GuiError $message
            }
        }
        finally { Set-GuiBusy -Busy $false }
    }

    function Invoke-GuiLocalOffboard {
        if ($script:WdlGuiBusy) { return }

        if (-not (Confirm-GuiAction -Title 'Local offboarding' -Message 'Remove all known local DeviceLink UEFI variables? The tenant-side Device Association record will remain unchanged.')) {
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
        $effectiveAccessToken = $null
        try {
            if ($backendMode) {
                $serialNumber = ([string](Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop).SerialNumber).Trim()
                $sourceTenantId = if ($script:WdlGuiCloudStatus) { [string]$script:WdlGuiCloudStatus.TenantId } else { $null }
                $credential = New-Object System.Management.Automation.PSCredential('api-key',$BackendApiKey)
                $plainKey = $null
                try {
                    $plainKey = $credential.GetNetworkCredential().Password
                    Write-GuiConsole -Message 'Invoke backend cloud offboarding' -Command
                    $removed = Invoke-WindowsDeviceLinkBackendOffboard -BackendUri $BackendUri -BackendApiKey $plainKey -SerialNumber $serialNumber -SourceTenantId $sourceTenantId
                }
                finally { $plainKey=$null; $credential=$null }
                Write-GuiObject $removed

                Write-GuiConsole -Message 'Reset-WindowsDeviceLinkFirmwareState' -Command
                $reset = Reset-WindowsDeviceLinkFirmwareState -Confirm:$false
                Write-GuiObject $reset

                $script:WdlGuiCloudStatus = $null
                Refresh-LocalView
                $verifiedCloud = Refresh-CloudView -WriteCommand
                Write-GuiObject $verifiedCloud
                Set-GuiStatus 'Full offboarding completed and verified'
                return
            }

            $auth = Get-GuiAuthParameters
            $effectiveAuth = @{}
            foreach ($key in $auth.Keys) { $effectiveAuth[$key] = $auth[$key] }

            if ($effectiveAuth.Method -eq 'DeviceCode') {
                Write-GuiConsole -Message 'Acquiring one DeviceCode token for the complete offboarding flow.' -Command

                $tokenParameters = @{}
                if ($auth.ContainsKey('TenantId')) { $tokenParameters.TenantId = $auth.TenantId }
                if ($auth.ContainsKey('ClientId')) { $tokenParameters.ClientId = $auth.ClientId }

                $tokenResults = @(Invoke-GuiInformationCommand -ScriptBlock {
                    Get-WindowsDeviceLinkDeviceCodeToken @tokenParameters
                })
                $token = $tokenResults | Select-Object -Last 1

                if (-not $token -or [string]::IsNullOrWhiteSpace([string]$token.AccessToken)) {
                    throw 'Device code authentication did not return an access token.'
                }

                $effectiveAccessToken = ConvertTo-SecureString ([string]$token.AccessToken) -AsPlainText -Force
                $effectiveAuth = @{
                    Method = 'AccessToken'
                    AccessToken = $effectiveAccessToken
                    Environment = $Environment
                    ClientTimeout = $ClientTimeout
                }
                if ($token.TenantId) {
                    $effectiveAuth.TenantId = [string]$token.TenantId
                }

                $token = $null
                Write-GuiConsole -Message 'DeviceCode token acquired once; reusing it for cloud verification and removal.'
            }

            $statusParameters = @{}
            foreach ($key in $effectiveAuth.Keys) { $statusParameters[$key] = $effectiveAuth[$key] }
            $runtimeParameters = Get-GuiRuntimeParameters
            foreach ($key in $runtimeParameters.Keys) {
                $statusParameters[$key] = $runtimeParameters[$key]
            }
            $statusParameters.Online = $true

            $displayMethod = [string]$effectiveAuth.Method
            Write-GuiConsole -Message "Get-WindowsDeviceLinkStatus -Online -Method $displayMethod" -Command
            $cloudResults = @(Invoke-GuiInformationCommand -ScriptBlock {
                Get-WindowsDeviceLinkStatus @statusParameters
            })
            $cloud = $cloudResults | Select-Object -Last 1
            Write-GuiObject $cloud

            if ($null -eq $cloud.AssociationPresent -or [string]$cloud.AssociationState -eq 'Unknown') {
                throw 'Cloud Device Association state is indeterminate. Local firmware was not reset.'
            }

            if ($cloud.AssociationPresent) {
                $removeParameters = @{}
                foreach ($key in $effectiveAuth.Keys) { $removeParameters[$key] = $effectiveAuth[$key] }
                $removeParameters.Confirm = $false

                Write-GuiConsole -Message "Remove-WindowsDeviceLinkAssociation -Method $displayMethod" -Command
                $removeResults = @(Invoke-GuiInformationCommand -ScriptBlock {
                    Remove-WindowsDeviceLinkAssociation @removeParameters
                })
                $removed = $removeResults | Select-Object -Last 1
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
            $ui.CloudTenant.Text = 'Not checked'
            $ui.CloudId.Text = 'Not checked'
            $ui.CloudChecked.Text = 'Not checked'
            $ui.CloudAccent.BackColor = $colorCardAccent
            $cloudCard.BackColor = $colorCardTint

            Refresh-LocalView
            Set-GuiStatus 'Full offboarding completed'
        }
        catch {
            Set-GuiStatus 'Full offboarding failed'
            Show-GuiError $_.Exception.Message
        }
        finally {
            $effectiveAccessToken = $null
            Set-GuiBusy -Busy $false
        }
    }

    $btnSignIn.Add_Click({ Invoke-GuiSignIn })
    $btnRefresh.Add_Click({ Invoke-GuiRefresh })
    $btnAssign.Add_Click({ Invoke-GuiTenantAssignment })
    $btnOnline.Add_Click({ Invoke-GuiOnline })
    $btnExport.Add_Click({ Invoke-GuiExport })
    $btnFullAssociate.Add_Click({ Invoke-GuiFullAssociate })
    $btnCloudOffboard.Add_Click({ Invoke-GuiCloudOffboard })
    $btnLocalOffboard.Add_Click({ Invoke-GuiLocalOffboard })
    $btnFullOffboard.Add_Click({ Invoke-GuiFullOffboard })

    $tenantSelector.Add_SelectedIndexChanged({
        if (-not $script:WdlGuiBusy) {
            $selectedTenant = Get-SelectedTenantId
            if (-not $backendMode) {
                if ($script:WdlGuiSessionAuthenticated) {
                    Clear-GuiSessionAuthentication
                    Write-GuiConsole -Message 'Target tenant changed; sign in again to create a Direct-mode session for the selected tenant.'
                }
                $ui.TenantScope.Text = if ($selectedTenant) { Get-TenantDisplayName -TenantId $selectedTenant } else { 'Determined by sign-in' }
            }
            Set-GuiCapabilities
        }
    })

    $btnClearActivity.Add_Click({
        $consoleBox.Clear()
        Write-GuiConsole -Message 'Activity log cleared.'
    })

    $form.Add_FormClosing({
        param($sender,$eventArgs)

        if ($script:WdlGuiBusy) {
            $eventArgs.Cancel = $true
            Write-GuiConsole -Message 'Close request ignored because an operation is still running.'
        }
        else {
            Clear-GuiSessionAuthentication
        }
    })

    $form.Add_Shown({
        $environmentName = if ($isWinPE) { 'Windows PE' } else { 'Windows' }
        $connectionText = if ($backendMode) { 'Backend mode' } else { "Direct mode; authentication method: $Method" }
        Write-GuiConsole -Message "WindowsDeviceLink dashboard opened in $environmentName. $connectionText."
        Set-GuiBusy -Busy $true -StatusText 'Loading local state...'
        try {
            Refresh-LocalView
            if ($backendMode) {
                try {
                    Set-GuiStatus 'Checking cloud association...'
                    $cloud = Refresh-CloudView -WriteCommand
                    Write-GuiObject $cloud
                    Set-GuiStatus 'Device and cloud state loaded'
                }
                catch {
                    $ui.CloudState.Text = 'Check failed'
                    $ui.CloudTenant.Text = 'Unavailable'
                    $ui.CloudId.Text = 'Unavailable'
                    $ui.CloudChecked.Text = (Get-Date).ToString('HH:mm:ss')
                    $ui.CloudAccent.BackColor = $colorCardAccent
                    $cloudCard.BackColor = $colorCardTint
                    Write-GuiConsole -Message ("Automatic cloud check failed: " + $_.Exception.Message) -ErrorMessage
                    Set-GuiStatus 'Local state loaded; cloud check unavailable'
                }
            }
            else {
                Set-GuiStatus 'Local state loaded; sign in to check the cloud association'
            }
        }
        catch { Show-GuiError $_.Exception.Message }
        finally { Set-GuiBusy -Busy $false }
    })

    function Resize-GuiLayout {
        $fullWidth = [Math]::Max(760,$content.ClientSize.Width - 32)
        $gap = 14
        $halfWidth = [Math]::Floor(($fullWidth - $gap) / 2)

        $deviceCard.Location = [System.Drawing.Point]::new(14,12)
        $deviceCard.Size = [System.Drawing.Size]::new([int]$halfWidth,126)
        $connectionCard.Location = [System.Drawing.Point]::new((14 + $halfWidth + $gap),12)
        $connectionCard.Size = [System.Drawing.Size]::new([int]$halfWidth,126)

        $associationCard.Location = [System.Drawing.Point]::new(14,150)
        $associationCard.Size = [System.Drawing.Size]::new([int]$halfWidth,126)
        $cloudCard.Location = [System.Drawing.Point]::new((14 + $halfWidth + $gap),150)
        $cloudCard.Size = [System.Drawing.Size]::new([int]$halfWidth,126)
        $cardsBottom = 276

        foreach ($card in @($deviceCard,$connectionCard,$associationCard,$cloudCard)) {
            foreach ($control in $card.Controls) {
                if ([string]$control.Tag -like 'Value:*') {
                    $control.Width = [Math]::Max(150,$halfWidth - $control.Left - 14)
                }
            }
        }

        $actionsY = $cardsBottom + 12
        $actionsTitle.Location = [System.Drawing.Point]::new(16,$actionsY)
        $actionsPanel.Location = [System.Drawing.Point]::new(14,($actionsY + 26))
        $actionsPanel.Width = $fullWidth

        $assignmentRow.Width = $fullWidth
        $btnFullAssociate.Left = $fullWidth - 16 - $btnFullAssociate.Width
        $btnAssign.Left = $btnFullAssociate.Left - 8 - $btnAssign.Width
        if ($showTenantSelector) {
            $tenantSelector.Left = $btnAssign.Left - 8 - $tenantSelector.Width
            $tenantCaption.Left = $tenantSelector.Left - 88
        }
        $assignmentSeparator.Width = [Math]::Max(480,$fullWidth - 28)

        $activityY = $actionsPanel.Bottom + 14
        $activityTitle.Location = [System.Drawing.Point]::new(16,$activityY)

        # Align Clear to the same right edge used by the action buttons.
        # Action buttons sit 16 px inside the right edge of the Actions panel.
        $clearX = $actionsPanel.Right - 16 - $btnClearActivity.Width
        $clearY = $activityY - 5
        $btnClearActivity.Location = [System.Drawing.Point]::new($clearX,$clearY)

        $activityCard.Location = [System.Drawing.Point]::new(14,($activityY + 26))
        $activityCard.Width = $fullWidth
        $consoleBox.Width = $fullWidth - 24

        # Let Activity consume the remaining client area instead of leaving an
        # unused band below the log on taller WinPE and Windows displays.
        $activityHeight = [Math]::Max(118,$content.ClientSize.Height - $activityCard.Top - 12)
        $activityCard.Height = $activityHeight
        $consoleBox.Height = [Math]::Max(96,$activityHeight - 22)


        foreach ($row in @($rowTools,$rowExport,$rowOffboard)) {
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
        $toolTip.Dispose()
        $form.Dispose()
        if ($formIcon) { $formIcon.Dispose() }
        Remove-Variable WdlGuiLocalAssociation -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable WdlGuiCloudStatus -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable WdlGuiBusy -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable WdlGuiSupport -Scope Script -ErrorAction SilentlyContinue
    }
}
