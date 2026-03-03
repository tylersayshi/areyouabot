# areyouabot

A public database and automated management system for tracking suspected bot accounts on GitHub. External repositories opt into a **trusted reporter network** and use a published GitHub Action to submit reports. Everything is driven through GitHub Issues + Actions — no external infrastructure needed.

Here is my motivation for making this: https://tylur.blog/harmful-prs

Plus: https://bsky.app/profile/nicr.dev/post/3mg4exe7sgs2r

Use this project, or not. I am adding it to Github because I think on principle, Github should carry the burden of the botnet that exists here today. This can act as a little trusted dataset of banned accounts for projects that like this idea. For others that are interested and weary, [reach out](https://bsky.app/profile/tylur.dev)!

## How It Works

### Trusted Reporter Network

Repositories must apply to join the trusted network before they can submit reports. This prevents abuse and ensures accountability.

### Three Flows

1. **Apply** — Repo owners request to join the trusted network
2. **Report** — Trusted repos flag suspected bot accounts
3. **Appeal** — Flagged users contest their flag

All flows are managed through GitHub Issues with automated validation and processing.

## Using the GitHub Action

### Check if a user is flagged

```yaml
- uses: tylersayshi/areyouabot/action/check@main
  id: bot-check
  with:
    username: ${{ github.event.issue.user.login }}

- name: Handle bot
  if: steps.bot-check.outputs.is_flagged == 'true'
  run: echo "User is flagged as a bot"
```

**Outputs:**
- `is_flagged` — `true` or `false`
- `status` — `flagged`, `cleared`, or `unknown`

No authentication is required for checks — the data is public.

### Report a suspected bot

The report action uses OIDC authentication — no PAT or token is needed. Your workflow just needs `permissions: id-token: write`.

```yaml
permissions:
  id-token: write

jobs:
  report:
    runs-on: ubuntu-latest
    steps:
      - uses: tylersayshi/areyouabot/action/report@main
        with:
          username: "suspected-bot-123"
          reason: "Automated spam comments on multiple issues"
          evidence_url: "https://github.com/owner/repo/issues/123"
```

**Requirements:**
- Your repository must be in the trusted reporter network
- Your workflow must have `permissions: id-token: write`

### Combined action (both modes)

```yaml
permissions:
  id-token: write

jobs:
  bot-check:
    runs-on: ubuntu-latest
    steps:
      # Check mode (no special permissions needed)
      - uses: tylersayshi/areyouabot@main
        id: check
        with:
          mode: check
          username: "some-user"

      # Report mode (requires id-token: write)
      - uses: tylersayshi/areyouabot@main
        with:
          mode: report
          username: "suspected-bot"
          reason: "Spam activity"
```

## Using as Slash Commands

Maintainers can comment `/checkbot` or `/reportbot` on any issue or PR. Only users with `MEMBER`, `COLLABORATOR`, or `OWNER` association on the repo can trigger these commands.

Add this workflow to `.github/workflows/bot-check.yml` in your repository:

### `/checkbot` — Check if the author is flagged

```yaml
name: Check Bot Slash Command

on:
  issue_comment:
    types: [created]

permissions:
  issues: write
  pull-requests: write

jobs:
  checkbot:
    if: |
      github.event.comment.body == '/checkbot' &&
      contains(fromJSON('["MEMBER","COLLABORATOR","OWNER"]'), github.event.comment.author_association)
    runs-on: ubuntu-latest
    steps:
      - name: Get issue/PR author
        id: author
        run: echo "username=${{ github.event.issue.user.login }}" >> "$GITHUB_OUTPUT"

      - uses: tylersayshi/areyouabot/action/check@main
        id: bot-check
        with:
          username: ${{ steps.author.outputs.username }}

      - name: Comment result
        uses: actions/github-script@v7
        with:
          script: |
            const status = '${{ steps.bot-check.outputs.status }}';
            const isFlagged = '${{ steps.bot-check.outputs.is_flagged }}';
            const username = '${{ steps.author.outputs.username }}';
            let body;
            if (isFlagged === 'true') {
              body = `⚠️ **@${username}** is flagged as a bot in [areyouabot](https://github.com/tylersayshi/areyouabot).`;
            } else if (status === 'cleared') {
              body = `✅ **@${username}** has been reviewed and cleared.`;
            } else {
              body = `ℹ️ **@${username}** has no record in [areyouabot](https://github.com/tylersayshi/areyouabot).`;
            }
            github.rest.issues.createComment({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: context.issue.number,
              body
            });
```

### `/reportbot` — Report the author as a bot

This requires your repo to be in the [trusted reporter network](#joining-the-trusted-network).

```yaml
name: Report Bot Slash Command

on:
  issue_comment:
    types: [created]

permissions:
  id-token: write
  issues: write
  pull-requests: write

jobs:
  reportbot:
    if: |
      github.event.comment.body == '/reportbot' &&
      contains(fromJSON('["MEMBER","COLLABORATOR","OWNER"]'), github.event.comment.author_association)
    runs-on: ubuntu-latest
    steps:
      - name: Get issue/PR author
        id: author
        run: echo "username=${{ github.event.issue.user.login }}" >> "$GITHUB_OUTPUT"

      - uses: tylersayshi/areyouabot/action/report@main
        id: bot-report
        with:
          username: ${{ steps.author.outputs.username }}
          reason: "Reported via /reportbot by ${{ github.event.comment.user.login }}"
          evidence_url: ${{ github.event.issue.html_url }}

      - name: Comment result
        uses: actions/github-script@v7
        with:
          script: |
            const username = '${{ steps.author.outputs.username }}';
            const isFlagged = '${{ steps.bot-report.outputs.is_flagged }}';
            let body;
            if (isFlagged === 'true') {
              body = `🚫 **@${username}** has been reported as a bot to [areyouabot](https://github.com/tylersayshi/areyouabot).`;
            } else {
              body = `❌ Failed to report **@${username}**. Make sure this repo is in the trusted reporter network.`;
            }
            github.rest.issues.createComment({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: context.issue.number,
              body
            });
```

## Joining the Trusted Network

1. [Open an application issue](../../issues/new?template=apply.yml)
2. Fill in your repository name and maintainer username
3. The automation validates your application
4. A maintainer reviews and approves by adding the `approved` label
5. Your repo is added to the trusted list

## Reporting a Bot Account

### Via GitHub Action (recommended)

Add the report action to your workflow. See [usage examples](#report-a-suspected-bot) above.

### Via Issue Template

1. [Open a report issue](../../issues/new?template=report.yml)
2. Fill in the suspected bot's username, your repository, and the reason
3. The automation validates your repo is trusted and processes the report

## Appealing a Flag

If your account has been flagged and you believe it's a mistake:

1. [Open an appeal issue](../../issues/new?template=appeal.yml)
2. Your GitHub username must match the flagged account
3. Provide an explanation and any supporting evidence
4. A maintainer reviews and approves or denies the appeal

## Data Format

Flagged accounts are stored as JSON files in `data/accounts/`:

```json
{
  "username": "bot-user-123",
  "status": "flagged",
  "first_reported": "2026-03-02",
  "last_reported": "2026-03-02",
  "reports": [
    {
      "reported_by": "owner/repo",
      "reason": "Automated spam comments",
      "evidence_url": "https://github.com/owner/repo/issues/123",
      "date": "2026-03-02"
    }
  ],
  "appeal": null
}
```

Trusted repos are listed in `data/trusted-repos.json`.

## Author Note

If this get's used and many repo's find it a useful source of truth for bot-prevention I will move this to a shared github org and give controls to a collective maintainers to help with stewarding this project. I'm making this from seeing the need and having an idea for how I think it can work. If you'd like to help or share another way, great! Let's stop slop PRs together :)
