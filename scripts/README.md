# Enzo Prompt Playground

A standalone Python script for iterating on Enzo's prompts, system prompt, and model behavior — no app build required.

## Setup

**Create a venv and install the SDK (one time):**
```bash
python3 -m venv scripts/.venv
scripts/.venv/bin/pip install anthropic
```

**Set your API key** (same key as in `Config/Debug.xcconfig`):
```bash
export ANTHROPIC_API_KEY=sk-ant-...
```

Add that export to your `~/.zshrc` so you don't have to repeat it.

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

Use `--fitness` to simulate different athlete states:

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
# Briefing for someone recovering, trending up
python3 scripts/enzo_playground.py --mode briefing --fitness recovering --trend up --days 3

# Lookahead for someone strong with 6 weeks to goal
python3 scripts/enzo_playground.py --mode lookahead --fitness strong --trend flat --weeks 6

# Goal reaction for a building athlete
python3 scripts/enzo_playground.py --mode goal --fitness building --trend up

# One-shot chat
python3 scripts/enzo_playground.py --mode chat --message "Am I close to Hawk Hill?"

# Interactive multi-turn chat
python3 scripts/enzo_playground.py --mode chat --fitness strong
```

---

## All flags

```
--mode        briefing | lookahead | goal | chat
--fitness     recovering | baseline | building | strong | epic  (default: recovering)
--trend       up | flat | down  (default: up)
--days        days since last ride  (default: 3)
--goal        goal segment name  (default: "Hawk Hill")
--weeks       weeks remaining to goal date  (omit = no deadline)
--message     one-shot chat message (skips interactive loop)
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
| Athlete context shape / fake data | `build_context()` function |

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
