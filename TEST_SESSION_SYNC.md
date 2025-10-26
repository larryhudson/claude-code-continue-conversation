# Testing Claude Code Session Synchronization

Complete end-to-end test of local session → GitHub sync → GitHub Actions continuation.

## Setup

Make sure you have the scripts in your repo:
```bash
ls -la scripts/claude-session-*.sh
```

You should see:
- `claude-session-discovery.sh`
- `claude-session-sync.sh`
- `claude-session-restore.sh`

## Step-by-Step Test

### Step 1: Create a new test branch

```bash
git checkout -b test/claude-session-sync
git push -u origin test/claude-session-sync
```

### Step 2: Start a conversation with Claude locally

This will create a new session tied to this branch and directory.

```bash
claude "Analyze this repository and suggest one improvement we could make"
```

Follow the conversation - Claude will ask questions and you can provide answers. Build up some context. For example:
- Ask it to explain the project structure
- Ask it to review the session sync scripts
- Ask it to suggest a feature

The key is to create enough conversation history that you'll notice it continuing in step 5.

Exit when ready (Ctrl+C or use `/exit` in the REPL).

### Step 3: Verify the session was created locally

List all your sessions to confirm one was created for this branch:

```bash
ls ~/.claude/projects/-home-larry-github-com-larryhudson-claude-code-continue-conversation/
```

You should see several `.jsonl` files (session files). The most recent one is your new session.

Get the session ID:
```bash
QUIET=1 ./scripts/claude-session-discovery.sh test/claude-session-sync
```

This should output a UUID. Keep note of it.

### Step 4: Sync the session to GitHub

```bash
./scripts/claude-session-sync.sh test/claude-session-sync
```

You should see:
```
✓ Found session: {SESSION_ID}
✓ Created session archive: claude-session-{SESSION_ID}.tar.gz
✓ Created metadata: claude-session-metadata-{SESSION_ID}.json
✓ Session uploaded to GitHub!
Release: claude-sessions-test/claude-session-sync
```

Verify it was uploaded:
```bash
gh release view claude-sessions-test/claude-session-sync
```

### Step 5: Push your branch to GitHub

```bash
git push origin test/claude-session-sync
```

Or if already pushed:
```bash
git push
```

### Step 6: Run the GitHub Actions workflow

1. Go to your repository on GitHub
2. Click **Actions** tab
3. Select **Claude Code - Continue Session** from the left sidebar
4. Click **Run workflow**
5. Fill in:
   - **prompt**: Something specific, like "Based on our previous conversation, what's the first step we should implement?"
   - **branch**: `test/claude-session-sync`
6. Click **Run workflow** (green button)

### Step 7: Watch the workflow run

1. Click on the workflow run that just started
2. Click on the **continue-session** job
3. Watch the steps execute:
   - "Restore Claude Code session" - should find and restore your session
   - "Run Claude Code (Continue Session)" - should run with `--resume {SESSION_ID}`
   - "Upload updated session" - syncs the updated session back to GitHub

### Step 8: Verify it continued the conversation

In the workflow logs, look for the "Run Claude Code (Continue Session)" step and expand it. You should see:

1. Claude acknowledges the previous conversation context
2. Claude responds to your new prompt using information from the previous conversation
3. The response shows it "remembered" what was discussed before

The output will show something like:
```
Running claude --resume d90b667f-c706-42da-9a70-bfd30dc5eefb -p "Based on..."
```

And Claude's response will reference the previous conversation.

### Step 9: Verify the session was updated on GitHub

```bash
gh release view claude-sessions-test/claude-session-sync --json updatedAt
```

The timestamp should be more recent than before (from when the workflow ran).

## Success Criteria

Your test is successful if:

✓ Local session was created with `claude` command
✓ `claude-session-discovery.sh` found the session ID
✓ `claude-session-sync.sh` uploaded to GitHub
✓ GitHub workflow restored the session
✓ Claude's response in the workflow referenced the previous conversation
✓ Updated session was synced back to GitHub

## Cleanup (Optional)

To delete the test branch and release when done:

```bash
# Delete local branch
git branch -D test/claude-session-sync

# Delete remote branch
git push origin --delete test/claude-session-sync

# Delete GitHub release
gh release delete claude-sessions-test/claude-session-sync
```

## Troubleshooting

### "No sessions found for branch" in restore step

**Problem**: The session discovery script couldn't find a session.

**Solution**:
1. Make sure you ran `claude` on the `test/claude-session-sync` branch
2. Check the session exists locally:
   ```bash
   git checkout test/claude-session-sync
   QUIET=1 ./scripts/claude-session-discovery.sh test/claude-session-sync
   ```
3. Make sure you synced it:
   ```bash
   ./scripts/claude-session-sync.sh test/claude-session-sync
   ```

### GitHub release not found

**Problem**: "No session found for branch. Starting fresh."

**Solution**:
1. Verify the release exists:
   ```bash
   gh release list | grep claude-sessions
   ```
2. Check the exact tag:
   ```bash
   gh release view claude-sessions-test/claude-session-sync
   ```
3. Make sure you pushed the branch after syncing:
   ```bash
   git push
   ```

### Claude doesn't seem to continue the conversation

**Problem**: Claude's response doesn't reference the previous conversation.

**Solution**:
1. Check the workflow logs - look for `SESSION_ID=` being set
2. If `SESSION_RESTORED=false`, the session wasn't found
3. Manually verify you synced and pushed:
   ```bash
   gh release view claude-sessions-test/claude-session-sync --json assets
   ```

### Workflow fails with "gh not found"

**Problem**: GitHub CLI not available in the action.

**Solution**: The scripts require `gh` CLI to be installed. The GitHub Actions environment should have it, but if not, add this step before the restore:

```yaml
- name: Install GitHub CLI
  run: sudo apt-get install -y gh
```

## What's Happening Behind the Scenes

1. **Local session** is stored in `~/.claude/projects/{encoded-path}/{uuid}.jsonl`
2. **Sync** compresses it and uploads to a GitHub Release
3. **Workflow restores** by downloading and extracting back to `~/.claude/projects/`
4. **Claude resumes** using `--resume {uuid}` flag
5. **New conversation** extends the JSONL file
6. **Upload back** syncs the extended session to GitHub

Each step maintains the full conversation history!
