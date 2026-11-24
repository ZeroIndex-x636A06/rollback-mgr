#!/bin/bash
# Builds a fake CachyOS-style NVIDIA stack for the pacman tests (inside an Arch container).
#
#   repo (fakerepo)   newest: NVIDIA 570.1-1, kernel linux-fake 6.11.1-1 with its prebuilt
#                     linux-fake-nvidia-open module (pins linux-fake=6.11.1-1 and nvidia-utils=570.1-1)
#   package cache     NVIDIA 560.1-1 userspace
#   CachyOS archive   linux-fake 6.10.1-1 + headers + module built for NVIDIA 560.1-1 (x86_64_v3),
#                     and /nvidia/555/ with NVIDIA 555.1-1
#   Arch archive      NVIDIA 550.1-1 (incl. nvidia-open-dkms), an epoch package
#
# Then installs the 560 stack and upgrades to 570, so pacman.log has real history.
set -e
WWW=${WWW:-/www}
STAGE=/srv/stage
REPO=/srv/repo
CACHE=/var/cache/pacman/pkg

mkpkg() { # out name ver base arch "deps" "provides" "conflicts"
    local out=$1 name=$2 ver=$3 base=$4 arch=$5 deps=$6 provs=$7 confl=$8 d x
    d=$(mktemp -d); mkdir -p "$d/usr/share/fake/$name" "$out"
    echo "$name $ver" > "$d/usr/share/fake/$name/VERSION"
    {
        echo "pkgname = $name"; echo "pkgbase = $base"; echo "pkgver = $ver"; echo "pkgdesc = fake $name"
        echo "url = https://example.invalid"; echo "builddate = 1700000000"; echo "packager = tests"
        echo "size = 10"; echo "arch = $arch"; echo "license = MIT"
        for x in $deps; do echo "depend = $x"; done
        for x in $provs; do echo "provides = $x"; done
        for x in $confl; do echo "conflict = $x"; done
    } > "$d/.PKGINFO"
    local fn="$name-$ver-$arch.pkg.tar.zst"
    chmod -R u=rwX,go=rX "$d"
    (cd "$d" && bsdtar --uid 0 --gid 0 -cf - .PKGINFO usr | zstd -q -c > "$out/$fn")
    rm -rf "$d"
}

nvidia_stack() { # out driver-version arch
    local out=$1 v=$2 a=$3 up=${2%-*}
    mkpkg "$out" nvidia-utils "$v" nvidia-utils "$a" "glibc libcurl.so=4-64" "vulkan-driver opengl-driver nvidia-libgl"
    mkpkg "$out" opencl-nvidia "$v" nvidia-utils "$a" "nvidia-utils=$v" "opencl-driver"
    mkpkg "$out" lib32-nvidia-utils "$v" lib32-nvidia-utils "$a" "nvidia-utils=$up" "lib32-vulkan-driver"
    mkpkg "$out" nvidia-settings "$v" nvidia-settings "$a" "nvidia-utils libxnvctrl glibc" ""
    mkpkg "$out" libxnvctrl "$v" nvidia-settings "$a" "glibc" "libXNVCtrl.so=0-64"
}

kernel_set() { # out kernel-version driver-version arch
    local out=$1 k=$2 drv=$3 a=$4
    mkpkg "$out" linux-fake "$k" linux-fake "$a" "coreutils" "KSMBD-MODULE"
    mkpkg "$out" linux-fake-headers "$k" linux-fake "$a" "" ""
    mkpkg "$out" linux-fake-nvidia-open "$k" linux-fake "$a" "linux-fake=$k nvidia-utils=$drv" "NVIDIA-MODULE"
}

# Fancyindex-like directory listing (relative links, sort links, a parent link)
mkindex() { # dir
    local dir=$1 f
    {
        echo '<html><head><title>Index</title></head><body><table>'
        echo '<tr><td><a href="?C=N&amp;O=A">File Name</a></td><td><a href="?C=S&amp;O=A">Size</a></td></tr>'
        echo '<tr><td><a href="../">Parent directory/</a></td></tr>'
        for f in "$dir"/*; do
            f=${f##*/}
            [ "$f" = "index.html" ] && continue
            if [ -d "$dir/$f" ]; then
                echo "<tr><td><a href=\"$f/\" title=\"$f\">$f/</a></td></tr>"
            else
                echo "<tr><td><a href=\"${f//:/%3A}\" title=\"$f\">$f</a></td><td>1 KiB</td></tr>"
            fi
        done
        echo '</table></body></html>'
    } > "$dir/index.html"
}

rm -rf "$STAGE" "$REPO" && mkdir -p "$STAGE" "$REPO" "$CACHE"
rm -rf "${WWW:?}"/* 2>/dev/null || true

# --- sync repo: newest versions ---
nvidia_stack "$REPO" 570.1-1 x86_64
kernel_set "$REPO" 6.11.1-1 570.1-1 x86_64
mkpkg "$REPO" nvidia-open-dkms 570.1-1 nvidia-utils x86_64 "dkms nvidia-utils=570.1-1" "NVIDIA-MODULE" "NVIDIA-MODULE"
mkpkg "$REPO" dkms 3.1-1 dkms any "" "" ""
mkpkg "$REPO" solo 2.0-1 solo x86_64 "glibc" ""
mkpkg "$REPO" fakepoch 1:3.0-1 fakepoch x86_64 "" ""
repo-add -q "$REPO/fakerepo.db.tar.gz" "$REPO"/*.pkg.tar.zst

# --- pacman config ---
cat > /etc/pacman.conf <<'EOF'
[options]
HoldPkg     = pacman glibc
Architecture = x86_64 x86_64_v3
#IgnorePkg   =
#IgnoreGroup =
SigLevel    = Never
LocalFileSigLevel = Never
RemoteFileSigLevel = Never

[fakerepo]
Server = file:///srv/repo
EOF
cp /etc/pacman.conf /etc/pacman.conf.pristine
pacman -Sy >/dev/null

# --- package cache: 560 userspace, plus files that must be ignored ---
nvidia_stack "$STAGE" 560.1-1 x86_64
cp "$STAGE"/{nvidia-utils,opencl-nvidia,lib32-nvidia-utils,nvidia-settings,libxnvctrl}-560.1-1-x86_64.pkg.tar.zst "$CACHE/"
mkpkg "$STAGE" solo 1.0-1 solo x86_64 "glibc" ""
cp "$STAGE/solo-1.0-1-x86_64.pkg.tar.zst" "$CACHE/"
mkpkg "$STAGE/arm" nvidia-utils 540.1-1 nvidia-utils aarch64 "" ""
cp "$STAGE/arm/nvidia-utils-540.1-1-aarch64.pkg.tar.zst" "$CACHE/"
touch "$CACHE/nvidia-utils-530.1-1-x86_64.pkg.tar.zst.part" "$CACHE/nvidia-utils-560.1-1-x86_64.pkg.tar.zst.sig"

# --- CachyOS archive ---
C="$WWW/cachy/archive/cachyos-v3"; mkdir -p "$C"
kernel_set "$STAGE" 6.10.1-1 560.1-1 x86_64_v3
cp "$STAGE"/linux-fake*-6.10.1-1-x86_64_v3.pkg.tar.zst "$C/"
for f in "$C"/*.zst; do touch "$f.sig"; done
mkpkg "$C" linux-fake 6.9.1-1 linux-fake aarch64 "" ""          # wrong architecture: ignored
mkindex "$C"
mkdir -p "$WWW/cachy/nvidia/555" "$WWW/cachy/nvidia/560"
nvidia_stack "$WWW/cachy/nvidia/555" 555.1-1 x86_64
mkindex "$WWW/cachy/nvidia/555"; mkindex "$WWW/cachy/nvidia/560"; mkindex "$WWW/cachy/nvidia"
mkdir -p "$WWW/cachy/archive"; mkindex "$WWW/cachy/archive"

# --- Arch archive (archive.archlinux.org/packages/<letter>/<name>/) ---
A="$STAGE/ala"; mkdir -p "$A"
nvidia_stack "$A" 550.1-1 x86_64
mkpkg "$A" nvidia-open-dkms 550.1-1 nvidia-utils x86_64 "dkms nvidia-utils=550.1-1" "NVIDIA-MODULE" "NVIDIA-MODULE"
mkpkg "$A" nvidia-open-dkms 560.1-1 nvidia-utils x86_64 "dkms nvidia-utils=560.1-1" "NVIDIA-MODULE" "NVIDIA-MODULE"
mkpkg "$A" fakepoch 1:2.0-1 fakepoch x86_64 "" ""
mkpkg "$A" fakepoch 0.9-1 fakepoch x86_64 "" ""
for f in "$A"/*.pkg.tar.zst; do
    n=${f##*/}; n=${n%-*-*-*}
    d="$WWW/ala/${n:0:1}/$n"; mkdir -p "$d"
    cp "$f" "$d/"; touch "$d/${f##*/}.sig"
done
for d in "$WWW"/ala/*/*/; do mkindex "${d%/}"; done

# --- history: install the 560 stack with kernel 6.10, then upgrade to 570 / 6.11 ---
pacman -U --noconfirm "$CACHE"/{nvidia-utils,opencl-nvidia,lib32-nvidia-utils,nvidia-settings,libxnvctrl}-560.1-1-x86_64.pkg.tar.zst \
    "$STAGE"/linux-fake{,-headers,-nvidia-open}-6.10.1-1-x86_64_v3.pkg.tar.zst "$CACHE/solo-1.0-1-x86_64.pkg.tar.zst" >/dev/null
pacman -U --noconfirm "$A/fakepoch-1:2.0-1-x86_64.pkg.tar.zst" >/dev/null
sleep 1
pacman -Syu --noconfirm >/dev/null
echo "fixtures ready: $(pacman -Q nvidia-utils linux-fake linux-fake-nvidia-open solo fakepoch | tr '\n' ' ')"
