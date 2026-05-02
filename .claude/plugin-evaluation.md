# claude-workflow → Plugin: Evaluation & Proposal

Evaluating whether to repackage [chadallen/claude-workflow](https://github.com/chadallen/claude-workflow) as a Claude Code plugin, and what doc/structure work that implies.

---

## TL;DR

- Yes — it's a clean fit. The repo is already a coherent bundle of commands, agents, language skills, and hooks meant to be reused across projects. That's exactly the plugin shape.
- Migration is mostly mechanical: add `.claude-plugin/plugin.json`, split today's `skills/` directory into `commands/` (the `/`-invoked ones) vs `skills/` (the auto-invoked language ones), add a `hooks/hooks.json` for the Beads `SessionStart` / `PreCompact` hooks.
- Doc cost is moderate. The README's whole install/setup narrative needs a rewrite — `git clone … your-project-path` becomes `/plugin install …`, and the "copy to global" footgun goes away. `CLAUDE.example.md` and `PRD.md` need light edits only.
- The biggest substantive risk isn't the package format — it's that `/init-project` *bootstraps state* into the consumer's repo (CLAUDE.md, plan.MD, .beads/). That state forks at install time and has no clean upgrade story. Plan for this before v0.1 instead of after.
- Plugin commands and skills are **auto-namespaced** (`/claude-workflow:start-session`, not `/start-session`). That's a real UX shift, not a cosmetic one. Worth aliasing or accepting upfront.

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

Per the current plugin spec, only `name` is required; everything else is optional metadata. Auto-discovery handles `commands/`, `agents/`, `skills/`, `hooks/hooks.json` if you use the conventional layout, so the manifest stays small.

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
  "keywords": ["workflow", "agents", "beads", "task-tracking", "adr"]
}
```

Notes on what's *not* in the manifest:

- **No `requirements.external` field exists.** Beads-as-prerequisite has to be documented in the README and enforced at hook-runtime (the hook script does `command -v bd` and prints an install hint if missing). The manifest can't gate install on a binary being present.
- **`userConfig`** is available if you want to prompt the user at enable time for things like a default LTHR, default branch name, or remote-marketplace URL — skipping for v0.1.
- **`dependencies`** is for plugin-to-plugin deps with semver constraints. Not relevant here unless you spin language skills out into companion plugins later.
- **Versioning choice**: with `"version": "0.1.0"` set, consumers only get updates when you bump the field. Omit `version` and every commit to your default branch becomes an update. Recommendation: keep an explicit version — better upgrade discipline.

`hooks/hooks.json`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "*",
        "hooks": [
          { "type": "command", "command": "bd prime --stealth" }
        ]
      }
    ],
    "PreCompact": [
      {
        "matcher": "*",
        "hooks": [
          { "type": "command", "command": "bd prime --stealth" }
        ]
      }
    ]
  }
}
```

(Hook entries take a `type` — `command` is the right choice here. Other types: `http`, `mcp_tool`, `prompt`, `agent`. All hooks from user/project/plugin sources execute together; precedence for blocking decisions is `deny > defer > ask > allow`.)

---

## Future: LSP integration (out of scope for v0.1)

The plugin spec supports declaring LSP servers (`tsserver`, `pyright`, `sourcekit-lsp`, etc.). Worth a deliberate "not yet" rather than silence — it's the obvious next question once you're already shipping language-aware tooling.

**Skills and LSPs are not substitutes; they cover different surfaces.**

| | LSP server | Language skill |
|---|---|---|
| Source of truth | The compiler / language toolchain | The team's conventions |
| Updates when | Code changes | You change your mind about how to write code |
| Strong at | Types, diagnostics, find-usages, real refactors | Style, idioms, "we don't do X here" |
| Wrong tool for | "Prefer Result over throwing" | "What's the type of this expression" |

Today the `implementer` and `code-reviewer` agents load a skill (prose conventions) and then act with grep-and-pattern-match semantics. They have no compiler view of the code. Adding LSPs would let those agents query `tsserver` for the actual type of a symbol before changing it, or pull real diagnostics after an edit instead of waiting for a build to fail. Strict upgrade, no overlap with what the skills already do.

**Why not in v0.1:**

- **Per-language runtime prerequisite, multiplied.** Beads-as-prerequisite is one binary on PATH. LSPs add one *per language* — `tsserver`, `pyright` (or `pylsp`), `sourcekit-lsp`. Each has its own install story and version drift. Same hook-time `command -v` check pattern, but now N of them.
- **Scope.** v0.1 is already shipping a state-bootstrapping plugin with a hook trust model and a namespace UX shift. "Also we run language servers" is a separable concern.
- **Skill content stays the same regardless.** Whether or not you add LSPs later, the existing TS/Python/iOS skills don't need to change — they're orthogonal. So adding LSPs is purely additive future work, not a migration item.

**v0.2+ shape, sketched:** declare the LSP servers in `plugin.json`, ship a hook-time check that warns if any are missing, update the `implementer` agent's prompt to mention "use available LSP tools to verify types/diagnostics before and after edits." Skills stay exactly as they are.

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
| "The skills" table | Rename heading to "Commands" for the `/`-invoked entries. Keep the language skills as a separate "Skills" table with a one-line note that these are auto-invoked, not user-invoked. **Note**: plugin commands are automatically prefixed (`/claude-workflow:start-session`). Decide whether to document the namespaced form, alias, or accept the longer command names. |
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

## Risks

Severity ordered. The first two could meaningfully change scope or sequencing; the rest are "know about it before shipping."

### 1. Per-project state coupling — the real risk

`/init-project` doesn't just register commands. It *forks state* into the consumer's repo: `CLAUDE.md`, `plan.MD`, `.beads/` all get materialised from plugin templates and then live there forever, owned by the user. The plugin and the consumer's files diverge from minute one.

That's fine until v0.2 ships with a different `CLAUDE.md` shape — a renamed convention, a new section, a tweaked commit format, a different hook command. Every project that ran `/init-project` against v0.1 keeps the old shape. Agents in those projects keep emitting v0.1-style commits, reading v0.1-style plans, against a plugin that's moved on. Nothing crashes — it just rots silently.

This is fundamentally different from a plugin that only provides commands. You're a *bootstrapper*, and bootstrappers age badly. Options:

- **Version-stamp the templates.** `<!-- claude-workflow v0.1.0 -->` header in the generated CLAUDE.md so a future `/migrate-project --sync` can detect drift and offer to rebase user customisations. Cheap to add now; expensive to retrofit later.
- **Make `/migrate-project` re-runnable as a template-sync.** Diff the user's CLAUDE.md against the current plugin template, three-way merge. Real engineering work.
- **Move runtime conventions out of CLAUDE.md and into the plugin.** Have agents read commit-format / hook-contract / etc. from the plugin itself, so updates propagate without touching user files. Architecturally cleaner, biggest scope.
- **Accept the fork. Document it.** "Your CLAUDE.md is yours. Manual migration on plugin upgrade." Honest, ships fastest, worst UX.

Recommendation: do option 1 in v0.1 (template version-stamp costs nothing) and defer the rest until you've felt the pain on a second project.

### 2. Stale global copies will shadow the plugin

The current README explicitly tells users to `cp -r .claude/skills/* ~/.claude/skills/` for global access. Anyone who followed that advice has copies of every command and agent at `~/.claude/skills/start-session/`, `~/.claude/agents/code-reviewer.MD`, etc. After plugin migration, the plugin installs to `~/.claude/plugins/cache/claude-workflow/<version>/`.

Both will load. Plugin skills are namespaced (`/claude-workflow:start-session`) so they technically don't collide — but the user's stale `/start-session` from `~/.claude/skills/` still works, and points at the old code. Same for agents. The user will think they're on the new version and silently be running the old one.

First step in the migration README has to be: "If you previously copied this repo's contents into `~/.claude/`, delete those copies before installing the plugin." With a one-line script that lists what to remove.

### 3. Hook trust model

`SessionStart` runs `bd prime --stealth` automatically, unsandboxed, with the user's privileges. That's fine for a known maintainer, known command. Two failure modes worth knowing about:

- **Compromised maintainer / bad release.** A future malicious release (or a hijacked GitHub account) could swap the hook command for anything. Hook scripts have no signing, no verification, no sandbox. Auto-update is *off* by default for community-hosted plugins (only Anthropic-maintained marketplaces auto-update), which softens this — but users who explicitly enable auto-update inherit the risk.
- **The autonomous-walk-away mode (`/build-tasks --auto`) makes blast radius worse.** Whatever a hook runs in that mode happens unobserved.

Mitigations: tell users to pin to a tag (`/plugin install …@v0.1.0`), document "review the hook diff on every plugin update," eventually code-sign. None of these are migration blockers, but the threat model is qualitatively new vs. the current "you cloned a git repo, you can read the files" model.

### 4. Uninstall semantics

Good news / bad news:

- Good: `/plugin uninstall` removes the plugin's cache directory and its plugin-data directory (use `--keep-data` to preserve), but does *not* touch files inside the user's project repo. So `CLAUDE.md`, `plan.MD`, `.beads/` survive uninstall — that's correct, those are the user's data.
- Bad: the commands that read those files disappear. The user's repo is left holding files no agent knows what to do with. `bd ready` still works (Beads is a separate CLI), but `/build-tasks` is gone.

Document it in the README: "Uninstalling removes the workflow commands but leaves your project state in place. Delete `CLAUDE.md`, `plan.MD`, and `.beads/` manually if you're done with the workflow."

### 5. Auto-namespacing is a real UX shift

Plugin commands and skills get prefixed with the plugin name: `/claude-workflow:start-session` instead of `/start-session`. This prevents collisions across plugins (good) but also means every command in the README, every reference in `CLAUDE.example.md`, every muscle-memory keystroke gets longer.

Options:
- Accept the longer names and update all docs.
- Ship a `commands/aliases/` set of short-named commands that just delegate to the namespaced ones (if the spec allows; verify).
- Encourage users to set up their own short aliases in personal settings.

Worth deciding before publishing — flip-flopping later breaks every existing reference.

### 6. Beads as a runtime prerequisite

Plugins can't install external CLIs. If `bd` isn't on PATH, the `SessionStart` hook fails on every session. Specific failure modes to handle:

- **Missing on first install.** Have the hook script `command -v bd >/dev/null || { echo "Beads not installed: brew install beads"; exit 0; }`. Exit 0, not non-zero — don't block sessions over a missing optional dep at startup.
- **Cross-machine sync.** A user installs the plugin on their Mac (has `bd`), syncs their Claude config to a Linux box (no `bd`). Same fix above handles it.
- **Beads itself is alpha.** The `--stealth` flag is a Beads-specific contract. If Beads renames it, every consumer breaks at SessionStart simultaneously. Pin the documented Beads version range in the README's Requirements section.

### 7. Hidden coupling between agents and skill names

Per CLAUDE.example.md: "The `implementer` and `code-reviewer` agents automatically invoke a language skill at the start of each task based on the files being touched." The agents reference language skills *by name* in their prompts. If the plugin renames or removes a skill, the agents silently stop matching — no compile-time error, just degraded behavior on TS/Python/iOS work.

Worth a smoke-test in CI: boot each agent against representative file types and assert the right skill loads. Cheap insurance.

### 8. Language-skill backlog

Once published, every user wants their language. TS/Python/iOS today; tomorrow Rust, Go, Java, Ruby, Kotlin, PHP. You either:

- Become a meta-language repo (maintenance balloon, you don't write Ruby).
- Define a skill contract and let third parties ship companion plugins (`claude-workflow-rust`, etc.) that depend on the core. More upfront design, scales better.
- Stay opinionated, reject PRs, watch a fork ecosystem emerge.

No urgency for v0.1 but worth a stance in the README so PR authors aren't surprised.

### 9. Cosmetic / mechanical

- **`.MD` vs `.md` casing.** Current repo is inconsistent. Fix during the move; Linux is case-sensitive and discovery may be picky.
- **Marketplace vs. direct git install.** Direct install (`/plugin install <git-url>@<tag>`) is fine for v0.1. Marketplace is the eventual right answer for discoverability and version listings — defer until there's actual demand.
- **`/clear` is a built-in.** Drop it from the workflow's command list; it's a Claude Code primitive, not yours to ship.

### Softening factors worth knowing

- **7-day cache grace period on updates.** When a plugin updates mid-session, the old version stays cached for 7 days. Existing sessions keep running against the old version; new sessions get the new one. Mid-flight breaking-change risk is much smaller than I initially worried.
- **Plugin skills are namespaced.** Collisions with other plugins' commands/skills are essentially eliminated by construction (the trade-off being risk #5 above).
- **Auto-update is off by default for community plugins.** Users have to opt in per marketplace, so most won't be on the bleeding edge unless they want to be.

---

## Suggested sequencing

1. Verify plugin manifest spec against current Claude Code docs (resolve the open questions above).
2. Branch, restructure files, add `plugin.json` + `hooks/hooks.json`, normalise casing.
3. Rewrite README install/setup sections; leave conceptual sections alone.
4. Touch up `CLAUDE.example.md` ("Skills" → "Commands"; hooks-provided-by-plugin note).
5. Smoke test: install into a fresh project, run `/init-project`, run `/start-session`, confirm hooks fire and `bd prime --stealth` runs.
6. Tag `v0.1.0`, publish.
