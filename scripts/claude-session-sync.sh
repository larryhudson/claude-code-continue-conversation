#!/bin/bash
# Claude Code Session Sync Script
# Uploads the most recent local Claude Code session to GitHub Artifacts
# This allows GitHub Actions to continue the conversation

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISCOVERY_SCRIPT="$SCRIPT_DIR/claude-session-discovery.sh"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
PROJECTS_DIR="$CLAUDE_DIR/projects"
CURRENT_CWD="${PWD}"
GIT_BRANCH="${1:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')}"
TEMP_DIR="${TEMP_DIR:-.}"

# Helper functions
log_info() {
  echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
  echo -e "${GREEN}✓${NC} $1"
}

log_error() {
  echo -e "${RED}✗${NC} $1" >&2
}

log_warn() {
  echo -e "${YELLOW}⚠${NC} $1"
}

# Check requirements
if ! command -v gh &> /dev/null; then
  log_error "GitHub CLI (gh) is not installed. Please install it from https://cli.github.com/"
  exit 1
fi

if ! command -v gzip &> /dev/null; then
  log_error "gzip is not installed."
  exit 1
fi

if [[ ! -f "$DISCOVERY_SCRIPT" ]]; then
  log_error "Session discovery script not found: $DISCOVERY_SCRIPT"
  exit 1
fi

log_info "Starting Claude Code session sync..."
log_info "Branch: $GIT_BRANCH"
log_info "Repository: $(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || echo 'unknown')"

# Find the session ID using the discovery script
log_info "Finding latest session for this branch..."
SESSION_ID=$(QUIET=1 "$DISCOVERY_SCRIPT" "$GIT_BRANCH" 2>/dev/null) || {
  log_warn "No sessions found for branch '$GIT_BRANCH'. Skipping sync."
  exit 0
}

log_success "Found session: $SESSION_ID"

# Find the actual session file
SESSION_FILE=$(find "$PROJECTS_DIR" -name "${SESSION_ID}.jsonl" -type f | head -1)

if [[ ! -f "$SESSION_FILE" ]]; then
  log_error "Session file not found: $SESSION_FILE"
  exit 1
fi

# Create a compressed archive of the session
log_info "Compressing session file..."
SESSION_ARCHIVE="$TEMP_DIR/claude-session-${SESSION_ID}.tar.gz"
METADATA_FILE="$TEMP_DIR/claude-session-metadata-${SESSION_ID}.json"

# Archive the session file
tar -czf "$SESSION_ARCHIVE" -C "$(dirname "$SESSION_FILE")" "$(basename "$SESSION_FILE")"

# Create metadata file with session info
cat > "$METADATA_FILE" << EOF
{
  "sessionId": "$SESSION_ID",
  "gitBranch": "$GIT_BRANCH",
  "cwd": "$CURRENT_CWD",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "archivePath": "$(basename "$SESSION_ARCHIVE")"
}
EOF

log_success "Created session archive: $(basename "$SESSION_ARCHIVE")"
log_success "Created metadata: $(basename "$METADATA_FILE")"

# Upload to GitHub
log_info "Uploading to GitHub..."

if [[ -z "$GITHUB_TOKEN" && -z "$GITHUB_ACTIONS" ]]; then
  # Not in GitHub Actions and no token - check if gh is authenticated
  if ! gh auth status > /dev/null 2>&1; then
    log_error "Not authenticated with GitHub. Run 'gh auth login' or set GITHUB_TOKEN"
    exit 1
  fi
fi

log_info "Using gh CLI to create release..."

# Check if release already exists for this branch
RELEASE_TAG="claude-sessions-${GIT_BRANCH}"
if gh release view "$RELEASE_TAG" > /dev/null 2>&1; then
  log_info "Release $RELEASE_TAG already exists, updating..."
  # Delete old assets with same session ID
  gh release delete-asset "$RELEASE_TAG" "$(basename "$SESSION_ARCHIVE")" 2>/dev/null || true
  gh release delete-asset "$RELEASE_TAG" "$(basename "$METADATA_FILE")" 2>/dev/null || true
  # Upload new files
  gh release upload "$RELEASE_TAG" "$SESSION_ARCHIVE" "$METADATA_FILE" --clobber
else
  log_info "Creating new release $RELEASE_TAG..."
  gh release create "$RELEASE_TAG" "$SESSION_ARCHIVE" "$METADATA_FILE" \
    --title "Claude Session for $GIT_BRANCH" \
    --notes "Session ID: $SESSION_ID
Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Branch: $GIT_BRANCH" \
    --draft
fi

log_success "Session uploaded to GitHub!"
log_success "Release: $RELEASE_TAG"
log_info "Session ID: $SESSION_ID"
log_info "Archive: $SESSION_ARCHIVE"
log_info "Metadata: $METADATA_FILE"

exit 0
