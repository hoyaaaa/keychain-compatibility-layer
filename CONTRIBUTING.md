# Contributing

Bug reports, compatibility checks and small, focused pull requests are welcome.

## Getting started

Development requires Intel macOS, Xcode Command Line Tools, Go 1.23+ and make.
End users only need the prebuilt app. See [architecture](docs/ARCHITECTURE.md)
for the shared core and Codex/Secretive integration packages.

```sh
make test       # Automated checks; does not create Keychain keys
make all        # Build the app
make dmg        # Build the versioned DMG and checksum
```

## Tests

The repository includes tests for installer rollback, diagnostic parsing,
package boundaries, SSH public-key encoding and token-store concurrency.

Additional tests are opt-in:

- `make test-auto`: verifies one restart and watcher shutdown using a disposable
  GUI app. Run in a GUI login session; it does not restart Codex.
- `KCL_TEST_KEYS=1 go test ./cmd/kcl -run TestSSHSharedStoreConcurrent -count=1`:
  creates and deletes two dedicated test keys. Requires an installed KCL app.

Manual signature tests require macOS authentication. Use dedicated test keys
and delete only those keys afterward. See [Secretive testing](docs/SECRETIVE.md)
and [verification records](docs/VERIFICATION.md).

## Reporting a bug

Include the KCL version, app version, macOS version, CPU architecture and steps
to reproduce. Share a short, redacted error message; do not upload raw logs,
private keys, credentials, account identifiers or diagnostic dumps.

## Pull requests

Describe what changes, why it is needed and how you tested it. Add a regression
check for changed behavior. Keep dependencies minimal and update all four
README languages when user-facing behavior changes.

Preserve these boundaries:

- Do not patch, re-sign or replace the original Codex or Secretive app.
- Keep private material inside the token extension and retain owner authentication.
- Never label software-backed keys as hardware-backed or skip required approval.
- When changing storage identifiers, migrate keys and verify their public identity.

## Releases

Update `VERSION` and `CHANGELOG.md`, run the checks, and inspect the DMG.
A matching `vVERSION` tag triggers the release workflow; a manual workflow run
only creates CI artifacts. The workflow expects this project at the repo root.

Current builds are ad-hoc signed test prereleases. A normal public macOS release
still needs Developer ID signing, appropriate entitlements and Apple notarization.

## License

Contributions are made under the project's [MIT License](LICENSE).
This guide is maintained in English only.
