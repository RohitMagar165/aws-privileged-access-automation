<#
.SYNOPSIS
    Activates a Microsoft Entra PIM group for time-bound AWS console access.

.DESCRIPTION
    Triggered by Jira Automation webhook when a Break Glass access request
    ticket is approved. Authenticates to Microsoft Graph using Client
    Credentials, resolves the user and group, then submits a PIM
    SelfActivate request for the specified duration.

    Architecture:
        Jira Ticket (approved)
            → Jira Automation Webhook
            → Power Automate (HTTP Trigger)
            → This Azure Automation Runbook
            → Microsoft Graph API (PIM for Groups)
            → Entra PIM Group Activated
            → SCIM sync → AWS IAM Identity Centre (2-3 min)
            → Engineer gains time-bound AWS console access

    Security:
        - TenantId and ClientId stored as Azure Automation Variables
        - Client secret stored as encrypted Automation Variable
        - No credentials hardcoded in this script
        - Max duration enforced by Entra PIM policy (configure in tenant)

.NOTES
    Required App Registration permissions (Application type):
        PrivilegedAccess.ReadWrite.AzureADGroup
        PrivilegedAssignmentSchedule.ReadWrite.AzureADGroup
        PrivilegedAssignmentSchedule.Remove.AzureADGroup
    Admin consent must be granted for all permissions.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$EmailId,
    # User email/UPN to activate

    [Parameter(Mandatory = $true)]
    [string]$GroupName,
    # PIM-enabled Group DisplayName — ObjectId resolved automatically

    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 24)]
    [int]$DurationHours,
    # Must not exceed PIM policy maximum (e.g. 8 hours)

    [Parameter(Mandatory = $true)]
    [string]$Reason
    # Justification from Jira ticket (incident number + reason)
)

# ==========================================================
# CONFIGURATION
# All sensitive values stored in Azure Automation Variables
# Replace these placeholder names with your actual variable names
# ==========================================================
$TenantId  = Get-AutomationVariable -Name "TenantId"
$ClientId  = Get-AutomationVariable -Name "ClientId"
$SecretVar = "ServicePrincipalGraph"
# ^ Name of the encrypted Automation Variable holding the client secret

# ==========================================================
# STEP 1 — AUTHENTICATION (Client Credentials)
# ==========================================================
try {
    $ClientSecret = Get-AutomationVariable -Name $SecretVar
    if ([string]::IsNullOrWhiteSpace($ClientSecret)) {
        throw "Automation variable '$SecretVar' is missing or empty."
    }

    $tokenBody = @{
        client_id     = $ClientId
        scope         = "https://graph.microsoft.com/.default"
        client_secret = $ClientSecret
        grant_type    = "client_credentials"
    }

    $tokenResponse = Invoke-RestMethod `
        -Uri     "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
        -Method  POST `
        -Body    $tokenBody `
        -ErrorAction Stop

    $accessToken = $tokenResponse.access_token
    $headers     = @{ Authorization = "Bearer $accessToken" }

    Write-Output "INFO: Authenticated to Microsoft Graph."
}
catch {
    Write-Error "AUTH FAILED: $($_.Exception.Message)"
    exit 1
}

# ==========================================================
# STEP 2 — RESOLVE USER OBJECT ID (from UPN)
# ==========================================================
try {
    $userUri = "https://graph.microsoft.com/v1.0/users?`$filter=userPrincipalName eq '$EmailId'&`$select=id,userPrincipalName"
    $user    = Invoke-RestMethod -Method GET -Uri $userUri -Headers $headers -ErrorAction Stop

    if (-not $user.value) {
        throw "User '$EmailId' not found in Entra ID."
    }

    $PrincipalId = $user.value[0].id
    Write-Output "INFO: User resolved: $PrincipalId"
}
catch {
    Write-Error "USER LOOKUP FAILED: $($_.Exception.Message)"
    exit 1
}

# ==========================================================
# STEP 3 — RESOLVE GROUP OBJECT ID (from DisplayName)
# Exact case-insensitive match preferred.
# Fails safely if duplicate group names exist.
# ==========================================================
try {
    $encodedName = $GroupName.Replace("'", "''")   # escape single quotes for OData filter
    $grpUri = "https://graph.microsoft.com/v1.0/groups?`$filter=displayName eq '$encodedName'&`$select=id,displayName,onPremisesSyncEnabled"
    $groups = Invoke-RestMethod -Method GET -Uri $grpUri -Headers $headers -ErrorAction Stop

    if (-not $groups.value) {
        throw "Group '$GroupName' not found. Verify the name exactly as shown in Entra ID."
    }

    $exact = $groups.value | Where-Object { $_.displayName -eq $GroupName }
    if (-not $exact) {
        $exact = $groups.value | Where-Object { $_.displayName -ieq $GroupName }
    }

    if ($exact.Count -gt 1) {
        Write-Error "Multiple groups found with name '$GroupName'. Use a unique name or ObjectId. Found:`n$($exact.displayName -join "`n")"
        exit 1
    }

    $GroupObjectId = $exact[0].id
    Write-Output "INFO: Group resolved '$GroupName' -> $GroupObjectId"
}
catch {
    Write-Error "GROUP LOOKUP FAILED: $($_.Exception.Message)"
    exit 1
}

# ==========================================================
# STEP 4 — DURATION POLICY GUARD (example: 8 hours)
# ==========================================================
if ($DurationHours -gt 8) {
    Write-Warning "Duration $DurationHours hours exceeds example max (8h). PIM policy may reject with ExpirationRule error."
}

# ==========================================================
# STEP 5 — BUILD PIM ACTIVATION REQUEST
# POST /identityGovernance/privilegedAccess/group/assignmentScheduleRequests
# ==========================================================
$isoDuration = "PT${DurationHours}H"

$body = @{
    accessId      = "member"
    principalId   = $PrincipalId
    groupId       = "$GroupObjectId"
    action        = "SelfActivate"
    justification = $Reason
    scheduleInfo  = @{
        startDateTime = (Get-Date).ToUniversalTime().ToString("o")
        expiration    = @{
            type     = "AfterDuration"
            duration = $isoDuration
        }
    }
}

$bodyJson = $body | ConvertTo-Json -Depth 10
Write-Output "INFO: Submitting PIM activation for group '$GroupName' (duration=$DurationHours h)..."

# ==========================================================
# STEP 6 — SUBMIT ACTIVATION REQUEST
# ==========================================================
try {
    $uri    = "https://graph.microsoft.com/v1.0/identityGovernance/privilegedAccess/group/assignmentScheduleRequests"
    $result = Invoke-RestMethod `
        -Uri         $uri `
        -Method      POST `
        -Headers     $headers `
        -Body        $bodyJson `
        -ContentType "application/json" `
        -ErrorAction Stop

    Write-Output "SUCCESS: PIM SelfActivate request submitted."
    Write-Output "REQUEST ID : $($result.id)"
    Write-Output "USER       : $EmailId"
    Write-Output "GROUP      : $GroupName"
    Write-Output "DURATION   : $DurationHours hour(s)"
    Write-Output "EXPIRES    : $((Get-Date).AddHours($DurationHours).ToUniversalTime().ToString('u'))"
    Write-Output "NOTE       : Allow 2-3 minutes for SCIM sync to AWS IAM Identity Centre."
}
catch {
    $raw = $_.ErrorDetails.Message
    if (-not $raw -and $_.Exception.Response) {
        try {
            $stream = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($stream)
            $raw    = $reader.ReadToEnd()
        }
        catch { }
    }
    Write-Error "PIM ACTIVATION FAILED: $raw"
    exit 1
}
