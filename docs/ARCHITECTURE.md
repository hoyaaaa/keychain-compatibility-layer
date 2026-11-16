# Package layout

The application ships as one app/DMG. Its source and native build targets are
separated by responsibility; no plugin loader, extra daemon or dependency is added.

```text
native/
  core/                      Shared Keychain storage, owner authentication,
                             CryptoTokenKit driver, provisioning and deletion
  integrations/
    codex/                   Codex-only runtime hooks, fallback policy,
                             launch observer and maintainer launcher
    secretive/               SSH key/public-key encoding and creation dialog
  app/                       Menu-bar lifecycle and CLI command routing
  migration/                 Historical identifiers and key-preserving upgrades
cmd/kcl/                     Go build/install/diagnostic/distribution CLI
compatibility/               Native/client integration checks and fixtures
```

## Interfaces and build targets

| Package | Public entry point | Build output |
| --- | --- | --- |
| Core | `native/core/Core.h` | `build/libKCLCore.a`, token extension |
| Codex | `native/integrations/codex/CodexIntegration.h` | `build/libKCLCodex.a`, runtime dylib, launch helper |
| Secretive | `native/integrations/secretive/SecretiveIntegration.h` | `build/libKCLSecretive.a` |
| App | `native/app/Host.m`, `native/app/Application.m` | Main app executable |

The app composes the public APIs. Both integrations use the shared token
provider; neither imports the other integration. The core has no Codex or
Secretive dependency. Backing-key type selection and authentication remain in
the provider, preserving the same cryptographic policy for every client.

The Codex runtime adapter only redirects its known software-key requests.
Secretive uses the OS token interface and does not need a runtime injection.
SSH key creation and its dialog are entirely in the Secretive integration,
not in the common app lifecycle implementation.

The extension is built separately from the public provisioning library. Its
private-group entitlement is unchanged; the host remains public-group-only.
Migration is isolated and retains historical identifiers only for existing keys.
Bundle IDs, token IDs, Keychain account names and authentication behavior do not
change in this refactor. Secretive's two authentication prompts remain unchanged.

## Verification

`make test` checks Go code, public SSH encoding and package boundaries.
`make all` builds the three static libraries and all signed native targets.
`make test-auto` exercises the original launch-observer fixture and owner exit.
`KCL_TEST_KEYS=1 go test ./cmd/kcl -run TestSSHSharedStoreConcurrent -count=1`
checks key provisioning/deletion using dedicated temporary keys.

App and DMG installation do not require these development tools. CI keeps the
same version-tag validation and DMG upload workflow; the new `native/` tree is
also included in maintainer source archives.
