# Release readiness

The current preview backs up inventory only. Config capture, encryption and restore are future features. Do not describe this release as setup recovery.

## Local verification

- Run scanner tests, native snapshot/cloud checks, icon checks and the UI fixture harness.
- Exercise browser email sign-up, verification, sign-in, password reset and code approval against a local development service.
- Verify upload, restart/retry, download integrity, cross-device access, revocation and deletion using disposable accounts.
- Review connected, signed-out, pending, failed and expired-session screens; check keyboard navigation and VoiceOver.

## Release build

`scripts/package-macos.sh` builds a universal app and DMG. Set `DEVCLOUD_API_URL` to the public HTTPS API origin for a connected release; leaving it empty deliberately produces a local-only build. Local HTTP origins are refused for release packages.

Set `DEVCLOUD_SIGN_IDENTITY` to a Developer ID identity and `DEVCLOUD_NOTARY_PROFILE` to an existing notarization profile. The script signs, submits, staples and verifies when both are configured. Without them, the result is an ad-hoc preview, not a notarized public release.

The draft-release workflow reads the repository variable `DEVCLOUD_API_URL`, runs cloud checks and leak checks, and creates a draft prerelease. It does not configure release signing. Review the draft, checksum and signing status before publishing.

## Remaining public-release gates

- Public API domain and reliable email delivery, with no development inbox exposed.
- Developer ID signing and notarization; clean-machine Gatekeeper check.
- Physical second-Mac round trip, Intel validation and supported macOS testing.
- Connected-cloud visual/accessibility review, privacy and license text, hosted CI results.
- Final source/history/artifact leak review; publish only the intended branch.
