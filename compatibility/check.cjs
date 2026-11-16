// Run each phase in a separate process, with the runtime shim loaded.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const crypto = require('node:crypto');
const mod = require('/Applications/ChatGPT.app/Contents/Resources/native/remote-control-device-key.node');
const state = process.env.KCL_CHECK_STATE;
const payload = Buffer.from('Unmodified Codex / Keychain Compatibility Layer compatibility check');
assert(state, 'Set KCL_CHECK_STATE to a public test-state path');

(async () => {
  assert.equal(process.env.DYLD_INSERT_LIBRARIES, undefined, 'Injection must not propagate to children');
  if (process.argv[2] === 'create') {
    await assert.rejects(mod.createDeviceKey('hardware_only'));
    const key = await mod.createDeviceKey('allow_os_protected_nonextractable');
    fs.writeFileSync(state, JSON.stringify({key}), {mode: 0o600});
    assert.equal(key.protectionClass, 'os_protected_nonextractable');
    assert.equal((await mod.getDeviceKeyPublic(key.keyId)).publicKeySpkiDerBase64, key.publicKeySpkiDerBase64);
    const signed = await mod.signDeviceKey(key.keyId, payload);
    const publicKey = crypto.createPublicKey({key: Buffer.from(key.publicKeySpkiDerBase64, 'base64'), format:'der', type:'spki'});
    assert(crypto.verify('sha256', payload, publicKey, Buffer.from(signed.signatureDerBase64, 'base64')));
    assert(!crypto.verify('sha256', Buffer.from('modified payload'), publicKey, Buffer.from(signed.signatureDerBase64, 'base64')));
    fs.writeFileSync(state, JSON.stringify({key, signed}), {mode: 0o600});
    console.log('Original module: hardware-only denied; software creation + lookup + authenticated signature + verification: PASS');
  } else {
    const {key, signed} = JSON.parse(fs.readFileSync(state));
    try {
      const reopened = await mod.getDeviceKeyPublic(key.keyId);
      assert.equal(reopened.publicKeySpkiDerBase64,key.publicKeySpkiDerBase64);
      if (signed) {
        const publicKey = crypto.createPublicKey({key:Buffer.from(reopened.publicKeySpkiDerBase64,'base64'),format:'der',type:'spki'});
        assert(crypto.verify('sha256',payload,publicKey,Buffer.from(signed.signatureDerBase64,'base64')));
      }
    } finally {
      await mod.deleteDeviceKey(key.keyId);
      await assert.rejects(mod.getDeviceKeyPublic(key.keyId));
      fs.unlinkSync(state);
    }
    console.log('Separate process: reopen + verify + purge + absence: PASS');
  }
})().catch(error => { console.error(error.message); process.exitCode=1; });
