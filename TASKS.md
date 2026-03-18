# TASKS

## Docs

- [x] Link every current workspace package from `/home/agent/prg/pykoclaw-dev/README.md`
- [x] Audit root and core READMEs against current plugin entry points and commands
- [x] Fix stale package/plugin counts in `/home/agent/prg/pykoclaw-dev/CLAUDE.md`
- [x] Add dedicated READMEs for `/home/agent/prg/pykoclaw-dev/pykoclaw-slack`, `/home/agent/prg/pykoclaw-dev/pykoclaw-messaging`, and `/home/agent/prg/pykoclaw-dev/pykoclaw-vision`
- [x] Clarify private workspace vs public core-repo boundaries in root and package docs

## Pykoclaw-Slack: Thread Routing

- [ ] Fix `connection.py`: tallenna `thread_ts` `_thread_ts_map`-sanakirjaan aina kun ketjuun tulee viesti – ei vain @-maininnan yhteydessä. Nyt pehmeät triggerit (aikakatkaisu, passiiviset tarkkailijat) vastaavat päävirtaan koska `_thread_ts_map.get(effective_channel_id)` palauttaa `None`.
- [ ] Paranna `pykoclaw-slack`-agentin system prompt -injektiota ja/tai `send_slack_message`-työkalun ohjetekstiä: työkalu on tarkoitettu *aloittamaan* viestejä muilla kanavilla, ei koskaan vastaamaan ketjussa – tämä pitää olla yksiselitteisesti kirjattu ohjeistukseen niin ettei agentti käytä sitä ketjuvastauksiin.

## Pykofinder Plugin

- [x] Turn `/home/agent/prg/pykoclaw-worktrees/pykoclaw-pykofinder/.sisyphus/plans/pykoclaw-pykofinder.md` into a repo/file implementation checklist
- [x] Add core response-transform hook in `/home/agent/prg/pykoclaw-worktrees/pykoclaw-pykofinder/pykoclaw` and `/home/agent/prg/pykoclaw-worktrees/pykoclaw-pykofinder/pykoclaw-messaging`
- [x] Create `/home/agent/prg/pykoclaw-worktrees/pykoclaw-pykofinder/pykoclaw-pykofinder/` package skeleton with config, index, transform, and tests
- [x] Wire composed transformers into `/home/agent/prg/pykoclaw-worktrees/pykoclaw-pykofinder/pykoclaw-whatsapp` and `/home/agent/prg/pykoclaw-worktrees/pykoclaw-pykofinder/pykoclaw-matrix`
- [x] Add URL-image segmentation and sending support in `/home/agent/prg/pykoclaw-worktrees/pykoclaw-pykofinder/pykoclaw-whatsapp` and `/home/agent/prg/pykoclaw-worktrees/pykoclaw-pykofinder/pykoclaw-matrix`
- [x] Run focused pytest slices for core, messaging, pykofinder, WhatsApp, and Matrix changes

## Config / Data Path Resolution

- [x] Move global `.env` from `~/.local/share/pykoclaw/.env` → `~/.config/pykoclaw/.env` (XDG-compliant)
- [x] Add `$PYKOCLAW_DATA/.env` as per-workspace override (loaded when env var is set)
- [x] Use `platformdirs.user_data_path` for `settings.data` default
- [x] Apply changes to both `pykoclaw/config.py` and `pykoclaw-pykofinder/config.py`
- [x] Migrate production config: copy `~/.local/share/pykoclaw/.env` → `~/.config/pykoclaw/.env`
- [x] Add comprehensive tests (809 passing)
