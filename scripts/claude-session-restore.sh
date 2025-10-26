#!/bin/bash
# Claude Code Session Restore Script
# Downloads and restores a Claude Code session from GitHub Releases
# For use in GitHub Actions workflows

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
PROJECTS_DIR="$CLAUDE_DIR/projects"
GIT_BRANCH="${1:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'main')}"
TEMP_DIR="${TEMP_DIR:-/tmp}"

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

log_info "Claude Code Session Restore Script"
log_info "Branch: $GIT_BRANCH"

# Check for gh CLI
if ! command -v gh &> /dev/null; then
  log_error "GitHub CLI (gh) is not installed"
  exit 1
fi

# Try to download the session from GitHub release
RELEASE_TAG="claude-sessions-${GIT_BRANCH}"
log_info "Looking for release: $RELEASE_TAG"

# Check if release exists
if ! gh release view "$RELEASE_TAG" > /dev/null 2>&1; then
  log_warn "No session found for branch '$GIT_BRANCH'. Starting fresh."
  exit 0
fi

log_success "Found release: $RELEASE_TAG"

# Download the session archive
log_info "Downloading session archive..."
DOWNLOAD_DIR=$(mktemp -d)
gh release download "$RELEASE_TAG" \
  --pattern "claude-session-*.tar.gz" \
  --dir "$DOWNLOAD_DIR"

# Find the downloaded archive
SESSION_ARCHIVE=$(ls "$DOWNLOAD_DIR"/*.tar.gz 2>/dev/null | head -1)
if [[ -z "$SESSION_ARCHIVE" || ! -f "$SESSION_ARCHIVE" ]]; then
  log_error "Failed to download session archive"
  exit 1
fi

# Download metadata
log_info "Downloading metadata..."
gh release download "$RELEASE_TAG" \
  --pattern "*metadata*.json" \
  --dir "$DOWNLOAD_DIR"

METADATA_FILE=$(ls "$DOWNLOAD_DIR"/*.json 2>/dev/null | head -1)
if [[ -z "$METADATA_FILE" || ! -f "$METADATA_FILE" ]]; then
  METADATA_FILE=""
fi

# Extract metadata using jq if available, otherwise grep
SESSION_ID=""
if [[ -f "$METADATA_FILE" ]]; then
  log_info "Reading session metadata..."
  if command -v jq &> /dev/null; then
    SESSION_ID=$(jq -r '.sessionId' "$METADATA_FILE" 2>/dev/null || echo "")
    STORED_BRANCH=$(jq -r '.gitBranch' "$METADATA_FILE" 2>/dev/null || echo "")
  else
    # Fallback to grep if jq is not available
    SESSION_ID=$(grep '"sessionId"' "$METADATA_FILE" | grep -o '[a-f0-9\-]*' | tail -1)
    STORED_BRANCH=$(grep '"gitBranch"' "$METADATA_FILE" | cut -d'"' -f4)
  fi
  log_info "Session ID: $SESSION_ID"
  log_info "Stored branch: $STORED_BRANCH"
fi

# Create projects directory if it doesn't exist
mkdir -p "$PROJECTS_DIR"

# Extract the session archive
if [[ -f "$SESSION_ARCHIVE" ]]; then
  log_info "Extracting session to $PROJECTS_DIR..."
  tar -xzf "$SESSION_ARCHIVE" -C "$PROJECTS_DIR"
  log_success "Session restored!"
else
  log_error "Failed to download session archive"
  exit 1
fi

# Set environment variables for the workflow
if [[ -n "$SESSION_ID" ]]; then
  log_info "Setting environment variables for workflow..."
  if [[ -n "$GITHUB_ENV" ]]; then
    echo "SESSION_ID=$SESSION_ID" >> "$GITHUB_ENV"
    echo "SESSION_RESTORED=true" >> "$GITHUB_ENV"
    log_success "Environment variables set"
  fi
  log_info "To continue this session, use:"
  log_info "  claude -r \"$SESSION_ID\" -p \"Your prompt here\""
fi

# Cleanup
rm -rf "$DOWNLOAD_DIR"

exit 0
