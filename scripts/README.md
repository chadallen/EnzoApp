# Enzo Prompt Playground

A standalone Python script for iterating on Enzo's prompts, system prompt, and model behavior — no app build required.

## Setup

**Create a venv and install the SDK (one time):**
```bash
python3 -m venv scripts/.venv
scripts/.venv/bin/pip install anthropic
```

**Set your API keys** in `~/.zshrc` so they persist across sessions:
```bash
export ANTHROPIC_API_KEY=sk-ant-...
export SUPABASE_URL=https://your-project.supabase.co
export SUPABASE_ANON_KEY=your-anon-key
```

Same values as `Config/Debug.xcconfig`. Reload with `source ~/.zshrc`.

---

## Fetch real data (do this first)

Pulls your real fitness history, segments, and goal from Supabase and saves to `scripts/data/context.json`. The playground uses this automatically once it exists.

```bash
python3 scripts/fetch_data.py
```

The data file is gitignored — it stays local. Re-run it any time after a sync to refresh.

---

## Running it

From the repo root:
```bash
scripts/.venv/bin/python3 scripts/enzo_playground.py
```

Or activate the venv first for a shorter command:
```bash
source scripts/.venv/bin/activate
python3 scripts/enzo_playground.py
# when done:
deactivate
```

Without arguments you get an interactive mode picker. Pass `--mode` to skip straight to a prompt type.

If `scripts/data/context.json` exists, the playground uses your real data automatically. Otherwise it falls back to hardcoded presets.

---

## Modes

| Mode | What it tests |
|---|---|
| `briefing` | Daily Arc briefing (2-3 sentences) |
| `lookahead` | 5-7 day suggestion |
| `goal` | Goal reaction when user picks a segment |
| `chat` | Free conversation — interactive or one-shot |

---

## Fitness presets

Only used when real data isn't available. Use `--fitness` to simulate different athlete states:

| Flag | Label | Value |
|---|---|---|
| `recovering` | Recovering | 0.15 |
| `baseline` | Baseline | 0.35 |
| `building` | Building | 0.55 |
| `strong` | Strong | 0.72 |
| `epic` | Epic | 0.90 |

---

## Examples

```bash
# Fetch real data first
python3 scripts/fetch_data.py

# Then run against your real data
python3 scripts/enzo_playground.py --mode briefing
python3 scripts/enzo_playground.py --mode lookahead
python3 scripts/enzo_playground.py --mode goal
python3 scripts/enzo_playground.py --mode chat

# One-shot chat
python3 scripts/enzo_playground.py --mode chat --message "Am I close to Hawk Hill?"

# Interactive multi-turn chat
python3 scripts/enzo_playground.py --mode chat

# Force hardcoded preset (ignore real data)
python3 scripts/enzo_playground.py --mode briefing --preset --fitness strong --trend up
```

---

## All flags

```
--mode        briefing | lookahead | goal | chat
--message     one-shot chat message (skips interactive loop)

Preset overrides (only used when context.json is absent):
--fitness     recovering | baseline | building | strong | epic  (default: recovering)
--trend       up | flat | down  (default: up)
--days        days since last ride  (default: 3)
--goal        goal segment name  (default: "Hawk Hill")
--weeks       weeks remaining to goal date  (omit = no deadline)
```

---

## Iterating on prompts

All prompts and the system prompt live at the top of `enzo_playground.py`:

| What to edit | Where in the file |
|---|---|
| Enzo's personality, rules, format | `SYSTEM_PROMPT` constant |
| Daily briefing prompt | `briefing_prompt()` function |
| Lookahead suggestion prompt | `lookahead_prompt()` function |
| Goal reaction prompt | `goal_reaction_prompt()` function |
| Fallback fake data | `build_context()` function |

Once you're happy with changes, paste the refined text back into the Swift source:
- System prompt → `EnzoApp/Services/ClaudeService.swift` → `systemPrompt`
- Briefing/lookahead/goal prompts → `EnzoApp/App/AppState.swift` → static prompt functions

---

## Changing the model

Edit the `MODEL` constant near the top of `enzo_playground.py`:

```python
MODEL = "claude-sonnet-4-6"   # change to test other models
```

Available models: `claude-sonnet-4-6`, `claude-opus-4-6`, `claude-haiku-4-5-20251001`
