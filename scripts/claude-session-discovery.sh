#!/bin/bash
# Claude Code Session Discovery Utility
# Finds the most recent Claude Code session for the current directory and git branch

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
CURRENT_CWD="${PWD}"
GIT_BRANCH="${1:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')}"
QUIET="${QUIET:-0}"

# Helper functions
log_info() {
  [[ "$QUIET" == "1" ]] && return
  echo -e "${BLUE}ℹ${NC} $1" >&2
}

log_success() {
  [[ "$QUIET" == "1" ]] && return
  echo -e "${GREEN}✓${NC} $1" >&2
}

log_error() {
  echo -e "${RED}✗${NC} $1" >&2
}

log_warn() {
  [[ "$QUIET" == "1" ]] && return
  echo -e "${YELLOW}⚠${NC} $1" >&2
}

# Validate inputs
if [[ -z "$GIT_BRANCH" ]]; then
  log_error "Could not determine git branch. Please provide it as an argument."
  echo "Usage: $0 [BRANCH_NAME]"
  exit 1
fi

if [[ ! -d "$PROJECTS_DIR" ]]; then
  log_error "Claude projects directory not found: $PROJECTS_DIR"
  exit 1
fi

log_info "Looking for sessions with:"
log_info "  cwd: $CURRENT_CWD"
log_info "  gitBranch: $GIT_BRANCH"

# Find all .jsonl session files and search for matching cwd + gitBranch
BEST_SESSION=""
BEST_MTIME=0

while IFS= read -r session_file; do
  # Extract cwd and gitBranch from the session file
  # These appear in the second line (first user message)
  cwd=$(grep -m1 '"cwd"' "$session_file" 2>/dev/null | grep -o '"cwd":"[^"]*' | cut -d'"' -f4 || echo "")
  branch=$(grep -m1 '"gitBranch"' "$session_file" 2>/dev/null | grep -o '"gitBranch":"[^"]*' | cut -d'"' -f4 || echo "")

  # Check if this session matches both cwd and branch
  if [[ "$cwd" == "$CURRENT_CWD" && "$branch" == "$GIT_BRANCH" ]]; then
    # Get modification time (most recent session is what we want)
    mtime=$(stat -c %Y "$session_file" 2>/dev/null || stat -f %m "$session_file" 2>/dev/null || echo 0)

    if (( mtime > BEST_MTIME )); then
      BEST_MTIME=$mtime
      BEST_SESSION="$session_file"
    fi
  fi
done < <(find "$PROJECTS_DIR" -name "*.jsonl" -type f 2>/dev/null)

if [[ -z "$BEST_SESSION" ]]; then
  log_warn "No sessions found for branch: $GIT_BRANCH"
  exit 1
fi

# Extract session ID from filename (basename without .jsonl)
SESSION_ID=$(basename "$BEST_SESSION" .jsonl)

# Output the session ID (main output for scripts to capture)
echo "$SESSION_ID"

log_success "Found session ID: $SESSION_ID"
log_info "Session file: $BEST_SESSION"
log_info "Session modified: $(date -d @"$BEST_MTIME" 2>/dev/null || date -r "$BEST_MTIME" 2>/dev/null || echo '(unknown)')"

exit 0
