#!/bin/bash
# DNF tests on Fedora with the fake NVIDIA RPMs from build-rpms.sh (mounted at /rpms).

source "$(dirname "$0")/../lib.sh"
export TERM=dumb

rm -f /etc/yum.repos.d/*.repo
# dnf5 also reads the Fedora repos from /usr/share/dnf5/repos.d; use only the fake one
printf '[main]\nreposdir=/etc/yum.repos.d\n' > /etc/dnf/dnf.conf
cat > /etc/yum.repos.d/fake.repo <<'EOF'
[fake]
name=fake
baseurl=file:///rpms
gpgcheck=0
EOF
dnf -q -y install xorg-x11-drv-nvidia-560.1 xorg-x11-drv-nvidia-libs-560.1-1.fc45.i686 kmod-nvidia-560.1 \
    xorg-x11-drv-nvidia-cuda-560.1 >/dev/null 2>&1
echo "installed: $(rpm -q xorg-x11-drv-nvidia kmod-nvidia | tr '\n' ' ')"

setup_shims
load_script
fresh_run() { rm -rf "${RM_TMPDIR:?}"/*; }
rv() { rpm -q --qf '%{EPOCH}:%{VERSION}-%{RELEASE}\n' "$1" 2>/dev/null | head -n1; }
# dnf5 lists "Package name: X"; dnf4 lists "X-epoch:version-release.*"
locks() { dnf versionlock list 2>/dev/null | awk '/^Package name: / {print $3; next} /^[a-z0-9]/ && !/ = / {sub(/-[0-9]+:.*/, ""); print}' | sort -u | tr '\n' ' '; }

# ---------------------------------------------------------------------------
t "linked set detection"
out=$("$REPO_DIR/rollback-mgr" linked dnf xorg-x11-drv-nvidia 2>&1)
keep_out dnf-linked "$out"
contains "libs come from the same source" "$out" "xorg-x11-drv-nvidia-libs.x86_64"
contains "the i686 libs are linked" "$out" "xorg-x11-drv-nvidia-libs.i686"
contains "kmodsrc comes from the same source" "$out" "xorg-x11-drv-nvidia-kmodsrc.x86_64"
contains "the prebuilt module is linked by its exact requirement" "$out" "kmod-nvidia.x86_64"
contains "cuda comes from the same source" "$out" "xorg-x11-drv-nvidia-cuda.x86_64"
lacks "glibc stays out" "$out" "glibc"

# ---------------------------------------------------------------------------
t "hold the set with versionlock, then roll it back 560 -> 550"
fzf_picks '^dnf$' '^xorg-x11-drv-nvidia\.x86_64'
create_hold_wizard >/dev/null 2>&1 <<< $'y\n7\n'
held=$(locks)
contains "versionlock holds the module" "$held" "kmod-nvidia"
contains "versionlock holds the libs" "$held" "xorg-x11-drv-nvidia-libs"
fzf_picks '^dnf$' '^xorg-x11-drv-nvidia\.x86_64' '^3:550\.1-1\.fc45|^550\.1-1\.fc45'
out=$(downgrade_wizard 2>&1 <<< $'y\ny\nn\n\n')
keep_out dnf-downgrade "$out"
for p in xorg-x11-drv-nvidia xorg-x11-drv-nvidia-libs.x86_64 xorg-x11-drv-nvidia-libs.i686 xorg-x11-drv-nvidia-kmodsrc xorg-x11-drv-nvidia-cuda kmod-nvidia; do
    eq "$p is 550.1" "3:550.1-1.fc45" "$(rv "$p")"
done
eq "the locks were put back" "$held" "$(locks)"
lockv=$(dnf versionlock list 2>/dev/null)
lacks "no lock is left on 560.1" "$lockv" "560.1"
contains "the locks now keep 550.1" "$lockv" "550.1-1.fc45"
check "rpm reports nothing broken" bash -c '! rpm -Va --nofiles --nodigest 2>&1 | grep -q .'

# ---------------------------------------------------------------------------
t "cancel changes nothing"
fresh_run
fzf_picks '^dnf$' '^xorg-x11-drv-nvidia\.x86_64' '560\.1-1\.fc45'
out=$(downgrade_wizard 2>&1 <<< $'y\nn\n\n')
eq "still 550.1" "3:550.1-1.fc45" "$(rv xorg-x11-drv-nvidia)"
eq "locks unchanged" "$held" "$(locks)"

# ---------------------------------------------------------------------------
t "expired set hold: unlock and update together"
sed -i 's/^\(kmod-nvidia\.x86_64|dnf|\)[0-9]*|/\11|/' "$HOLD_FILE"
cat > "$SHIM_DIR/zenity" <<'EOS'
#!/bin/bash
d=$(dirname "$0"); echo "$*" >> "$d/zenity-log"
case " $* " in *" --question "*) exit 0 ;; esac
EOS
printf '#!/bin/bash\n[ "$1" = --help ] && exit 0\n' > "$SHIM_DIR/notify-send"
printf '#!/bin/bash\nshift\nyes | "$@"\n' > "$SHIM_DIR/x-terminal-emulator"
chmod +x "$SHIM_DIR/zenity" "$SHIM_DIR/notify-send" "$SHIM_DIR/x-terminal-emulator"
check_holds >/dev/null 2>&1
eq "one prompt for the set" 1 "$(grep -c -- '--title=Hold Expired' "$SHIM_DIR/zenity-log")"
for p in xorg-x11-drv-nvidia xorg-x11-drv-nvidia-libs.i686 kmod-nvidia; do
    eq "$p updated to 560.1" "3:560.1-1.fc45" "$(rv "$p")"
done
eq "no locks left" "" "$(locks)"
eq "hold file empty" "" "$(cat "$HOLD_FILE")"

summary "dnf"
