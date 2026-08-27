# claude-plugin

Personal Claude Code plugin — skills, agents, hooks, and other extensions for my own workflows.

## Development

Test locally without installing:

```bash
claude --plugin-dir ./
```

Run `/reload-plugins` inside a session to pick up changes.

## Structure

- `.claude-plugin/plugin.json` — plugin manifest
- `SKILL.md` — this plugin's skill (single-skill layout; move to `skills/<name>/SKILL.md` if it grows to more than one)
