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
log_info ""
log_info "Debug: GitHub authentication status:"
gh auth status 2>&1 | head -3
log_info ""
log_info "Debug: Available releases with 'claude-sessions':"
gh release list | grep -i claude-sessions || log_warn "  (none found with that pattern)"
log_info ""

# Check if release exists
log_info "Debug: Checking for release: $RELEASE_TAG"
if ! gh release view "$RELEASE_TAG" > /dev/null 2>&1; then
  log_warn "Release not found: $RELEASE_TAG"
  log_info "Debug: All releases:"
  gh release list
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

# Calculate the project-specific directory name based on current working directory
# Claude Code stores sessions in subdirectories named after the working directory path
# Example: /home/user/path/to/project -> -home-user-path-to-project
CURRENT_CWD="${PWD}"
PROJECT_DIR_NAME=$(echo "$CURRENT_CWD" | sed 's/^\//-/; s/\//-/g')
PROJECT_DIR="$PROJECTS_DIR/$PROJECT_DIR_NAME"

log_info "Project directory: $PROJECT_DIR"

# Create project-specific directory if it doesn't exist
mkdir -p "$PROJECT_DIR"

# Extract the session archive into the project-specific directory
if [[ -f "$SESSION_ARCHIVE" ]]; then
  log_info "Extracting session to $PROJECT_DIR..."
  tar -xzf "$SESSION_ARCHIVE" -C "$PROJECT_DIR"
  log_success "Session restored!"

  # Extract the stored cwd from metadata
  STORED_CWD=""
  if [[ -f "$METADATA_FILE" ]]; then
    if command -v jq &> /dev/null; then
      STORED_CWD=$(jq -r '.cwd' "$METADATA_FILE" 2>/dev/null || echo "")
    else
      # Fallback to grep if jq is not available
      STORED_CWD=$(grep '"cwd"' "$METADATA_FILE" | head -1 | cut -d'"' -f4)
    fi
  fi

  # Update cwd in the session file if stored_cwd differs from current cwd
  if [[ -n "$STORED_CWD" && "$STORED_CWD" != "$CURRENT_CWD" ]]; then
    log_info "Updating session cwd from: $STORED_CWD"
    log_info "                      to: $CURRENT_CWD"

    # Find the session file (should be the only .jsonl file)
    SESSION_FILE=$(find "$PROJECT_DIR" -name "*.jsonl" -type f | head -1)
    if [[ -f "$SESSION_FILE" ]]; then
      # Use sed to replace all occurrences of the old cwd with the new cwd
      # Escape special characters in the paths for sed
      ESCAPED_STORED=$(printf '%s\n' "$STORED_CWD" | sed -e 's/[\/&]/\\&/g')
      ESCAPED_CURRENT=$(printf '%s\n' "$CURRENT_CWD" | sed -e 's/[\/&]/\\&/g')

      sed -i "s/\"cwd\":\"$ESCAPED_STORED\"/\"cwd\":\"$ESCAPED_CURRENT\"/g" "$SESSION_FILE"
      log_success "Updated cwd in session file"
    else
      log_warn "Could not find session file to update cwd"
    fi
  fi
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
