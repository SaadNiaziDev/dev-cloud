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
./scripts/package-macos.sh                       # dist/Continuity.app + .dmg (universal)
```

Packaging needs Rust 1.95+, `rustup target add aarch64-apple-darwin x86_64-apple-darwin`, and Xcode Command Line Tools. CI (`.github/workflows/ci.yml`) runs fmt, clippy, test, package, and `cargo audit`.

## Architecture

Two halves joined by a subprocess:

- **Rust scanner** (`continuity-agent`, `src/`): read-only discovery. Never executes discovered tools; versions come from filesystem layout (Homebrew Cellar, pyenv, extension dirs, plists). `discovery.rs` holds per-OS scanners gated by `cfg(target_os)`; `model.rs` defines the versioned `Report` (schema in `schema/resource-schema-v1.json`). `--local` wraps the report in an envelope with opt-in metadata (`workspace`, `mcp_metadata`, `editor_metadata`, `path_extras`) that stays outside the versioned schema. `--history-dir` (`history.rs`) saves the report and adds a `changes` diff to the envelope.
- **AppKit app** (`macos-appkit/`, Objective-C, compiled with `clang` in the package script, no Xcode project): `ScanModel.m` launches only the helper at `Contents/Helpers/continuity-agent` (the `CONTINUITY_AGENT_PATH` override exists only when compiled with `-DCONTINUITY_TESTING`) with `scan --format json --progress --local --history-dir <Application Support>/Continuity/History` plus opt-in flags. `BrandMark.m` draws the app icon and menu bar mark; `scripts/make-icon.m` renders it into `AppIcon.icns` at package time. JSON comes on stdout; progress lines `CONTINUITY_PROGRESS|done|total|message` come on stderr. Changing CLI flags or output requires updating both sides.

Tests inject fake filesystem roots through `ScanPaths` (see `tests/discovery.rs`) instead of reading the real machine. macOS is the active target; Windows code exists but is paused.

## Scope

Local, read-only inventory only. Cloud sync, backups, restore, and accounts are later phases.
