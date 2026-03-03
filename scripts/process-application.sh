#!/usr/bin/env bash
set -euo pipefail

# Process a trusted reporter application
# Expected environment variables (from issue parser):
#   REPOSITORY  - owner/repo applying to join
#   MAINTAINER  - GitHub username claiming maintainership
#   ISSUE_AUTHOR - the GitHub username that opened the issue

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATA_DIR="$REPO_ROOT/data"
TRUSTED_REPOS="$DATA_DIR/trusted-repos.json"

# Validate required fields
if [[ -z "${REPOSITORY:-}" ]]; then
  echo "::error::Missing required field: repository"
  exit 1
fi

if [[ -z "${MAINTAINER:-}" ]]; then
  echo "::error::Missing required field: maintainer"
  exit 1
fi

if [[ -z "${ISSUE_AUTHOR:-}" ]]; then
  echo "::error::Missing required field: issue_author"
  exit 1
fi

# Verify issue author matches claimed maintainer
if [[ "${ISSUE_AUTHOR,,}" != "${MAINTAINER,,}" ]]; then
  echo "::error::Issue author ($ISSUE_AUTHOR) does not match claimed maintainer ($MAINTAINER)"
  echo "result=author_mismatch" >> "$GITHUB_OUTPUT"
  exit 1
fi

# Check if already trusted
if jq -e --arg repo "$REPOSITORY" 'map(ascii_downcase) | index($repo | ascii_downcase)' "$TRUSTED_REPOS" > /dev/null 2>&1; then
  echo "::error::Repository '$REPOSITORY' is already in the trusted reporter network"
  echo "result=already_trusted" >> "$GITHUB_OUTPUT"
  exit 1
fi

# Verify the repository exists on GitHub
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "https://api.github.com/repos/${REPOSITORY}" \
  -H "Accept: application/vnd.github.v3+json" \
  ${GITHUB_TOKEN:+-H "Authorization: token $GITHUB_TOKEN"})

if [[ "$HTTP_STATUS" != "200" ]]; then
  echo "::error::Repository '$REPOSITORY' does not exist or is not accessible (HTTP $HTTP_STATUS)"
  echo "result=repo_not_found" >> "$GITHUB_OUTPUT"
  exit 1
fi

# Add to trusted repos
jq --arg repo "$REPOSITORY" '. += [$repo]' "$TRUSTED_REPOS" > "${TRUSTED_REPOS}.tmp" \
  && mv "${TRUSTED_REPOS}.tmp" "$TRUSTED_REPOS"

echo "Added $REPOSITORY to trusted reporter network"
echo "result=success" >> "$GITHUB_OUTPUT"
