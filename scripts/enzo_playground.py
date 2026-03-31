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

DATA_PATH = Path(__file__).parent / "data" / "context.json"

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
# ── SYSTEM PROMPT ─────────────────────────────────────────────────────────
# Mirror of ClaudeService.swift → systemPrompt
# Edit this to tune Enzo's personality, rules, and format constraints.
# ---------------------------------------------------------------------------
SYSTEM_PROMPT = """You are Enzo — a cycling training companion with deep knowledge of this athlete's \
history and an easy, direct way of talking about it. You're not a certified coach \
and you don't pretend to be. You're the knowledgeable friend who's done a lot of \
miles and knows how to read a fitness trend.

Your name is Enzo. Use it occasionally but not constantly — like a person would.

Your personality:
- Direct and warm. You tell the truth but you're not harsh about it.
- European cycling sensibility — you care about the craft of riding, not just metrics.
- Unhurried. You take the long view. One bad week doesn't define anything.
- Occasionally a little poetic about riding, but never pretentious.

Your job:
- Help this athlete stay oriented toward their goal.
- React to their recent riding honestly and specifically.
- Suggest what makes sense next — loosely, not rigidly.
- Never make them feel bad for gaps, missed rides, or changed goals.

Rules:
- Always use their actual numbers and labels. Never give advice that could apply to anyone.
- Fitness is described using these labels only: Epic, Strong, Building, Baseline, Recovering.
- Segment readiness uses: No brainer, Worth a shot, Not quite ready.
- Frame everything relative to their personal history and their goal.
- Don't reference power, FTP, or watts unless the athlete brings it up.
- A suggestion is not a plan. Make that clear when offering workouts.

Format:
- 2-4 sentences for simple questions.
- Up to 3 short paragraphs for complex ones.
- No bullet points in conversational responses.
- Bullet points only for workout suggestions, and keep them loose.
- No exclamation marks."""


# ---------------------------------------------------------------------------
# ── PROMPTS ───────────────────────────────────────────────────────────────
# Mirrors AppState.swift static prompt builders.
# Edit these to iterate on output quality.
# ---------------------------------------------------------------------------

def briefing_prompt(ctx: dict) -> str:
    """Mirror of AppState.briefingPrompt(context:)"""
    return (
        "Generate today's Arc briefing. Write 2-3 sentences: where their fitness stands relative "
        "to their goal, what the trend means, and one forward-looking line. "
        "Be specific to their actual data — reference their current fitness label, goal segment, "
        "and trend direction. Do not start with 'I' or 'You'."
    )


def lookahead_prompt(ctx: dict) -> str:
    """Mirror of AppState.lookaheadPrompt(context:)"""
    fitness = ctx["athlete"]["current_fitness_label"]
    trend   = ctx["athlete"]["trend_direction"]
    days    = ctx["days_since_last_ride"]
    return (
        "Generate a 5-7 day lookahead suggestion. What should this athlete do in the next week? "
        f"Keep it loose — not a rigid plan. Be specific to their current fitness ({fitness}), "
        f"trend ({trend}), and days since last ride ({days}). "
        "2-3 sentences max. Do not include any headers or labels — just the suggestion."
    )


def goal_reaction_prompt(ctx: dict) -> str:
    """Mirror of AppState.goalReactionPrompt(segment:athleteContext:)"""
    goal    = ctx["goal"]
    athlete = ctx["athlete"]
    # Find goal segment in top_segments for pr details
    seg = next((s for s in ctx.get("top_segments", []) if s.get("is_goal_segment")), None)
    pr_time    = seg["pr_seconds"] if seg else "unknown"
    pr_date    = seg["pr_date"]    if seg else "unknown"
    fitness_at_pr = seg["fitness_at_pr"] if seg else goal["required_fitness_label"]
    segment_name  = goal["segment_name"]
    current_label = athlete["current_fitness_label"]
    trend         = athlete["trend_direction"]
    return (
        f"I want to set {segment_name} as my PR goal. "
        f"I set that PR ({pr_time}s) on {pr_date} "
        f"when I was at {fitness_at_pr} fitness. "
        f"My current fitness is {current_label}, trending {trend}. "
        "React to this goal choice — be honest about where I stand and whether a target date makes sense."
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
# ── API CALL ──────────────────────────────────────────────────────────────
# ---------------------------------------------------------------------------

MODEL = "claude-sonnet-4-6"   # ← change to test other models
MAX_TOKENS = 1024


def stream_response(client: anthropic.Anthropic, user_message: str, context: dict) -> None:
    """Stream Enzo's response to stdout, token by token."""
    context_str = json.dumps(context, indent=2)
    full_message = f"Athlete context:\n{context_str}\n\nUser: {user_message}"

    print(f"\n{'─'*60}")
    print(f"MODEL : {MODEL}")
    print(f"{'─'*60}")
    print(f"PROMPT: {user_message[:120]}{'…' if len(user_message) > 120 else ''}")
    print(f"{'─'*60}\n")

    with client.messages.stream(
        model=MODEL,
        max_tokens=MAX_TOKENS,
        system=SYSTEM_PROMPT,
        messages=[{"role": "user", "content": full_message}],
    ) as stream:
        for text in stream.text_stream:
            print(text, end="", flush=True)
    print(f"\n\n{'─'*60}\n")


# ---------------------------------------------------------------------------
# ── INTERACTIVE CHAT ──────────────────────────────────────────────────────
# ---------------------------------------------------------------------------

def interactive_chat(client: anthropic.Anthropic, ctx: dict) -> None:
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
        stream_response(client, msg, ctx)


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
    args = parser.parse_args()

    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        print("Error: ANTHROPIC_API_KEY not set.")
        print("  export ANTHROPIC_API_KEY=sk-ant-...")
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

    # Interactive mode picker if --mode not supplied
    if not mode:
        print("\nModes:")
        print("  1) briefing      — daily Arc briefing")
        print("  2) lookahead     — 5-7 day suggestion")
        print("  3) goal          — goal reaction")
        print("  4) chat          — free conversation")
        choice = input("\nPick a mode (1-4): ").strip()
        mode_map = {"1": "briefing", "2": "lookahead", "3": "goal", "4": "chat"}
        mode = mode_map.get(choice, "chat")

    if mode == "briefing":
        stream_response(client, briefing_prompt(ctx), ctx)
    elif mode == "lookahead":
        stream_response(client, lookahead_prompt(ctx), ctx)
    elif mode == "goal":
        stream_response(client, goal_reaction_prompt(ctx), ctx)
    elif mode == "chat":
        if args.message:
            stream_response(client, args.message, ctx)
        else:
            interactive_chat(client, ctx)


if __name__ == "__main__":
    main()
