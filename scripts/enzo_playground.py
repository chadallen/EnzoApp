#!/usr/bin/env python3
# Run with the venv: scripts/.venv/bin/python3 scripts/enzo_playground.py
# Or: source scripts/.venv/bin/activate && python3 scripts/enzo_playground.py
"""
Enzo Prompt Playground
======================
Iterate on Enzo's prompts without building the iOS app.
Mirrors ClaudeService.swift + AppState.swift prompts exactly.

Usage:
    python scripts/enzo_playground.py                     # interactive menu
    python scripts/enzo_playground.py --mode briefing
    python scripts/enzo_playground.py --mode lookahead
    python scripts/enzo_playground.py --mode goal
    python scripts/enzo_playground.py --mode chat
    python scripts/enzo_playground.py --mode chat --message "What should I do this weekend?"

Fitness presets (--fitness flag):
    recovering  building  baseline  strong  epic

    python scripts/enzo_playground.py --mode briefing --fitness strong --trend up --days 2

Requires:
    export ANTHROPIC_API_KEY=sk-ant-...
    pip install anthropic   (or: pip install --quiet anthropic)
"""

import argparse
import json
import os
import sys
from pathlib import Path

import xcconfig

DATA_PATH = Path(__file__).parent / "data" / "context.json"
_cfg = xcconfig.load()

# ---------------------------------------------------------------------------
# Dependency check
# ---------------------------------------------------------------------------
try:
    import anthropic
except ImportError:
    print("Install the Anthropic SDK first:")
    print("  pip install anthropic")
    sys.exit(1)


# ---------------------------------------------------------------------------
# ── PROMPT LOADING ────────────────────────────────────────────────────────
# Prompts live in scripts/prompts/*.md — edit those files, not this one.
# ---------------------------------------------------------------------------

PROMPTS_DIR = Path(__file__).parent / "prompts"

def _load(filename: str) -> str:
    path = PROMPTS_DIR / filename
    if not path.exists():
        raise FileNotFoundError(f"Prompt file missing: {path}")
    return path.read_text().strip()

def _system_prompt() -> str:
    return _load("system.md")

def briefing_prompt(ctx: dict) -> str:
    return _load("briefing.md")

def lookahead_prompt(ctx: dict) -> str:
    # Substitute live context values into the template
    template = _load("lookahead.md")
    return template  # context values are already in the athlete payload sent to Claude

def goal_reaction_prompt(ctx: dict) -> str:
    goal    = ctx["goal"]
    athlete = ctx["athlete"]
    seg = next((s for s in ctx.get("top_segments", []) if s.get("is_goal_segment")), None)
    pr_time       = seg["pr_seconds"] if seg else "unknown"
    pr_date       = seg["pr_date"]    if seg else "unknown"
    fitness_at_pr = seg["fitness_at_pr"] if seg else goal["required_fitness_label"]
    segment_name  = goal["segment_name"]
    current_label = athlete["current_fitness_label"]
    trend         = athlete["trend_direction"]
    template = _load("goal_reaction.md")
    return template.format(
        segment_name  = segment_name,
        pr_time       = f"{pr_time}s",
        pr_date       = pr_date,
        fitness_at_pr = fitness_at_pr,
        current_fitness = current_label,
        trend         = trend,
    )


# ---------------------------------------------------------------------------
# ── ATHLETE CONTEXT ───────────────────────────────────────────────────────
# Mirrors AthleteContext.contextPayload() + preview data.
# Edit fitness_presets or build_context() to simulate different athlete states.
# ---------------------------------------------------------------------------

FITNESS_PRESETS = {
    "recovering": {"label": "Recovering", "value": 0.15},
    "baseline":   {"label": "Baseline",   "value": 0.35},
    "building":   {"label": "Building",   "value": 0.55},
    "strong":     {"label": "Strong",     "value": 0.72},
    "epic":       {"label": "Epic",       "value": 0.90},
}

def fitness_label(value: float) -> str:
    if value >= 0.85: return "Epic"
    if value >= 0.65: return "Strong"
    if value >= 0.45: return "Building"
    if value >= 0.25: return "Baseline"
    return "Recovering"


def build_context(
    fitness: str = "recovering",
    trend: str = "up",
    days_since_ride: int = 3,
    goal_segment: str = "Hawk Hill",
    goal_weeks: int | None = None,
) -> dict:
    """
    Build a context payload matching AthleteContext.contextPayload().
    Swap fitness/trend/days to simulate different athlete states quickly.
    """
    preset = FITNESS_PRESETS.get(fitness.lower(), FITNESS_PRESETS["recovering"])
    current_label = preset["label"]
    current_value = preset["value"]

    # Required fitness = one tier below PR fitness (SegmentScorer.requiredFitnessLabel logic)
    tier_order = ["Recovering", "Baseline", "Building", "Strong", "Epic"]
    goal_fitness_at_pr = "Strong"   # what fitness Hawk Hill PR required
    req_idx = max(0, tier_order.index(goal_fitness_at_pr) - 1)
    required_label = tier_order[req_idx]

    goal: dict = {
        "type": "segment_pr",
        "segment_name": goal_segment,
        "required_fitness_label": required_label,
        "current_fitness_label": current_label,
        "has_date": goal_weeks is not None,
    }
    if goal_weeks is not None:
        goal["weeks_remaining"] = goal_weeks

    # Simulated 18-month fitness history (matches FitnessSnapshot.previewSnapshots shape)
    fitness_history = [
        {"month": "2024-06", "hours": 12.5, "fitness_label": "Baseline",   "trend_direction": "up",   "activity_count": 8},
        {"month": "2024-07", "hours": 18.0, "fitness_label": "Building",   "trend_direction": "up",   "activity_count": 11},
        {"month": "2024-08", "hours": 30.0, "fitness_label": "Epic",       "trend_direction": "up",   "activity_count": 16},
        {"month": "2024-09", "hours": 14.0, "fitness_label": "Strong",     "trend_direction": "down", "activity_count": 9},
        {"month": "2024-10", "hours": 8.0,  "fitness_label": "Building",   "trend_direction": "down", "activity_count": 5},
        {"month": "2024-11", "hours": 6.0,  "fitness_label": "Baseline",   "trend_direction": "down", "activity_count": 4},
        {"month": "2024-12", "hours": 4.0,  "fitness_label": "Recovering", "trend_direction": "down", "activity_count": 3},
        {"month": "2025-01", "hours": 5.0,  "fitness_label": "Recovering", "trend_direction": "flat", "activity_count": 3},
        {"month": "2025-02", "hours": 6.5,  "fitness_label": "Recovering", "trend_direction": "up",   "activity_count": 4},
        {"month": "2025-03", "hours": 7.0,  "fitness_label": current_label,"trend_direction": trend,  "activity_count": 5},
    ]

    top_segments = [
        {
            "name": "Hawk Hill",
            "pr_seconds": 342,
            "pr_date": "2024-08-14",
            "fitness_at_pr": "Epic",
            "current_fitness": current_label,
            "trend_direction": trend,
            "strike_score": round(max(0, min(1, 0.5 + (current_value - 0.87) * 0.8)), 2),
            "strike_label": "Not quite ready",
            "is_goal_segment": True,
        },
        {
            "name": "Cardiac Hill",
            "pr_seconds": 198,
            "pr_date": "2024-07-22",
            "fitness_at_pr": "Strong",
            "current_fitness": current_label,
            "trend_direction": trend,
            "strike_score": round(max(0, min(1, 0.5 + (current_value - 0.70) * 0.8)), 2),
            "strike_label": "Worth a shot" if current_value >= 0.45 else "Not quite ready",
            "is_goal_segment": False,
        },
        {
            "name": "Marin Ave",
            "pr_seconds": 510,
            "pr_date": "2024-06-05",
            "fitness_at_pr": "Building",
            "current_fitness": current_label,
            "trend_direction": trend,
            "strike_score": round(max(0, min(1, 0.5 + (current_value - 0.55) * 0.8)), 2),
            "strike_label": "Worth a shot" if current_value >= 0.30 else "Not quite ready",
            "is_goal_segment": False,
        },
    ]

    return {
        "athlete": {
            "name": "Chad",
            "years_active": 11,
            "current_fitness_label": current_label,
            "trend_direction": trend,
        },
        "goal": goal,
        "peak_fitness": {"month": "2024-08", "label": "Epic"},
        "fitness_history": fitness_history,
        "top_segments": top_segments,
        "recent_weeks": [],
        "days_since_last_ride": days_since_ride,
    }


# ---------------------------------------------------------------------------
# ── MODEL SELECTION ───────────────────────────────────────────────────────
# ---------------------------------------------------------------------------

MAX_TOKENS = 1024

# Family sort order — most capable first
_MODEL_FAMILIES = ("claude-opus", "claude-sonnet", "claude-haiku")
# App's production model — marked as default in the picker
_DEFAULT_MODEL = "claude-sonnet-4-6"


def fetch_models(client: anthropic.Anthropic) -> list[str]:
    """Fetch available models from the API, filtered to relevant Claude families."""
    try:
        all_models = [m.id for m in client.models.list()]
        relevant = [m for m in all_models if any(m.startswith(p) for p in _MODEL_FAMILIES)]
        # Sort: opus → sonnet → haiku; newest first within each family (reverse-lex on version)
        def sort_key(m: str) -> tuple:
            family = next((i for i, p in enumerate(_MODEL_FAMILIES) if m.startswith(p)), 99)
            return (family, m[::-1])  # reverse string = newest versions sort first
        relevant.sort(key=sort_key)
        return relevant
    except Exception:
        return ["claude-opus-4-6", _DEFAULT_MODEL, "claude-haiku-4-5-20251001"]


def pick_model(client: anthropic.Anthropic, preselected: str | None = None) -> str:
    """Interactively pick a model, or return preselected if provided."""
    if preselected:
        return preselected

    models = fetch_models(client)

    print("\nModels:")
    for i, m in enumerate(models, 1):
        tag = "  ← app default" if m == _DEFAULT_MODEL else ""
        print(f"  {i}) {m}{tag}")

    choice = input("\nPick a model (default: 1): ").strip()
    if not choice:
        return models[0]
    try:
        idx = int(choice) - 1
        return models[idx] if 0 <= idx < len(models) else models[0]
    except ValueError:
        return models[0]


def stream_response(client: anthropic.Anthropic, user_message: str, context: dict, model: str) -> None:
    """Stream Enzo's response to stdout, token by token."""
    context_str = json.dumps(context, indent=2)
    full_message = f"Athlete context:\n{context_str}\n\nUser: {user_message}"

    print(f"\n{'─'*60}")
    print(f"MODEL : {model}")
    print(f"{'─'*60}")
    print(f"PROMPT: {user_message[:120]}{'…' if len(user_message) > 120 else ''}")
    print(f"{'─'*60}\n")

    with client.messages.stream(
        model=model,
        max_tokens=MAX_TOKENS,
        system=_system_prompt(),
        messages=[{"role": "user", "content": full_message}],
    ) as stream:
        for text in stream.text_stream:
            print(text, end="", flush=True)
    print(f"\n\n{'─'*60}\n")


# ---------------------------------------------------------------------------
# ── INTERACTIVE CHAT ──────────────────────────────────────────────────────
# ---------------------------------------------------------------------------

def interactive_chat(client: anthropic.Anthropic, ctx: dict, model: str) -> None:
    """Multi-turn chat loop. Type 'quit' or Ctrl+C to exit."""
    print("\nEntering Enzo chat mode. Type 'quit' to exit, Ctrl+C to abort.\n")
    while True:
        try:
            msg = input("You: ").strip()
        except (KeyboardInterrupt, EOFError):
            print("\nExiting chat.")
            break
        if not msg or msg.lower() in {"quit", "exit", "q"}:
            break
        stream_response(client, msg, ctx, model)


# ---------------------------------------------------------------------------
# ── MAIN ──────────────────────────────────────────────────────────────────
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description="Enzo Prompt Playground")
    parser.add_argument(
        "--mode",
        choices=["briefing", "lookahead", "goal", "chat"],
        help="Which prompt to run (omit for interactive menu)",
    )
    parser.add_argument(
        "--fitness",
        default="recovering",
        choices=list(FITNESS_PRESETS.keys()),
        help="Athlete fitness preset (default: recovering)",
    )
    parser.add_argument(
        "--trend",
        default="up",
        choices=["up", "flat", "down"],
        help="Trend direction (default: up)",
    )
    parser.add_argument(
        "--days",
        type=int,
        default=3,
        help="Days since last ride (default: 3)",
    )
    parser.add_argument(
        "--goal",
        default="Hawk Hill",
        help="Goal segment name (default: Hawk Hill)",
    )
    parser.add_argument(
        "--weeks",
        type=int,
        default=None,
        help="Weeks remaining to goal date (omit for no date)",
    )
    parser.add_argument(
        "--message",
        default=None,
        help="Message for --mode chat (skips interactive prompt)",
    )
    parser.add_argument(
        "--model",
        default=None,
        help="Model ID to use (omit to pick interactively)",
    )
    args = parser.parse_args()

    api_key = _cfg.get("CLAUDE_API_KEY") or os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        print("Error: could not load Claude API key.")
        print("  Expected: EnzoApp/Config/Debug.xcconfig with CLAUDE_API_KEY")
        print("  Or set env var: export ANTHROPIC_API_KEY=sk-ant-...")
        sys.exit(1)

    client = anthropic.Anthropic(api_key=api_key)

    # Load real data if available, otherwise fall back to hardcoded preset
    if DATA_PATH.exists():
        ctx = json.loads(DATA_PATH.read_text())
        data_source = f"real data ({DATA_PATH})"
    else:
        ctx = build_context(
            fitness=args.fitness,
            trend=args.trend,
            days_since_ride=args.days,
            goal_segment=args.goal,
            goal_weeks=args.weeks,
        )
        data_source = "hardcoded preset (run fetch_data.py to use real data)"

    # Print context summary so you know what state you're testing
    athlete = ctx["athlete"]
    goal = ctx["goal"]
    print(f"\nData:    {data_source}")
    print(f"Context: {athlete['name']} | {athlete['current_fitness_label']} fitness | "
          f"trend {athlete['trend_direction']} | {ctx['days_since_last_ride']}d since ride | "
          f"goal: {goal['segment_name']}")

    mode = args.mode

    # Interactive pickers if flags not supplied
    if not mode:
        print("\nModes:")
        print("  1) briefing      — daily Arc briefing")
        print("  2) lookahead     — 5-7 day suggestion")
        print("  3) goal          — goal reaction")
        print("  4) chat          — free conversation")
        choice = input("\nPick a mode (1-4): ").strip()
        mode_map = {"1": "briefing", "2": "lookahead", "3": "goal", "4": "chat"}
        mode = mode_map.get(choice, "chat")

    model = pick_model(client, preselected=args.model)
    print(f"Model:   {model}\n")

    if mode == "briefing":
        stream_response(client, briefing_prompt(ctx), ctx, model)
    elif mode == "lookahead":
        stream_response(client, lookahead_prompt(ctx), ctx, model)
    elif mode == "goal":
        stream_response(client, goal_reaction_prompt(ctx), ctx, model)
    elif mode == "chat":
        if args.message:
            stream_response(client, args.message, ctx, model)
        else:
            interactive_chat(client, ctx, model)


if __name__ == "__main__":
    main()
