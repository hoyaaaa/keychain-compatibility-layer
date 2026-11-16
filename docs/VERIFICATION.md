# Verification record

## Supported features and verified versions

Verified locally on **2026-11-16**, on **macOS 26.7.3 / Intel x86_64** without
Secure Enclave. Current KCL build: **0.5.1**. These are tested combinations,
not a minimum-version list or a guarantee for other app/OS versions.

| Target | Verified app version (build) | Supported path | Verification and limits |
| --- | --- | --- | --- |
| Shared core | KCL **0.5.1** | Software Keychain storage and CryptoTokenKit signing | Key identity preservation, host private-group denial, concurrent create/delete, and watcher lifecycle fixtures passed. Software-backed protection; no Secure Enclave hardware emulation. |
| Codex | **26.1111.21308** (**27194**) | Automatic compatibility for the specific software P-256 device-key fallback | Original native-module create/reopen/delete and hardware-only rejection passed with KCL **0.5.0 / 0.5.1**. Final browser approval and a live remote-control session are outside this verification. |
| Secretive | **4.0.0** (**1.35554366823**) | Create separate **RSA-2048 / RSA-SHA2-512** SSH keys in KCL; use Secretive's existing smart-card interface | With KCL **0.5.0**, the original UI/agent listed the key, local agent signing/verification passed, and tampered data was rejected. KCL **0.5.1** passed refactor/regression checks with unchanged signing logic; the full agent signing test was not repeated. Two authentication prompts remain; Secretive's Secure Enclave Create button is unchanged. No live SSH-server login was tested. |
| Other apps / hardware features | Not verified | No additional automatic integration | No general app compatibility, Touch ID emulation, hardware attestation, or hardware-key generation is claimed. |

Secretive's ECDSA smart-card signatures failed verification in the tested build;
this integration therefore creates RSA keys. `ssh-rsa` is the public-key format;
SSH signatures use SHA-512, not SHA-1. See [verification details](SECRETIVE.md).
