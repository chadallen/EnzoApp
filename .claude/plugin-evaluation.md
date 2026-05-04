# claude-workflow → Plugin: Evaluation & Proposal

Evaluating whether to repackage [chadallen/claude-workflow](https://github.com/chadallen/claude-workflow) as a Claude Code plugin, and what the resulting plugin should look like.

---

## TL;DR

- Yes — it's a clean fit, and the design simplifies dramatically once you commit to a *"plugin manages no files in the user's repo"* rule.
- The plugin's surface is six elements: a SessionStart hook (injects conventions into context) and five slash commands (`/start-session`, `/end-session`, `/create-tasks`, `/build-tasks`, `/adr`).
- Workflow conventions live inside the plugin (`docs/conventions.md`), prepended to context every session via the SessionStart hook — same pattern as `bd prime`. They never get materialized into user files, so they never go stale.
- The bootstrap commands (`/init-project`, `/migrate-project`) go away. Their only valuable function — turning a PRD into a starter set of Beads issues — gets absorbed into `/create-tasks`, which now accepts a path: `/create-tasks PRD.md`. `bd init` runs automatically on first invocation if `.beads/` is missing.
- `/start-session` becomes a trampoline: it checks state and tells the user what's next ("install bd," "no tasks; write a PRD," "here's ready work"). One command, four states, always points at the right next step.
- `plan.MD` is killed. "Current status" lives in a designated Beads issue.
- Risk #1 (per-project state coupling) from the previous draft collapses to a paragraph, because there are no plugin-managed files in user repos to drift. The proposed migration runner is no longer needed.
- Auto-namespacing (`/<plugin-name>:start-session`) is still a real UX shift. Otherwise, doc cost is light: the README install flow needs a rewrite, and that's most of it.

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

Two structural notes:

1. Eight of the ten `skills/` entries are user-invoked (`/start-session`, `/build-tasks`, …). In Claude Code plugin terms those are **slash commands**, not Skills. Three are auto-invoked by `implementer` / `code-reviewer` based on file type (`typescript-developer`, `python-developer`, `ios-developer`). Those *are* Skills.
2. Hooks are referenced in `CLAUDE.example.md` ("Both `SessionStart` and `PreCompact` hooks must use `bd prime --stealth`") but there's no hook config file in the repo — `/init-project` and `/migrate-project` install them into the consuming project. Under the plugin model, the `bd prime` hooks come from `bd init` (Beads writes them itself when initialized) and the plugin's own SessionStart hook handles conventions injection.

---

## Proposed plugin structure

```
claude-workflow/
├── .claude-plugin/
│   └── plugin.json
├── commands/
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
│   └── hooks.json              # SessionStart hook for conventions injection
├── scripts/
│   └── inject-conventions.sh   # reads docs/conventions.md, prepends to context
├── docs/
│   ├── conventions.md          # plugin-internal: workflow rules, commit format, etc.
│   ├── plugin.md               # plugin developer notes
│   └── workflow.md             # optional: longer-form conceptual doc
└── README.md
```

Notes:

- **No `templates/` directory.** The plugin doesn't ship CLAUDE.md or PRD.md templates. Built-in `/init` already produces a project-aware CLAUDE.md before the user installs the plugin. PRDs are user-authored content the plugin reads on demand — not something to template.
- **No `init-project.md` or `migrate-project.md` commands.** Their only valuable function (PRD → Beads ingestion) absorbs into `/create-tasks`. `bd init` happens automatically when `/create-tasks` is run against an uninitialized repo.
- Filename casing normalises to `.md` (current repo mixes `.MD` and `.md`).
- Plugin name when published needs to be **kebab-case, no spaces or dots** (e.g., `loop-fork-pizza`). The `fork.pizza` domain can live in `homepage` and branding; the manifest name has to match the plugin spec's validation rule.

---

## Manifest sketch

Per the plugin spec, only `name` is required; everything else is optional. Auto-discovery handles `commands/`, `agents/`, `skills/`, `hooks/hooks.json` if you use the conventional layout, so the manifest stays small.

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

- **No `requirements.external` field exists.** Beads-as-prerequisite has to be documented in the README and enforced at hook-runtime + slash-command-runtime (see `/start-session` trampoline below). The manifest can't gate install on a binary being present.
- **`userConfig`** is available if you want to prompt the user at enable time for things like a default branch name — skipping for v0.1.
- **`dependencies`** is for plugin-to-plugin deps with semver constraints. Not relevant here unless you spin language skills out into companion plugins later.
- **Version is explicit, not omitted.** With `"version": "0.1.0"` set, consumers only get updates when you bump the field. Omit `version` and every commit to your default branch becomes an update — strict upgrade discipline disappears.

`hooks/hooks.json`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "*",
        "hooks": [
          { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/scripts/inject-conventions.sh" }
        ]
      }
    ]
  }
}
```

The hook script reads `${CLAUDE_PLUGIN_ROOT}/docs/conventions.md` and prepends it to context. Same shape as `bd prime`, just with workflow conventions instead of Beads state. The script should also do a `command -v bd` check and print a soft install hint if Beads is missing — exits 0 to avoid blocking the session.

**Two things intentionally not in `hooks/hooks.json`:**

1. **`bd prime --stealth` hooks.** `bd init` writes these into the consumer's `.claude/settings.json` directly. Plugin shouldn't duplicate them — Beads owns its own lifecycle, and double-priming runs `bd prime` twice per session.
2. **A migration runner.** No plugin-managed files in user repos means nothing to migrate. The previous draft included a SessionStart-driven migration script for managed-region content in CLAUDE.md / plan.MD; that's gone now.

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
- **Scope.** v0.1 is already shipping a plugin with a hook trust model and a namespace UX shift. "Also we run language servers" is a separable concern.
- **Skill content stays the same regardless.** Whether or not you add LSPs later, the existing TS/Python/iOS skills don't need to change — they're orthogonal. So adding LSPs is purely additive future work.

**v0.2+ shape, sketched:** declare the LSP servers in `plugin.json`, ship a hook-time check that warns if any are missing, update the `implementer` agent's prompt to mention "use available LSP tools to verify types/diagnostics before and after edits." Skills stay exactly as they are.

---

## Doc-by-doc proposal

### `README.md` — major rewrite

The current README is built around clone-into-your-project. That has to go. The new install flow:

```
1. /init                       (Claude Code built-in → CLAUDE.md)
2. /plugin install <source>
3. /start-session              (tells you "install bd")
4. brew install beads          (or platform equivalent)
5. /start-session              (tells you "write a PRD or describe work")
6. write PRD.md
7. /create-tasks PRD.md        (auto-runs bd init, ingests PRD)
8. /start-session              (shows ready work)
9. /build-tasks
```

The user never has to remember the right next command — `/start-session` always tells them. Same pattern as `git status`.

Concrete README edits:

| Section | Action |
|---|---|
| Top tagline | Keep. |
| "The short version" | Replace with the install flow above. |
| "The pieces" | Keep, but trim — the plugin no longer materializes templates. |
| "The skills" table | Rename to "Commands." Note the namespace prefix (`/<plugin-name>:start-session`). Keep language skills as a separate "Skills" table noting they're auto-invoked. |
| "Want these skills available in all your projects?" callout | **Delete.** Plugin install is global by default. |
| "First time setup for newbies" | Rewrite around the install flow above. |
| "Getting started" | Update — entry point is `/start-session`, which trampolines to the right next step. |
| "How to use" | Mostly unchanged; the `/start-session` → `/build-tasks` → `/end-session` loop is the same. |

Add: **Requirements** section — Beads (`bd`) on PATH, with install instructions per platform.
Add: **Versioning** section — semver, what counts as breaking (renaming a command, changing hook contracts).

### `CLAUDE.example.md` — section deleted

Was: a template the plugin would ship and `/init-project` would materialize. Now: not a thing. Built-in `/init` produces CLAUDE.md before the plugin is installed, and the plugin never touches it. Workflow conventions that previously lived in this template move into the plugin's `docs/conventions.md`, injected via SessionStart hook.

### `PRD.md` — user-authored, not shipped

PRDs are user content the plugin consumes. Plugin doesn't ship a template; the user writes one and points `/create-tasks` at it. The repo's existing `PRD.md` (a generic product-requirements scaffold) can become an optional reference doc in the README — *"here's a starting structure, but write whatever you want."*

### New: `docs/conventions.md`

Plugin-internal. Holds the workflow rules that previously lived in the user's `CLAUDE.md`:

- Beads CLI usage (`--json` flag, etc.)
- Commit format (`<message> (<task-id>)`)
- Hook commands (`bd prime --stealth`, not `bd prime`)
- "scratch.md is always in .gitignore, never read"
- The Workflow / Agents / Task Tracking sections from today's `CLAUDE.example.md`

Loaded into context every session by the SessionStart hook. When you change the rules in v0.2, every project running the new plugin version gets the new rules on next session — no migration required, nothing in user files to update.

### New: `docs/plugin.md`

Plugin developer notes:

- Local development (`/plugin install ./path/to/checkout` if supported, or symlinking).
- Version contract: what changes break consumers, how to deprecate a command.
- Auto-namespacing implications for command references.

### New: `docs/workflow.md` (optional)

Lift the conceptual content out of README into a longer-form doc; keep README focused on install + quick reference. Only worth doing if README starts pushing past ~250 lines after the rewrite.

---

## Skill-by-skill changes

### `/init-project` and `/migrate-project` — deleted

Both go away in the plugin. Their valuable function — turning a PRD into a starter set of Beads issues — gets absorbed into `/create-tasks PRD.md`. `bd init` happens transparently on first `/create-tasks` if `.beads/` is missing.

What this drops: hand-written CLAUDE.md scaffolding (built-in `/init` does this), plan.MD scaffolding (no longer a file), template materialization (no templates), the "URL contains claude-workflow" stop check (irrelevant under plugin install).

### `/start-session` — trampoline

Promotes from "minor" to a real responsibility. The slash command checks state and tells the user what's next:

| State | Output |
|---|---|
| `bd` not installed | "Install Beads: `brew install beads`. Then re-run." |
| `bd` installed, no `.beads/` or no issues | "No tasks yet. `/create-tasks PRD.md`, or describe work." |
| Tasks exist | "N issues open, M ready: …" + summary of ready work |

One command, three states, always tells you what's next. Same pattern as `git status` — bootstrap and steady-state use the same command.

The SessionStart hook (separate from the slash command) handles automatic conventions injection — fires every session whether or not the user types `/start-session`.

### `/end-session` — small

References `bd doctor` only working in server mode and skips in embedded — that's a Beads detail, not a plugin concern. Update: also write a current-status summary to a designated Beads issue (replaces the old `plan.MD` update step). Otherwise unchanged.

### `/create-tasks` — absorbs PRD ingestion + chat-native UX

The biggest behavioral change in the plugin. Replaces `proposal.md` / `plan.MD` writing with a chat-native flow:

- **Accepts a source path:** `/create-tasks PRD.md` for bulk PRD ingestion; `/create-tasks` (no args) uses recent chat context.
- **Auto-runs `bd init`** if `.beads/` is missing — transparently. The user doesn't need to know it's bootstrapping Beads on first run.
- **No intermediate planning file.** Writes directly to Beads. The conversation is the working surface; Beads is the durable record.
- **Render created issues inline in `bd show` shape.** After creation, print a compact summary (`id  priority  title  blocks/depends`) so the user sees exactly what was written without leaving chat. If they want full detail on a specific issue, they ask and Claude runs `bd show <id>` inline.
- **React to free-text edits.** *"Drop bug-25, bump bug-26 to P1"* → Claude executes `bd close bug-25 --reason "..."` and `bd update bug-26 --priority 1` in the same turn. No second confirmation loop.

### `/build-tasks` — keystroke gate enforced architecturally

- **Human-keystroke gate** between `/create-tasks` and `/build-tasks` is enforced architecturally — they're separate slash commands, each requires explicit user invocation. The "review pause" is the gap between commands; no status flag or approval marker needed.
- **`/create-tasks` must never auto-invoke `/build-tasks`.** Resist the temptation to chain them ("you've created tasks, want me to start building?"). That collapses one keystroke into the gate for both, which is the failure mode.
- **`--auto` mode bypasses the gate by design.** Document in README that `/build-tasks --auto` skips the review pause — that's the trade the user opts into when they pass `--auto`.

### `/adr` — namespace prefix only

Reads project state and writes ADR files. Unchanged behavior; just gets the namespace prefix in docs (`/<plugin-name>:adr`).

### `implementer` and `code-reviewer` agents — small

Both reference CLAUDE.md for "test command, lint command, project conventions." Test/lint commands stay in user CLAUDE.md (project facts, written by built-in `/init`). The "project conventions" reference splits: project conventions stay in CLAUDE.md, workflow conventions come from the plugin's injected context (no agent change needed — context is just *there*). Worth a prompt edit to remove explicit "see CLAUDE.md for commit format" references.

### Language skills — no functional changes

`typescript-developer`, `python-developer`, `ios-developer` are pure prose conventions, auto-loaded by the agents based on file types touched. Move into `skills/` under the plugin layout. The `ios-developer` skill is notably more verbose than the other two and is mostly "I know iOS" rather than "here are catches" — worth a separate pruning pass but not blocking.

---

## Risks

Severity ordered. The previous draft's risk #1 (per-project state coupling) collapses entirely under this design, because there are no plugin-managed files in user repos to drift. Other risks are mostly unchanged.

### 1. Stale global copies will shadow the plugin

The current README explicitly tells users to `cp -r .claude/skills/* ~/.claude/skills/` for global access. Anyone who followed that has copies of every command and agent at `~/.claude/skills/start-session/`, `~/.claude/agents/code-reviewer.MD`, etc.

After plugin migration, the plugin installs to its own cache directory under `~/.claude/`. Both will load. Plugin commands are namespaced (`/<plugin-name>:start-session`) so they technically don't collide — but the user's stale `/start-session` from `~/.claude/skills/` still works, and points at the old code. Same for agents. The user will think they're on the new version and silently be running the old one.

First step in the migration README has to be: *"If you previously copied this repo's contents into `~/.claude/`, delete those copies before installing the plugin."* With a one-line script that lists what to remove.

### 2. Hook trust model

`SessionStart` runs the conventions-injection script automatically, unsandboxed, with the user's privileges. The script reads from `${CLAUDE_PLUGIN_ROOT}/docs/conventions.md` — content the plugin author controls. A future malicious release (or a hijacked GitHub account) could swap the script for anything.

Hook scripts have no signing, no verification, no sandbox. Plugins are cached locally and don't auto-fetch on session start, so a user has to explicitly run `/plugin update` to pull a new version — that's the soft mitigation. But once they do, the new hook command runs unsandboxed on the next session.

The autonomous-walk-away mode (`/build-tasks --auto`) makes blast radius worse. Whatever a hook runs in that mode happens unobserved.

Mitigations: tell users to pin to a tag (`/plugin install …@v0.1.0`), document "review the hook diff on every plugin update," eventually code-sign. None of these are migration blockers, but the threat model is qualitatively new vs. the current "you cloned a git repo, you can read the files" model.

### 3. `/plugin update` may not actually update

There are open Claude Code issues (anthropics/claude-code#15642 and #29071) reporting that `/plugin update` runs `git fetch` against the remote but does not fast-forward the local clone — so the cache stays on the old commit even after the user explicitly tries to update. `CLAUDE_PLUGIN_ROOT` then points at a stale version with no obvious signal that the update silently no-op'd.

Practical consequences:

- A user who runs `/plugin update` after a bug fix may keep hitting the bug.
- Security fixes (especially to hook scripts, see risk #2) won't reach users who think they updated.
- Debugging "did the update apply?" becomes part of every support conversation.

Workaround until the upstream issues are fixed: tell users in the README to `/plugin uninstall <plugin-name> && /plugin install …@<tag>` for upgrades rather than `/plugin update`. Ugly but reliable. Re-evaluate when the issues close.

### 4. Uninstall semantics — cleaner under this design

Now that the plugin doesn't write files into the user's repo:

- `/plugin uninstall` removes the plugin's cache directory and plugin-data directory.
- The user's project files (CLAUDE.md, PRD.md, .beads/) are entirely user-owned and survive uninstall correctly.
- The only orphaned thing is `.beads/` — which is Beads's domain, not the plugin's. The user can `rm -rf .beads` and uninstall `bd` if they're done with the workflow entirely.

Document in the README: *"Uninstalling removes the workflow commands but leaves your project state in place. Your tasks and ADRs survive."*

This is cleaner than the previous proposal, which left `plan.MD` and managed regions in CLAUDE.md as orphans.

### 5. Auto-namespacing is a real UX shift

Plugin commands and skills get prefixed with the plugin name: `/<plugin-name>:start-session` instead of `/start-session`. This prevents collisions across plugins (good) but every command in the README and every muscle-memory keystroke gets longer.

Options:
- Accept the longer names and update all docs.
- Encourage users to set up their own short aliases in personal settings.
- Ship `commands/aliases/` short-named delegators (verify spec allows).

Worth deciding before publishing — flip-flopping later breaks every existing reference.

### 6. Beads as a runtime prerequisite

Plugins can't install external CLIs. If `bd` isn't on PATH, the SessionStart hook soft-fails (exits 0 with a hint), `/start-session` prompts "install Beads," and `/create-tasks` does the same check before doing anything. Specific failure modes:

- **Missing on first install.** Hook script does `command -v bd >/dev/null || { echo "Beads not installed: brew install beads"; exit 0; }`. Slash commands print conversational guidance.
- **Cross-machine sync.** A user installs the plugin on Mac (has `bd`), syncs Claude config to Linux (no `bd`). Same fix above handles it.
- **Beads itself is alpha.** The `--stealth` flag is a Beads-specific contract. If Beads renames it, every consumer breaks at SessionStart simultaneously. Pin the documented Beads version range in the README's Requirements section.

`/start-session`'s trampoline behavior makes this graceful — the user runs `/start-session`, gets a clear install instruction, comes back. No mysterious failures.

### 7. Hidden coupling between agents and skill names

The `implementer` and `code-reviewer` agents reference language skills *by name* in their prompts. If the plugin renames or removes a skill, the agents silently stop matching — no compile-time error, just degraded behavior on TS/Python/iOS work.

Worth a smoke-test in CI: boot each agent against representative file types and assert the right skill loads. Cheap insurance.

### 8. Language-skill backlog

Once published, every user wants their language. TS/Python/iOS today; tomorrow Rust, Go, Java, Ruby, Kotlin, PHP. You either:

- Become a meta-language repo (maintenance balloon, you don't write Ruby).
- Define a skill contract and let third parties ship companion plugins (`<plugin-name>-rust`, etc.) that depend on the core. More upfront design, scales better.
- Stay opinionated, reject PRs, watch a fork ecosystem emerge.

No urgency for v0.1 but worth a stance in the README so PR authors aren't surprised.

### 9. Cosmetic / mechanical

- **`.MD` vs `.md` casing.** Current repo is inconsistent. Fix during the move; Linux is case-sensitive and discovery may be picky.
- **Plugin name is kebab-case only.** No spaces, no dots — `fork.pizza` won't pass validation as a manifest name. The dotted form lives in `homepage` and branding; the manifest name needs to be like `loop-fork-pizza`.
- **Marketplace vs. direct git install.** Direct install (`/plugin install <git-url>@<tag>`) is fine for v0.1. Marketplace is the eventual right answer for discoverability and version listings — defer until there's actual demand.
- **`/clear` is a built-in.** Drop it from the workflow's command list — it's a Claude Code primitive, not yours to ship.

### Softening factors worth knowing

- **7-day cache grace period on updates.** When a plugin updates mid-session, the old version stays cached for 7 days. Existing sessions keep running against the old version; new sessions get the new one. Mid-flight breaking-change risk is much smaller than I initially worried.
- **Plugin commands are namespaced.** Collisions with other plugins' commands/skills are essentially eliminated by construction (the trade-off being risk #5).
- **No auto-fetch on session start.** Plugins load from a local cache; updates require an explicit `/plugin update`. So mid-flight breaking changes can't ambush an active user.

---

## Suggested sequencing

1. Verify plugin manifest spec against current Claude Code docs.
2. Branch, restructure files: add `.claude-plugin/plugin.json`, `hooks/hooks.json`, `scripts/inject-conventions.sh`, `docs/conventions.md`. Delete `init-project/`, `migrate-project/`, the templates concept entirely. Normalize casing.
3. Move workflow conventions out of `CLAUDE.example.md` into `docs/conventions.md`. Delete `CLAUDE.example.md` from the plugin — built-in `/init` produces CLAUDE.md before the plugin is installed, so the template has no role.
4. Update `/create-tasks`: accept a source path (`/create-tasks PRD.md`), auto-run `bd init` if needed, render created issues inline in `bd show` shape, react to free-text edits, never auto-invoke `/build-tasks`.
5. Update `/start-session` to trampoline: `bd` check → empty-tasks check → ready-work summary.
6. Update `/end-session` to write a current-status summary to a designated Beads issue (replaces `plan.MD`).
7. Update `implementer` and `code-reviewer` agent prompts to drop "see CLAUDE.md for workflow conventions" references — those are now in injected context.
8. Rewrite README install/setup sections; leave conceptual sections alone.
9. Smoke test: install into a fresh project; run `/start-session` (expect "install bd"); install bd; run `/start-session` (expect "no tasks"); write a PRD; run `/create-tasks PRD.md`; run `/start-session` (expect ready-work summary); run `/build-tasks`; run `/end-session`.
10. Tag `v0.1.0`, publish.
