# Inventory cloud backup

Connected builds support browser sign-in, inventory backup, listing, verified download and deletion. Builds without an API origin keep everything local. Configuration backup, installation and restore are not implemented.

Back Up Now first saves the allowlisted inventory in a durable local queue. The page says “queued” until the service acknowledges a matching committed snapshot; only then does it appear among saved backups. Up to five distinct inventories can wait, each at most 1 MiB. Repeated clicks for the same pending bytes do not add duplicates.

Interrupted uploads retry with exponential backoff while DevCloud is open. Rate-limit responses delay the next attempt. Retry keys and exact bytes survive app restarts, so a lost commit response does not create another backup. Commit attempts are persisted before sending. Uncertain commits retry that exact upload; a missing uncertain commit pauses for attention instead of recreating a backup someone may have deleted. Confirmed expired reservations receive a new retry key. Invalid requests or storage exhaustion pause the queue for Retry Now or Clear Queue.

Queue data lives under `~/Library/Application Support/DevCloud/CloudUploads`, with owner-only directory/file permissions. It contains inventory, checksums and retry metadata, without session tokens or configs. It is not encrypted. The token remains in Keychain. Queues are bound to the saved session and API origin; another account cannot inherit them. Sign-out or a rejected session clears pending intents; saved cloud backups stay. Clearing the queue cannot undo a request that the service already committed.

Only one app copy can own a queue. Writes use atomic replacement and sync to disk; incomplete writes are reclaimed on reopening. Corrupt, oversized, symlinked or unexpectedly permissive queue files fail closed. They can be cleared from the Backup page without following links.

## Checks

`./scripts/test-cloud.sh` covers inventory reduction, persistent queue recovery, uncertain commits, throttling, expiry, account isolation, concurrent app copies, late callbacks, invalid acknowledgements and file safety. Optional live checks use the documented local fixture environment; they download only for inspection.

`python3 scripts/check-cloud-leaks.py` checks tracked source. `--history HEAD` audits the current branch's ancestry; choose the branch intended for publication, since other local branches can hold private history. `--artifact <binary>` checks a built app or helper. CI runs the guard on source and both packaged binaries. Findings print paths and categories, never matched credentials. These signatures catch known endpoints, credential formats, private keys and provider identifiers; they do not replace a broader secret review before publication.
