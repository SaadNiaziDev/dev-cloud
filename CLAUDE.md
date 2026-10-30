# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Rules

- Every word must justify its existence (code, docs, messages).
- Commits: short single-line message, no co-author trailers (`agent.md`).

## Commands

```sh
cargo fmt --all -- --check
cargo clippy --all-targets --locked -- -D warnings
cargo test --locked
cargo test --test discovery                      # one test file
cargo test --test discovery <test_name>          # one test
cargo run -- scan [--format json] [--tools] [--include-paths]
cargo run -- scan --format json --progress --local --inspect-mcp --approved-root <dir>
./scripts/package-macos.sh                       # dist/DevCloud.app + .dmg (universal)
./scripts/test-ui.sh [--screenshots DIR]         # render every screen, fail on layout/a11y issues
```

Packaging needs Rust 1.95+, `rustup target add aarch64-apple-darwin x86_64-apple-darwin`, and Xcode Command Line Tools. CI (`.github/workflows/ci.yml`) runs fmt, clippy, test, package, and `cargo audit`.

## Architecture

Two halves joined by a subprocess:

- **Rust scanner** (`devcloud-agent`, `src/`): read-only discovery. Never executes discovered tools; versions come from filesystem layout (Homebrew Cellar, pyenv, extension dirs, plists). `discovery.rs` holds per-OS scanners gated by `cfg(target_os)`; `model.rs` defines the versioned `Report` (schema in `schema/resource-schema-v1.json`). `--local` wraps the report in an envelope with opt-in metadata (`workspace`, `mcp_metadata`, `editor_metadata`, `path_extras`) that stays outside the versioned schema. `--history-dir` (`history.rs`) saves the report and adds a `changes` diff to the envelope.
- **AppKit app** (`macos-appkit/`, Objective-C, compiled with `clang` in the package script, no Xcode project): `ScanModel.m` launches only the helper at `Contents/Helpers/devcloud-agent` (the `DEVCLOUD_AGENT_PATH` override exists only when compiled with `-DDEVCLOUD_TESTING`) with `scan --format json --progress --local --history-dir <Application Support>/DevCloud/History` plus opt-in flags. `Theme.m` holds the palette and shared views, `Inventory.m` turns the report into tools, warnings, and the Activity timeline, each sidebar page is a `*Page.m`, and `StatusMenu.m` is the menu bar dropdown. `BrandMark.m` draws the app icon and menu bar mark; `scripts/make-icon.m` renders it into `AppIcon.icns` at package time. JSON comes on stdout; progress lines `DEVCLOUD_PROGRESS|done|total|message` come on stderr. Changing CLI flags or output requires updating both sides.

Tests inject fake filesystem roots through `ScanPaths` (see `tests/discovery.rs`) instead of reading the real machine. macOS is the active target; Windows code exists but is paused.

## UI and motion

Design follows Emil Kowalski's design-engineering rules (`emil-design-eng`, `animate`, `review-animations` skills). Motion tokens and helpers live in `Theme.h`: `EaseOut()` (0.23, 1, 0.32, 1) for anything entering or responding, `EaseInOut()` for on-screen movement, `AnimatePress`, `AnimateIn`, `AnimateOut`.

- Animate only with a purpose: feedback, spatial consistency, or softening a jarring change. Never animate keyboard-driven actions (page switches, ⌘ shortcuts) or anything seen dozens of times an hour.
- Under 300 ms; exits faster than entrances; never ease-in; never scale from 0 (start at 0.95–0.97 with opacity).
- Pressables scale to 0.97; popovers grow from their trigger; toasts enter and leave through the same edge; staggers 30–80 ms.
- Animate transform and opacity only, and respect Reduce Motion (keep fades, drop movement).
- No perpetual decorative motion.

## Scope

Local, read-only inventory only. Cloud sync, backups, restore, and accounts are later phases.
