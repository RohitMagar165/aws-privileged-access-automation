# Troubleshooting guide

## Common issues

| Issue | Likely cause | Fix |
|---|---|---|
| Access not visible after approval | SCIM sync delay (normal) | Wait 2–3 min, refresh browser or try incognito |
| Runbook fails — user not found | Wrong email in Jira or UPN mismatch | Verify UPN in Entra ID matches Jira email |
| Runbook fails — group not found | Group name typo in Jira dropdown | Check exact display name in Entra ID |
| ExpirationRule error | Duration exceeds PIM maximum | Reduce duration or update PIM policy |
| Auth failed in runbook | Client secret expired | Rotate secret in Azure Automation Variables |
| Ticket approved but no access | Power Automate flow not triggered | Check Power Automate run history |
| Wrong group selected | User selected wrong role | Revoke in Entra PIM, raise a new ticket |

## Where to check logs

- **Azure Automation:** Portal → Automation Account → Jobs → Output
- **Power Automate:** My flows → Run history
- **Jira Automation:** Project settings → Automation → Audit log
- **Entra PIM:** Entra admin center → Identity Governance → PIM → Groups → Audit history

## Manually revoking access early

```powershell
Connect-MgGraph -Scopes "PrivilegedAccess.ReadWrite.AzureADGroup"

$body = @{
    accessId      = "member"
    principalId   = "USER_OBJECT_ID"
    groupId       = "GROUP_OBJECT_ID"
    action        = "SelfDeactivate"
    justification = "Early revocation - incident resolved"
} | ConvertTo-Json

Invoke-MgGraphRequest -Method POST `
    -Uri "https://graph.microsoft.com/v1.0/identityGovernance/privilegedAccess/group/assignmentScheduleRequests" `
    -Body $body `
    -ContentType "application/json"
```

## Security operations notification

Define a process so your security / operations team is notified when break-glass access is activated (e.g. ticket comment, email, or SIEM alert). The incident manager or approver typically owns this step before the engineer uses elevated access.
