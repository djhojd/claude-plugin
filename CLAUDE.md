# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`djhojd-claude-plugin`: a personal Claude Code plugin distributed through a self-wrapping marketplace in this same repo. It bundles skills (and, in the future, possibly agents/hooks) for the author's own workflows — currently just Proxmox homelab tooling.

## Repo layout

- `.claude-plugin/plugin.json` — the plugin manifest (name, version, description, `skills` array listing every skill directory).
- `.claude-plugin/marketplace.json` — a single-entry marketplace pointing back at this repo (`source: "./"`), which is what makes `/plugin install djhojd-claude-plugin@djhojd-marketplace` work. Marketplace name and plugin name are deliberately different (`djhojd-marketplace` vs `djhojd-claude-plugin`) to avoid the redundant `name@name` install syntax.
- `skills/<name>/SKILL.md` — one directory per skill, `skills/` layout (not the flat single-`SKILL.md`-at-root layout, since there's more than one skill). A skill's `scripts/` subfolder holds executables the skill's instructions shell out to.

## Adding a new skill

1. `mkdir skills/<new-skill-name>` and add `SKILL.md` with YAML frontmatter (`name`, `description`) — the `description` is what Claude matches user requests against, so make it specific with concrete trigger phrases, not generic.
2. Add the new path to the `skills` array in `.claude-plugin/plugin.json`.
3. Bump `version` in `plugin.json` (semver; a new skill is a minor bump while the plugin is pre-1.0).
4. Test locally without installing: `claude --plugin-dir ./` from the repo root, then `/reload-plugins` inside a session to pick up further edits.

## Versioning and publishing

- Bump `.claude-plugin/plugin.json`'s `version` whenever skills/agents/hooks change — installs are pinned to this field, so users only get updates when it moves.
- This is the author's only clone of the repo and the only consumer of the install flow, so squashing/amending/force-pushing on `main` is acceptable here in a way it wouldn't be on a shared repo.

## Skill content conventions (see `skills/proxmox-lxc-cifs-mount/SKILL.md` as the reference example)

- Skills in this repo are written as deep, narrative runbooks: explain *why* the problem happens before the fix, call out common wrong turns explicitly ("things that look like a fix but aren't"), and require diagnosis steps before any destructive/irreversible action.
- Shell scripts backing a skill live in that skill's `scripts/` folder and are invoked by path from `SKILL.md`, not inlined.
- Security-sensitive handling (e.g. credentials) is spelled out explicitly in both the skill prose and the script itself — never echo secrets to stdout/logs, write credential files at `chmod 600`, prefer reusing existing stored credentials over re-prompting.
