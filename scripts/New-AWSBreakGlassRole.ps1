<#
.SYNOPSIS
    Sets up a new AWS role in Entra ID and enables it for PIM-managed
    just-in-time access via the Break Glass automation pipeline.

.DESCRIPTION
    Run this script when onboarding a new AWS role/permission set.
    It walks through:
      1. Creating a new security group in Entra ID
      2. Assigning the group to the AWS IAM Identity Center enterprise app
      3. Reminders for platform team steps (permission sets in AWS)
      4. Enabling PIM on the group
      5. Adding eligible user assignments
      6. Adding the group name to the Jira custom field dropdown

    After this script, the new role can appear in the Jira form dropdown
    and be requested via the Break Glass automation.

.NOTES
    Prerequisites:
      Install-Module Microsoft.Graph -Scope CurrentUser
      Connect-MgGraph -Scopes "Group.ReadWrite.All","Application.ReadWrite.All"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$GroupName,
    # e.g. "AWS - Amazon EC2 Admin"

    [Parameter(Mandatory = $true)]
    [string]$GroupDescription,
    # e.g. "Amazon EC2 administrator permissions"

    [Parameter(Mandatory = $true)]
    [string]$AWSEnterpriseAppObjectId,
    # Object ID of the AWS IAM Identity Center Enterprise App in Entra ID

    [Parameter(Mandatory = $false)]
    [string[]]$EligibleUserEmails = @()
    # UPNs of users who should be eligible to activate this role
)

Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
Connect-MgGraph -Scopes "Group.ReadWrite.All", "Application.ReadWrite.All", "User.Read.All"

# ----------------------------------------------------------
# STEP 1 — Create security group in Entra ID
# ----------------------------------------------------------
Write-Host "`nSTEP 1: Creating security group '$GroupName'..." -ForegroundColor Yellow

$existingGroup = Get-MgGroup -Filter "displayName eq '$GroupName'" -ErrorAction SilentlyContinue
if ($existingGroup) {
    Write-Host "  [SKIP] Group already exists: $($existingGroup.Id)" -ForegroundColor Green
    $group = $existingGroup
}
else {
    $groupParams = @{
        DisplayName     = $GroupName
        Description     = $GroupDescription
        MailEnabled     = $false
        MailNickname    = $GroupName.Replace(" ", "").Replace("-", "")
        SecurityEnabled = $true
    }
    $group = New-MgGroup -BodyParameter $groupParams
    Write-Host "  [OK] Group created: $($group.Id)" -ForegroundColor Green
}

# ----------------------------------------------------------
# STEP 2 — Assign group to AWS IAM Identity Centre Enterprise App
# ----------------------------------------------------------
Write-Host "`nSTEP 2: Assigning group to AWS Enterprise App..." -ForegroundColor Yellow

$sp = Get-MgServicePrincipal -ServicePrincipalId $AWSEnterpriseAppObjectId
$appRoleId = ($sp.AppRoles | Where-Object { $_.DisplayName -eq "User" } | Select-Object -First 1).Id

if (-not $appRoleId) {
    $appRoleId = "00000000-0000-0000-0000-000000000000"
}

$assignParams = @{
    PrincipalId = $group.Id
    ResourceId  = $sp.Id
    AppRoleId   = $appRoleId
}

try {
    New-MgGroupAppRoleAssignment -GroupId $group.Id -BodyParameter $assignParams
    Write-Host "  [OK] Group assigned to '$($sp.DisplayName)'" -ForegroundColor Green
    Write-Host "  NOTE: Initial SCIM sync may take up to 40 minutes." -ForegroundColor DarkYellow
}
catch {
    Write-Warning "  Assignment may already exist or failed: $_"
}

# ----------------------------------------------------------
# STEP 3 — Platform team reminder
# ----------------------------------------------------------
Write-Host "`nSTEP 3: Platform Team Action Required" -ForegroundColor Magenta
Write-Host "  Complete in AWS IAM Identity Center for each target account:" -ForegroundColor White
Write-Host "  1. Create a Permission Set" -ForegroundColor White
Write-Host "  2. Attach the required policies to the Permission Set" -ForegroundColor White
Write-Host "  3. Assign the Permission Set to the group '$GroupName'" -ForegroundColor White
Write-Host "  4. Repeat for production and non-production accounts as required" -ForegroundColor White

# ----------------------------------------------------------
# STEP 4 — Enable PIM on the group (manual step reminder)
# ----------------------------------------------------------
Write-Host "`nSTEP 4: Enable PIM for this group (manual step in Entra portal)" -ForegroundColor Magenta
Write-Host "  1. Go to: https://entra.microsoft.com" -ForegroundColor White
Write-Host "  2. Groups → All groups → '$GroupName'" -ForegroundColor White
Write-Host "  3. Activity → Privileged Identity Management → Enable PIM for this group" -ForegroundColor White
Write-Host "  4. Set activation max duration per your policy (e.g. 8 hours)" -ForegroundColor White
Write-Host "  5. Require justification on activation" -ForegroundColor White

# ----------------------------------------------------------
# STEP 5 — Add eligible user assignments via Graph
# ----------------------------------------------------------
if ($EligibleUserEmails.Count -gt 0) {
    Write-Host "`nSTEP 5: Adding eligible user assignments..." -ForegroundColor Yellow
    foreach ($email in $EligibleUserEmails) {
        $user = Get-MgUser -Filter "userPrincipalName eq '$email'" -ErrorAction SilentlyContinue
        if (-not $user) {
            Write-Warning "  User not found: $email"
            continue
        }
        Write-Host "  [OK] Add '$email' as eligible in PIM portal manually (Graph PIM eligibility requires additional permissions)" -ForegroundColor Green
    }
}

# ----------------------------------------------------------
# STEP 6 — Jira custom field reminder
# ----------------------------------------------------------
Write-Host "`nSTEP 6: Add group to Jira custom field dropdown" -ForegroundColor Magenta
Write-Host "  1. Jira → Project settings → Fields (or global field configuration)" -ForegroundColor White
Write-Host "  2. Open the 'Group / Role Name' (or equivalent) select list field" -ForegroundColor White
Write-Host "  3. Edit options and add: $GroupName" -ForegroundColor White

Write-Host "`nSetup complete for '$GroupName'. Complete the manual steps above to finish onboarding." -ForegroundColor Green
