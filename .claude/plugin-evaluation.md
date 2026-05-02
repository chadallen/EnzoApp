# claude-workflow → Plugin: Evaluation & Proposal

Evaluating whether to repackage [chadallen/claude-workflow](https://github.com/chadallen/claude-workflow) as a Claude Code plugin, and what doc/structure work that implies.

---

## TL;DR

- Yes — it's a clean fit. The repo is already a coherent bundle of commands, agents, language skills, and hooks meant to be reused across projects. That's exactly the plugin shape.
- Migration is mostly mechanical: add `.claude-plugin/plugin.json`, split today's `skills/` directory into `commands/` (the `/`-invoked ones) vs `skills/` (the auto-invoked language ones), add a `hooks/hooks.json` for the Beads `SessionStart` / `PreCompact` hooks.
- Doc cost is moderate. The README's whole install/setup narrative needs a rewrite — `git clone … your-project-path` becomes `/plugin install …`, and the "copy to global" footgun goes away. `CLAUDE.example.md` and `PRD.md` need light edits only.
- The biggest substantive risk: `/init-project` materialises plugin templates (CLAUDE.md, plan.MD, .beads/) into the consumer's repo. Without an upgrade path, those files silently rot as the plugin evolves. The recommended fix is a schema-migration-on-startup runner (managed regions inside user files, version-stamp headers, ordered idempotent migrations, dirty-tree guard). Roughly a week of engineering, but it's the difference between a plugin that ages well and one that breaks every existing project on every release. Build it before v0.1.
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
- **Scope.** v0.1 is already shipping a plugin with a migration runner, a hook trust model, and a namespace UX shift. "Also we run language servers" is a separable concern.
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

### `CLAUDE.example.md` — needs splitting, not just edits

This file becomes a template the plugin ships under `templates/` and `/init-project` writes into a consumer project. After reading the current content end-to-end, the changes are bigger than originally framed.

The template today mixes two kinds of content in one file:

| Project-owned (stays in user's CLAUDE.md) | Plugin-owned (should leave the user's repo) |
|---|---|
| What This Is, Stack, Commands, Tests, Key Conventions | "Beads CLI: All bd commands use --json" |
| | "Commit format: `<message> (<task-id>)`" |
| | "Hook commands: bd prime --stealth, not bd prime" |
| | "plan.MD Current Status: only one entry ever exists" |
| | "CLAUDE.md target length: under 80 lines" |
| | "scratch.md is always in .gitignore, never read" |
| | The Workflow / Agents / Task Tracking sections |

The right-column content is workflow rules, not project facts. They're in the user's CLAUDE.md today only because that's the file Claude auto-loads — there's no other channel to get them in front of every session. Under the plugin model that channel exists (skill descriptions, hook scripts, plugin-internal docs that skills read on demand), so they should move out.

Concrete edits:

- **Split the template.** `templates/CLAUDE.example.md` keeps only project-owned content (What This Is, Stack, Commands, Tests, Key Conventions). The Workflow / Agents / Workflow Conventions / Task Tracking sections move into a plugin-internal doc (`docs/conventions.md` or similar) that the relevant skills read directly when they need to.
- **Update every skill that says "see CLAUDE.md for X."** A grep pass is needed: `start-session.md`, `build-tasks.md`, `implementer.MD`, `code-reviewer.MD` all reference CLAUDE.md for things like the test command, lint command, or commit format. Test command and lint command stay (those are project facts). Commit format and the bd CLI conventions move — skills should read them from the plugin's own conventions doc.
- **Final line "`Skills: …`" → "`Commands: …`"** to match new terminology. (Was already noted; still applies.)

Why this matters: this is the architectural fix that makes risk #1 (state coupling) tractable. If conventions stay in the user's CLAUDE.md, every plugin convention change requires a migration — even a typo fix. If conventions live in the plugin, they update with the plugin and never drift. The migration runner only handles real schema changes, not convention churn.

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

## Skill-by-skill changes for the plugin transition

The skills in the current repo are mature — most need only mechanical updates (path adjustments, version stamping, reading conventions from the new location). Two need real rework. Catalogued here so the work can be scoped before v0.1.

### `/init-project` and `/migrate-project` — collapse into one command, OR clearly disambiguate

The two commands today have substantial overlap and a real naming problem under the plugin model:

- `/init-project` — assumes greenfield, requires PRD.md, errors if `.claude/` doesn't exist, builds from `CLAUDE.example.md` template.
- `/migrate-project` — handles existing projects, much more interactive, 12 steps including content merge and ADR backfill. Currently the more sophisticated of the two.
- **The new SessionStart migration runner** (risk #1 mitigation) is *also* called migration. Three things share one word.

Two ways out:

1. **Merge into one `/setup-project` (or keep `/init-project`)** that detects state and branches. Greenfield is just "nothing exists yet" — same code path with no merging to do. User doesn't have to know which command applies. Frees the word "migrate" for the upgrade runner.
2. **Keep both but rename `/migrate-project` → `/adopt-project`.** Smaller code change, clearer intent. Same naming benefit.

Recommendation: option 1. The two skills already share most of their work (template-driven CLAUDE.md, plan.MD scaffold, `bd init`, hook setup, gitignore, commit). Maintaining two near-duplicates is more cost than the conditional logic to detect state.

Either way, both commands need:

- **Emit version-stamp headers** on every managed file: `<!-- claude-workflow v0.1.0 -->`.
- **Emit managed-region markers** around plugin-owned content: `<!-- claude-workflow:begin <slot-name> -->` / `<!-- claude-workflow:end -->`. These are what the SessionStart migration runner needs to safely update content later without touching user additions.
- **Stop writing workflow-conventions content into CLAUDE.md** (per the CLAUDE.example.md split above). The output should contain only project facts plus markers.
- **Drop the "URL contains claude-workflow" stop check.** That guards against the user forgetting to set their own remote when the workflow was distributed by clone. With plugin install, the user's project already has its own remote — the check is dead.
- **Two-commits-is-normal needs to be documented.** `/migrate-project`'s key principles already note that `bd init` auto-commits. The SessionStart migration runner needs to know about this too — it can't assume "one commit per migration."

### `/start-session` — minor

Currently reads `plan.MD` and stops if it doesn't exist with a "run /init-project or /migrate-project" message. Update that error to reference the (possibly merged) setup command. Otherwise unchanged.

### `/end-session` — minor

References `bd doctor` only working in server mode and skips in embedded — that's a Beads detail, not a plugin concern. Unchanged.

### `/create-tasks`, `/build-tasks`, `/adr` — no changes

These read project state and create tasks/commits/ADRs. They don't write to the structured user files we've been talking about. Just need the namespace prefix in their docs (`/claude-workflow:create-tasks` etc.).

### `implementer` and `code-reviewer` agents — small

Both reference CLAUDE.md for "test command, lint command, project conventions." Test/lint commands stay in user CLAUDE.md (project facts). The "project conventions" reference needs to split: project conventions stay, workflow conventions (commit format especially) come from the plugin's own conventions doc. Update both prompts to reflect that split.

### Language skills — no functional changes

`typescript-developer`, `python-developer`, `ios-developer` are pure prose conventions. They move into `skills/` under the plugin layout and get auto-loaded by the agents based on file types touched (current behaviour, just under the new file layout). The `ios-developer` skill is notably more verbose than the other two and is mostly "I know iOS" rather than "here are catches" — worth a separate pruning pass but not blocking.

---

## Risks

Severity ordered. Risks are real but largely mitigable; the first is the one that warrants real engineering before v0.1 ships.

### 1. Per-project state coupling — solvable, but needs a migration runner *and* a conventions split

`/init-project` doesn't just register commands. It *forks state* into the consumer's repo: `CLAUDE.md`, `plan.MD`, `.beads/` all get materialised from plugin templates and then live there forever, owned by the user. Without intervention, the plugin and the consumer's files diverge from minute one.

The failure mode is concrete, not hypothetical. Today's `CLAUDE.example.md` ships these as user-file content:

- "Beads CLI: All bd commands use --json"
- "Commit format: `<message> (<task-id>)`"
- "Hook commands: Both SessionStart and PreCompact must use `bd prime --stealth`"
- "plan.MD Current Status: Only one entry ever exists"
- "CLAUDE.md target length: Under 80 lines"

If v0.2 changes the commit format to "(refs <task-id>)", every project that ran `/init-project` against v0.1 keeps the old rule embedded in their CLAUDE.md. Agents in those projects keep emitting v0.1-style commits while the plugin's skills now expect v0.2-style. Nothing crashes — it just rots silently.

**The fix has two parts:**

**Part A: split user-owned from plugin-owned content** (see "CLAUDE.example.md — needs splitting" above). Workflow conventions move out of user files entirely, into plugin-internal docs that skills read directly. After the split, the user's CLAUDE.md only contains project facts (Stack, Commands, Tests, Key Conventions). Plugin convention changes don't require a migration because they don't touch user files.

**Part B: schema-migration-on-startup for what's left.** Even after the split, *some* shape lives in user files: `plan.MD`'s section structure, `.beads/`'s field names, the version-stamp header itself. For these, the SessionStart hook runs a fast check (read version stamp, compare to plugin version, exit if matched). On mismatch, it runs ordered, idempotent migrations to bring the user's files up to current. Same pattern as Rails migrations or framework upgrade scripts.

Three things to get right on Part B:

- **Managed regions, not whole-file ownership.** Don't let the plugin own all of `plan.MD` — users add their own notes and the migration will fight them. Mark plugin-owned slots with `<!-- claude-workflow:begin … -->` / `<!-- claude-workflow:end -->` markers. Migration only touches content between markers. Everything outside is the user's. Collapses surprise factor and conflict surface in one move.

- **Version-stamp + ordered migrations.** Each managed file gets a header `<!-- claude-workflow v0.2.0 -->`. Plugin keeps a numbered migration list (`001-rename-conventions.ts`, `002-add-beads-priority-field.ts`) and runs only the ones the user hasn't applied. Difference between "works for v0.1 → v0.2" and "works for any old version → current" — matters the moment there's more than one user.

- **Dirty-tree guard + visible commits.** Two non-negotiables:
  - If user has uncommitted changes in a file you'd touch, refuse and print: "Plugin v0.2 wants to update plan.MD. You have uncommitted changes there — stash or commit first."
  - Migrations land as a separate, well-named git commit (`chore: migrate workflow files from v0.1 → v0.2`). Never silent. The user can `git show` it, revert it, review what moved.

Costs to budget for:

- **Migration code is forever.** Once v0.2 ships a migration, you maintain it. Removing old migrations means users on truly ancient versions can't upgrade. Standard schema-migration discipline.
- **Hook latency.** SessionStart runs every session. The "no migration needed" path needs to be sub-100ms (read header, compare versions, exit). The "actually migrating" path can be slower because it's rare.
- **Test burden.** Every release: "given a v(N-1) repo, does migration produce valid v(N) state?" CI needs fixtures of old repo shapes. Skipping this once = breaking everyone simultaneously.
- **plan.md "always exists" assumption.** Some users will delete it intentionally. Need an opt-out — a `.claude-workflow/disabled` marker or a frontmatter flag — or the migration will keep re-creating files they killed on purpose.
- **`bd init` auto-commits.** Beads creates its own commit during init. Migration runner can't assume "one commit per migration" — needs to handle the two-commit case the existing `/migrate-project` skill already documents.

Roughly a week of work for the migration runner, plus a few days for the conventions split (Part A) and updating the skills that reference CLAUDE.md for workflow rules. Both before v0.1. With both in place, the "bootstrapper" framing largely goes away — you're not seeding state and walking away, you're actively maintaining it across versions, and most of what would have drifted no longer lives in user files in the first place.

### 2. Stale global copies will shadow the plugin

The current README explicitly tells users to `cp -r .claude/skills/* ~/.claude/skills/` for global access. Anyone who followed that advice has copies of every command and agent at `~/.claude/skills/start-session/`, `~/.claude/agents/code-reviewer.MD`, etc. After plugin migration, the plugin installs to its own cache directory under `~/.claude/` (exact path is an implementation detail — not publicly documented, don't rely on it).

Both will load. Plugin skills are namespaced (`/claude-workflow:start-session`) so they technically don't collide — but the user's stale `/start-session` from `~/.claude/skills/` still works, and points at the old code. Same for agents. The user will think they're on the new version and silently be running the old one.

First step in the migration README has to be: "If you previously copied this repo's contents into `~/.claude/`, delete those copies before installing the plugin." With a one-line script that lists what to remove.

### 3. Hook trust model

`SessionStart` runs `bd prime --stealth` automatically, unsandboxed, with the user's privileges. That's fine for a known maintainer, known command. Two failure modes worth knowing about:

- **Compromised maintainer / bad release.** A future malicious release (or a hijacked GitHub account) could swap the hook command for anything. Hook scripts have no signing, no verification, no sandbox. Plugins are cached locally and don't auto-fetch from remote on session start, so a user has to explicitly run `/plugin update` to pull a new version — that's the soft mitigation. But once they do, the new hook command runs unsandboxed on the next session.
- **The autonomous-walk-away mode (`/build-tasks --auto`) makes blast radius worse.** Whatever a hook runs in that mode happens unobserved.

Mitigations: tell users to pin to a tag (`/plugin install …@v0.1.0`), document "review the hook diff on every plugin update," eventually code-sign. None of these are migration blockers, but the threat model is qualitatively new vs. the current "you cloned a git repo, you can read the files" model.

### 4. `/plugin update` may not actually update

There are open Claude Code issues (anthropics/claude-code#15642 and #29071) reporting that `/plugin update` runs `git fetch` against the remote but does not fast-forward the local clone — so the cache stays on the old commit even after the user explicitly tries to update. `CLAUDE_PLUGIN_ROOT` then points at a stale version with no obvious signal that the update silently no-op'd.

Practical consequences for this workflow:

- A user who runs `/plugin update` after a bug fix may keep hitting the bug.
- Security fixes (especially to hook commands, see risk #3) won't reach users who think they updated.
- Debugging "did the update apply?" becomes part of every support conversation.

Workaround until the upstream issues are fixed: tell users in the README to `/plugin uninstall claude-workflow && /plugin install …@<tag>` for upgrades rather than `/plugin update`. Ugly but reliable. Re-evaluate when the issues close.

### 5. Uninstall semantics

Good news / bad news:

- Good: `/plugin uninstall` removes the plugin's cache directory and its plugin-data directory (use `--keep-data` to preserve), but does *not* touch files inside the user's project repo. So `CLAUDE.md`, `plan.MD`, `.beads/` survive uninstall — that's correct, those are the user's data.
- Bad: the commands that read those files disappear. The user's repo is left holding files no agent knows what to do with. `bd ready` still works (Beads is a separate CLI), but `/build-tasks` is gone.

Document it in the README: "Uninstalling removes the workflow commands but leaves your project state in place. Delete `CLAUDE.md`, `plan.MD`, and `.beads/` manually if you're done with the workflow."

### 6. Auto-namespacing is a real UX shift

Plugin commands and skills get prefixed with the plugin name: `/claude-workflow:start-session` instead of `/start-session`. This prevents collisions across plugins (good) but also means every command in the README, every reference in `CLAUDE.example.md`, every muscle-memory keystroke gets longer.

Options:
- Accept the longer names and update all docs.
- Ship a `commands/aliases/` set of short-named commands that just delegate to the namespaced ones (if the spec allows; verify).
- Encourage users to set up their own short aliases in personal settings.

Worth deciding before publishing — flip-flopping later breaks every existing reference.

### 7. Beads as a runtime prerequisite

Plugins can't install external CLIs. If `bd` isn't on PATH, the `SessionStart` hook fails on every session. Specific failure modes to handle:

- **Missing on first install.** Have the hook script `command -v bd >/dev/null || { echo "Beads not installed: brew install beads"; exit 0; }`. Exit 0, not non-zero — don't block sessions over a missing optional dep at startup.
- **Cross-machine sync.** A user installs the plugin on their Mac (has `bd`), syncs their Claude config to a Linux box (no `bd`). Same fix above handles it.
- **Beads itself is alpha.** The `--stealth` flag is a Beads-specific contract. If Beads renames it, every consumer breaks at SessionStart simultaneously. Pin the documented Beads version range in the README's Requirements section.

### 8. Hidden coupling between agents and skill names

Per CLAUDE.example.md: "The `implementer` and `code-reviewer` agents automatically invoke a language skill at the start of each task based on the files being touched." The agents reference language skills *by name* in their prompts. If the plugin renames or removes a skill, the agents silently stop matching — no compile-time error, just degraded behavior on TS/Python/iOS work.

Worth a smoke-test in CI: boot each agent against representative file types and assert the right skill loads. Cheap insurance.

### 9. Language-skill backlog

Once published, every user wants their language. TS/Python/iOS today; tomorrow Rust, Go, Java, Ruby, Kotlin, PHP. You either:

- Become a meta-language repo (maintenance balloon, you don't write Ruby).
- Define a skill contract and let third parties ship companion plugins (`claude-workflow-rust`, etc.) that depend on the core. More upfront design, scales better.
- Stay opinionated, reject PRs, watch a fork ecosystem emerge.

No urgency for v0.1 but worth a stance in the README so PR authors aren't surprised.

### 10. Cosmetic / mechanical

- **`.MD` vs `.md` casing.** Current repo is inconsistent. Fix during the move; Linux is case-sensitive and discovery may be picky.
- **Marketplace vs. direct git install.** Direct install (`/plugin install <git-url>@<tag>`) is fine for v0.1. Marketplace is the eventual right answer for discoverability and version listings — defer until there's actual demand.
- **`/clear` is a built-in.** Drop it from the workflow's command list; it's a Claude Code primitive, not yours to ship.

### Softening factors worth knowing

- **7-day cache grace period on updates.** When a plugin updates mid-session, the old version stays cached for 7 days. Existing sessions keep running against the old version; new sessions get the new one. Mid-flight breaking-change risk is much smaller than I initially worried.
- **Plugin skills are namespaced.** Collisions with other plugins' commands/skills are essentially eliminated by construction (the trade-off being risk #5 above).
- **No auto-fetch on session start.** Plugins load from a local cache; updates require an explicit `/plugin update`. So mid-flight breaking changes can't ambush an active user.

---

## Suggested sequencing

1. Verify plugin manifest spec against current Claude Code docs (resolve the open questions above).
2. Branch, restructure files, add `plugin.json` + `hooks/hooks.json`, normalise casing.
3. **Build the migration runner** (risk #1): managed-region markers in template files, version-stamp headers, migration script invoked by SessionStart hook, dirty-tree guard, ordered migration list (empty for v0.1, but the harness exists). CI fixtures for "v(N-1) repo → migrate → v(N) repo."
4. Rewrite README install/setup sections; leave conceptual sections alone.
5. Touch up `CLAUDE.example.md` ("Skills" → "Commands"; hooks-provided-by-plugin note; document managed regions).
6. Smoke test: install into a fresh project, run `/init-project`, run `/start-session`, confirm hooks fire, `bd prime --stealth` runs, and migration check exits clean on a current-version repo.
7. Tag `v0.1.0`, publish.
