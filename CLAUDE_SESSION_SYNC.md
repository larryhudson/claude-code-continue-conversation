# Claude Code Session Synchronization

This repository includes tooling to synchronize Claude Code sessions between your local machine and GitHub Actions workflows, enabling continuous conversations across environments.

## Overview

Claude Code stores conversations locally in `~/.claude/projects/`. This setup allows you to:

1. **Locally**: Work with Claude Code, building context and state
2. **Sync**: Upload your session to GitHub as a release artifact
3. **GitHub Actions**: Download and resume the same session in CI/CD workflows
4. **Continue**: Pick up exactly where you left off, with full context

## Components

### 1. Session Discovery (`scripts/claude-session-discovery.sh`)

Finds the most recent Claude Code session for a given branch and working directory.

**Usage:**
```bash
./scripts/claude-session-discovery.sh [BRANCH_NAME]
```

**Output:** Session ID (UUID) or exit code 1 if not found

**Example:**
```bash
$ SESSION_ID=$(QUIET=1 ./scripts/claude-session-discovery.sh main)
$ echo $SESSION_ID
d90b667f-c706-42da-9a70-bfd30dc5eefb
```

### 2. Session Sync (`scripts/claude-session-sync.sh`)

Uploads the latest local session to GitHub as a release artifact.

**Usage:**
```bash
./scripts/claude-session-sync.sh [BRANCH_NAME]
```

**What it does:**
- Finds the latest session for the branch
- Compresses it into a `.tar.gz` archive
- Creates a metadata JSON file
- Uploads both to a GitHub Release (`claude-sessions-{branch}`)

**Example:**
```bash
$ ./scripts/claude-session-sync.sh main
✓ Found session: d90b667f-c706-42da-9a70-bfd30dc5eefb
✓ Created session archive: claude-session-d90b667f-c706-42da-9a70-bfd30dc5eefb.tar.gz
✓ Session uploaded to GitHub!
Release: claude-sessions-main
```

### 3. Session Restore (`scripts/claude-session-restore.sh`)

Downloads and restores a session from GitHub in CI/CD workflows.

**Usage:**
```bash
./scripts/claude-session-restore.sh [BRANCH_NAME]
```

**What it does:**
- Looks for a GitHub Release named `claude-sessions-{branch}`
- Downloads the session archive
- Extracts it to `~/.claude/projects/`
- Sets `$SESSION_ID` environment variable for use in workflows

**Example:**
```bash
$ ./scripts/claude-session-restore.sh main
✓ Found release: claude-sessions-main
✓ Session restored!
Session ID: d90b667f-c706-42da-9a70-bfd30dc5eefb
```

## Workflows

### Manual Continuation (`claude-continue.yml`)

A manually-dispatched workflow that resumes a session from your local work.

**Trigger:**
```
GitHub → Actions → Claude Code - Continue Session → Run workflow
```

**Inputs:**
- `prompt` (required): What you want Claude to do
- `branch` (optional): Which branch's session to continue from (defaults to current)

**How it works:**
1. Checks out your code
2. Restores the session from the GitHub Release
3. Runs Claude with `--resume {SESSION_ID}` to continue
4. Uploads the updated session back to GitHub

**Example workflow:**
```
prompt: "Add tests for the new validation function"
branch: main
```

## Local Workflow

### 1. Work locally with Claude Code

```bash
cd /path/to/repo
claude -c  # Continue existing session
# or
claude "Implement the feature"  # Start new session
```

### 2. Before pushing, sync your session

```bash
./scripts/claude-session-sync.sh
# Creates a GitHub Release with your session
```

### 3. Push your branch

```bash
git push origin feature-branch
```

### 4. Later, continue in GitHub Actions

Visit the Actions tab and manually trigger "Claude Code - Continue Session" with your prompt.

## GitHub Actions Workflow

### 1. Session is restored from GitHub Release
```yaml
- name: Restore Claude Code session
  run: bash ./scripts/claude-session-restore.sh main
```

### 2. Claude runs with the restored context
```yaml
- name: Run Claude Code (Continue Session)
  uses: anthropics/claude-code-action@v1
  with:
    claude_args: --resume ${{ env.SESSION_ID }}
    prompt: "Your instruction here"
```

### 3. Updated session is synced back
```yaml
- name: Upload updated session
  run: bash ./scripts/claude-session-sync.sh main
```

## Session Storage

Sessions are stored as GitHub Releases with the tag `claude-sessions-{branch}`. Each release contains:

- **Archive**: `claude-session-{uuid}.tar.gz` - The full session JSONL file
- **Metadata**: `claude-session-metadata-{uuid}.json` - Session info (ID, branch, timestamp)

The releases are marked as **draft** so they don't clutter your public releases.

## Environment Variables

When a session is restored in GitHub Actions:

- `SESSION_ID`: The UUID of the restored session (available for subsequent steps)
- `SESSION_RESTORED`: Set to `true` if a session was successfully restored

## Security Considerations

1. **Session files contain conversation history** - Keep your repository private if discussing sensitive information
2. **Local filesystem paths are included** - Session metadata includes your local `cwd` path
3. **Credentials in sessions** - If you've discussed API keys or secrets, they may be in session history
4. **GitHub Release visibility** - Draft releases are hidden from the public but visible to repo members

## Requirements

- Bash shell
- `gh` CLI tool (GitHub's command-line tool)
- Git
- Claude Code CLI (`claude` command)

Install `gh`:
```bash
# macOS
brew install gh

# Linux (apt)
sudo apt install gh

# Or from https://github.com/cli/cli
```

## Troubleshooting

### "No sessions found for branch"
- Make sure you've run `claude` commands on this branch locally
- Check that sessions exist: `ls ~/.claude/projects/`

### GitHub Release upload fails
- Make sure your `gh` CLI is authenticated: `gh auth status`
- Check your GitHub token has appropriate permissions

### Session not restored in Actions
- Verify the release tag matches the branch: `gh release list`
- Check that the archive was uploaded: `gh release view claude-sessions-main`

## Advanced Usage

### List all sessions for a branch
```bash
gh release view claude-sessions-main --json assets --jq '.assets'
```

### Delete a session from GitHub
```bash
gh release delete claude-sessions-main
```

### Manually download a session
```bash
gh release download claude-sessions-main --pattern "*.tar.gz"
tar -xzf claude-session-*.tar.gz
```

## Best Practices

1. **Sync regularly**: Run `./scripts/claude-session-sync.sh` before pushing code
2. **One session per branch**: Each branch maintains its own separate session
3. **Use meaningful prompts**: When dispatching from GitHub, be clear about what you want
4. **Clean up old releases**: Delete old session releases after they're no longer needed
5. **Review conversation context**: Check `~/.claude/projects/` locally to see conversation history
