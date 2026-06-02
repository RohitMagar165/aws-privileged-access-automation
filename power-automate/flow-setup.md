# Power Automate Flow — Setup Guide

## Overview

This flow bridges Jira and Azure Automation. When a ticket is approved, Jira Automation POSTs a webhook to the flow, which starts the `Invoke-PIMGroupActivation` runbook.

---

## Trigger — When an HTTP request is received

### JSON Schema

Paste this schema into the Power Automate HTTP trigger:

```json
{
  "type": "object",
  "properties": {
    "emailId": {
      "type": "string",
      "description": "UPN of the engineer requesting access"
    },
    "ticketKey": {
      "type": "string",
      "description": "Jira ticket key e.g. PROJ-12345"
    },
    "requestedFor": {
      "type": "string",
      "description": "Same as emailId - user requesting access"
    },
    "groupName": {
      "type": "string",
      "description": "Entra PIM group name selected from Jira dropdown"
    },
    "durationHours": {
      "type": "string",
      "description": "Duration in hours from Jira (must match PIM policy max)"
    },
    "justification": {
      "type": "string",
      "description": "Incident number and reason from Jira ticket fields"
    },
    "status": {
      "type": "string",
      "description": "Jira ticket status at time of webhook"
    }
  },
  "required": ["emailId", "groupName", "durationHours", "justification"]
}
```

---

## Step 2 — Azure Automation: Create Job

| Field | Value |
|---|---|
| Subscription | Your Azure subscription |
| Resource Group | Your Automation Account resource group |
| Automation Account | Your Automation Account name |
| Runbook Name | `Invoke-PIMGroupActivation` |
| Wait for Job | Yes (recommended for logging) |

### Runbook Parameters

| Parameter | Dynamic Content |
|---|---|
| `EmailId` | `emailId` from trigger |
| `GroupName` | `groupName` from trigger |
| `DurationHours` | `durationHours` from trigger |
| `Reason` | `justification` from trigger |

---

## Jira Automation Webhook Body

Replace `customfield_*` tokens with your Jira field IDs. For ADF rich-text justification fields, use the merge syntax Jira provides for your field type.

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

### Jira custom field mapping (your instance)

| Field | Placeholder ID | Purpose |
|---|---|---|
| Group / Role Name | `customfield_GROUP_NAME` | PIM group dropdown |
| Duration Required | `customfield_DURATION` | Hours dropdown |
| Justification / Reason | `customfield_JUSTIFICATION` | Text or ADF field |

---

## Error Handling

If the runbook fails, check Azure Automation → Jobs → Output.

| Error | Cause | Fix |
|---|---|---|
| User not found | Wrong email in Jira | Verify UPN matches Entra ID |
| Group not found | Group name mismatch | Check exact display name in Entra ID |
| ExpirationRule error | Duration exceeds PIM max | Reduce duration in Jira form / PIM policy |
| Auth failed | Secret expired or wrong | Rotate secret in Automation Variables |
