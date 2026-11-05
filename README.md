# DevCloud

**Your dev setup, remembered.** DevCloud finds every runtime, package manager, editor and extension on your Mac, tracks what changes, and installs it all again on your next Mac.

<p align="center">
  <img src="assets/media/devcloud-preview.gif" alt="DevCloud tour: discover tools, inspect versions, track changes, back up inventory, and set up a new Mac" width="720">
</p>

<p align="center">
  <a href="https://github.com/SaadNiaziDev/dev-cloud/releases"><b>Download for macOS</b></a> ·
  <a href="assets/media/devcloud-preview.mp4">Watch the 27-second video</a> ·
  <a href="#move-to-a-new-mac">Move to a new Mac</a> ·
  <a href="CLOUD_BACKUP.md">Cloud backup</a>
</p>

Free · macOS 14 or later · Apple silicon and Intel · the demo uses sample data.

## Why

A new Mac takes a day of remembering: which Node versions, which Python, that one CLI you installed in March, forty editor extensions. DevCloud keeps that list for you, without running your tools or reading your code.

## What it does

| | |
|---|---|
| **Discover** | Homebrew formulae and apps, Node, Python, Rust, Go, Java, Xcode tools, VS Code and Cursor with their extensions, and version managers like nvm and pyenv. |
| **Understand** | See versions, where each tool came from, and when two installations fight over your `PATH`. |
| **Track** | Opt in to monitoring from the menu bar. DevCloud records every install, upgrade and removal, and lets you save and compare snapshots. |
| **Back up** | Keep an off-device copy of your tool list in your account, so it survives a lost or broken Mac. |
| **Set up a new Mac** | Sign in on the new Mac, pick your backup, tick what you want, and DevCloud installs it with Homebrew. |

## Move to a new Mac

<p align="center">
  <img src="assets/media/setup-new-mac.gif" alt="DevCloud on a new Mac: sign in, pick a backup, install the missing tools with Homebrew" width="720">
</p>

1. **On your old Mac:** open DevCloud, sign in, and choose **Backup → Back Up Now**.
2. **On your new Mac:** install [Homebrew](https://brew.sh) and DevCloud, then sign in with the same GitHub account. DevCloud opens **Set Up Mac** with your latest backup.
3. Untick anything you don't want and choose **Install**. DevCloud shows what is already on this Mac, installs the rest with Homebrew, and marks each item as installed or not.
4. Copy the **Finish in Terminal** commands for things Homebrew doesn't manage, such as `nvm install 22.11.0` or Cursor extensions.

Homebrew installs its current versions, not necessarily the ones you had. Apps that ask for your password, and formulae from third-party taps, may need installing from Terminal; **Show Log** says why. Prefer to run it yourself? **Save Setup File…** gives you a `Brewfile` for `brew bundle`. Configuration files, dotfiles and secrets are not included.

## Install

Download `DevCloud.dmg` from the [latest release](https://github.com/SaadNiaziDev/dev-cloud/releases), drag DevCloud to Applications, and sign in with GitHub. DevCloud needs an account; it doesn't scan or show anything until you sign in.

The preview is not notarized yet, so macOS blocks the first launch. Open it once with **right-click → Open**, or go to **System Settings → Privacy & Security → Open Anyway**. Check the download against the SHA-256 checksum in the release notes.

## Privacy

- Discovery reads file and folder metadata. It never runs your tools or reads source code, `.env` files or keys.
- Monitoring, workspace folders and automatic backup are off until you turn them on. Backups upload only when you choose Back Up Now or enable automatic backup.
- Backups hold only tool names, versions and sources, plus your Mac's OS version and chip. Paths, workspaces and configuration stay on your Mac. Delete backups or your whole account from the app at any time. Details: [Cloud backup](CLOUD_BACKUP.md).

## Not ready yet

DevCloud does not back up configuration files, dotfiles or secrets, and installs nothing without your approval. Cloud backups are not end-to-end encrypted. Keep your own backups too.

## Build from source

```sh
cargo test --locked
./scripts/package-macos.sh   # dist/DevCloud.app and DevCloud.dmg (universal)
```

Needs Rust 1.95+ with the `aarch64-apple-darwin` and `x86_64-apple-darwin` targets, and Xcode Command Line Tools.
