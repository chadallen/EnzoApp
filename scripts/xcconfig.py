"""
Shared helper: parse Config/Debug.xcconfig and return a dict of resolved key-value pairs.

Handles:
  - Line comments (//)
  - Variable references: $(VAR_NAME)
  - The empty-substitution URL trick: https://$()/ → https://
  - Whitespace around = signs

Import this from fetch_data.py and enzo_playground.py instead of setting env vars manually.
"""

import re
from pathlib import Path

# Path to xcconfig relative to this file (scripts/ → EnzoApp/Config/)
_XCCONFIG_PATH = Path(__file__).parent.parent / "EnzoApp" / "Config" / "Debug.xcconfig"


def load(path: Path = _XCCONFIG_PATH) -> dict[str, str]:
    """
    Parse an xcconfig file and return a dict of resolved key-value pairs.
    Env vars take precedence over xcconfig values (allows one-off overrides).
    """
    import os

    raw: dict[str, str] = {}

    if not path.exists():
        return {}

    for line in path.read_text().splitlines():
        # Strip inline comments — anything after // (xcconfig treats // as comment start)
        line = line.split("//")[0].strip()
        if "=" not in line:
            continue
        key, _, value = line.partition("=")
        raw[key.strip()] = value.strip()

    # Resolve $(VAR) references, including the $() empty-string trick
    resolved: dict[str, str] = {}
    for key, value in raw.items():
        def replacer(m: re.Match) -> str:
            ref = m.group(1)
            if ref == "":          # $() → empty string (the URL // workaround)
                return ""
            return resolved.get(ref) or raw.get(ref) or ""
        resolved[key] = re.sub(r"\$\(([^)]*)\)", replacer, value)

    # Env vars win over xcconfig
    for key in resolved:
        env_val = os.environ.get(key)
        if env_val:
            resolved[key] = env_val

    return resolved
