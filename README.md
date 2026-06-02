# AWS Privileged Access Automation (Break Glass)

**Problem:** Platform engineers had no standing AWS console access to production. During incidents, remediation was slow — changes often had to go through CLI and a formal change process, which costs time when production is impacted.

**Solution:** A zero-standing-access, approval-gated, time-bound Privileged Access Management (PAM) flow. Engineers raise a service ticket, approvers sign off, and automation grants temporary AWS console access that auto-expires with no manual cleanup.

**Stack:** PowerShell · Azure Automation · Power Automate · Microsoft Graph API · Entra PIM · AWS IAM Identity Center · Jira Automation

---

## Business context

In a regulated environment, teams often cannot hold permanent admin access to production AWS accounts. A production incident showed the gap: infrastructure drifted from IaC, and without console access the on-call team could not remediate quickly.

This design follows zero standing access: temporary elevation only after approval, with time limits and auditability aligned to a formal change-management process.

**Typical scope:** production and non-production AWS accounts federated through IAM Identity Center (SCIM from Entra ID).

---

## Architecture

```
Engineer raises Jira ticket
  (selects role, duration, provides incident number + justification)
        ↓
Jira Approval Workflow
  (e.g. Platform Lead → Incident Manager → Engineering Director)
        ↓
Jira Automation fires webhook on approval
        ↓
Power Automate (HTTP Trigger) receives JSON payload
        ↓
Azure Automation Runbook (PowerShell)
  ├── Retrieves client secret from Automation Variables
  ├── Authenticates to Microsoft Graph (Client Credentials)
  ├── Resolves user Object ID from email (UPN)
  ├── Resolves group Object ID from display name
  ├── Enforces max duration policy (e.g. 8 hours)
  └── Submits PIM SelfActivate request via Graph API
        ↓
Microsoft Entra PIM activates group membership
  (validates MFA, policy, duration)
        ↓
SCIM sync → AWS IAM Identity Center (2–3 min)
        ↓
Engineer accesses AWS Console via myapplications.microsoft.com
        ↓
Access auto-expires after approved duration — no manual cleanup
```

---

## Access duration policy (example)

Configure per role in Entra PIM. Example caps:

| Role (example) | Max duration |
|---|---|
| AWS admin permission set | 3 hours |
| DevOps break-glass group | 8 hours |
| Production support group | 2 hours |

All access is time-bound and auto-expires. No standing admin access.

---

## Jira request form

Restrict the request type to platform / DevOps groups.

**Fields:**

| Field | Type | Notes |
|---|---|---|
| Group / Role Name | Dropdown | Maps to Entra PIM group |
| Duration Required | Dropdown | Cap per your policy (e.g. 8 hours) |
| Incident or ticket number | Text | Required for justification |
| Reason for requesting access | Text | Reviewed by approvers |

**Approvers (example):** platform lead, incident manager, engineering director.

Once approved, automation runs; no further manual steps for activation.

---

## Jira Automation webhook payload

Replace `customfield_*` placeholders with your Jira field IDs.

```json
{
  "emailId": "{{issue.creator.emailAddress}}",
  "ticketKey": "{{issue.key}}",
  "requestedFor": "{{issue.creator.emailAddress}}",
  "groupName": "{{issue.customfield_GROUP_NAME.value}}",
  "durationHours": "{{issue.customfield_DURATION.value}}",
  "justification": "{{issue.customfield_JUSTIFICATION}}",
  "status": "{{issue.status.name}}"
}
```

### Jira custom field mapping (configure in your instance)

| Field | Placeholder ID | Purpose |
|---|---|---|
| Group / Role Name | `customfield_GROUP_NAME` | PIM group dropdown |
| Duration Required | `customfield_DURATION` | Hours (per policy) |
| Justification | `customfield_JUSTIFICATION` | Reason / incident reference |

---

## Azure Automation Runbook

**File:** `runbook/Invoke-PIMGroupActivation.ps1`

The runbook:

1. Reads the client secret from Azure Automation Variables
2. Authenticates to Microsoft Graph (client credentials)
3. Resolves the user Object ID from UPN
4. Resolves the Entra group Object ID from display name
5. Submits a `SelfActivate` PIM request for the requested duration

### Required App Registration permissions

| Permission | Type | Purpose |
|---|---|---|
| `PrivilegedAccess.ReadWrite.AzureADGroup` | Application | PIM group access |
| `PrivilegedAssignmentSchedule.ReadWrite.AzureADGroup` | Application | Create activations |
| `PrivilegedAssignmentSchedule.Remove.AzureADGroup` | Application | Remove activations |

Admin consent is required.

### Azure Automation Variables (example names)

| Variable | Description |
|---|---|
| `TenantId` | Entra tenant ID |
| `ClientId` | App registration client ID |
| `ServicePrincipalGraph` | Client secret (encrypted) |

Rename variables in the runbook to match your Automation account.

---

## Repository structure

```
aws-privileged-access-automation/
├── runbook/
│   └── Invoke-PIMGroupActivation.ps1
├── power-automate/
│   └── flow-setup.md
├── scripts/
│   ├── New-AWSBreakGlassRole.ps1
│   └── Get-BreakGlassAuditReport.ps1
├── docs/
│   └── troubleshooting.md
├── .gitignore
└── README.md
```

---

## Onboarding a new AWS role

```powershell
.\scripts\New-AWSBreakGlassRole.ps1 `
    -GroupName "AWS - Amazon EC2 Admin" `
    -GroupDescription "Amazon EC2 administrator permissions" `
    -AWSEnterpriseAppObjectId "your-enterprise-app-object-id" `
    -EligibleUserEmails @("engineer@example.com")
```

The script covers Entra group creation, enterprise app assignment, and reminders for AWS permission sets, PIM, and Jira dropdown updates.

---

## Audit and compliance

```powershell
.\scripts\Get-BreakGlassAuditReport.ps1
```

Exports a CSV of active AWS-related group memberships (groups whose display names start with `AWS` — adjust the filter in the script for your naming convention).

---

## Troubleshooting

See [docs/troubleshooting.md](docs/troubleshooting.md).

**Console access after activation:** https://myapplications.microsoft.com → AWS SSO application.

Allow 2–3 minutes for SCIM sync to IAM Identity Center. If access is missing after ~5 minutes, refresh the session, try a private window, and check Azure Automation job output.

---

## Technologies used

- PowerShell 7+
- Azure Automation (runbooks)
- Power Automate (HTTP trigger)
- Microsoft Graph API (PIM for groups)
- Microsoft Entra PIM
- AWS IAM Identity Center (SCIM)
- Jira Service Management + Jira Automation

---

## Disclaimer

This repository is a sanitized reference implementation for learning and portfolio use. Replace all placeholders (tenant IDs, Jira fields, account IDs, URLs) with values from your own environment. Do not commit secrets.

---

## License

MIT
