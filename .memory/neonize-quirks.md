# Neonize Quirks

**Tags:** whatsapp, neonize, gotcha
**Related:** [threading-model.md]

Two common pitfalls when working with the Neonize WhatsApp library:

1. **Timestamps are in milliseconds**, not seconds. Always divide by 1000
   before passing to `datetime.fromtimestamp()`.

2. **`client.me` is not a JID.** Use `client.me.JID` to get the JID object
   that `Jid2String()` expects.

[threading-model.md]: threading-model.md
