#!/bin/bash
# pacman tests: run inside an Arch container after fixtures.sh.
# Needs HTTP_BASE pointing at the web root fixtures.sh filled (served by tests/run.sh).

source "$(dirname "$0")/../lib.sh"
: "${HTTP_BASE:?set HTTP_BASE}"
export ROLLBACK_MGR_CACHYOS=1
export ROLLBACK_MGR_ALA_URL="$HTTP_BASE/ala"
export ROLLBACK_MGR_CACHYOS_ARCHIVE_URL="$HTTP_BASE/cachy"
# --ask=4 answers yes when pacman asks to remove a conflicting package (the DKMS swap)
export ROLLBACK_MGR_TXN_FLAGS="--noconfirm --ask=4"
export TERM=dumb

setup_shims
load_script

STACK="nvidia-utils opencl-nvidia lib32-nvidia-utils nvidia-settings libxnvctrl linux-fake linux-fake-headers linux-fake-nvidia-open"
ver() { pacman -Q "$1" 2>/dev/null | awk '{print $2}'; }
ignored() { pacman-conf IgnorePkg | tr ' ' '\n' | sed '/^$/d' | sort | tr '\n' ' '; }
sorted() { tr ' ' '\n' <<< "$*" | sed '/^$/d' | sort | tr '\n' ' '; }
fresh_run() { rm -rf "${RM_TMPDIR:?}"/*; }
reset_stack() {
    cp /etc/pacman.conf.pristine /etc/pacman.conf
    : > "$HOLD_FILE"
    local p
    for p in nvidia-open-dkms dkms; do
        if pacman -Q "$p" &>/dev/null; then pacman -Rdd --noconfirm "$p" >/dev/null; fi
    done
    # shellcheck disable=SC2086
    pacman -S --noconfirm --needed $STACK solo >/dev/null 2>&1
    rm -f /var/cache/pacman/pkg/linux-fake*6.10.1-1*
    fresh_run
}
rm -f "$SHIM_DIR/flatpak"

# ---------------------------------------------------------------------------
t "linked set detection (read-only report)"
out=$("$REPO_DIR/rollback-mgr" linked pacman nvidia-utils 2>&1)
contains "opencl-nvidia shares the package base" "$out" "opencl-nvidia           570.1-1   same package base as nvidia-utils"
contains "lib32 copy is linked" "$out" "lib32-nvidia-utils      570.1-1   32-bit counterpart of nvidia-utils"
contains "prebuilt module is linked by its exact pin" "$out" "linux-fake-nvidia-open  6.11.1-1  needs the exact version of nvidia-utils"
contains "kernel comes with its module" "$out" "linux-fake              6.11.1-1  same package base as linux-fake-nvidia-open"
contains "kernel headers come with the kernel" "$out" "linux-fake-headers"
contains "nvidia-settings follows the driver" "$out" "nvidia-settings         570.1-1   same version as nvidia-utils and depends on it"
contains "libxnvctrl comes with nvidia-settings" "$out" "libxnvctrl              570.1-1   same package base as nvidia-settings"
lacks "plain dependencies (glibc) stay out" "$out" "glibc"
lacks "soname dependencies (curl) stay out" "$out" "curl"
lacks "unrelated packages stay out" "$out" "solo"
contains "restore point from history is offered" "$out" "1. Before"
contains "restore point shows the old driver" "$out" "nvidia-utils 560.1-1"
lacks "points from before the stack existed are hidden" "$out" "(not installed), lib32-nvidia-utils (not installed)"
out=$("$REPO_DIR/rollback-mgr" linked pacman solo 2>&1)
contains "a package with nothing linked says so" "$out" "solo 2.0-1 has no linked packages"
out=$("$REPO_DIR/rollback-mgr" linked pacman not-installed-pkg 2>&1); rc=$?
eq "missing package exits non-zero" 1 "$rc"

# ---------------------------------------------------------------------------
t "finding older versions (cache, repo, CachyOS archive, CachyOS NVIDIA archive, Arch archive)"
fresh_run
out=$(pacman_find_versions nvidia-utils)
eq "nvidia-utils versions, newest first" "570.1-1 560.1-1 555.1-1 550.1-1" "$(cut -f1 <<< "$out" | tr '\n' ' ' | sed 's/ $//')"
contains "560 comes from the package cache" "$out" $'560.1-1\t/var/cache/pacman/pkg/nvidia-utils-560.1-1-x86_64.pkg.tar.zst\tpackage cache'
contains "555 comes from the CachyOS NVIDIA archive" "$out" $'555.1-1\t'"$HTTP_BASE/cachy/nvidia/555/nvidia-utils-555.1-1-x86_64.pkg.tar.zst"$'\tCachyOS NVIDIA archive'
contains "550 comes from the Arch archive" "$out" "Arch archive"
lacks "wrong-architecture cache file is ignored" "$out" "540.1-1"
lacks "partial downloads are ignored" "$out" "530.1-1"
lacks "signature files are ignored" "$out" ".sig"
out=$(pacman_find_versions linux-fake)
eq "kernel versions (x86_64_v3 build from the CachyOS archive, aarch64 ignored)" "6.11.1-1 6.10.1-1" "$(cut -f1 <<< "$out" | tr '\n' ' ' | sed 's/ $//')"
contains "kernel 6.10 is the v3 build" "$out" "cachyos-v3/linux-fake-6.10.1-1-x86_64_v3.pkg.tar.zst"
out=$(pacman_find_versions fakepoch)
eq "epoch versions sort correctly (%3A in the archive link)" "1:3.0-1 1:2.0-1 0.9-1" "$(cut -f1 <<< "$out" | tr '\n' ' ' | sed 's/ $//')"
contains "epoch link keeps its encoding" "$out" "fakepoch-1%3A2.0-1-x86_64.pkg.tar.zst"
eq "info from a remote package (only its header is read)" "depend nvidia-utils=550.1" "$(pacman_pkginfo "$HTTP_BASE/ala/l/lib32-nvidia-utils/lib32-nvidia-utils-550.1-1-x86_64.pkg.tar.zst" | grep '^depend')"

# ---------------------------------------------------------------------------
t "IgnorePkg editing (the lib32-nvidia-utils / nvidia-utils hold bug)"
cp /etc/pacman.conf /tmp/conf.bak
pacman_ignore_edit add lib32-nvidia-utils
pacman_ignore_edit add nvidia-utils
eq "holding nvidia-utils after lib32-nvidia-utils holds both" "lib32-nvidia-utils nvidia-utils " "$(ignored)"
check "the hold sits under the commented example line" grep -qx 'IgnorePkg   = lib32-nvidia-utils nvidia-utils' /etc/pacman.conf
check "the commented example line is kept" grep -qx '#IgnorePkg   =' /etc/pacman.conf
pacman_ignore_edit add nvidia-utils
eq "holding twice adds nothing" "lib32-nvidia-utils nvidia-utils " "$(ignored)"
pacman_ignore_edit remove nvidia-utils
eq "unholding nvidia-utils leaves lib32-nvidia-utils whole" "lib32-nvidia-utils " "$(ignored)"
pacman_ignore_edit remove lib32-nvidia-utils
eq "unholding the last one leaves an empty list" "" "$(ignored)"
check "pacman still reads the config" pacman-conf IgnorePkg
check "pacman sync still works with the empty list" pacman -Sl fakerepo
# an existing active line with other packages on it
sed -i 's/^IgnorePkg .*/IgnorePkg = foo nvidia-utils-beta/' /etc/pacman.conf
pacman_ignore_edit add bar
check "adds to the existing line" grep -qx 'IgnorePkg = foo nvidia-utils-beta bar' /etc/pacman.conf
pacman_ignore_edit remove nvidia-utils
eq "removing a name that is a prefix of another touches nothing" "bar foo nvidia-utils-beta " "$(ignored)"
pacman_ignore_edit remove foo
eq "removing one name keeps the rest" "bar nvidia-utils-beta " "$(ignored)"
# the old code, for comparison
cp /tmp/conf.bak /etc/pacman.conf
sed -i "/^\[options\]/a IgnorePkg = lib32-nvidia-utils nvidia-utils" /etc/pacman.conf
pkg=nvidia-utils; bash -c "sed -i 's/[[:space:]]*\b$pkg\b//g' /etc/pacman.conf"
eq "(old code turned lib32-nvidia-utils into lib32-)" "lib32- " "$(ignored)"
cp /tmp/conf.bak /etc/pacman.conf

# ---------------------------------------------------------------------------
t "roll back NVIDIA 570 -> 560: the prebuilt module needs an older kernel too"
reset_stack
cat > "$SHIM_DIR/flatpak" <<'EOF'
#!/bin/bash
echo "$*" >> "$(dirname "$0")/flatpak-log"
case "$1 $2" in
    "list --runtime") printf '%s\n' org.freedesktop.Platform.GL.default org.freedesktop.Platform.GL.nvidia-570-1 org.freedesktop.Platform.GL32.nvidia-570-1 ;;
esac
exit 0
EOF
chmod +x "$SHIM_DIR/flatpak"; : > "$SHIM_DIR/flatpak-log"
fzf_picks '^pacman$' '^nvidia-utils$' 'Choose a version' '^560\.1-1'
# answers: set? / apply? / flatpak GL? / hold all? / days / enter
out=$(downgrade_wizard 2>&1 <<< $'y\ny\ny\ny\n3\n')
keep_out pick-560 "$out"
contains "asks to roll the set back together" "$out" "linked to 7 other package(s)"
contains "plan downgrades the driver from the cache" "$out" "nvidia-utils            570.1-1 -> 560.1-1    package cache"
contains "plan downgrades the kernel from the CachyOS archive" "$out" "linux-fake              6.11.1-1 -> 6.10.1-1  CachyOS archive"
for p in nvidia-utils opencl-nvidia lib32-nvidia-utils nvidia-settings libxnvctrl; do eq "$p is now 560.1-1" "560.1-1" "$(ver $p)"; done
for p in linux-fake linux-fake-headers linux-fake-nvidia-open; do eq "$p is now 6.10.1-1" "6.10.1-1" "$(ver $p)"; done
check "pacman reports nothing broken" pacman -Dk
contains "offers the matching flatpak GL extension" "$out" "org.freedesktop.Platform.GL.nvidia-560-1"
contains "reminds to restart" "$out" "Restart your computer when you're ready"
check "installs both GL extensions" grep -qx 'install -y flathub org.freedesktop.Platform.GL.nvidia-560-1 org.freedesktop.Platform.GL32.nvidia-560-1' "$SHIM_DIR/flatpak-log"
eq "the whole set is held in pacman.conf" "$(sorted $STACK)" "$(ignored)"
eq "the hold file groups all 8 under the nvidia-utils set" 8 "$(grep -c '|pacman|[0-9]*|nvidia-utils$' "$HOLD_FILE")"
rm -f "$SHIM_DIR/flatpak"

# ---------------------------------------------------------------------------
t "expired set hold: one expiry unholds and updates the whole set"
add_hold_entry solo pacman 30 >/dev/null
sed -i 's/^opencl-nvidia|pacman|[0-9]*|/opencl-nvidia|pacman|1|/' "$HOLD_FILE"
cat > "$SHIM_DIR/zenity" <<'EOF'
#!/bin/bash
d=$(dirname "$0"); echo "$*" >> "$d/zenity-log"
case " $* " in
    *" --question "*) c=$(head -n1 "$d/zenity-answers"); sed -i '1d' "$d/zenity-answers"; exit "${c:-1}" ;;
    *" --entry "*) echo "${ZENITY_ENTRY:-}"; exit 0 ;;
esac
EOF
printf '#!/bin/bash\n[ "$1" = --help ] && { echo "Usage: notify-send [OPTION...] <SUMMARY> [BODY]"; exit 0; }\necho "$*" >> "$(dirname "$0")/notify-log"\n' > "$SHIM_DIR/notify-send"
# the update runs in a terminal; this one answers pacman's prompts with "y"
printf '#!/bin/bash\nshift\necho "$*" >> "$(dirname "$0")/term-log"\nyes | "$@"\n' > "$SHIM_DIR/x-terminal-emulator"
chmod +x "$SHIM_DIR/zenity" "$SHIM_DIR/notify-send" "$SHIM_DIR/x-terminal-emulator"
: > "$SHIM_DIR/zenity-log"; : > "$SHIM_DIR/term-log"
printf '0\n0\n' > "$SHIM_DIR/zenity-answers"   # review now / unhold & update
check_holds >/dev/null 2>&1
eq "one prompt for the whole set" 1 "$(grep -c -- '--title=Hold Expired' "$SHIM_DIR/zenity-log")"
check "the prompt names the set and its packages" grep -q 'Hold for the nvidia-utils set (pacman) has ended: .*linux-fake-nvidia-open' "$SHIM_DIR/zenity-log"
for p in nvidia-utils lib32-nvidia-utils nvidia-settings; do eq "$p updated to 570.1-1" "570.1-1" "$(ver $p)"; done
for p in linux-fake linux-fake-nvidia-open; do eq "$p updated to 6.11.1-1" "6.11.1-1" "$(ver $p)"; done
eq "only the unrelated hold is left in pacman.conf" "solo " "$(ignored)"
eq "only the unrelated hold is left in the hold file" "solo" "$(cut -d'|' -f1 "$HOLD_FILE" | tr '\n' ' ' | sed 's/ $//')"

# ---------------------------------------------------------------------------
t "expired set hold: 'Hold longer' extends every package in the set"
fresh_run
fzf_picks '^pacman$' '^nvidia-utils$'
create_hold_wizard >/dev/null 2>&1 <<< $'y\n7\n'
eq "create hold: whole set held" "$(sorted $STACK solo)" "$(ignored)"
sed -i 's/^libxnvctrl|pacman|[0-9]*|/libxnvctrl|pacman|1|/' "$HOLD_FILE"
printf '0\n1\n' > "$SHIM_DIR/zenity-answers"   # review now / hold longer
: > "$SHIM_DIR/term-log"
ZENITY_ENTRY=5 check_holds >/dev/null 2>&1
now=$(date +%s)
eq "all 8 holds now end in about 5 days" 8 "$(awk -F'|' -v lo=$((now + 4*86400)) -v hi=$((now + 6*86400)) '$4 == "nvidia-utils" && $3 > lo && $3 < hi' "$HOLD_FILE" | wc -l)"
eq "the set packages stay held" "$(sorted $STACK solo)" "$(ignored)"
eq "no update was started" "" "$(cat "$SHIM_DIR/term-log")"
printf '1\n' > "$SHIM_DIR/zenity-answers"       # "Later"
sed -i 's/^libxnvctrl|pacman|[0-9]*|/libxnvctrl|pacman|1|/' "$HOLD_FILE"; before=$(sort "$HOLD_FILE")
check_holds >/dev/null 2>&1
eq "'Later' leaves the hold file as it was" "$before" "$(sort "$HOLD_FILE")"

# ---------------------------------------------------------------------------
t "cancel and failure leave every hold in place"
reset_stack
fzf_picks '^pacman$' '^nvidia-utils$'
create_hold_wizard >/dev/null 2>&1 <<< $'y\n7\n'
held_before=$(ignored); file_before=$(cat "$HOLD_FILE")
fzf_picks '^pacman$' '^nvidia-utils$' 'Choose a version' '^560\.1-1'
out=$(downgrade_wizard 2>&1 <<< $'y\nn\n\n')
contains "says it was cancelled" "$out" "Downgrade cancelled or failed."
contains "says the holds are still in place" "$out" "Hold on linux-fake-nvidia-open (pacman) is still in place."
eq "nothing was installed" "570.1-1" "$(ver nvidia-utils)"
eq "pacman.conf holds unchanged" "$held_before" "$(ignored)"
eq "hold file unchanged" "$file_before" "$(cat "$HOLD_FILE")"
fresh_run
fzf_picks '^pacman$' '^nvidia-utils$' 'Choose a version' '^560\.1-1'
out=$(downgrade_wizard 2>&1 <<< $'o\n\n')
keep_out only-this "$out"
contains "only-this-package warns first" "$out" "Rolling back only nvidia-utils"
contains "pacman's dry run refuses the lone downgrade" "$out" "pacman would refuse this change, so nothing was changed"
contains "and says why" "$out" "nvidia-utils=570.1-1"
eq "still nothing installed" "570.1-1" "$(ver nvidia-utils)"
eq "pacman.conf holds still unchanged" "$held_before" "$(ignored)"
eq "hold file still unchanged" "$file_before" "$(cat "$HOLD_FILE")"

# ---------------------------------------------------------------------------
t "restore the set to an earlier state from pacman history"
reset_stack
fzf_picks '^pacman$' '^nvidia-utils$' 'Restore the set' 'nvidia-utils 560\.1-1'
out=$(downgrade_wizard 2>&1 <<< $'y\ny\nn\n\n')
for p in nvidia-utils opencl-nvidia lib32-nvidia-utils nvidia-settings libxnvctrl; do eq "$p restored to 560.1-1" "560.1-1" "$(ver $p)"; done
for p in linux-fake linux-fake-headers linux-fake-nvidia-open; do eq "$p restored to 6.10.1-1" "6.10.1-1" "$(ver $p)"; done
keep_out restore "$out"
contains "the kernel came from the CachyOS archive" "$out" "CachyOS archive"
eq "no holds when the user says no" "" "$(ignored)"

# ---------------------------------------------------------------------------
t "roll back to 550: no prebuilt module exists, so swap to the DKMS module"
reset_stack
fzf_picks '^pacman$' '^nvidia-utils$' 'Choose a version' '^550\.1-1'
# answers: set? / replace with DKMS? / apply? / hold all? / days / enter
out=$(downgrade_wizard 2>&1 <<< $'y\ny\ny\ny\n0\n')
keep_out dkms-550 "$out"
contains "explains the swap" "$out" "No prebuilt linux-fake-nvidia-open was found that matches NVIDIA 550.1 and your kernel."
contains "plan removes the prebuilt module" "$out" "6.11.1-1 -> removed"
contains "plan adds dkms" "$out" "dkms"
eq "nvidia-utils is 550.1-1" "550.1-1" "$(ver nvidia-utils)"
eq "lib32-nvidia-utils is 550.1-1 (from the Arch archive)" "550.1-1" "$(ver lib32-nvidia-utils)"
eq "nvidia-open-dkms 550.1-1 installed" "550.1-1" "$(ver nvidia-open-dkms)"
eq "dkms installed" "3.1-1" "$(ver dkms)"
eq "prebuilt module removed" "" "$(ver linux-fake-nvidia-open)"
eq "kernel left alone" "6.11.1-1" "$(ver linux-fake)"
check "pacman reports nothing broken" pacman -Dk
check "the DKMS module is held with the set" grep -q '^nvidia-open-dkms|pacman|0|nvidia-utils$' "$HOLD_FILE"
lacks "the removed module is not held" "$(ignored)" "linux-fake-nvidia-open"

# ---------------------------------------------------------------------------
t "a package with nothing linked rolls back on its own"
reset_stack
add_hold_entry solo pacman 30 >/dev/null
solo_hold=$(grep '^solo|' "$HOLD_FILE")
fzf_picks '^pacman$' '^solo$' 'Choose a version' '^1\.0-1'
# answers: apply? / place hold? (no) / enter
out=$(downgrade_wizard 2>&1 <<< $'y\nn\n\n')
lacks "no set prompt" "$out" "is linked to"
contains "plan has just solo" "$out" "solo  2.0-1 -> 1.0-1  package cache"
lacks "no restart reminder for an ordinary package" "$out" "Restart your computer"
eq "the hold entry is untouched" "$solo_hold" "$(grep '^solo|' "$HOLD_FILE")"
eq "solo is 1.0-1" "1.0-1" "$(ver solo)"
eq "its existing hold stays" "solo " "$(ignored)"

# ---------------------------------------------------------------------------
t "command line"
out=$("$REPO_DIR/rollback-mgr" --help 2>&1); rc=$?
eq "--help exits 0" 0 "$rc"; contains "--help shows the linked command" "$out" "rollback-mgr linked <manager> <package>"
"$REPO_DIR/rollback-mgr" --bogus >/dev/null 2>&1; eq "unknown option exits 1" 1 "$?"
"$REPO_DIR/rollback-mgr" linked pacman >/dev/null 2>&1; eq "linked with a missing argument exits 1" 1 "$?"
printf '#!/bin/bash\necho "$*" >> "$(dirname "$0")/systemctl-log"\n' > "$SHIM_DIR/systemctl"; chmod +x "$SHIM_DIR/systemctl"
fzf_picks '4\. Exit'
HOME=$(mktemp -d) "$REPO_DIR/rollback-mgr" >/dev/null 2>&1 < /dev/null; eq "main menu opens and exits cleanly" 0 "$?"
check "the daily timer is enabled on first run" grep -q 'enable --now rollback-mgr.timer' "$SHIM_DIR/systemctl-log"

summary "pacman"
