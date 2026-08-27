# claude-plugin

Personal Claude Code plugin — skills, agents, hooks, and other extensions for my own workflows.

## Install

The repo is private, so `gh auth login` (or an SSH key loaded in `ssh-agent`) must already grant access.

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
- `SKILL.md` — this plugin's skill (single-skill layout; move to `skills/<name>/SKILL.md` if it grows to more than one)
