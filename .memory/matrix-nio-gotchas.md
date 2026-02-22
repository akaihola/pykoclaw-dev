# matrix-nio Gotchas

**Tags:** matrix, matrix-nio, gotcha, e2ee, cross-signing
**Related:** [neonize-quirks.md], [channel-dispatch.md]

Common pitfalls when working with the matrix-nio library:

1. **`room.is_group` means "unnamed room"**, NOT "group chat". DMs are
   typically unnamed, so `is_group=True` for DMs — the exact opposite of
   what you'd expect. Use `room.member_count <= 2` to detect DMs instead.

2. **`server_timestamp` is in milliseconds**, same as Neonize. Divide by
   1000 before `datetime.fromtimestamp()`.

3. **No logging without `basicConfig`** — matrix-nio doesn't configure
   Python logging. The `run` CLI command must call `logging.basicConfig()`
   or all `log.info()` calls are silently swallowed.

4. **matrix-nio has NO cross-signing support.** Bot devices appear as
   "unverified by owner" (red ⚠️ in Element) unless you bootstrap
   cross-signing via the raw Matrix CS API (`/keys/device_signing/upload`
   - `/keys/signatures/upload`). Requires `olm.pk.PkSigning` (needs a
     32-byte random seed!) and `canonicaljson`. See `pykoclaw matrix verify`.

5. **Matrix.org UIA uses `org.matrix.cross_signing_reset`**, not password
   auth, for cross-signing key uploads. The flow requires the user to
   approve via a browser URL. Don't assume `m.login.password` will work.

6. **`olm.pk.PkSigning(seed)` requires a seed argument** — it does NOT
   generate one automatically. Pass `os.urandom(32)`.

7. **Send typing indicators** — call `client.room_typing(room_id, True)`
   before agent dispatch and `False` after. Without this, Element shows
   no feedback while the agent thinks, and users assume it's broken.

8. **E2EE setup requires multiple steps:** `ClientConfig(store_sync_tokens=True)`,
   `load_store()`, `keys_upload()`, `ignore_unverified_devices=True`, and a
   `MegolmEvent` callback for undecryptable messages. Missing any one causes
   silent failures.

[neonize-quirks.md]: neonize-quirks.md
[channel-dispatch.md]: channel-dispatch.md
