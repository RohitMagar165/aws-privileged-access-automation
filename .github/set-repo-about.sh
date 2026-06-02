#!/usr/bin/env bash
# Run once after: gh auth login
set -euo pipefail

REPO="RohitMagar165/aws-privileged-access-automation"
DESC="Zero-standing-access AWS break glass system using Entra PIM, Azure Automation, Power Automate and Microsoft Graph API"

gh repo edit "$REPO" --description "$DESC" \
  --add-topic powershell \
  --add-topic azure-automation \
  --add-topic entra-pim \
  --add-topic microsoft-graph \
  --add-topic aws \
  --add-topic jira-automation \
  --add-topic privileged-access \
  --add-topic break-glass \
  --add-topic iam

echo "Done. Check: https://github.com/$REPO"
