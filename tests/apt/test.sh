#!/bin/bash
# APT tests with real Ubuntu 24.04 packages (needs archive.ubuntu.com).
#  - curl + libcurl4t64 (amd64 and i386): one source, exact "=" pins, a Multi-Arch copy,
#    and two versions (noble and noble-updates), so the set can really be rolled back.
#  - NVIDIA 535 userspace (amd64 + i386): set detection on the real driver packages.

source "$(dirname "$0")/../lib.sh"
export TERM=dumb DEBIAN_FRONTEND=noninteractive

dpkg --add-architecture i386
apt-get update -qq >/dev/null 2>&1
apt-get install -y -qq --no-install-recommends curl libcurl4t64:i386 >/dev/null 2>&1
REL=$(apt-cache madison curl | awk '$6 ~ /^noble\// {print $3; exit}')
NEW=$(dpkg-query -W -f='${Version}' curl)
NV=535.171.04-0ubuntu2
apt-get install -y -qq --no-install-recommends "nvidia-utils-535=$NV" "libnvidia-compute-535=$NV" "libnvidia-decode-535=$NV" \
    "libnvidia-gl-535=$NV" "libnvidia-gl-535:i386=$NV" "libnvidia-common-535=$NV" "libnvidia-compute-535:i386=$NV" >/dev/null 2>&1
echo "curl: installed $NEW, release $REL; nvidia-utils-535 $(dpkg-query -W -f='${Version}' nvidia-utils-535 2>/dev/null)"

setup_shims
load_script
fresh_run() { rm -rf "${RM_TMPDIR:?}"/*; }
dver() { dpkg-query -W -f='${Version}' "$1" 2>/dev/null; }
holds() { apt-mark showhold | sort | tr '\n' ' '; }

# ---------------------------------------------------------------------------
t "linked set detection"
out=$("$REPO_DIR/rollback-mgr" linked apt curl 2>&1)
contains "libcurl4t64 comes from the same source" "$out" "libcurl4t64:amd64  $NEW  built from the same source as curl"
contains "the i386 copy is linked" "$out" "libcurl4t64:i386"
lacks "libc6 stays out" "$out" "libc6"
out=$("$REPO_DIR/rollback-mgr" linked apt nvidia-utils-535 2>&1)
keep_out apt-linked-nvidia "$out"
contains "NVIDIA compute libs are linked" "$out" "libnvidia-compute-535:amd64"
contains "NVIDIA decode libs are linked" "$out" "libnvidia-decode-535"
contains "32-bit GL libs are linked" "$out" "libnvidia-gl-535:i386"
contains "arch-independent common files are linked" "$out" "libnvidia-common-535"
lacks "libc6 stays out of the NVIDIA set" "$out" "libc6"
lacks "curl stays out of the NVIDIA set" "$out" "curl"

# ---------------------------------------------------------------------------
t "hold the whole set"
fzf_picks '^apt$' '^curl$'
create_hold_wizard >/dev/null 2>&1 <<< $'y\n7\n'
eq "apt holds all three" "curl libcurl4t64 libcurl4t64:i386 " "$(holds)"
eq "hold file groups them under curl" 3 "$(grep -c '|apt|[0-9]*|curl$' "$HOLD_FILE")"

# ---------------------------------------------------------------------------
t "cancel leaves everything as it was"
fzf_picks '^apt$' '^curl$' "^${REL//./\\.}( |$)"
out=$(downgrade_wizard 2>&1 <<< $'y\nn\n\n')
contains "plan lists the i386 copy" "$out" "libcurl4t64:i386"
eq "curl unchanged" "$NEW" "$(dver curl)"
eq "holds unchanged" "curl libcurl4t64 libcurl4t64:i386 " "$(holds)"

# ---------------------------------------------------------------------------
t "roll the set back in one transaction"
fresh_run
fzf_picks '^apt$' '^curl$' "^${REL//./\\.}( |$)"
out=$(downgrade_wizard 2>&1 <<< $'y\ny\ny\n2\n\n')
keep_out apt-downgrade "$out"
eq "curl is the release version" "$REL" "$(dver curl)"
eq "libcurl4t64:amd64 matches" "$REL" "$(dver libcurl4t64:amd64)"
eq "libcurl4t64:i386 matches" "$REL" "$(dver libcurl4t64:i386)"
eq "holds still in place" "curl libcurl4t64 libcurl4t64:i386 " "$(holds)"
check "apt reports nothing broken" apt-get check -qq

# ---------------------------------------------------------------------------
t "expired set hold: unhold and update together"
sed -i 's/^libcurl4t64:i386|apt|[0-9]*|/libcurl4t64:i386|apt|1|/' "$HOLD_FILE"
cat > "$SHIM_DIR/zenity" <<'EOF'
#!/bin/bash
d=$(dirname "$0"); echo "$*" >> "$d/zenity-log"
case " $* " in *" --question "*) exit 0 ;; esac
EOF
printf '#!/bin/bash\n[ "$1" = --help ] && exit 0\n' > "$SHIM_DIR/notify-send"
printf '#!/bin/bash\nshift\nyes | "$@"\n' > "$SHIM_DIR/x-terminal-emulator"
chmod +x "$SHIM_DIR/zenity" "$SHIM_DIR/notify-send" "$SHIM_DIR/x-terminal-emulator"
check_holds >/dev/null 2>&1
eq "one prompt for the set" 1 "$(grep -c -- '--title=Hold Expired' "$SHIM_DIR/zenity-log")"
eq "curl updated" "$NEW" "$(dver curl)"
eq "libcurl4t64:amd64 updated" "$NEW" "$(dver libcurl4t64:amd64)"
eq "libcurl4t64:i386 updated" "$NEW" "$(dver libcurl4t64:i386)"
eq "no holds left" "" "$(holds)"
eq "hold file empty" "" "$(cat "$HOLD_FILE")"

summary "apt"
