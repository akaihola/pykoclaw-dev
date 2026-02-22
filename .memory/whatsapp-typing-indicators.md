# WhatsApp Typing Indicators

**Tags:** whatsapp, neonize, user-experience, presence
**Related:** [CLAUDE.md](../CLAUDE.md)

Neonize exposes a `send_chat_presence()` method that can show a "Writing..." indicator in the recipient's WhatsApp app.

```python
from neonize.utils.enum import ChatPresence, ChatPresenceMedia

# Show typing indicator
client.send_chat_presence(
    jid,
    ChatPresence.CHAT_PRESENCE_COMPOSING,
    ChatPresenceMedia.CHAT_PRESENCE_MEDIA_TEXT
)

# Hide typing indicator
client.send_chat_presence(
    jid,
    ChatPresence.CHAT_PRESENCE_PAUSED,
    ChatPresenceMedia.CHAT_PRESENCE_MEDIA_TEXT
)
```

This was implemented in the WhatsApp plugin to mirror the Matrix plugin's typing indicator behavior. The call must be wrapped in a `try/finally` to ensure the indicator is cleared even if the agent dispatch fails.

[CLAUDE.md]: ../CLAUDE.md
