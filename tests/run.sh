#!/bin/bash
# Runs the rollback-mgr tests in throwaway containers (needs docker and python3).
#   tests/run.sh               all suites
#   tests/run.sh pacman dnf    some of them
#
# pacman: fake CachyOS-style NVIDIA stack, offline (Arch image only)
# apt:    real Ubuntu 24.04 packages (needs archive.ubuntu.com)
# dnf:    fake RPM Fusion-style NVIDIA RPMs (built with rpmbuild in an Ubuntu container)
# Nothing touches the machine running this script except the containers.

cd "$(dirname "$0")/.." || exit 1
REPO=$PWD
WORK=$(mktemp -d)
PORT=${PORT:-18080}
OUT=${OUT:-$WORK/out}
mkdir -p "$WORK/www" "$OUT"
suites=${*:-pacman apt dnf}
status=0

python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$WORK/www" >"$WORK/http.log" 2>&1 &
HTTP_PID=$!
trap 'kill $HTTP_PID 2>/dev/null; rm -rf "$WORK/www" "$WORK/rpms"' EXIT
sleep 1

run() { # image script...
    local image=$1; shift
    docker run --rm --network host -v "$REPO:/repo:ro" -v "$WORK/www:/www" -v "$OUT:/out" \
        -e HTTP_BASE="http://127.0.0.1:$PORT" -e OUT_DIR=/out "$image" bash -c "$*"
}

for s in $suites; do
    echo ""
    echo "################ $s ################"
    case $s in
        pacman)
            run archlinux:latest 'bash /repo/tests/pacman/fixtures.sh >/dev/null 2>&1 && bash /repo/tests/pacman/test.sh' || status=1 ;;
        apt)
            run ubuntu:24.04 'bash /repo/tests/apt/test.sh' || status=1 ;;
        dnf)
            mkdir -p "$WORK/rpms"
            docker run --rm --network host -v "$REPO:/repo:ro" -v "$WORK/rpms:/rpms" ubuntu:24.04 \
                bash /repo/tests/dnf/build-rpms.sh /rpms >"$WORK/rpm-build.log" 2>&1 \
                || { echo "RPM build failed:"; tail -20 "$WORK/rpm-build.log"; status=1; continue; }
            docker run --rm -v "$REPO:/repo:ro" -v "$WORK/rpms:/rpms:ro" -v "$OUT:/out" -e OUT_DIR=/out \
                fedora:latest bash /repo/tests/dnf/test.sh || status=1 ;;
        *) echo "unknown suite $s"; status=1 ;;
    esac
done
echo ""
echo "Scenario output saved in $OUT"
exit $status
