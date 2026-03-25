#Requires -Version 5.1
$ErrorActionPreference = "Stop"
try { $MaximumFunctionCount = 32768 } catch {}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# =========================
# Branding / Config
# =========================
$ToolName    = "Entra PIM Role Activator"
$ToolVersion = "3.0.1"
$LogFolder   = Join-Path $PSScriptRoot "Logs"

if (-not (Test-Path $LogFolder)) {
    New-Item -Path $LogFolder -ItemType Directory -Force | Out-Null
}

$LogFile = Join-Path $LogFolder ("PIMActivation_GUI_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))

$script:IsConnected         = $false
$script:SuppressRoleEvents  = $false
$script:EligibleRoles       = @()
$script:CurrentUserId       = $null
$script:CurrentTenantName   = ""
$script:RoleDescriptions    = @{}
$script:RoleDefinitionMap   = @{}
$script:PrereqsReady        = $false

# =========================
# Role sets
# =========================
$RoleSets = [ordered]@{
    "Daily Work" = @(
        "Application Administrator",
        "Azure AD Joined Device Local Administrator",
        "Intune Administrator",
        "Authentication Administrator",
        "User Administrator",
        "Groups Administrator"
    )
    "Intune / Endpoint Only" = @(
        "Azure AD Joined Device Local Administrator",
        "Intune Administrator",
        "Groups Administrator",
        "Cloud Device Administrator",
        "Office Apps Administrator"
    )
    "Identity / Authentication" = @(
        "Authentication Administrator",
        "User Administrator",
        "Groups Administrator",
        "Conditional Access Administrator",
        "Privileged Authentication Administrator",
        "Privileged Role Administrator",
        "Global Reader",
        "Security Reader"
    )
    "Collaboration / M365" = @(
        "Exchange Administrator",
        "SharePoint Administrator",
        "Teams Administrator",
        "Teams Devices Administrator",
        "Teams Communications Administrator",
        "Office Apps Administrator",
        "License Administrator"
    )
    "Read Only / Audit" = @(
        "Global Reader",
        "Security Reader"
    )
    "All Eligible Roles" = @()
    "Custom Selection" = @()
}

# =========================
# Duration options
# =========================
$DurationOptions = @(
    [pscustomobject]@{ Display = "1 Hour"; Hours = 1; UseMaximum = $false }
    [pscustomobject]@{ Display = "2 Hours"; Hours = 2; UseMaximum = $false }
    [pscustomobject]@{ Display = "4 Hours"; Hours = 4; UseMaximum = $false }
    [pscustomobject]@{ Display = "8 Hours"; Hours = 8; UseMaximum = $false }
    [pscustomobject]@{ Display = "Maximum Allowed"; Hours = $null; UseMaximum = $true }
)

# =========================
# Role descriptions
# =========================
$script:RoleDescriptions = @{
    "Application Administrator"                   = "Can manage app registrations, enterprise apps, application proxy settings, and related application administration."
    "Azure AD Joined Device Local Administrator" = "Can manage local administrator rights for Microsoft Entra joined devices."
    "Intune Administrator"                       = "Can manage Microsoft Intune including device configuration, compliance, apps, and endpoint management settings."
    "Authentication Administrator"               = "Can manage authentication methods for users, including password resets for many non-admin users and MFA method administration."
    "User Administrator"                         = "Can create and manage users and groups, and reset passwords for many users."
    "Groups Administrator"                       = "Can create and manage groups, group membership, and selected group settings."
    "Cloud Device Administrator"                 = "Can enable, disable, and delete devices in Microsoft Entra ID."
    "Office Apps Administrator"                  = "Can manage Microsoft 365 Apps cloud policies and Office app configuration."
    "Conditional Access Administrator"           = "Can create and manage Conditional Access policies that control access and MFA requirements."
    "Privileged Authentication Administrator"    = "Can manage authentication methods for privileged accounts and administrators."
    "Privileged Role Administrator"              = "Can manage Microsoft Entra role assignments and Privileged Identity Management settings."
    "Global Reader"                              = "Read-only access across Microsoft 365 services and Microsoft Entra configuration."
    "Security Reader"                            = "Read-only access to security-related features, reports, and alerts."
    "Exchange Administrator"                     = "Can manage Exchange Online recipients, mail flow, mailbox settings, and service configuration."
    "SharePoint Administrator"                   = "Can manage SharePoint Online and OneDrive settings, sites, sharing, and service configuration."
    "Teams Administrator"                        = "Can manage Microsoft Teams workloads, policies, meetings, apps, and organisation-wide Teams settings."
    "Teams Devices Administrator"                = "Can manage Teams certified devices, phones, and meeting room devices."
    "Teams Communications Administrator"         = "Can manage Teams calling, meetings, and live events related configuration."
    "License Administrator"                      = "Can assign, remove, and manage product licenses for users and groups."
}

# =========================
# Helpers
# =========================
function Write-UILog {
    param(
        [string]$Message,
        [ValidateSet("INFO","WARN","ERROR","OK")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"

    $color = switch ($Level) {
        "INFO"  { [System.Drawing.Color]::White }
        "WARN"  { [System.Drawing.Color]::Gold }
        "ERROR" { [System.Drawing.Color]::Salmon }
        "OK"    { [System.Drawing.Color]::LightGreen }
    }

    if ($script:txtLog) {
        $script:txtLog.SelectionStart = $script:txtLog.TextLength
        $script:txtLog.SelectionLength = 0
        $script:txtLog.SelectionColor = $color
        $script:txtLog.AppendText($line + [Environment]::NewLine)
        $script:txtLog.SelectionColor = $script:txtLog.ForeColor
        $script:txtLog.ScrollToCaret()
        [System.Windows.Forms.Application]::DoEvents()
    }

    Add-Content -Path $LogFile -Value $line
}

function Set-Status {
    param(
        [string]$Text,
        [System.Drawing.Color]$Color
    )
    $script:lblStatus.Text = "Status: $Text"
    $script:lblStatus.ForeColor = $Color
    [System.Windows.Forms.Application]::DoEvents()
}

function Set-UiEnabled {
    param([bool]$Enabled)

    $script:cmbRoleSet.Enabled      = $Enabled
    $script:clbRoles.Enabled        = $Enabled
    $script:txtReason.Enabled       = $Enabled
    $script:cmbDuration.Enabled     = $Enabled
    $script:btnActivate.Enabled     = $Enabled
    $script:btnDisconnect.Enabled   = $Enabled
    $script:btnSelectAll.Enabled    = $Enabled
    $script:btnClear.Enabled        = $Enabled
    $script:btnRefresh.Enabled      = $Enabled
}

function Ensure-PackageProviderAndNuGet {
    try {
        Write-UILog "Checking NuGet package provider..." "INFO"
        $nugetProvider = Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue

        if (-not $nugetProvider) {
            Write-UILog "NuGet provider not found. Attempting install..." "WARN"
            Install-PackageProvider -Name NuGet -Force | Out-Null
            Write-UILog "NuGet package provider ready." "OK"
        }
        else {
            Write-UILog "NuGet package provider already available." "INFO"
        }
    }
    catch {
        Write-UILog "NuGet package provider check/install failed: $($_.Exception.Message)" "WARN"
    }
}

function Ensure-PowerShellGet {
    try {
        if (-not (Get-Module -ListAvailable -Name PowerShellGet)) {
            Write-UILog "PowerShellGet not found. Installing..." "WARN"
            Install-Module -Name PowerShellGet -Scope CurrentUser -Force -AllowClobber
            Write-UILog "PowerShellGet installed." "OK"
        }
        else {
            Write-UILog "PowerShellGet already installed." "INFO"
        }
    }
    catch {
        Write-UILog "PowerShellGet check/install failed: $($_.Exception.Message)" "WARN"
    }
}

function Ensure-Module {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModuleName
    )

    try {
        if (-not (Get-Module -ListAvailable -Name $ModuleName -ErrorAction SilentlyContinue)) {
            Write-UILog "Installing missing module [$ModuleName]..." "WARN"
            Install-Module -Name $ModuleName -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
            Write-UILog "Module [$ModuleName] installed successfully." "OK"
        }
    }
    catch {
        throw "Failed installing module [$ModuleName]. $($_.Exception.Message)"
    }
}

function Test-RequiredCommands {
    $requiredCommands = @(
        "Connect-MgGraph",
        "Disconnect-MgGraph",
        "Get-MgContext",
        "Get-MgUser",
        "Get-MgOrganization",
        "Get-MgRoleManagementDirectoryRoleEligibilitySchedule",
        "Get-MgRoleManagementDirectoryRoleDefinition",
        "Get-MgRoleManagementDirectoryRoleAssignmentScheduleInstance",
        "New-MgRoleManagementDirectoryRoleAssignmentScheduleRequest"
    )

    $missing = @()

    foreach ($cmd in $requiredCommands) {
        if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
            $missing += $cmd
        }
    }

    if ($missing.Count -gt 0) {
        throw "The following required command(s) are unavailable: $($missing -join ', ')"
    }

    Write-UILog "All required Microsoft Graph commands are available." "OK"
}

function Import-RequiredModules {
    $modulesToImport = @(
        "Microsoft.Graph.Authentication",
        "Microsoft.Graph.Users",
        "Microsoft.Graph.Identity.DirectoryManagement",
        "Microsoft.Graph.Identity.Governance"
    )

    foreach ($module in $modulesToImport) {
        try {
            if (-not (Get-Module -Name $module -ErrorAction SilentlyContinue)) {
                Write-UILog "Importing [$module]..." "INFO"
                Import-Module $module -Force -ErrorAction Stop
                Write-UILog "Imported [$module]." "OK"
            }
            else {
                Write-UILog "Module [$module] already loaded." "INFO"
            }
        }
        catch {
            throw "Could not import module [$module]. $($_.Exception.Message)"
        }
    }

    Test-RequiredCommands
    Write-UILog "Required modules are ready." "OK"
}

function Ensure-Prereqs {
    try {
        if ($script:PrereqsReady) {
            Write-UILog "Prerequisites already prepared for this session." "INFO"
            Set-Status "Ready to connect" ([System.Drawing.Color]::LightGreen)
            return $true
        }

        Set-Status "Checking prerequisites..." ([System.Drawing.Color]::Gold)

        $requiredModules = @(
            "Microsoft.Graph.Authentication",
            "Microsoft.Graph.Users",
            "Microsoft.Graph.Identity.DirectoryManagement",
            "Microsoft.Graph.Identity.Governance"
        )

        $missingModules = $requiredModules | Where-Object {
            -not (Get-Module -ListAvailable -Name $_ -ErrorAction SilentlyContinue)
        }

        if ($missingModules.Count -gt 0) {
            Write-UILog "Missing modules detected: $($missingModules -join ', ')" "WARN"

            try {
                Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted -ErrorAction SilentlyContinue | Out-Null
                Write-UILog "PSGallery repository set to Trusted." "INFO"
            }
            catch {
                Write-UILog "Could not set PSGallery as trusted: $($_.Exception.Message)" "WARN"
            }

            Ensure-PackageProviderAndNuGet
            Ensure-PowerShellGet

            foreach ($module in $missingModules) {
                Ensure-Module -ModuleName $module
            }
        }
        else {
            Write-UILog "All required modules already installed. Skipping install checks." "INFO"
        }

        Import-RequiredModules
        $script:PrereqsReady = $true

        Set-Status "Ready to connect" ([System.Drawing.Color]::LightGreen)
        return $true
    }
    catch {
        Write-UILog "Prerequisite check failed: $($_.Exception.Message)" "ERROR"
        Set-Status "Prerequisite failure" ([System.Drawing.Color]::Salmon)

        [System.Windows.Forms.MessageBox]::Show(
            "Failed to prepare prerequisites.`r`n`r`n$($_.Exception.Message)",
            $ToolName,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null

        return $false
    }
}

function Get-SelectedRoles {
    $roles = @()
    for ($i = 0; $i -lt $script:clbRoles.Items.Count; $i++) {
        if ($script:clbRoles.GetItemChecked($i)) {
            $roles += [string]$script:clbRoles.Items[$i]
        }
    }
    return $roles
}

function Update-SelectedCount {
    $script:lblSelectedCount.Text = "Selected Roles: $((Get-SelectedRoles).Count)"
}

function Get-SelectedDurationOption {
    if ($script:cmbDuration.SelectedItem -is [pscustomobject]) {
        return $script:cmbDuration.SelectedItem
    }

    $selectedText = [string]$script:cmbDuration.Text
    foreach ($opt in $DurationOptions) {
        if ($opt.Display -eq $selectedText) {
            return $opt
        }
    }

    return $DurationOptions[-1]
}

function Get-RoleDescription {
    param([string]$RoleName)

    if ([string]::IsNullOrWhiteSpace($RoleName)) {
        return "Select a role to see its description."
    }

    if ($script:RoleDescriptions.ContainsKey($RoleName)) {
        return $script:RoleDescriptions[$RoleName]
    }

    return "No role description is currently defined in the tool for this role."
}

function Update-RoleDescriptionPane {
    $selectedRole = $null
    if ($script:clbRoles.SelectedItem) {
        $selectedRole = [string]$script:clbRoles.SelectedItem
    }
    $script:txtRoleDescription.Text = Get-RoleDescription -RoleName $selectedRole
}

function Clear-AccountInfo {
    $script:txtAccountValue.Text = ""
    $script:txtTenantValue.Text = ""
    $script:txtTenantNameValue.Text = ""
    $script:txtScopesValue.Text = ""
}

function Update-AccountInfo {
    try {
        $ctx = Get-MgContext
        if (-not $ctx) { return }

        $script:txtAccountValue.Text = if ($ctx.Account) { $ctx.Account } else { "" }
        $script:txtTenantValue.Text = if ($ctx.TenantId) { $ctx.TenantId } else { "" }
        $script:txtScopesValue.Text = if ($ctx.Scopes) { ($ctx.Scopes -join ", ") } else { "" }

        $tenantName = ""
        try {
            $org = Get-MgOrganization -ErrorAction Stop | Select-Object -First 1
            if ($org.DisplayName) {
                $tenantName = $org.DisplayName
                $script:CurrentTenantName = $tenantName
            }
        }
        catch {
            Write-UILog "Could not resolve tenant display name: $($_.Exception.Message)" "WARN"
        }

        $script:txtTenantNameValue.Text = $tenantName
    }
    catch {
        Write-UILog "Failed to update account info: $($_.Exception.Message)" "WARN"
    }
}

function Clear-ActiveRolesList {
    $script:lvActiveRoles.Items.Clear()
}

function Add-ActiveRoleRow {
    param(
        [string]$RoleName,
        [string]$Status,
        [string]$Start,
        [string]$End
    )

    $item = New-Object System.Windows.Forms.ListViewItem($RoleName)
    [void]$item.SubItems.Add($Status)
    [void]$item.SubItems.Add($Start)
    [void]$item.SubItems.Add($End)
    [void]$script:lvActiveRoles.Items.Add($item)
}

function Resize-ActiveRoleColumns {
    if (-not $script:lvActiveRoles) { return }
    if ($script:lvActiveRoles.Columns.Count -lt 4) { return }

    $clientWidth = $script:lvActiveRoles.ClientSize.Width
    if ($clientWidth -lt 200) { return }

    $script:lvActiveRoles.Columns[0].Width = [Math]::Max(160, [int]($clientWidth * 0.42))
    $script:lvActiveRoles.Columns[1].Width = [Math]::Max(70,  [int]($clientWidth * 0.14))
    $script:lvActiveRoles.Columns[2].Width = [Math]::Max(95,  [int]($clientWidth * 0.20))
    $script:lvActiveRoles.Columns[3].Width = [Math]::Max(95,  [int]($clientWidth * 0.20))
}

function Convert-HoursToIsoDuration {
    param([int]$Hours)

    if ($Hours -le 0) {
        throw "Hours must be greater than zero."
    }

    return "PT{0}H" -f $Hours
}

function Get-RolePolicyMaximumHours {
    param(
        [string]$RoleDefinitionId
    )

    return $null
}

function Load-EligibleRolesForCurrentUser {
    $script:clbRoles.Items.Clear()
    $script:EligibleRoles = @()
    $script:RoleDefinitionMap = @{}

    $ctx = Get-MgContext
    if (-not $ctx -or -not $ctx.Account) {
        throw "No active Graph context found."
    }

    Write-UILog "Resolving signed-in user [$($ctx.Account)]..." "INFO"
    $user = Get-MgUser -UserId $ctx.Account -ErrorAction Stop
    $script:CurrentUserId = $user.Id

    $eligibilityCmd = Get-Command Get-MgRoleManagementDirectoryRoleEligibilitySchedule -ErrorAction SilentlyContinue
    $roleDefCmd     = Get-Command Get-MgRoleManagementDirectoryRoleDefinition -ErrorAction SilentlyContinue

    if (-not $eligibilityCmd -or -not $roleDefCmd) {
        throw "Required Graph role management cmdlets are unavailable."
    }

    Write-UILog "Querying eligible PIM roles..." "INFO"
    $eligibilities = Get-MgRoleManagementDirectoryRoleEligibilitySchedule -Filter "principalId eq '$($script:CurrentUserId)'" -All -ErrorAction Stop

    if (-not $eligibilities) {
        Write-UILog "No eligible PIM roles were returned for this account." "WARN"
        return
    }

    $roleNames = New-Object System.Collections.Generic.List[string]

    foreach ($elig in $eligibilities) {
        try {
            $roleDef = Get-MgRoleManagementDirectoryRoleDefinition -UnifiedRoleDefinitionId $elig.RoleDefinitionId -ErrorAction Stop
            if ($roleDef.DisplayName) {
                if (-not $roleNames.Contains($roleDef.DisplayName)) {
                    $roleNames.Add($roleDef.DisplayName)
                }
                $script:RoleDefinitionMap[$roleDef.DisplayName] = $roleDef.Id
            }
        }
        catch {
            Write-UILog "Failed to resolve role definition [$($elig.RoleDefinitionId)]: $($_.Exception.Message)" "WARN"
        }
    }

    $script:EligibleRoles = $roleNames | Sort-Object

    foreach ($role in $script:EligibleRoles) {
        [void]$script:clbRoles.Items.Add($role)
    }

    $RoleSets["All Eligible Roles"] = $script:EligibleRoles
    Write-UILog "Loaded $($script:EligibleRoles.Count) eligible role(s)." "OK"
    Update-SelectedCount
    Update-RoleDescriptionPane
}

function Load-ActiveRolesForCurrentUser {
    Clear-ActiveRolesList

    if (-not $script:CurrentUserId) { return }

    $assignmentCmd = Get-Command Get-MgRoleManagementDirectoryRoleAssignmentScheduleInstance -ErrorAction SilentlyContinue
    $roleDefCmd    = Get-Command Get-MgRoleManagementDirectoryRoleDefinition -ErrorAction SilentlyContinue

    if (-not $assignmentCmd -or -not $roleDefCmd) {
        Add-ActiveRoleRow -RoleName "Unavailable" -Status "Cmdlet missing" -Start "-" -End "-"
        Write-UILog "Active role cmdlets are not available in this session." "WARN"
        Resize-ActiveRoleColumns
        return
    }

    try {
        Write-UILog "Querying current active roles..." "INFO"
        $instances = Get-MgRoleManagementDirectoryRoleAssignmentScheduleInstance -Filter "principalId eq '$($script:CurrentUserId)'" -All -ErrorAction Stop

        if (-not $instances) {
            Add-ActiveRoleRow -RoleName "No active roles found" -Status "-" -Start "-" -End "-"
            Write-UILog "No active roles currently assigned." "INFO"
            Resize-ActiveRoleColumns
            return
        }

        foreach ($inst in ($instances | Sort-Object EndDateTime)) {
            $roleName = $inst.RoleDefinitionId
            try {
                $roleDef = Get-MgRoleManagementDirectoryRoleDefinition -UnifiedRoleDefinitionId $inst.RoleDefinitionId -ErrorAction Stop
                if ($roleDef.DisplayName) {
                    $roleName = $roleDef.DisplayName
                }
            }
            catch {
                Write-UILog "Could not resolve active role definition [$($inst.RoleDefinitionId)]: $($_.Exception.Message)" "WARN"
            }

            $start = if ($inst.StartDateTime) { ([datetime]$inst.StartDateTime).ToString("yyyy-MM-dd HH:mm") } else { "-" }
            $end   = if ($inst.EndDateTime)   { ([datetime]$inst.EndDateTime).ToString("yyyy-MM-dd HH:mm") } else { "-" }

            Add-ActiveRoleRow -RoleName $roleName -Status "Active" -Start $start -End $end
        }

        Write-UILog "Loaded $($instances.Count) active role assignment(s)." "OK"
        Resize-ActiveRoleColumns
    }
    catch {
        Write-UILog "Failed loading active roles: $($_.Exception.Message)" "WARN"
        Add-ActiveRoleRow -RoleName "Failed to load active roles" -Status "Error" -Start "-" -End "-"
        Resize-ActiveRoleColumns
    }
}

function Refresh-UserData {
    if (-not $script:IsConnected) { return }

    Update-AccountInfo
    Load-EligibleRolesForCurrentUser

    if ($script:cmbRoleSet.SelectedItem) {
        Apply-RoleSet -RoleSetName ([string]$script:cmbRoleSet.SelectedItem)
    }

    Load-ActiveRolesForCurrentUser
}

function Apply-RoleSet {
    param([string]$RoleSetName)

    $script:SuppressRoleEvents = $true
    try {
        for ($i = 0; $i -lt $script:clbRoles.Items.Count; $i++) {
            $script:clbRoles.SetItemChecked($i, $false)
        }

        if ($RoleSetName -and $RoleSets.Contains($RoleSetName) -and $RoleSetName -ne "Custom Selection") {
            $targetRoles = $RoleSets[$RoleSetName]
            for ($i = 0; $i -lt $script:clbRoles.Items.Count; $i++) {
                $roleName = [string]$script:clbRoles.Items[$i]
                if ($targetRoles -contains $roleName) {
                    $script:clbRoles.SetItemChecked($i, $true)
                }
            }
        }
    }
    finally {
        $script:SuppressRoleEvents = $false
        Update-SelectedCount
    }
}

function Connect-GraphInteractive {
    try {
        Write-UILog "Disconnecting any previous Microsoft Graph session..." "INFO"
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    }
    catch {}

    Write-UILog "Using interactive browser authentication." "INFO"
    Connect-MgGraph -Scopes @(
        "RoleManagement.ReadWrite.Directory",
        "RoleAssignmentSchedule.ReadWrite.Directory",
        "User.Read",
        "Organization.Read.All"
    ) -NoWelcome

    $ctx = Get-MgContext
    $script:IsConnected = $true

    Write-UILog "Connected to Microsoft Graph successfully as [$($ctx.Account)]." "OK"
    Set-Status "Connected as $($ctx.Account)" ([System.Drawing.Color]::LightGreen)

    Update-AccountInfo
    Load-EligibleRolesForCurrentUser
    Apply-RoleSet -RoleSetName "Daily Work"
    Load-ActiveRolesForCurrentUser

    Set-UiEnabled -Enabled $true
    $script:btnConnect.Enabled = $true
}

function Invoke-RoleActivationDirectGraph {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RoleName,

        [Parameter(Mandatory = $true)]
        [string]$Reason,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$DurationOption
    )

    $ctx = Get-MgContext
    if (-not $ctx) {
        throw "No active Microsoft Graph session found."
    }

    if (-not $script:CurrentUserId) {
        throw "Current user could not be resolved."
    }

    if (-not $script:RoleDefinitionMap.ContainsKey($RoleName)) {
        throw "Role [$RoleName] was not found in the loaded eligible role map."
    }

    $roleDefinitionId = $script:RoleDefinitionMap[$RoleName]
    $startDateTime = Get-Date

    if ($DurationOption.UseMaximum) {
        $maxHours = Get-RolePolicyMaximumHours -RoleDefinitionId $roleDefinitionId
        if ($null -eq $maxHours) {
            throw "Maximum allowed duration lookup is not configured in this version. Select a fixed duration such as 1, 2, 4, or 8 hours."
        }
        $durationIso = Convert-HoursToIsoDuration -Hours ([int]$maxHours)
    }
    else {
        $durationIso = Convert-HoursToIsoDuration -Hours ([int]$DurationOption.Hours)
    }

    $params = @{
        action           = "SelfActivate"
        principalId      = $script:CurrentUserId
        roleDefinitionId = $roleDefinitionId
        directoryScopeId = "/"
        justification    = $Reason
        scheduleInfo     = @{
            startDateTime = $startDateTime
            expiration    = @{
                type     = "AfterDuration"
                duration = $durationIso
            }
        }
    }

    Write-UILog "Submitting direct Graph activation request for [$RoleName]..." "INFO"
    $result = New-MgRoleManagementDirectoryRoleAssignmentScheduleRequest -BodyParameter $params -ErrorAction Stop
    Write-UILog "Graph activation submitted for [$RoleName] with status [$($result.Status)]." "OK"

    return $result
}

function Activate-SelectedRoles {
    $roles    = Get-SelectedRoles
    $reason   = $script:txtReason.Text.Trim()
    $duration = Get-SelectedDurationOption

    if (-not $roles -or $roles.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "Please select at least one eligible role.",
            $ToolName,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return
    }

    if ([string]::IsNullOrWhiteSpace($reason)) {
        $reason = "Daily Work"
        $script:txtReason.Text = $reason
    }

    if ($duration.UseMaximum) {
        [System.Windows.Forms.MessageBox]::Show(
            "Maximum Allowed is not implemented in the direct Graph version yet. Please select a fixed duration.",
            $ToolName,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return
    }

    $selectedRoleSet = [string]$script:cmbRoleSet.SelectedItem
    $confirmText = @"
Role Set:
$selectedRoleSet

Roles:
$($roles -join "`r`n")

Reason:
$reason

Duration:
$($duration.Display)

Proceed with activation?
"@

    $confirm = [System.Windows.Forms.MessageBox]::Show(
        $confirmText,
        $ToolName,
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )

    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) {
        Write-UILog "User cancelled before activation." "WARN"
        return
    }

    Set-Status "Activating roles..." ([System.Drawing.Color]::Gold)
    Write-UILog "Activation reason: $reason" "INFO"
    Write-UILog "Duration selected: $($duration.Display)" "INFO"
    Write-UILog "Roles selected: $($roles -join '; ')" "INFO"

    $results = New-Object System.Collections.Generic.List[object]

    foreach ($role in $roles) {
        try {
            $result = Invoke-RoleActivationDirectGraph -RoleName $role -Reason $reason -DurationOption $duration
            $results.Add([pscustomobject]@{
                Role   = $role
                Status = if ($result.Status) { [string]$result.Status } else { "Submitted" }
                Detail = "Activation request created successfully"
            })
        }
        catch {
            $results.Add([pscustomobject]@{
                Role   = $role
                Status = "Failed"
                Detail = $_.Exception.Message
            })
            Write-UILog "Activation failed for role [$role]: $($_.Exception.Message)" "ERROR"
        }
    }

    Refresh-UserData

    $successCount = ($results | Where-Object { $_.Status -ne "Failed" }).Count
    $failCount    = ($results | Where-Object { $_.Status -eq "Failed" }).Count
    $summary      = ($results | ForEach-Object { "$($_.Role) - $($_.Status) - $($_.Detail)" }) -join [Environment]::NewLine

    if ($failCount -eq 0) {
        Set-Status "Activation complete" ([System.Drawing.Color]::LightGreen)
        [System.Windows.Forms.MessageBox]::Show(
            "Role activation completed successfully.`r`n`r`n$summary",
            $ToolName,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    }
    else {
        Set-Status "Activation completed with errors" ([System.Drawing.Color]::Gold)
        [System.Windows.Forms.MessageBox]::Show(
            "Activation finished.`r`nSuccess: $successCount`r`nFailed: $failCount`r`n`r`n$summary",
            $ToolName,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
    }
}

function Disconnect-GraphSafe {
    try {
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
        $script:IsConnected = $false
        $script:EligibleRoles = @()
        $script:CurrentUserId = $null
        $script:RoleDefinitionMap = @{}
        $script:clbRoles.Items.Clear()
        Clear-ActiveRolesList
        Clear-AccountInfo
        $script:txtRoleDescription.Text = "Select a role to see its description."
        Write-UILog "Disconnected from Microsoft Graph." "INFO"
        Set-Status "Disconnected" ([System.Drawing.Color]::Salmon)
        Update-SelectedCount
        Set-UiEnabled -Enabled $false
        $script:btnConnect.Enabled = $true
        $script:btnDisconnect.Enabled = $false
    }
    catch {
        Write-UILog "Failed to disconnect Graph cleanly: $($_.Exception.Message)" "WARN"
    }
}

function New-ColoredButton {
    param(
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$W,
        [int]$H,
        [System.Drawing.Color]$BackColor
    )
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $Text
    $btn.Location = New-Object System.Drawing.Point($X,$Y)
    $btn.Size = New-Object System.Drawing.Size($W,$H)
    $btn.BackColor = $BackColor
    $btn.ForeColor = [System.Drawing.Color]::White
    $btn.FlatStyle = "Flat"
    $btn.FlatAppearance.BorderSize = 0
    $btn.Font = New-Object System.Drawing.Font("Segoe UI",10,[System.Drawing.FontStyle]::Bold)
    return $btn
}

function New-ReadOnlyValueBox {
    param(
        [int]$X,
        [int]$Y,
        [int]$W,
        [int]$H,
        [bool]$MultiLine = $false
    )

    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Location = New-Object System.Drawing.Point($X,$Y)
    $tb.Size = New-Object System.Drawing.Size($W,$H)
    $tb.ReadOnly = $true
    $tb.BorderStyle = "FixedSingle"
    $tb.BackColor = [System.Drawing.Color]::FromArgb(45,45,48)
    $tb.ForeColor = [System.Drawing.Color]::White
    $tb.Multiline = $MultiLine
    $tb.ScrollBars = if ($MultiLine) { "Vertical" } else { "Horizontal" }
    return $tb
}

function Update-FormLayout {
    if (-not $form) { return }

    $padding = 20
    $gap = 20

    $clientW = $form.ClientSize.Width
    $clientH = $form.ClientSize.Height

    $panelHeader.Location = New-Object System.Drawing.Point(0,0)
    $panelHeader.Size     = New-Object System.Drawing.Size($clientW,100)

    $lblTitle.Location    = New-Object System.Drawing.Point(20,16)
    $lblSubtitle.Location = New-Object System.Drawing.Point(22,50)

    $btnExit.Location = New-Object System.Drawing.Point(($clientW - 130),18)
    $btnExit.Size     = New-Object System.Drawing.Size(100,32)

    $lblContact.Location = New-Object System.Drawing.Point(22,74)
    $lblContact.Size     = New-Object System.Drawing.Size(($clientW - 170),20)

    $lblLogFile.Location = New-Object System.Drawing.Point(20,110)
    $lblLogFile.Size     = New-Object System.Drawing.Size(($clientW - 40),20)

    $topY = 140
    $reservedBelow = 250
    $topHeight = [Math]::Max(360, [int](($clientH - $topY - $reservedBelow) * 0.52))

    $configW  = 300
    $actionsW = 220
    $rolesX   = $padding + $configW + $gap
    $actionsX = $clientW - $padding - $actionsW
    $rolesW   = [Math]::Max(360, ($actionsX - $gap - $rolesX))

    $grpConfig.Location = New-Object System.Drawing.Point($padding,$topY)
    $grpConfig.Size     = New-Object System.Drawing.Size($configW,$topHeight)

    $grpRoles.Location  = New-Object System.Drawing.Point($rolesX,$topY)
    $grpRoles.Size      = New-Object System.Drawing.Size($rolesW,$topHeight)

    $grpActions.Location = New-Object System.Drawing.Point($actionsX,$topY)
    $grpActions.Size     = New-Object System.Drawing.Size($actionsW,$topHeight)

    $clbRoles.Location = New-Object System.Drawing.Point(20,30)
    $clbRoles.Size     = New-Object System.Drawing.Size(($grpRoles.ClientSize.Width - 40),($grpRoles.ClientSize.Height - 50))

    $bottomGap = 20
    $bottomY = $grpConfig.Bottom + $bottomGap
    $bottomHeight = 170

    $accountW  = 340
    $roleDescW = 380
    $accountX  = $padding
    $roleDescX = $accountX + $accountW + $gap
    $activeX   = $roleDescX + $roleDescW + $gap
    $activeW   = $clientW - $padding - $activeX
    if ($activeW -lt 320) { $activeW = 320 }

    $grpAccount.Location = New-Object System.Drawing.Point($accountX,$bottomY)
    $grpAccount.Size     = New-Object System.Drawing.Size($accountW,$bottomHeight)

    $grpRoleDetails.Location = New-Object System.Drawing.Point($roleDescX,$bottomY)
    $grpRoleDetails.Size     = New-Object System.Drawing.Size($roleDescW,$bottomHeight)

    $grpActiveRoles.Location = New-Object System.Drawing.Point($activeX,$bottomY)
    $grpActiveRoles.Size     = New-Object System.Drawing.Size($activeW,$bottomHeight)

    $txtAccountValue.Location    = New-Object System.Drawing.Point(95,24)
    $txtAccountValue.Size        = New-Object System.Drawing.Size(($grpAccount.ClientSize.Width - 115),24)

    $txtTenantValue.Location     = New-Object System.Drawing.Point(95,54)
    $txtTenantValue.Size         = New-Object System.Drawing.Size(($grpAccount.ClientSize.Width - 115),24)

    $txtTenantNameValue.Location = New-Object System.Drawing.Point(95,84)
    $txtTenantNameValue.Size     = New-Object System.Drawing.Size(($grpAccount.ClientSize.Width - 115),24)

    $txtScopesValue.Location     = New-Object System.Drawing.Point(95,114)
    $txtScopesValue.Size         = New-Object System.Drawing.Size(($grpAccount.ClientSize.Width - 115),42)

    $txtRoleDescription.Location = New-Object System.Drawing.Point(15,28)
    $txtRoleDescription.Size     = New-Object System.Drawing.Size(($grpRoleDetails.ClientSize.Width - 30),($grpRoleDetails.ClientSize.Height - 45))

    $lvActiveRoles.Location = New-Object System.Drawing.Point(15,28)
    $lvActiveRoles.Size     = New-Object System.Drawing.Size(($grpActiveRoles.ClientSize.Width - 30),($grpActiveRoles.ClientSize.Height - 45))

    $statusY = $bottomY + $bottomHeight + 15
    $logY    = $statusY + 30
    $logH    = $clientH - $logY - 20
    if ($logH -lt 140) { $logH = 140 }

    $lblStatus.Location = New-Object System.Drawing.Point(20,$statusY)
    $lblStatus.Size     = New-Object System.Drawing.Size(($clientW - 40),22)

    $grpLog.Location = New-Object System.Drawing.Point(20,$logY)
    $grpLog.Size     = New-Object System.Drawing.Size(($clientW - 40),$logH)

    $txtLog.Location = New-Object System.Drawing.Point(15,28)
    $txtLog.Size     = New-Object System.Drawing.Size(($grpLog.ClientSize.Width - 30),($grpLog.ClientSize.Height - 45))

    Resize-ActiveRoleColumns
}

# =========================
# Form
# =========================
$form = New-Object System.Windows.Forms.Form
$form.Text = $ToolName
$form.Size = New-Object System.Drawing.Size(1260,960)
$form.StartPosition = "CenterScreen"
$form.BackColor = [System.Drawing.Color]::FromArgb(37,37,38)
$form.ForeColor = [System.Drawing.Color]::White
$form.Font = New-Object System.Drawing.Font("Segoe UI",10)
$form.MinimumSize = New-Object System.Drawing.Size(1260,960)

$panelHeader = New-Object System.Windows.Forms.Panel
$panelHeader.BackColor = [System.Drawing.Color]::White
$form.Controls.Add($panelHeader)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = $ToolName
$lblTitle.Font = New-Object System.Drawing.Font("Segoe UI",18,[System.Drawing.FontStyle]::Bold)
$lblTitle.ForeColor = [System.Drawing.Color]::FromArgb(0,122,204)
$lblTitle.AutoSize = $true
$panelHeader.Controls.Add($lblTitle)

$lblSubtitle = New-Object System.Windows.Forms.Label
$lblSubtitle.Text = "Version $ToolVersion"
$lblSubtitle.Font = New-Object System.Drawing.Font("Segoe UI",11)
$lblSubtitle.ForeColor = [System.Drawing.Color]::FromArgb(60,60,60)
$lblSubtitle.AutoSize = $true
$panelHeader.Controls.Add($lblSubtitle)

$lblContact = New-Object System.Windows.Forms.Label
$lblContact.Text = "Open-source edition"
$lblContact.ForeColor = [System.Drawing.Color]::FromArgb(90,90,90)
$lblContact.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$panelHeader.Controls.Add($lblContact)

$lblLogFile = New-Object System.Windows.Forms.Label
$lblLogFile.Text = "Log file: $LogFile"
$lblLogFile.ForeColor = [System.Drawing.Color]::Silver
$form.Controls.Add($lblLogFile)

$grpConfig = New-Object System.Windows.Forms.GroupBox
$grpConfig.Text = "Activation Settings"
$grpConfig.ForeColor = [System.Drawing.Color]::White
$form.Controls.Add($grpConfig)

$lblRoleSet = New-Object System.Windows.Forms.Label
$lblRoleSet.Text = "Role Set"
$lblRoleSet.Location = New-Object System.Drawing.Point(20,35)
$lblRoleSet.AutoSize = $true
$grpConfig.Controls.Add($lblRoleSet)

$cmbRoleSet = New-Object System.Windows.Forms.ComboBox
$cmbRoleSet.Location = New-Object System.Drawing.Point(20,60)
$cmbRoleSet.Size = New-Object System.Drawing.Size(250,30)
$cmbRoleSet.DropDownStyle = "DropDownList"
$cmbRoleSet.BackColor = [System.Drawing.Color]::FromArgb(45,45,48)
$cmbRoleSet.ForeColor = [System.Drawing.Color]::White
foreach ($key in $RoleSets.Keys) { [void]$cmbRoleSet.Items.Add($key) }
$cmbRoleSet.SelectedIndex = 0
$grpConfig.Controls.Add($cmbRoleSet)
$script:cmbRoleSet = $cmbRoleSet

$lblReason = New-Object System.Windows.Forms.Label
$lblReason.Text = "Reason"
$lblReason.Location = New-Object System.Drawing.Point(20,105)
$lblReason.AutoSize = $true
$grpConfig.Controls.Add($lblReason)

$txtReason = New-Object System.Windows.Forms.TextBox
$txtReason.Location = New-Object System.Drawing.Point(20,130)
$txtReason.Size = New-Object System.Drawing.Size(250,27)
$txtReason.BackColor = [System.Drawing.Color]::FromArgb(45,45,48)
$txtReason.ForeColor = [System.Drawing.Color]::White
$txtReason.Text = "Daily Work"
$grpConfig.Controls.Add($txtReason)
$script:txtReason = $txtReason

$lblDuration = New-Object System.Windows.Forms.Label
$lblDuration.Text = "Activation Duration"
$lblDuration.Location = New-Object System.Drawing.Point(20,175)
$lblDuration.AutoSize = $true
$grpConfig.Controls.Add($lblDuration)

$cmbDuration = New-Object System.Windows.Forms.ComboBox
$cmbDuration.Location = New-Object System.Drawing.Point(20,200)
$cmbDuration.Size = New-Object System.Drawing.Size(250,30)
$cmbDuration.DropDownStyle = "DropDownList"
$cmbDuration.BackColor = [System.Drawing.Color]::FromArgb(45,45,48)
$cmbDuration.ForeColor = [System.Drawing.Color]::White
$cmbDuration.DisplayMember = "Display"
foreach ($opt in $DurationOptions) { [void]$cmbDuration.Items.Add($opt) }
$cmbDuration.SelectedIndex = 2
$grpConfig.Controls.Add($cmbDuration)
$script:cmbDuration = $cmbDuration

$lblSelectedCount = New-Object System.Windows.Forms.Label
$lblSelectedCount.Text = "Selected Roles: 0"
$lblSelectedCount.Location = New-Object System.Drawing.Point(20,245)
$lblSelectedCount.Size = New-Object System.Drawing.Size(250,24)
$lblSelectedCount.ForeColor = [System.Drawing.Color]::LightGreen
$grpConfig.Controls.Add($lblSelectedCount)
$script:lblSelectedCount = $lblSelectedCount

$lblHint = New-Object System.Windows.Forms.Label
$lblHint.Text = "Connect first to load your eligible PIM roles and active assignments."
$lblHint.Location = New-Object System.Drawing.Point(20,275)
$lblHint.Size = New-Object System.Drawing.Size(250,55)
$lblHint.ForeColor = [System.Drawing.Color]::Silver
$grpConfig.Controls.Add($lblHint)

$grpRoles = New-Object System.Windows.Forms.GroupBox
$grpRoles.Text = "Eligible Roles"
$grpRoles.ForeColor = [System.Drawing.Color]::White
$form.Controls.Add($grpRoles)

$clbRoles = New-Object System.Windows.Forms.CheckedListBox
$clbRoles.CheckOnClick = $true
$clbRoles.BackColor = [System.Drawing.Color]::FromArgb(45,45,48)
$clbRoles.ForeColor = [System.Drawing.Color]::White
$clbRoles.BorderStyle = "FixedSingle"
$grpRoles.Controls.Add($clbRoles)
$script:clbRoles = $clbRoles

$grpActions = New-Object System.Windows.Forms.GroupBox
$grpActions.Text = "Actions"
$grpActions.ForeColor = [System.Drawing.Color]::White
$form.Controls.Add($grpActions)

$btnConnect    = New-ColoredButton "Connect"        20 35 180 42 ([System.Drawing.Color]::FromArgb(0,122,204))
$btnActivate   = New-ColoredButton "Activate Roles" 20 87 180 42 ([System.Drawing.Color]::FromArgb(16,124,16))
$btnRefresh    = New-ColoredButton "Refresh"        20 139 180 42 ([System.Drawing.Color]::FromArgb(91,91,91))
$btnDisconnect = New-ColoredButton "Disconnect"     20 191 180 42 ([System.Drawing.Color]::FromArgb(160,80,0))
$btnSelectAll  = New-ColoredButton "Select All"     20 243 180 42 ([System.Drawing.Color]::FromArgb(91,91,91))
$btnClear      = New-ColoredButton "Clear"          20 295 180 42 ([System.Drawing.Color]::FromArgb(120,0,0))

$grpActions.Controls.Add($btnConnect)
$grpActions.Controls.Add($btnActivate)
$grpActions.Controls.Add($btnRefresh)
$grpActions.Controls.Add($btnDisconnect)
$grpActions.Controls.Add($btnSelectAll)
$grpActions.Controls.Add($btnClear)

$script:btnConnect    = $btnConnect
$script:btnActivate   = $btnActivate
$script:btnRefresh    = $btnRefresh
$script:btnDisconnect = $btnDisconnect
$script:btnSelectAll  = $btnSelectAll
$script:btnClear      = $btnClear

$grpAccount = New-Object System.Windows.Forms.GroupBox
$grpAccount.Text = "Connected Account"
$grpAccount.ForeColor = [System.Drawing.Color]::White
$form.Controls.Add($grpAccount)

$lblAccount = New-Object System.Windows.Forms.Label
$lblAccount.Text = "Account:"
$lblAccount.Location = New-Object System.Drawing.Point(15,28)
$lblAccount.Size = New-Object System.Drawing.Size(75,20)
$grpAccount.Controls.Add($lblAccount)

$txtAccountValue = New-ReadOnlyValueBox -X 95 -Y 24 -W 225 -H 24
$grpAccount.Controls.Add($txtAccountValue)
$script:txtAccountValue = $txtAccountValue

$lblTenant = New-Object System.Windows.Forms.Label
$lblTenant.Text = "Tenant ID:"
$lblTenant.Location = New-Object System.Drawing.Point(15,58)
$lblTenant.Size = New-Object System.Drawing.Size(75,20)
$grpAccount.Controls.Add($lblTenant)

$txtTenantValue = New-ReadOnlyValueBox -X 95 -Y 54 -W 225 -H 24
$grpAccount.Controls.Add($txtTenantValue)
$script:txtTenantValue = $txtTenantValue

$lblTenantName = New-Object System.Windows.Forms.Label
$lblTenantName.Text = "Tenant Name:"
$lblTenantName.Location = New-Object System.Drawing.Point(15,88)
$lblTenantName.Size = New-Object System.Drawing.Size(75,20)
$grpAccount.Controls.Add($lblTenantName)

$txtTenantNameValue = New-ReadOnlyValueBox -X 95 -Y 84 -W 225 -H 24
$grpAccount.Controls.Add($txtTenantNameValue)
$script:txtTenantNameValue = $txtTenantNameValue

$lblScopes = New-Object System.Windows.Forms.Label
$lblScopes.Text = "Scopes:"
$lblScopes.Location = New-Object System.Drawing.Point(15,118)
$lblScopes.Size = New-Object System.Drawing.Size(75,20)
$grpAccount.Controls.Add($lblScopes)

$txtScopesValue = New-ReadOnlyValueBox -X 95 -Y 114 -W 225 -H 42 -MultiLine $true
$grpAccount.Controls.Add($txtScopesValue)
$script:txtScopesValue = $txtScopesValue

$grpRoleDetails = New-Object System.Windows.Forms.GroupBox
$grpRoleDetails.Text = "Role Description"
$grpRoleDetails.ForeColor = [System.Drawing.Color]::White
$form.Controls.Add($grpRoleDetails)

$txtRoleDescription = New-Object System.Windows.Forms.RichTextBox
$txtRoleDescription.ReadOnly = $true
$txtRoleDescription.BackColor = [System.Drawing.Color]::FromArgb(30,30,30)
$txtRoleDescription.ForeColor = [System.Drawing.Color]::White
$txtRoleDescription.Font = New-Object System.Drawing.Font("Segoe UI",9)
$txtRoleDescription.Text = "Select a role to see its description."
$grpRoleDetails.Controls.Add($txtRoleDescription)
$script:txtRoleDescription = $txtRoleDescription

$grpActiveRoles = New-Object System.Windows.Forms.GroupBox
$grpActiveRoles.Text = "Current Active Roles"
$grpActiveRoles.ForeColor = [System.Drawing.Color]::White
$form.Controls.Add($grpActiveRoles)

$lvActiveRoles = New-Object System.Windows.Forms.ListView
$lvActiveRoles.View = [System.Windows.Forms.View]::Details
$lvActiveRoles.FullRowSelect = $true
$lvActiveRoles.GridLines = $true
$lvActiveRoles.BackColor = [System.Drawing.Color]::FromArgb(30,30,30)
$lvActiveRoles.ForeColor = [System.Drawing.Color]::White
$lvActiveRoles.HideSelection = $false
[void]$lvActiveRoles.Columns.Add("Role", 170)
[void]$lvActiveRoles.Columns.Add("Status", 80)
[void]$lvActiveRoles.Columns.Add("Start", 100)
[void]$lvActiveRoles.Columns.Add("End", 100)
$grpActiveRoles.Controls.Add($lvActiveRoles)
$script:lvActiveRoles = $lvActiveRoles

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "Status: Please connect to load eligible roles..."
$lblStatus.ForeColor = [System.Drawing.Color]::Gold
$form.Controls.Add($lblStatus)
$script:lblStatus = $lblStatus

$grpLog = New-Object System.Windows.Forms.GroupBox
$grpLog.Text = "Activity Log"
$grpLog.ForeColor = [System.Drawing.Color]::White
$form.Controls.Add($grpLog)

$txtLog = New-Object System.Windows.Forms.RichTextBox
$txtLog.ReadOnly = $true
$txtLog.BackColor = [System.Drawing.Color]::FromArgb(30,30,30)
$txtLog.ForeColor = [System.Drawing.Color]::White
$txtLog.Font = New-Object System.Drawing.Font("Consolas",9)
$grpLog.Controls.Add($txtLog)
$script:txtLog = $txtLog

$btnExit = New-ColoredButton "Exit" 0 0 100 32 ([System.Drawing.Color]::FromArgb(120,0,0))
$btnExit.Font = New-Object System.Drawing.Font("Segoe UI",9,[System.Drawing.FontStyle]::Bold)
$panelHeader.Controls.Add($btnExit)

# =========================
# Events
# =========================
$cmbRoleSet.Add_SelectedIndexChanged({
    Apply-RoleSet -RoleSetName ([string]$script:cmbRoleSet.SelectedItem)
})

$clbRoles.Add_ItemCheck({
    if (-not $script:SuppressRoleEvents) {
        $form.BeginInvoke([System.Action]{ Update-SelectedCount }) | Out-Null
    }
})

$clbRoles.Add_SelectedIndexChanged({
    Update-RoleDescriptionPane
})

$btnConnect.Add_Click({
    try {
        $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
        [System.Windows.Forms.Application]::DoEvents()
        if (Ensure-Prereqs) {
            Set-Status "Connecting..." ([System.Drawing.Color]::Gold)
            Connect-GraphInteractive
        }
    }
    catch {
        Write-UILog "Connection failed: $($_.Exception.Message)" "ERROR"
        Set-Status "Connection failed" ([System.Drawing.Color]::Salmon)
        [System.Windows.Forms.MessageBox]::Show(
            "Connection failed.`r`n`r`n$($_.Exception.Message)",
            $ToolName,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
    finally {
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
    }
})

$btnActivate.Add_Click({
    try {
        $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
        if (-not $script:IsConnected) {
            throw "Please connect first."
        }
        Activate-SelectedRoles
    }
    catch {
        Write-UILog "Activation failed: $($_.Exception.Message)" "ERROR"
        Set-Status "Activation failed" ([System.Drawing.Color]::Salmon)
        [System.Windows.Forms.MessageBox]::Show(
            "Activation failed.`r`n`r`n$($_.Exception.Message)",
            $ToolName,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
    finally {
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
    }
})

$btnRefresh.Add_Click({
    try {
        $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
        if (-not $script:IsConnected) {
            throw "Please connect first."
        }
        Write-UILog "Refreshing account, eligible roles, and active roles..." "INFO"
        Refresh-UserData
        Set-Status "Refreshed successfully" ([System.Drawing.Color]::LightGreen)
    }
    catch {
        Write-UILog "Refresh failed: $($_.Exception.Message)" "ERROR"
        Set-Status "Refresh failed" ([System.Drawing.Color]::Salmon)
        [System.Windows.Forms.MessageBox]::Show(
            "Refresh failed.`r`n`r`n$($_.Exception.Message)",
            $ToolName,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
    finally {
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
    }
})

$btnDisconnect.Add_Click({
    Disconnect-GraphSafe
})

$btnSelectAll.Add_Click({
    for ($i = 0; $i -lt $script:clbRoles.Items.Count; $i++) {
        $script:clbRoles.SetItemChecked($i, $true)
    }
    Update-SelectedCount
})

$btnClear.Add_Click({
    for ($i = 0; $i -lt $script:clbRoles.Items.Count; $i++) {
        $script:clbRoles.SetItemChecked($i, $false)
    }
    Update-SelectedCount
})

$btnExit.Add_Click({
    $form.Close()
})

$form.Add_FormClosing({
    Disconnect-GraphSafe
})

$form.Add_Shown({
    Update-FormLayout
    Resize-ActiveRoleColumns
})

$form.Add_Resize({
    try {
        Update-FormLayout
    }
    catch {}
})

# =========================
# Startup
# =========================
Write-UILog "GUI tool started." "INFO"

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-UILog "Running in Windows PowerShell. PowerShell 7 is recommended." "WARN"
}
else {
    Write-UILog "Running in PowerShell 7+." "OK"
}

Set-UiEnabled -Enabled $false
$btnConnect.Enabled = $true
$btnDisconnect.Enabled = $false
Clear-AccountInfo
Set-Status "Please connect to load eligible roles..." ([System.Drawing.Color]::Gold)

[void]$form.ShowDialog()