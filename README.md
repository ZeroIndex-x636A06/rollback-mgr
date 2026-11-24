# rollback-mgr
Rollback Manager: A comprehensive Linux package version-control utility. Automates downgrades for Pacman (including AUR), Flatpak, APT, and DNF with a built-in "Hold &amp; Review" system. Features systemd-scheduled expiration checks and cross-DE native notifications.

## Why use this?

Manually managing package downgrades and preventing them from immediately updating again is tedious. **Rollback Manager** streamlines this workflow by:

1. **Unified Downgrading:** Provides a single interface to roll back system packages or Flatpaks to specific commits or archive versions.
2. **Automated Holds:** Prevents your package manager from updating specific apps once they are rolled back.
3. **Smart Expiration:** Allows you to set a custom hold duration (e.g., 7 days).
4. **Desktop Integration:** Sends native desktop notifications and uses a GUI queue to review expired holds.

## Linked packages (NVIDIA, kernels, 32-bit libraries)

Some packages can't be rolled back on their own. The NVIDIA driver is the usual example: `nvidia-utils`, `lib32-nvidia-utils`, `opencl-nvidia` and the kernel module all have to be on the same driver version, and a prebuilt module like CachyOS's `linux-cachyos-nvidia` is also tied to one exact kernel build. Rolling back only one of them leaves a broken stack.

When you pick a package to downgrade or hold, Rollback Manager first works out its **linked set**, the packages that have to move with it:

* packages built from the same source (same `pkgbase` on Arch, same source package on Debian/Ubuntu, same source RPM on Fedora),
* 32-bit and other-architecture copies (`lib32-*` on Arch, `:i386` on Debian/Ubuntu, `.i686` on Fedora),
* packages that require an exact version of each other (for example a kernel module and its kernel),
* packages on the same version that depend on each other (like `nvidia-utils` and `nvidia-settings`).

It then shows the set, lets you choose a version (or, on Arch, an earlier state from your pacman history), lists every change, and only after you say yes runs **one** transaction for the whole set. Holds go on the whole set and expire together. If anything fails, the holds you had stay in place.

On Arch-based systems older versions are looked up, in this order, in the local package cache, your sync repos, the CachyOS archive (on CachyOS) and the Arch Linux Archive. If no prebuilt NVIDIA module exists for the version you picked, it offers to switch to the matching DKMS package for that version and keep your current kernel.

You can see a set without changing anything:

```bash
rollback-mgr linked pacman nvidia-utils
```

After a kernel or NVIDIA change, Rollback Manager reminds you to restart, and if you use Flatpak apps it checks that the matching NVIDIA GL extension (`org.freedesktop.Platform.GL.nvidia-*`) is installed.

## Compatibility

* **Distros:** Designed to work on any Linux distribution (CachyOS, Arch, Fedora, Debian, Ubuntu, etc.).
* **Desktop Environments:** DE-agnostic; works on GNOME, KDE Plasma, Cinnamon, and others via `zenity` and `notify-send`.

## Dependencies

* `fzf` (For terminal menus)
* `zenity` (For GUI prompts)
* `libnotify` (For `notify-send` alerts)
* `git` (For AUR downgrades)
* `curl` (For looking up older versions in the online archives; installed with pacman on Arch)
* `bsdtar` (Arch only, for reading package info from the archives; part of `libarchive`, which pacman needs)

The `downgrade` helper is no longer needed: repo packages are rolled back with pacman directly.

## Installation

### Manual

1. Change directory to home directory:
```bash
cd ~

```


2. Clone the repository:
```bash
git clone https://github.com/ZeroIndex-x636A06/rollback-mgr.git

```


3. Change directory to rollback-mgr install folder:
```bash
cd rollback-mgr

```


4. Make the install script executable and run it:
```bash
chmod +x install.sh
./install.sh

```



## Usage

Once installed, the background timer will check for expired holds daily. You can also launch the manager manually from the terminal.

### Launch Manager

```bash
rollback-mgr

```

### Manual Expiry Check

```bash
rollback-mgr check

```

### Show a Linked Set (read-only)

```bash
rollback-mgr linked pacman nvidia-utils
rollback-mgr linked apt nvidia-utils-550
rollback-mgr linked dnf xorg-x11-drv-nvidia.x86_64

```

## Tests

The tests run in throwaway Docker containers and never touch the machine running them. You need `docker` and `python3`.

```bash
tests/run.sh               # all suites
tests/run.sh pacman        # one suite: pacman, apt or dnf

```

* **pacman:** an offline fake CachyOS-style NVIDIA stack (driver, 32-bit libraries, a prebuilt kernel module tied to its kernel, DKMS packages) served as a local repo, cache, CachyOS archive and Arch Linux Archive.
* **apt:** real Ubuntu 24.04 packages (needs access to archive.ubuntu.com).
* **dnf:** fake RPM Fusion-style NVIDIA RPMs built on the fly.

## Un-installation

### Manual

1. Change directory to home directory:
```bash
cd ~

```


2. Change directory to the rollback-mgr install folder:
```bash
cd rollback-mgr

```


*IF YOU DELETED THE DIRECTORY, RERUN THE CLONE COMMAND:*
```bash
git clone https://github.com/ZeroIndex-x636A06/rollback-mgr.git

```


3. Make the un-install script executable and run it:
```bash
chmod +x uninstall.sh
./uninstall.sh

```
