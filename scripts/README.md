# Enzo Prompt Playground

Iterate on Enzo's prompts and test different models — no app build required. Responses stream to terminal in ~2 seconds.

---

## Setup (one time)

```bash
python3 -m venv scripts/.venv
scripts/.venv/bin/pip install anthropic
```

Credentials are read automatically from `Config/Debug.xcconfig` — no env vars needed.

---

## Typical session

**1. Fetch your real data from Supabase:**
```bash
python3 scripts/fetch_data.py
```
Saves to `scripts/data/context.json` (gitignored). Re-run any time after a sync to refresh.

**2. Run the playground:**
```bash
python3 scripts/enzo_playground.py
```

It asks two questions then streams a response:
```
Pick a mode (1-4):
  1) briefing   2) lookahead   3) goal   4) chat

Models:
  1) claude-opus-4-6
  2) claude-sonnet-4-6  ← app default
  3) claude-haiku-4-5-20251001
  ...
Pick a model (default: 1):
```

Models are fetched live from the API — you'll always see what's actually available.

---

## Iterating on prompts

Edit the `.md` files in `scripts/prompts/` — no Python to touch:

| File | What it controls |
|---|---|
| `prompts/system.md` | Enzo's personality, rules, and format constraints |
| `prompts/briefing.md` | Daily Arc briefing |
| `prompts/lookahead.md` | 5-7 day suggestion |
| `prompts/goal_reaction.md` | Reaction when a goal segment is picked |

Edit → save → re-run. That's the loop.

When you're happy with a change, paste the refined text back into the Swift source:
- System prompt → `EnzoApp/Services/ClaudeService.swift` → `systemPrompt`
- Other prompts → `EnzoApp/App/AppState.swift` → static prompt functions

---

## Skipping the menus

Pass flags to go straight to a response:

```bash
# Specific mode, pick model interactively
python3 scripts/enzo_playground.py --mode briefing

# Specific mode and model — no prompts at all
python3 scripts/enzo_playground.py --mode briefing --model claude-haiku-4-5-20251001

# One-shot chat
python3 scripts/enzo_playground.py --mode chat --message "Am I close to my goal?"

# Interactive multi-turn chat
python3 scripts/enzo_playground.py --mode chat
```

---

## All flags

```
--mode      briefing | lookahead | goal | chat
--model     any model ID (omit to pick from live list)
--message   one-shot chat message, skips the interactive loop

Preset overrides (only used when context.json is absent):
--fitness   recovering | baseline | building | strong | epic
--trend     up | flat | down
--days      days since last ride
--goal      goal segment name
--weeks     weeks remaining to goal date
```
