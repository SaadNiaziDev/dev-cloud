# Continuity

Continuity is a native macOS app for keeping track of a development setup. It discovers installed tools and their versions, records changes locally, and provides a quick view in the menu bar.

## What it does

- Finds development tools, runtimes, package managers, Homebrew packages, and editor extensions.
- Shows installation sources and versions when local metadata provides them.
- Displays bundled icons for common tools, with a fallback for other packages.
- Tracks added, removed, and changed installations across scans.
- Optionally monitors known locations and checks them again every five minutes. A change received during a scan triggers a follow-up scan.
- Shows Git branch and worktree metadata for approved folders. MCP server names, selected editor preferences, extra PATH tools, and installation paths are separate opt-ins.

Open Continuity to scan, search the inventory, and review changes. Close its window to keep the menu bar control available. Monitoring, login at startup, and notifications can each be enabled in Settings.

## Privacy and scope

The scanner reads selected metadata on your Mac and never runs the tools it finds. It does not upload your inventory. Scan history is stored under `~/Library/Application Support/Continuity/History`, with owner-only permissions. Up to 50 change-point reports are retained.

Continuity maintains an inventory and change history on this Mac. It does not back up configuration files or synchronize devices. Optional paths, workspace names, extension names, and other metadata can be sensitive; review exported reports before sharing them. PATH results reflect the environment available to the app and can differ from your terminal.

## Install

Continuity targets macOS 14 and later. The app and scanner are built for Apple silicon and Intel. A public release is not available yet; build a local preview with the instructions below. Local previews are ad-hoc signed unless a Developer ID is supplied and are not notarized by default.

## Build and verify

Install Rust 1.95 or newer and the macOS Command Line Tools, then run:

```sh
rustup target add aarch64-apple-darwin x86_64-apple-darwin
./scripts/package-macos.sh
```

The script creates `dist/Continuity.app` and `dist/Continuity.dmg`. You can also use the scanner directly:

```sh
cargo run -- scan
cargo run -- scan --format json
cargo run -- doctor
cargo test --locked
```

## Releases

Pushing a tag matching the package version, such as `v0.1.0`, runs the release workflow. It builds a universal DMG, checks it, and creates a **draft prerelease** with a SHA-256 checksum. The workflow produces an ad-hoc signed preview; review it before publishing.

To build a signed, notarized DMG locally, install a Developer ID Application certificate, configure a `notarytool` keychain profile, and run:

```sh
CONTINUITY_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
CONTINUITY_NOTARY_PROFILE="your-notary-profile" \
./scripts/package-macos.sh
```

Replace the draft's preview DMG and checksum with the signed artifacts before publishing. Apple silicon has been tested locally; macOS 14 and Intel hardware still need release verification.

The scanner's JSON format is defined by [schema/resource-schema-v1.json](schema/resource-schema-v1.json).

Tool icons are from [Devicon](https://github.com/devicons/devicon); the source license and notice are included with the icons.
