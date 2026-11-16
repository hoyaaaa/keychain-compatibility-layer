# Reference review

Reviewed [Jericho-Y/chatgpt-remote-control-fix](https://github.com/Jericho-Y/chatgpt-remote-control-fix)
at commit `e5e8dd3217a2b2c6604f24b657f4d34461dbc973` (MIT).
The reference scripts were read, not executed. No third-party binary patch was
applied or incorporated. Improvements were implemented separately:

- Restrict runtime fallback to the known OSStatus Keychain failure family.
  Cancellation, malformed requests, missing entitlements and other domains retain
  their native failure rather than silently creating a compatibility key.
- Provide explicit-app and normal-location discovery for a read-only diagnostic.
  Report app version, vendor signature, module hash and scoped ACL-call evidence.
  A generic zero-immediate elsewhere in the binary is not evidence of a fix;
  absent, ambiguous and zero-valued evidence is reported without claiming repair.
  No account IDs, private keys, credentials, boot arguments or raw logs are read
  or printed by the diagnostic.
- Validate the source and staged app before stopping the watcher. Atomically
  switch bundles, retain the prior version, and restore it after activation
  failure. Preserve whether the startup agent was actually loaded. `--check`
  performs preflight only. Installation lifecycle status is recorded separately.

The original Codex application and its native module are never opened for writing
or re-signed by these tools. Current processes and existing device keys are kept.
Private token export rejection remains an actual operation check, not an inferred
property based solely on a key attribute.

Checks: `compatibility/check-policy.m`, `./build/kcl diagnose --self-test`,
`go test ./cmd/kcl`, and creation/lookup/deletion through the original
vendor native module using the runtime library. Diagnostics and installation
additionally verify that the original vendor app signature remains valid.
