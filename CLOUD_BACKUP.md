# Inventory cloud backup

Connected builds support browser sign-in, inventory backup, listing, verified download and deletion. Builds without an API origin keep everything local. Configuration backup, installation and restore are not implemented.

After scanning the destination Mac, Review on a saved backup downloads and verifies it, then compares its tools with the scan. The review identifies matching tools, differences and tools needing manual setup. It shows every inventory record and does not install anything.

For missing Git, Node.js or Python entries originally installed through Homebrew, the review can show a fixed manual Homebrew command. Homebrew must be installed separately, and its current package may differ from the saved version. No command is taken from the backup or run by DevCloud.

Back Up Now first saves the allowlisted inventory in a durable local queue. The page says “queued” until the service acknowledges a matching committed snapshot; only then does it appear among saved backups. Up to five distinct inventories can wait, each at most 1 MiB. Repeated clicks for the same pending bytes do not add duplicates.

Interrupted uploads retry with exponential backoff while DevCloud is open. Rate-limit responses delay the next attempt. Retry keys and exact bytes survive app restarts, so a lost commit response does not create another backup. Commit attempts are persisted before sending. Uncertain commits retry that exact upload; a missing uncertain commit pauses for attention instead of recreating a backup someone may have deleted. Confirmed expired reservations receive a new retry key. Invalid requests or storage exhaustion pause the queue for Retry Now or Clear Queue.

Queue data lives under `~/Library/Application Support/DevCloud/CloudUploads`, with owner-only directory/file permissions. It contains inventory, checksums and retry metadata, without session tokens or configs. It is not encrypted. The token remains in Keychain. Queues are bound to the saved session and API origin; another account cannot inherit them. Sign-out or a rejected session clears pending intents; saved cloud backups stay. Clearing the queue cannot undo a request that the service already committed.

Only one app copy can own a queue. Writes use atomic replacement and sync to disk; incomplete writes are reclaimed on reopening. Corrupt, oversized, symlinked or unexpectedly permissive queue files fail closed. They can be cleared from the Backup page without following links.

## Automatic backups

Automatic backup is off by default. Enable it explicitly in the Backup page for the signed-in session. The preference and last committed change marker stay with the session in Keychain; signing out resets consent. If Keychain cannot save consent, automatic backup stays off. Opting out also records a local veto, so an older Keychain preference cannot re-enable it after restart.

Only successful fresh scans can schedule uploads. Loading history, signing in, or enabling the option does not upload an old scan. Change detection compares allowlisted tools, versions, providers and host metadata; timestamps, resource ordering, paths, warnings and other local metadata do not create backups. Identical pending or already committed inventory is skipped.

Busy operations defer scheduling and keep only the newest waiting scan. A full queue waits for capacity. Turning the option off or clearing the queue drops unscheduled work; disabling alone leaves already queued backups to finish. Automatic backup does not enable monitoring or scan while the app is closed. Turn monitoring on separately for background scans.

## Connected Macs and account deletion

The Backup page lists connected Macs. Remove Access ends a lost Mac's enrolled session and pending uploads; its saved backups remain downloadable from your other Macs. Signing out removes access for this Mac.

When offline, Sign Out Locally removes the saved session and pending uploads on this Mac. It cannot confirm server revocation; remove this Mac from another signed-in device when connectivity is available. If Keychain refuses deletion, the app warns you and prevents automatic restoration of the old session.

Delete Cloud Account requires typing `delete my account` and confirming the displayed account. The dialog defaults to Cancel and rechecks account identity when submitted. A session older than ten minutes is rejected: sign out, sign in again, and confirm deletion again. Deletion never resumes automatically after reauthentication or a network failure.

A confirmed response ends access, clears this Mac's session and queue, and removes the account's metadata. Cloud backup cleanup is queued; the app reports deletion requested rather than claiming every object has already been removed. Local scans, history and exported files stay on the Mac. Rejected or uncertain deletion keeps the account and pending queue unless the session itself has ended.

## Checks

`./scripts/test-cloud.sh` covers account-management confirmation, stale sign-in, unknown devices, uncertain deletion and session cleanup, as well as inventory reduction, persistent queue recovery, uncertain commits, throttling, expiry, account isolation, concurrent app copies, late callbacks, invalid acknowledgements and file safety. Optional live checks use the documented local fixture environment; they download only for inspection.

`python3 scripts/check-cloud-leaks.py` checks tracked source. `--history HEAD` audits the current branch's ancestry; choose the branch intended for publication, since other local branches can hold private history. `--artifact <binary>` checks a built app or helper. CI runs the guard on source and both packaged binaries. Findings print paths and categories, never matched credentials. These signatures catch known endpoints, credential formats, private keys and provider identifiers; they do not replace a broader secret review before publication.

An optional management fixture checks the real native client against a disposable loopback service: two Macs on one account, a separate account, revocation, verified cross-Mac download and account deletion. It refuses non-loopback destinations and uses temporary queues without saving fixture credentials to Keychain. The private service repository supplies its isolated test runner.

The fixture also starts a fresh client instance with its own empty local queue, enrolls it with a seeded session, and verifies a selected cloud inventory. It does not exercise browser sign-in, a clean macOS installation, or software restoration.
