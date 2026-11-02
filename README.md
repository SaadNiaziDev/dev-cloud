# DevCloud

Your dev setup, remembered. A native macOS app that finds every runtime, package manager and editor on your Mac, and tells you what changed.

<p align="center">
  <!-- <img alt="DevCloud in 20 seconds: scan, understand, track, menu bar, privacy" src="assets/media/tour.gif" width="420"> -->
  <img alt="Under the hood: discover, monitor, snapshot, encrypt, back up, restore" src="assets/media/under-the-hood.gif" width="420">
</p>

## How it works

1. **Discover** — a small Rust scanner inside the app reads folders and metadata to find your tools and versions.
2. **Monitor** — it watches those folders from the menu bar and records every install, upgrade and removal.
3. **Back up** — save local inventory snapshots or, in connected builds, sign in and queue an off-device copy. [Cloud backup](CLOUD_BACKUP.md) retries interrupted uploads.
4. **Later** — config capture, encryption and recovery on a new Mac.

## Privacy

Reads metadata only. Never runs your tools, never reads code, `.env` files or keys. Cloud backup is optional: manual backups or explicitly enabled automatic backups send only allowlisted inventory. Queued uploads contain no configs or credentials.

Requires macOS 14 or later.
