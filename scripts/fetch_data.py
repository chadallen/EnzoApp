#!/usr/bin/env python3
# Run with the venv: scripts/.venv/bin/python3 scripts/fetch_data.py
"""
Fetch real athlete data from Supabase and save to scripts/data/context.json.

This builds the same payload shape as AthleteContext.contextPayload() in Swift,
so enzo_playground.py can use real data instead of hardcoded presets.

Required env vars (same values as Config/Debug.xcconfig):
    SUPABASE_URL       e.g. https://hizswbzxwfxddocryvci.supabase.co
    SUPABASE_ANON_KEY  your anon/public key

Usage:
    source scripts/.venv/bin/activate
    python3 scripts/fetch_data.py
"""

import json
import os
import sys
import urllib.request
import urllib.parse
from datetime import date, datetime
from pathlib import Path

import xcconfig

# ---------------------------------------------------------------------------
# Config — read from Debug.xcconfig, env vars override if set
# ---------------------------------------------------------------------------

_cfg = xcconfig.load()
SUPABASE_URL      = _cfg.get("SUPABASE_URL", "").rstrip("/")
SUPABASE_ANON_KEY = _cfg.get("SUPABASE_ANON_KEY", "")
OUTPUT_PATH       = Path(__file__).parent / "data" / "context.json"


def headers() -> dict:
    return {
        "apikey":        SUPABASE_ANON_KEY,
        "Authorization": f"Bearer {SUPABASE_ANON_KEY}",
        "Content-Type":  "application/json",
    }


def get(path: str) -> list:
    url = f"{SUPABASE_URL}/rest/v1/{path}"
    req = urllib.request.Request(url, headers=headers())
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())


# ---------------------------------------------------------------------------
# Fitness label (mirrors AthleteContext.fitnessLabel in Swift)
# ---------------------------------------------------------------------------

def fitness_label(value: float) -> str:
    if value >= 0.85: return "Epic"
    if value >= 0.65: return "Strong"
    if value >= 0.45: return "Building"
    if value >= 0.25: return "Baseline"
    return "Recovering"


# ---------------------------------------------------------------------------
# Strike label (mirrors SegmentScorer.strikeLabel in Swift)
# ---------------------------------------------------------------------------

def strike_label(score: float) -> str:
    if score >= 0.70: return "No brainer"
    if score >= 0.45: return "Worth a shot"
    return "Not quite ready"


# ---------------------------------------------------------------------------
# Days since date
# ---------------------------------------------------------------------------

def days_since(date_str: str | None) -> int:
    if not date_str:
        return 0
    try:
        d = datetime.strptime(date_str[:10], "%Y-%m-%d").date()
        return max(0, (date.today() - d).days)
    except ValueError:
        return 0


# ---------------------------------------------------------------------------
# Main fetch + assemble
# ---------------------------------------------------------------------------

def main():
    if not SUPABASE_URL or not SUPABASE_ANON_KEY:
        print("Error: could not load Supabase credentials.")
        print("  Expected: EnzoApp/Config/Debug.xcconfig with SUPABASE_URL and SUPABASE_ANON_KEY")
        print("  Or set env vars: export SUPABASE_URL=... SUPABASE_ANON_KEY=...")
        sys.exit(1)

    print("Fetching user...")
    users = get("users?limit=1")
    if not users:
        print("No users found in Supabase.")
        sys.exit(1)
    user = users[0]
    user_id   = user["id"]
    user_name = user.get("display_name") or "Athlete"
    last_ride  = user.get("last_activity_date")
    print(f"  Found: {user_name} ({user_id})")

    print("Fetching fitness snapshots...")
    snapshots_raw = get(f"fitness_snapshots?user_id=eq.{user_id}&order=month.asc")
    print(f"  {len(snapshots_raw)} snapshots")

    print("Fetching segment scores...")
    segments_raw = get(f"segment_scores?user_id=eq.{user_id}")
    print(f"  {len(segments_raw)} segments")

    print("Fetching active goal...")
    goals_raw = get(f"goals?user_id=eq.{user_id}&is_active=eq.true&limit=1")
    goal_row  = goals_raw[0] if goals_raw else None
    print(f"  Goal: {goal_row['target_segment_name'] if goal_row else 'none'}")

    # ── Assemble fitness_history ────────────────────────────────────────────
    fitness_history = []
    for s in snapshots_raw:
        month = (s.get("month") or "")[:7]   # "2024-08-01" → "2024-08"
        fitness_history.append({
            "month":           month,
            "hours":           round(s.get("hours_ridden") or 0, 1),
            "fitness_label":   s.get("fitness_label") or fitness_label(s.get("fitness_value") or 0),
            "trend_direction": s.get("trend_direction") or "flat",
            "activity_count":  s.get("activity_count") or 0,
        })

    # ── Current + peak fitness ──────────────────────────────────────────────
    if fitness_history:
        current_snap = fitness_history[-1]
        current_label = current_snap["fitness_label"]
        current_trend = current_snap["trend_direction"]
    else:
        current_label = "Recovering"
        current_trend = "flat"

    # Peak = snapshot with highest raw fitness_value
    peak_snap_raw = max(snapshots_raw, key=lambda s: s.get("fitness_value") or 0) if snapshots_raw else None
    peak_label = peak_snap_raw.get("fitness_label") or "Recovering" if peak_snap_raw else "Recovering"
    peak_month = (peak_snap_raw.get("month") or "")[:7] if peak_snap_raw else ""
    peak_fitness = {"month": peak_month, "label": peak_label} if peak_month else {}

    # years_active from first snapshot to today
    if snapshots_raw:
        first_month = (snapshots_raw[0].get("month") or "")[:7]
        try:
            first_date = datetime.strptime(first_month, "%Y-%m").date()
            years_active = max(1, (date.today() - first_date).days // 365)
        except ValueError:
            years_active = 1
    else:
        years_active = 1

    total_activities = sum(s.get("activity_count") or 0 for s in snapshots_raw)

    # ── Current fitness value (for segment strike score computation) ────────
    current_value = max(
        (s.get("fitness_value") or 0 for s in snapshots_raw),
        default=0.0
    ) if snapshots_raw else 0.0
    # Actually want the LATEST snapshot's value, not the max
    current_value = snapshots_raw[-1].get("fitness_value") or 0.0 if snapshots_raw else 0.0

    # ── Assemble top_segments ───────────────────────────────────────────────
    goal_segment_name = goal_row["target_segment_name"] if goal_row else ""

    top_segments = []
    for seg in segments_raw:
        name        = seg.get("name") or seg.get("segment_name") or "Unknown"
        pr_secs     = seg.get("pr_seconds") or 0
        pr_date     = (seg.get("pr_achieved_at") or "")[:10]
        fitness_at_pr = seg.get("fitness_value_at_pr") or 0.0
        score       = seg.get("strike_score") or 0.0
        top_segments.append({
            "name":             name,
            "pr_seconds":       pr_secs,
            "pr_date":          pr_date,
            "fitness_at_pr":    fitness_label(fitness_at_pr),
            "current_fitness":  current_label,
            "trend_direction":  current_trend,
            "strike_score":     round(score, 2),
            "strike_label":     seg.get("strike_label") or strike_label(score),
            "is_goal_segment":  name == goal_segment_name,
        })

    # Sort: goal segment first, then by strike_score descending
    top_segments.sort(key=lambda s: (not s["is_goal_segment"], -s["strike_score"]))

    # ── Goal context ────────────────────────────────────────────────────────
    if goal_row:
        required_label = goal_row.get("required_fitness_label") or current_label
        weeks_remaining: int | None = None
        if goal_row.get("target_date"):
            try:
                td = datetime.strptime(goal_row["target_date"][:10], "%Y-%m-%d").date()
                days_left = max(0, (td - date.today()).days)
                weeks_remaining = days_left // 7
            except ValueError:
                pass
        goal: dict = {
            "type":                   "segment_pr",
            "segment_name":           goal_segment_name,
            "required_fitness_label": required_label,
            "current_fitness_label":  current_label,
            "has_date":               goal_row.get("target_date") is not None,
        }
        if weeks_remaining is not None:
            goal["weeks_remaining"] = weeks_remaining
    else:
        goal = {
            "type":                   "segment_pr",
            "segment_name":           "",
            "required_fitness_label": current_label,
            "current_fitness_label":  current_label,
            "has_date":               False,
        }

    # ── Final payload (matches AthleteContext.contextPayload shape) ─────────
    payload = {
        "athlete": {
            "name":                  user_name,
            "years_active":          years_active,
            "current_fitness_label": current_label,
            "trend_direction":       current_trend,
        },
        "goal":             goal,
        "peak_fitness":     peak_fitness,
        "fitness_history":  fitness_history,
        "top_segments":     top_segments,
        "recent_weeks":     [],
        "days_since_last_ride": days_since(last_ride),
    }

    # ── Write output ────────────────────────────────────────────────────────
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PATH.write_text(json.dumps(payload, indent=2))
    print(f"\nSaved → {OUTPUT_PATH}")
    print(f"  Athlete:  {user_name}")
    print(f"  Fitness:  {current_label} (trending {current_trend})")
    print(f"  Goal:     {goal_segment_name or 'none'}")
    print(f"  Segments: {len(top_segments)}")
    print(f"  History:  {len(fitness_history)} months")
    print(f"\nRun the playground with real data:")
    print(f"  python3 scripts/enzo_playground.py --mode briefing")


if __name__ == "__main__":
    main()
