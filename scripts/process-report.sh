#!/usr/bin/env bash
set -euo pipefail

# Process a bot account report
# Expected environment variables (from issue parser):
#   USERNAME        - reported GitHub username
#   REPORTING_REPO  - owner/repo of the reporting repository
#   REASON          - reason for the report
#   EVIDENCE_URL    - optional evidence link
#   ISSUE_NUMBER    - the issue number for commenting

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATA_DIR="$REPO_ROOT/data"
TRUSTED_REPOS="$DATA_DIR/trusted-repos.json"
ACCOUNTS_DIR="$DATA_DIR/accounts"
TODAY="$(date -u +%Y-%m-%d)"

# Validate required fields
if [[ -z "${USERNAME:-}" ]]; then
  echo "::error::Missing required field: username"
  exit 1
fi

if [[ -z "${REPORTING_REPO:-}" ]]; then
  echo "::error::Missing required field: reporting_repo"
  exit 1
fi

if [[ -z "${REASON:-}" ]]; then
  echo "::error::Missing required field: reason"
  exit 1
fi

# Normalize username to lowercase
USERNAME="$(echo "$USERNAME" | tr '[:upper:]' '[:lower:]')"

# Check if reporting repo is trusted
if ! jq -e --arg repo "$REPORTING_REPO" 'map(ascii_downcase) | index($repo | ascii_downcase)' "$TRUSTED_REPOS" > /dev/null 2>&1; then
  echo "::error::Repository '$REPORTING_REPO' is not in the trusted reporter network"
  echo "result=untrusted" >> "$GITHUB_OUTPUT"
  exit 1
fi

ACCOUNT_FILE="$ACCOUNTS_DIR/${USERNAME}.json"

if [[ -f "$ACCOUNT_FILE" ]]; then
  # Update existing account file — add new report and update last_reported
  jq \
    --arg repo "$REPORTING_REPO" \
    --arg reason "$REASON" \
    --arg evidence "${EVIDENCE_URL:-}" \
    --arg date "$TODAY" \
    '.last_reported = $date |
     .reports += [{ reported_by: $repo, reason: $reason, evidence_url: $evidence, date: $date }] |
     .status = "flagged"' \
    "$ACCOUNT_FILE" > "${ACCOUNT_FILE}.tmp" && mv "${ACCOUNT_FILE}.tmp" "$ACCOUNT_FILE"
  echo "Updated existing report for $USERNAME"
else
  # Create new account file
  jq -n \
    --arg username "$USERNAME" \
    --arg repo "$REPORTING_REPO" \
    --arg reason "$REASON" \
    --arg evidence "${EVIDENCE_URL:-}" \
    --arg date "$TODAY" \
    '{
      username: $username,
      status: "flagged",
      first_reported: $date,
      last_reported: $date,
      reports: [{ reported_by: $repo, reason: $reason, evidence_url: $evidence, date: $date }],
      appeal: null
    }' > "$ACCOUNT_FILE"
  echo "Created new report for $USERNAME"
fi

echo "result=success" >> "$GITHUB_OUTPUT"
echo "account_file=$ACCOUNT_FILE" >> "$GITHUB_OUTPUT"
