<#
.SYNOPSIS
    Audits AWS Break Glass PIM-related group memberships.

.DESCRIPTION
    Exports a report of currently active members on Entra groups whose
    display names match a prefix (default: starts with 'AWS').

    Used for:
      - Security / compliance reviews
      - Quarterly access audits
      - Incident post-mortems

    Adjust the group filter in this script to match your naming convention.

.NOTES
    Prerequisites:
      Install-Module Microsoft.Graph -Scope CurrentUser
      Connect-MgGraph -Scopes "Group.Read.All","User.Read.All"
#>

Connect-MgGraph -Scopes "Group.Read.All", "User.Read.All"

Write-Host "Fetching AWS break-glass groups..." -ForegroundColor Cyan

$awsGroups = Get-MgGroup `
    -Filter "startsWith(displayName,'AWS')" `
    -ConsistencyLevel eventual `
    -CountVariable c `
    -All

Write-Host "Found $c matching groups." -ForegroundColor Green

$activeReport = @()

foreach ($group in $awsGroups) {

    $members = Get-MgGroupMember -GroupId $group.Id -All -ErrorAction SilentlyContinue

    foreach ($member in $members) {
        $user = Get-MgUser -UserId $member.Id -ErrorAction SilentlyContinue
        if ($user) {
            $activeReport += [PSCustomObject]@{
                GroupName  = $group.DisplayName
                UserName   = $user.DisplayName
                UserEmail  = $user.UserPrincipalName
                Status     = "ACTIVE"
                ReportedAt = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            }
        }
    }
}

$date         = Get-Date -Format "yyyy-MM-dd"
$activeOutput = ".\aws-breakglass-active-$date.csv"
$activeReport | Export-Csv -Path $activeOutput -NoTypeInformation -Encoding UTF8

Write-Host ""
Write-Host "Reports saved:" -ForegroundColor Green
Write-Host "  Active access : $activeOutput" -ForegroundColor White
Write-Host "  Total active  : $($activeReport.Count) user-group assignments" -ForegroundColor White
