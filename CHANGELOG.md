# Changelog

## 0.5.1

- Separate common native core, Codex adapter, Secretive integration, app lifecycle and migrations.
- Build Core/Codex/Secretive as distinct static libraries with explicit public headers.
- Update build/test/source packaging paths and add package-boundary regression checks.
- Preserve key identities, entitlements, authentication and original app binaries.

## 0.5.0

- Create separate software RSA-2048 SSH keys from the KCL menu for unmodified Secretive.
- Publish keys in a shared CryptoTokenKit store and migrate existing public identities.
- Keep Codex P-256 keys separate and select them explicitly in the runtime adapter.
- Restrict SSH signatures to RSA-SHA2-512 with native owner authentication; retain private export rejection.
- Add public-key encoding tests and document Secretive's smart-card limitations.

## 0.4.1

- Add the silver key and teal link app icon to the host, token extension and helper.
- Include icon assets in builds and prebuilt DMGs.

## 0.4.0

- Rename internal executables, bundle IDs, classes, environment variables and storage paths to Keychain Compatibility Layer / KCL.
- Import existing keys inside the extension and verify unchanged public-key identity before retiring legacy token configurations.
- Isolate old identifiers in migration code and retain encrypted legacy items for recovery.
- Purge both key namespaces for an explicitly deleted instance to prevent resurrection.
- Require a full Codex restart after the namespace upgrade; its original files remain unchanged.

## 0.3.1

- Apply compatibility automatically whenever the app is running; remove the toggle.
- Add a KCL menu with Quit, and stop the watcher on normal or forced app exit.
- Disable the legacy independent login helper during migration.
- Keep existing Codex processes unchanged until their next normal restart.

## 0.3.0

- Make prebuilt Intel macOS DMGs the default user distribution.
- Add in-app per-user installation and automatic-helper enable/disable controls.
- Remove the legacy manual Codex launch button from the user interface.
- Add tag/version-checked CI builds and GitHub test prereleases with SHA-256 assets.
- Rewrite all four user guides around DMG installation with no developer tools.
- Preserve Objective-C authentication modules and the original Codex app.

## 0.2.0

- Replace Python build, installation, automatic-helper setup, and diagnostics
  with a Go standard-library management CLI.
- Preserve native Objective-C/C authentication and unmodified Codex integration.
- Add semantic versioning, Go regression tests, an opt-in automatic-launch
  fixture test, and local Homebrew source packaging.
- Add an English contribution guide.

## 0.1.0

- Initial local software-backed CryptoTokenKit compatibility layer and
  per-user automatic application helper.
