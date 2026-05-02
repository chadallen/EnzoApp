# claude-workflow → Plugin: Evaluation & Proposal

Evaluating whether to repackage [chadallen/claude-workflow](https://github.com/chadallen/claude-workflow) as a Claude Code plugin, and what doc/structure work that implies.

---

## TL;DR

- Yes — it's a clean fit. The repo is already a coherent bundle of commands, agents, language skills, and hooks meant to be reused across projects. That's exactly the plugin shape.
- Migration is mostly mechanical: add `.claude-plugin/plugin.json`, split today's `skills/` directory into `commands/` (the `/`-invoked ones) vs `skills/` (the auto-invoked language ones), add a `hooks/hooks.json` for the Beads `SessionStart` / `PreCompact` hooks.
- Doc cost is moderate. The README's whole install/setup narrative needs a rewrite — `git clone … your-project-path` becomes `/plugin install …`, and the "copy to global" footgun goes away. `CLAUDE.example.md` and `PRD.md` need light edits only.
- Real costs: (1) once published, breaking changes affect downstream projects, so you need a version contract; (2) Beads is a runtime prerequisite the plugin can't install — has to be a documented requirement, not a bundled dep.

---

## Today's structure (observed)

```
claude-workflow/
├── README.md
├── CLAUDE.example.md
├── PRD.md
├── agents/
│   ├── code-reviewer.MD
│   └── implementer.MD
└── skills/
    ├── adr/
    ├── build-tasks/
    ├── create-tasks/
    ├── end-session/
    ├── init-project/
    ├── ios-developer/
    ├── migrate-project/
    ├── python-developer/
    ├── start-session/
    └── typescript-developer/
```

Install model today: clone the whole repo into a project path, files land in `.claude/skills/` and `.claude/agents/`. Optional `cp -r` to `~/.claude/skills/` for global use.

Two things to notice:

1. Eight of the ten `skills/` entries are user-invoked (`/start-session`, `/build-tasks`, …). In Claude Code plugin terms those are **slash commands**, not Skills. Three are auto-invoked by `implementer` / `code-reviewer` based on file type (`typescript-developer`, `python-developer`, `ios-developer`). Those *are* Skills.
2. Hooks are referenced in `CLAUDE.example.md` ("Both `SessionStart` and `PreCompact` hooks must use `bd prime --stealth`") but there's no hook config file in the repo — `/init-project` and `/migrate-project` install them into the consuming project. Under a plugin, those should ship from the plugin itself.

---

## Proposed plugin structure

```
claude-workflow/
├── .claude-plugin/
│   └── plugin.json
├── commands/
│   ├── init-project.md
│   ├── migrate-project.md
│   ├── start-session.md
│   ├── end-session.md
│   ├── create-tasks.md
│   ├── build-tasks.md
│   └── adr.md
├── agents/
│   ├── code-reviewer.md
│   └── implementer.md
├── skills/
│   ├── typescript-developer/SKILL.md
│   ├── python-developer/SKILL.md
│   └── ios-developer/SKILL.md
├── hooks/
│   └── hooks.json
├── templates/
│   ├── CLAUDE.example.md
│   └── PRD.example.md
├── README.md
└── docs/
    ├── workflow.md       # the conceptual "pieces" section, lifted out of README
    └── plugin.md         # plugin-specific install / version notes
```

Notes:

- Filename casing normalises to `.md` (current repo mixes `.MD` and `.md`).
- `CLAUDE.example.md` and `PRD.md` move under `templates/` — they're content the plugin's `/init-project` command writes into the user's project, not docs the plugin itself ships at root.
- Drop `/clear` from the commands list — that's a built-in Claude Code command, not part of this workflow.

---

## Manifest sketch

`.claude-plugin/plugin.json`:

```json
{
  "name": "claude-workflow",
  "version": "0.1.0",
  "description": "Autonomous sub-agent workflow with Beads task tracking, ADRs, and parallel implementer/reviewer loops.",
  "author": {
    "name": "Chad Allen",
    "url": "https://github.com/chadallen"
  },
  "homepage": "https://github.com/chadallen/claude-workflow",
  "repository": "https://github.com/chadallen/claude-workflow",
  "license": "MIT",
  "keywords": ["workflow", "agents", "beads", "task-tracking", "adr"],
  "requirements": {
    "claudeCode": ">=1.0.0",
    "external": [
      {
        "name": "beads",
        "command": "bd",
        "install": "brew install beads",
        "docs": "https://github.com/steveyegge/beads"
      }
    ]
  }
}
```

`hooks/hooks.json`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "*",
        "command": "bd prime --stealth"
      }
    ],
    "PreCompact": [
      {
        "matcher": "*",
        "command": "bd prime --stealth"
      }
    ]
  }
}
```

> Open questions on the manifest — verify against current Claude Code plugin spec before publishing:
> - Exact field name / shape for declaring external tool requirements (`requirements.external` is plausible but not confirmed). May need to live in README only and not the manifest.
> - Whether hooks should be inlined in `plugin.json` or sit in `hooks/hooks.json`. Both forms have appeared in docs; pick one.
> - Default discovery paths — if `commands/`, `agents/`, `skills/`, `hooks/` are auto-discovered we don't need to list them; otherwise the manifest needs explicit `commandsDir` / `agentsDir` / `skillsDir` / `hooksFile` entries.

---

## Doc-by-doc proposal

### `README.md` — major rewrite

The current README is split into "the pieces", "the skills", "first time setup", and "getting started / how to use." The structural assumption throughout is *clone-into-your-project*. That has to change.

Concrete edits:

| Section | Action |
|---|---|
| Top tagline / "let's create the world…" | Keep. |
| "The short version" | Replace `git clone … your-project-path` with `/plugin install chadallen/claude-workflow` (or whatever the marketplace URL is). Remove the "you don't need to clone" footnote later in the file — it's no longer the alternative, it's the only mode. |
| "The pieces" | Keep. Light edit: clarify that `CLAUDE.example.md` is now a template *inside the plugin* that `/init-project` materialises into the user's repo. |
| "The skills" table | Rename heading to "Commands" for the `/`-invoked entries. Keep the language skills as a separate "Skills" table with a one-line note that these are auto-invoked, not user-invoked. |
| "Want these skills available in all your projects?" callout | **Delete.** Plugin install is global by default; per-project copying is the obsolete model. |
| "First time setup for newbies" | Rewrite. Steps become: (1) install Claude Code, (2) install Beads, (3) `/plugin install …`. Drop the `git clone` and `cp -r` instructions entirely. |
| "Getting started" | Update to call out that `/init-project` and `/migrate-project` are the entry points after install — no clone step. |
| "How to use" | Mostly unchanged; the workflow loop (`/start-session` → `/build-tasks` → `/end-session`) doesn't change. |

Add a new short section: **Requirements** — Beads (`bd`) must be on PATH; the plugin's hooks invoke it directly.

Add: **Versioning** — semver, what counts as breaking (renaming a command, changing hook contracts, changing CLAUDE.md template structure that consuming projects already imported).

### `CLAUDE.example.md` — minor edits

This file becomes a template the plugin ships under `templates/` and `/init-project` writes into a consumer project. Edits needed:

- Final line "`Skills: /start-session, /end-session, /create-tasks, /build-tasks, /adr`" → rename to **Commands** to match new terminology.
- "Workflow Conventions" section currently says "Both `SessionStart` and `PreCompact` hooks must use `bd prime --stealth`" — fine for now, but worth noting these hooks are now plugin-provided, not project-local. Suggest: "Hooks are provided by the `claude-workflow` plugin; do not redefine them in `.claude/settings.json`."
- "Agent model: Never hardcode a model in agent or skill frontmatter — always use `model: inherit`" — keep, applies equally to plugin-shipped agents.

### `PRD.md` (template) — no changes

It's a generic product-requirements template. Move to `templates/PRD.example.md` and leave the content alone. `/init-project` already copies it over.

### New: `docs/plugin.md`

Short doc, plugin-specific concerns that don't belong in the user-facing README:

- How to develop the plugin locally (`/plugin install ./path/to/checkout` if supported, or symlinking into `~/.claude/plugins/`).
- Version contract: what changes break consumers, how to deprecate a command.
- How `/init-project` and `/migrate-project` interact with the plugin's templates directory (paths inside the plugin install vs. files written into the user repo).

### New: `docs/workflow.md` (optional)

Lift the "pieces" + conceptual content out of README into a longer-form doc; keep README focused on install + quick reference. Only worth doing if README starts pushing past ~250 lines after the rewrite.

---

## Risks / open questions

1. **Beads is a hard prerequisite.** Plugins can't install external CLIs. If `bd` isn't on PATH, the `SessionStart` hook fails on every session. Mitigation: have the hook script do a `command -v bd` check and print a one-line install hint instead of erroring. Worth doing as part of the migration.
2. **Per-project state coupling.** `/init-project` writes `CLAUDE.md`, `plan.MD`, `.beads/` into the consumer repo. That state is tied to a specific plugin version's templates. If the plugin's CLAUDE template changes shape later, existing projects don't auto-migrate. Need a migration strategy or an explicit "frozen at install time" stance.
3. **Command-vs-skill terminology drift.** The current README calls everything "skills". Renaming the user-invoked ones to "commands" is correct under plugin terminology but is a vocabulary shift for existing users. Worth a one-line note in the README.
4. **`.MD` vs `.md` casing.** Current repo is inconsistent. Fix during the move; some filesystems are case-sensitive and discovery may be picky.
5. **Marketplace vs. direct git install.** Decide whether to publish to a marketplace (`marketplace.json` in a separate repo) or just document `git+https` install. Direct install is simpler for v0.1; marketplace is the eventual right answer for discoverability.

---

## Suggested sequencing

1. Verify plugin manifest spec against current Claude Code docs (resolve the open questions above).
2. Branch, restructure files, add `plugin.json` + `hooks/hooks.json`, normalise casing.
3. Rewrite README install/setup sections; leave conceptual sections alone.
4. Touch up `CLAUDE.example.md` ("Skills" → "Commands"; hooks-provided-by-plugin note).
5. Smoke test: install into a fresh project, run `/init-project`, run `/start-session`, confirm hooks fire and `bd prime --stealth` runs.
6. Tag `v0.1.0`, publish.
