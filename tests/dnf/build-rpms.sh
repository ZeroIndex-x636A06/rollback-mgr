#!/bin/bash
# Builds fake RPM Fusion-style NVIDIA RPMs (versions 550.1 and 560.1, epoch 3) into $1 with repo metadata.
#   xorg-x11-drv-nvidia (source xorg-x11-drv-nvidia): -libs (x86_64 + i686), -kmodsrc, -cuda
#   kmod-nvidia (its own source): requires the exact xorg-x11-drv-nvidia-kmodsrc it was built from
# Runs in an Ubuntu container: needs rpm and createrepo-c from archive.ubuntu.com.
set -e
OUT=${1:?output dir}
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null
apt-get install -y -qq rpm createrepo-c >/dev/null
TOP=$(mktemp -d)
mkdir -p "$TOP"/{SPECS,BUILD,RPMS,SRPMS,SOURCES,BUILDROOT}

spec_driver() { # version
cat <<EOF
Name: xorg-x11-drv-nvidia
Version: $1
Release: 1.fc45
Epoch: 3
Summary: fake NVIDIA driver
License: MIT
%description
fake
%package libs
Summary: fake libs
%description libs
fake
%package kmodsrc
Summary: fake kmod source
%description kmodsrc
fake
%package cuda
Summary: fake cuda
Requires: %{name}-libs%{?_isa} = %{epoch}:%{version}-%{release}
%description cuda
fake
%install
mkdir -p %{buildroot}/usr/share/fake/%{_target_cpu} %{buildroot}/usr/lib/fake-%{_target_cpu}
echo driver > %{buildroot}/usr/share/fake/%{_target_cpu}/driver
echo libs > %{buildroot}/usr/lib/fake-%{_target_cpu}/libs
echo kmodsrc > %{buildroot}/usr/share/fake/%{_target_cpu}/kmodsrc
echo cuda > %{buildroot}/usr/share/fake/%{_target_cpu}/cuda
%files
/usr/share/fake/%{_target_cpu}/driver
%files libs
/usr/lib/fake-%{_target_cpu}/libs
%files kmodsrc
/usr/share/fake/%{_target_cpu}/kmodsrc
%files cuda
/usr/share/fake/%{_target_cpu}/cuda
EOF
}
# the main package needs its libs at the exact same version
spec_driver_requires() { sed 's/^License: MIT$/License: MIT\nRequires: %{name}-libs%{?_isa} = %{epoch}:%{version}-%{release}/'; }

spec_kmod() { # version
cat <<EOF
Name: kmod-nvidia
Version: $1
Release: 1.fc45
Epoch: 3
Summary: fake prebuilt NVIDIA module
License: MIT
Requires: xorg-x11-drv-nvidia-kmodsrc = 3:$1-1.fc45
%description
fake
%install
mkdir -p %{buildroot}/usr/share/fake
echo kmod > %{buildroot}/usr/share/fake/kmod
%files
/usr/share/fake/kmod
EOF
}

for v in 550.1 560.1; do
    spec_driver "$v" | spec_driver_requires > "$TOP/SPECS/driver-$v.spec"
    spec_kmod "$v" > "$TOP/SPECS/kmod-$v.spec"
    rpmbuild -bb --define "_topdir $TOP" --target x86_64 "$TOP/SPECS/driver-$v.spec" >/dev/null 2>&1
    rpmbuild -bb --define "_topdir $TOP" --target i686 "$TOP/SPECS/driver-$v.spec" >/dev/null 2>&1
    rpmbuild -bb --define "_topdir $TOP" --target x86_64 "$TOP/SPECS/kmod-$v.spec" >/dev/null 2>&1
done
mkdir -p "$OUT"
find "$TOP/RPMS" -name '*.rpm' -exec cp {} "$OUT/" \;
createrepo_c -q "$OUT"
ls "$OUT"
