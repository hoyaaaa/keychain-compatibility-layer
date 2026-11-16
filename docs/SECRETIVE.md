# Secretive integration

The original Secretive application is not patched, re-signed, injected, or given
a software implementation of `CryptoKit.SecureEnclave`. KCL provisions separate
SSH keys through the native CryptoTokenKit smart-card interface that Secretive
already supports. Its original Secure Enclave Create button remains unchanged.

## User flow

Open KCL, choose **Create SSH key for Secretive…**, enter a name, and copy the
public key. New keys were observed refreshing in both the original Secretive UI and agent without restarting. If a version retains stale metadata, restart Secretive and its agent using Secretive's controls. Configure
SSH_AUTH_SOCK using Secretive's own setup instructions. KCL never rewrites your
SSH configuration or adds keys to remote hosts automatically.

Keys created by this path are software RSA-2048 keys. Only RSA-SHA2-512 signing
is enabled for them; SHA-1, decryption and private export are not supported.
Every signing operation requires macOS owner authentication in the extension.
`ssh-rsa` in the public-key text identifies the key format, not SHA-1 signing.
Codex device keys remain separate P-256 keys with unchanged public identities.
This is software-backed protection, not hardware attestation or a Secure Enclave.

## Authentication prompts

The current unmodified Secretive integration prompts twice: Secretive authorizes
its agent request, then KCL independently authorizes private-key use in the token
extension. Secretive supplies an LAContext to its Security query, but the public
TKTokenSession API does not expose that authenticated context to this custom
extension. KCL does not trust a process name, a time window, or an unverified
"already authenticated" flag to skip owner authentication. This release retains
the two prompts rather than silently weakening all clients' key protection.

## Why these algorithms

The inspected Secretive source supports RSA-2048/SHA-512 in its smart-card store.
Its ECDSA smart-card path obtains X9.62 DER signatures while the current SSH writer
expects fixed-width r||s; the original agent failed `ssh-add -T` for the dedicated
ECDSA test key. KCL leaves that application behavior and the standard Security
ECDSA signature format untouched and provisions the supported RSA path instead.

Sources reviewed:

- [SmartCardStore.swift](https://github.com/maxgoedjen/secretive/blob/164aacc94e0e89a849491f31e018ac038309a6af/Sources/Packages/Sources/SmartCardSecretKit/SmartCardStore.swift)
- [KeychainTypes.swift](https://github.com/maxgoedjen/secretive/blob/164aacc94e0e89a849491f31e018ac038309a6af/Sources/Packages/Sources/SecretKit/KeychainTypes.swift)
- [OpenSSHSignatureWriter.swift](https://github.com/maxgoedjen/secretive/blob/164aacc94e0e89a849491f31e018ac038309a6af/Sources/Packages/Sources/SSHProtocolKit/OpenSSHSignatureWriter.swift)

## Token layout and compatibility

All published KCL keys are in one persistent `key-store` token. Each object ID
is its backing-key instance ID; encrypted Keychain account names do not change.
The previous per-instance tokens are migrated only after matching their public
keys. Private material remains inside the token extension. Codex lookup selects
its own canonical label within the shared token and does not select an SSH key.

Secretive chooses the first non-Secure-Enclave token. The shared store removes
ordering ambiguity between KCL keys. An independently connected smart card can
still be selected instead; disconnect it and restart Secretive to use KCL.
Other KCL public keys can be visible in Secretive: choose only **SSH — …** keys
for SSH, not a Codex device key. Secretive cannot delete smart-card keys; key
removal is handled by KCL's instance-scoped native `purge` command.

Fully restart Codex after upgrading to the shared-store version. Existing Codex
processes keep their prior runtime and token references; KCL never force-quits
or modifies the original application.

## Maintainer verification

`make test` includes public-only SSH packet/fingerprint and invalid DER checks.
No Keychain key is created by those automated tests. The opt-in token probe in
`compatibility/check-ssh-token.m` checks private export rejection, SHA-512 signing
availability, and SHA-1/decryption rejection for the dedicated integration fixture.

Manual integration uses a dedicated test key and the original Secretive agent.
`ssh-add -T` requests RSA-SHA2-256, which this Secretive path does not honor;
use the RSA-SHA2-512 signing test below instead.

```sh
"$HOME/Applications/Keychain Compatibility Layer.app/Contents/MacOS/KeychainCompatibilityLayer" ssh-create "KCL Secretive RSA integration test"
# Save only the returned public_key as test.pub. Never save private key material.
SSH_AUTH_SOCK="$HOME/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh" ssh-add -L
echo 'local signing test' > message.txt
SSH_AUTH_SOCK="$HOME/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh" ssh-keygen -Y sign -U -f test.pub -n kcl-secretive message.txt
# Build allowed_signers with: kcl-test <algorithm> <base64 public key>
ssh-keygen -Y verify -f allowed_signers -I kcl-test -n kcl-secretive -s message.txt.sig < message.txt
```

Authenticate both local prompts, verify a zero exit status and reject a modified message, then remove only
that returned test instance with `purge ID`. No remote SSH server is contacted.
Verify Secretive's vendor signature and executable hash before/after the test.

## Verified locally

The original signed Secretive UI displayed the dedicated key; its actual agent
listed it. `ssh-keygen -Y sign -U` through that agent and subsequent
`ssh-keygen -Y verify` succeeded, and modified-message verification failed as
expected. The original Secretive executable hash stayed unchanged. Codex
hardware-only rejection, software P-256 create/reopen identity, and scoped
test-key deletion also passed with the original Codex native module.
