# Technical reference

[English](../README.md) | [한국어](../README.ko.md) | [简体中文](../README.zh-CN.md) | [日本語](../README.ja.md)

Users install the prebuilt DMG; see the language guides above. Commands below
are optional maintainer/diagnostic operations, run from the project root.
`make dmg` builds the versioned Intel image and SHA-256. The native panel handles
per-user installation without developer tools. From 0.3.1, opening the app always starts automatic application; quitting it stops its child watcher. There is no user-facing toggle. The prior independent LaunchAgent is disabled during migration. A parent-PID timer stops the watcher if the app is force-quit. Already-loaded code remains in Codex until Codex exits.

## Source packages

See [package layout and dependency boundaries](ARCHITECTURE.md). Core, Codex and
Secretive are separate native build targets; users still install one app/DMG.

## Compatibility identifiers

All current identifiers use `io.hoya.KeychainCompatibilityLayer`. The host is
`KeychainCompatibilityLayer`, the extension is `KeychainCompatibilityLayer.appex`,
the watcher is `KCLAutoApply`, and the runtime library is
`KeychainCompatibilityLayerShim.dylib`. Runtime/log directories use
`Keychain Compatibility Layer`.

`native/migration/LegacyMigration.h`, `native/migration/LegacyMigration.m` and `cmd/kcl/legacy.go` isolate upgrade
handling. The extension imports existing private material directly between
Data Protection Keychain groups, derives the public key, and the host verifies
it against the previous token before retiring its configuration. The host never
receives private bytes. Historical group entitlements are retained only on the
extension for migration; the host retains public-only access. Encrypted legacy
material is retained for recovery. Explicit purge removes both namespaces for
that instance, preventing a deleted key from being re-imported.

Old runtime and log files are archived under the new directory. Fully restart
Codex after this namespace upgrade: already-running processes keep the previous
runtime library. The original Codex bundle is never changed or copied.

## Diagnostics and safe upgrades

```sh
"$HOME/Applications/Keychain Compatibility Layer.app/Contents/MacOS/KeychainCompatibilityLayer" diagnose
./build/kcl diagnose --app /Applications/ChatGPT.app
./build/kcl install --check
```

Diagnostics are read-only and use the bundled Go executable plus macOS tools;
no Go installation is needed to run installed diagnostics. They do not dump
credentials, account identifiers or raw logs. Native analysis describes the
original vendor file, so its known faulty constraint may remain present while
the runtime compatibility layer works. A zero instruction is never treated as
proof of a fix. Unknown or ambiguous analysis is reported explicitly.

Runtime fallback is restricted to the known Keychain failure codes `-25293` and
`-25300`. Cancellation, malformed requests, missing entitlements and other errors
are preserved. Hardware-only requests continue to use the native hardware path.

Upgrades validate a staged copy before stopping the helper, atomically switch
the installed app, retain the previous version, and restore it if activation
fails. The previous loaded/stopped startup state is preserved. Installation
records `started`, `running`, `completed` or `failed` in the app-owned runtime
`install-status.json`. See [REFERENCE_REVIEW.md](../REFERENCE_REVIEW.md) for the
reviewed upstream project and checks.

## Using the original Codex app

Open the installed app. It starts its child watcher automatically; the menu bar
shows KCL with a Quit action. Use the normal Codex icon. The watcher observes
new regular launches, gracefully quits an uninstrumented Codex once and reopens
the same original app with the runtime library. A fresh PID/start-time marker
confirms loading and prevents restart loops. Existing Codex processes are left
alone; quit refusal or timeout fails closed. No global DYLD settings are installed.

Quitting the app stops the watcher. A parent-PID timer handles forced app exit.
Already-loaded code remains in Codex until it exits. There is no independent
login helper or user-facing enable/disable toggle. The retired login-agent
configuration is removed from this environment's dotfiles.

Maintainer build/install:

```sh
make all
./build/kcl install
open "$HOME/Applications/Keychain Compatibility Layer.app"
```

Status lives in
`~/Library/Application Support/Keychain Compatibility Layer/runtime/auto-apply-status.json`.
Check the recorded watcher PID and its parent, rather than the retired LaunchAgent.

The `launch-codex` CLI command is retained only as a maintainer diagnostic; there
is no manual launch button in the user interface. It refuses a second copy and
never changes original files. Runtime loading has been tested in this environment;
other security configurations may block it.

Runtime hooks only handle Codex's software-key tag namespace. Hardware-only
requests and unrelated Security calls remain unchanged. Searchable key attributes
are translated only after checking that actual token private-key export fails.
Injected environment variables are cleared so child tools do not inherit them.

## Secretive and the shared token store

See [Secretive integration](SECRETIVE.md). From 0.5.0, each published key has its
backing instance as object ID in one `key-store` token. Codex selects its own
key label; new Secretive keys use RSA-2048/RSA-SHA2-512 with per-signature macOS
authentication. Existing P-256 keys and Keychain accounts are preserved.

## Implementation

- No network listener or system framework changes. An optional per-user
  LaunchAgent provides automatic application to Codex.
- macOS starts the token extension when needed.
- Private signing material is encrypted at rest in the extension-only Data
  Protection Keychain group `io.hoya.KeychainCompatibilityLayer.Private`, using
  `WhenUnlockedThisDeviceOnly`. Only public metadata is shared with the host via
  `io.hoya.KeychainCompatibilityLayer.Public`. The host's private-group read is denied by
  macOS with `errSecMissingEntitlement`.
- Software signing requires private-key material in the extension's memory.
  It does not provide Secure Enclave hardware isolation. The CTK client interface
  rejects private-key export. Different token instances have different keys.
- Every signature requires native `deviceOwnerAuthentication`. Failure,
  cancellation, unavailability or timeout denies the operation.
- The token exposes only its public key and ECDSA signing. Decryption, key
  exchange and system login are disabled.
- Token private-key export must fail in the independent client check.
- No private key or password is logged or written to project files.

## Build and check

```sh
make all
pluginkit -a "$PWD/build/Keychain Compatibility Layer.app/Contents/PlugIns/KeychainCompatibilityLayer.appex"
"build/Keychain Compatibility Layer.app/Contents/MacOS/KeychainCompatibilityLayer" enroll
build/check discover
build/check inspect
build/check
```

The signing check requires the user to finish the native macOS authentication
dialog. It verifies the signature using the public key in a separate executable.
Its discovery query matches the token-key mechanism used by Secretive's
SmartCardSecretKit. Actual Secretive UI/SSH integration needs a separate check.

## Remove registration

```sh
"build/Keychain Compatibility Layer.app/Contents/MacOS/KeychainCompatibilityLayer" unregister
pluginkit -r "$PWD/build/Keychain Compatibility Layer.app/Contents/PlugIns/KeychainCompatibilityLayer.appex"
```

Unregistering removes token publication but retains key material. `purge` instead
deletes the specified token's private/public Keychain items through the extension:

```sh
"$HOME/Applications/Keychain Compatibility Layer.app/Contents/MacOS/KeychainCompatibilityLayer" status
"$HOME/Applications/Keychain Compatibility Layer.app/Contents/MacOS/KeychainCompatibilityLayer" audit
# Destructive: use only when the token key is no longer needed.
"$HOME/Applications/Keychain Compatibility Layer.app/Contents/MacOS/KeychainCompatibilityLayer" purge local-software
```

The default token's generic-password service is `Keychain Compatibility Layer` and its
account is `signing-key.v3`. These are identifiers, not plaintext secret files.
Earlier trial keys were retained and are not used by the installed provider.

## Related experiment

`../rc-key-fix` contains inactive earlier replacement-module experiments. They
were not installed in Codex and are not used by the runtime compatibility library.
No Codex application copy was created. The current implementation redirects its
software fallback at runtime when launched through Keychain Compatibility Layer. It is
not a system-wide replacement for every app's Secure Enclave requests.

## Verified installation

Installed at `~/Applications/Keychain Compatibility Layer.app`. macOS launches its
CryptoTokenKit extension on demand. The token itself needs no network daemon;
the optional per-user LaunchAgent handles automatic application to Codex.
The installed extension and independent client passed token discovery, P-256
signing/verification, private export rejection, denied host access to private
storage, unsupported-operation rejection, and separate token creation/deletion.
The original Codex native module hash and application signature were unchanged.

The original, unmodified native module additionally passed hardware-only rejection,
software-key creation, public-key lookup, authenticated signing, verification,
tampered-payload rejection, separate-process reopening and verification, and key
purging with the compatibility library loaded. Automatic relaunch and runtime loading were also confirmed in desktop logs.
Completion of the actual remote browser authorization flow has not been confirmed.
Native UI inspection was unavailable because Computer Use timed out.

Repeat the original-module check (the create phase needs native authentication):

```sh
DYLD_INSERT_LIBRARIES="$HOME/Applications/Keychain Compatibility Layer.app/Contents/Frameworks/KeychainCompatibilityLayerShim.dylib" KCL_SHIM_TEST=1 KCL_CHECK_STATE="$PWD/build/check-state.json" /Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node compatibility/check.cjs create
DYLD_INSERT_LIBRARIES="$HOME/Applications/Keychain Compatibility Layer.app/Contents/Frameworks/KeychainCompatibilityLayerShim.dylib" KCL_SHIM_TEST=1 KCL_CHECK_STATE="$PWD/build/check-state.json" /Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node compatibility/check.cjs reopen
```

## Legacy management commands

`install-auto` and `disable-auto` are legacy maintainer commands for the old
independent LaunchAgent. Normal DMG users do not run them. The menu-bar app owns
its watcher directly; a disabled/missing legacy LaunchAgent does not mean the
app-owned watcher is off. Inspect the current status PID and its parent process.
