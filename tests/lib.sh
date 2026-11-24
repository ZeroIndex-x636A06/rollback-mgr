#!/bin/bash
# Shared helpers for the rollback-mgr tests. Runs inside a throwaway container as root.

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(cd "$TESTS_DIR/.." && pwd)
PASS=0
FAIL=0
FAILED_NAMES=()

# --- shims for tools the interactive script expects ---
setup_shims() {
    SHIM_DIR=$(mktemp -d)
    export PATH="$SHIM_DIR:$PATH"
    export FZF_QUEUE="$SHIM_DIR/fzf-queue" FZF_LOG="$SHIM_DIR/fzf-log"
    : > "$FZF_QUEUE"; : > "$FZF_LOG"

    # fzf: pick the first menu line matching the next regex in the queue
    cat > "$SHIM_DIR/fzf" <<'EOF'
#!/bin/bash
menu=$(cat)
{ echo "=== fzf $*"; echo "$menu"; } >> "$FZF_LOG"
pick=$(head -n1 "$FZF_QUEUE"); sed -i '1d' "$FZF_QUEUE"
if [ -z "$pick" ]; then echo "fzf shim: queue empty" >&2; exit 130; fi
if [ "$pick" = "__ESC__" ]; then exit 130; fi
line=$(grep -E -m1 -- "$pick" <<< "$menu")
if [ -z "$line" ]; then echo "fzf shim: nothing matches /$pick/ in:" >&2; echo "$menu" >&2; exit 1; fi
echo "$line"
EOF
    # sudo: we already run as root
    cat > "$SHIM_DIR/sudo" <<'EOF'
#!/bin/bash
[ "$1" = "-v" ] && exit 0
exec "$@"
EOF
    chmod +x "$SHIM_DIR/fzf" "$SHIM_DIR/sudo"
}

fzf_picks() { printf '%s\n' "$@" > "$FZF_QUEUE"; : > "$FZF_LOG"; }

# Load the script's functions without running its menu
load_script() {
    export HOME
    HOME=$(mktemp -d)
    # shellcheck source=/dev/null
    source "$REPO_DIR/rollback-mgr"
}

# --- assertions ---
CURRENT=""
t() { CURRENT=$1; echo ""; echo "### $1"; }
ok() { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad() { FAIL=$((FAIL + 1)); FAILED_NAMES+=("$CURRENT: $1"); echo "  FAIL: $1"; }
check() { # description command...
    local d=$1; shift
    if "$@"; then ok "$d"; else bad "$d"; fi
}
eq() { # description expected actual
    if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi
}
contains() { # description haystack needle
    if [[ "$2" == *"$3"* ]]; then ok "$1"; else bad "$1 (missing '$3')"; echo "$2" | sed 's/^/      | /' | head -n 40; fi
}
lacks() {
    if [[ "$2" != *"$3"* ]]; then ok "$1"; else bad "$1 (unexpected '$3')"; echo "$2" | sed 's/^/      | /' | head -n 40; fi
}

# Save a scenario's output for reading (OUT_DIR is set by run.sh)
keep_out() { [ -n "$OUT_DIR" ] && printf '%s\n' "$2" > "$OUT_DIR/$1.txt"; return 0; }

summary() {
    echo ""
    echo "=== $1: $PASS passed, $FAIL failed ==="
    for n in "${FAILED_NAMES[@]}"; do echo "  - $n"; done
    [ "$FAIL" -eq 0 ]
}
