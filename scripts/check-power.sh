#!/bin/bash
# Opt-in power gate (invariant 2): runs `t2m bench-power` on this Mac and compares each scenario's SoC
# power above the idle baseline (cpu+gpu+encoder+decoder, mW) with docs/power-baseline.json.
# Needs mac/build (scripts/build-app.sh, signed, with the Screen Recording grant) and ~1 min/scenario.
# Not part of check-all/CI: it needs real hardware and nothing else running.
#
#   scripts/check-power.sh                   # compare; fails if a scenario is >15% (and >50 mW) worse
#   scripts/check-power.sh --update          # record the current numbers as the baseline
#   TOLERANCE=0.25 scripts/check-power.sh --only 60
set -euo pipefail
cd "$(dirname "$0")/.."
update=0; [[ "${1:-}" == "--update" ]] && { update=1; shift; }
baseline=docs/power-baseline.json
[[ -x mac/build/t2m && -d mac/build/Tab2Mac.app ]] || { echo "mac/build is missing: run mac/scripts/build-app.sh (with someone at the keychain prompt)" >&2; exit 2; }
report="$(mktemp -t t2m-power).json"
mac/build/t2m bench-power --app mac/build/Tab2Mac.app --report "$report" "$@"
python3 - "$report" "$baseline" "$update" "${TOLERANCE:-0.15}" <<'PY'
import json, sys
report, baseline, update, tolerance = sys.argv[1], sys.argv[2], sys.argv[3] == "1", float(sys.argv[4])
def power(s):
    e = s.get("socAboveBaseline") or {}
    return sum(e.get(k, 0.0) for k in ("cpu", "gpu", "encoder", "decoder"))
current = {s["scenario"]: round(power(s), 1) for s in json.load(open(report))["summaries"] if s.get("socAboveBaseline")}
if update:
    json.dump(current, open(baseline, "w"), indent=2, sort_keys=True); print(f"baseline written: {baseline}"); sys.exit(0)
try: reference = json.load(open(baseline))
except FileNotFoundError: sys.exit(f"no {baseline}: run with --update on a known-good build first")
failed = False
for name, mw in sorted(current.items()):
    ref = reference.get(name)
    if ref is None: print(f"  new   {name}: {mw} mW"); continue
    worse = mw > ref * (1 + tolerance) and mw - ref > 50
    failed |= worse
    print(f"  {'FAIL' if worse else 'ok  '}  {name}: {mw} mW (baseline {ref})")
sys.exit(1 if failed else 0)
PY
