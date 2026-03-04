# rollback-mgr
Rollback Manager: A comprehensive Linux package version-control utility. Automates downgrades for Pacman (including AUR), Flatpak, APT, and DNF with a built-in "Hold &amp; Review" system. Features systemd-scheduled expiration checks and cross-DE native notifications.

## Why use this?

Manually managing package downgrades and preventing them from immediately updating again is tedious. **Rollback Manager** streamlines this workflow by:

1. **Unified Downgrading:** Provides a single interface to roll back system packages or Flatpaks to specific commits or archive versions.
2. **Automated Holds:** Prevents your package manager from updating specific apps once they are rolled back.
3. **Smart Expiration:** Allows you to set a custom hold duration (e.g., 7 days).
4. **Desktop Integration:** Sends native desktop notifications and uses a GUI queue to review expired holds.

## Compatibility

* **Distros:** Designed to work on any Linux distribution (CachyOS, Arch, Fedora, Debian, Ubuntu, etc.).
* **Desktop Environments:** DE-agnostic; works on GNOME, KDE Plasma, Cinnamon, and others via `zenity` and `notify-send`.

## Dependencies

* `fzf` (For terminal menus)
* `zenity` (For GUI prompts)
* `libnotify` (For `notify-send` alerts)
* `git` (For AUR downgrades)
* `downgrade` (Optional, recommended for Arch Linux)

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
