#!/usr/bin/env bash
set -euo pipefail

# Handle a bot flag appeal
# Expected environment variables (from issue parser):
#   USERNAME      - the flagged username appealing
#   ISSUE_AUTHOR  - the GitHub username that opened the issue
#   ACTION        - "validate" or "approve" or "deny"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATA_DIR="$REPO_ROOT/data"
ACCOUNTS_DIR="$DATA_DIR/accounts"
TODAY="$(date -u +%Y-%m-%d)"

# Validate required fields
if [[ -z "${USERNAME:-}" ]]; then
  echo "::error::Missing required field: username"
  exit 1
fi

# Normalize username
USERNAME="$(echo "$USERNAME" | tr '[:upper:]' '[:lower:]')"
ACCOUNT_FILE="$ACCOUNTS_DIR/${USERNAME}.json"

case "${ACTION:-validate}" in
  validate)
    # Check issue author matches username
    if [[ -z "${ISSUE_AUTHOR:-}" ]]; then
      echo "::error::Missing required field: issue_author"
      exit 1
    fi

    if [[ "${ISSUE_AUTHOR,,}" != "${USERNAME,,}" ]]; then
      echo "::error::Issue author ($ISSUE_AUTHOR) does not match appealed username ($USERNAME)"
      echo "result=author_mismatch" >> "$GITHUB_OUTPUT"
      exit 1
    fi

    # Check account exists and is flagged
    if [[ ! -f "$ACCOUNT_FILE" ]]; then
      echo "::error::No record found for username '$USERNAME'"
      echo "result=not_found" >> "$GITHUB_OUTPUT"
      exit 1
    fi

    CURRENT_STATUS=$(jq -r '.status' "$ACCOUNT_FILE")
    if [[ "$CURRENT_STATUS" != "flagged" ]]; then
      echo "::error::Account '$USERNAME' is not currently flagged (status: $CURRENT_STATUS)"
      echo "result=not_flagged" >> "$GITHUB_OUTPUT"
      exit 1
    fi

    echo "Appeal validated for $USERNAME"
    echo "result=valid" >> "$GITHUB_OUTPUT"
    ;;

  approve)
    if [[ ! -f "$ACCOUNT_FILE" ]]; then
      echo "::error::No record found for username '$USERNAME'"
      exit 1
    fi

    # Set status to cleared and record appeal
    jq \
      --arg date "$TODAY" \
      '.status = "cleared" |
       .appeal = { status: "approved", date: $date }' \
      "$ACCOUNT_FILE" > "${ACCOUNT_FILE}.tmp" && mv "${ACCOUNT_FILE}.tmp" "$ACCOUNT_FILE"

    echo "Appeal approved for $USERNAME — status set to cleared"
    echo "result=approved" >> "$GITHUB_OUTPUT"
    echo "account_file=$ACCOUNT_FILE" >> "$GITHUB_OUTPUT"
    ;;

  deny)
    if [[ ! -f "$ACCOUNT_FILE" ]]; then
      echo "::error::No record found for username '$USERNAME'"
      exit 1
    fi

    # Record denied appeal, keep flagged status
    jq \
      --arg date "$TODAY" \
      '.appeal = { status: "denied", date: $date }' \
      "$ACCOUNT_FILE" > "${ACCOUNT_FILE}.tmp" && mv "${ACCOUNT_FILE}.tmp" "$ACCOUNT_FILE"

    echo "Appeal denied for $USERNAME — status remains flagged"
    echo "result=denied" >> "$GITHUB_OUTPUT"
    echo "account_file=$ACCOUNT_FILE" >> "$GITHUB_OUTPUT"
    ;;

  *)
    echo "::error::Unknown action: $ACTION"
    exit 1
    ;;
esac
