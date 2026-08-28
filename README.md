# claude-plugin

Personal Claude Code plugin — skills, agents, hooks, and other extensions for my own workflows.

## Install

```
/plugin marketplace add djhojd/claude-plugin
/plugin install djhojd-claude-plugin@djhojd-marketplace
```

Update to the latest pushed version any time with `/plugin marketplace update djhojd-marketplace`.

## Development

Test changes locally before pushing, without installing:

```bash
claude --plugin-dir ./
```

Run `/reload-plugins` inside a session to pick up further changes.

## Structure

- `.claude-plugin/plugin.json` — plugin manifest
- `.claude-plugin/marketplace.json` — single-entry marketplace pointing back at this repo, so it can be installed with `/plugin install`
- `skills/<name>/SKILL.md` — one directory per skill
