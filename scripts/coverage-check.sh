#!/usr/bin/env bash
# RIZ-47: computes total line coverage for the app target(s) from an
# .xcresult bundle produced with -enableCodeCoverage YES, prints a
# human-readable summary, and fails the build if coverage is below
# COVERAGE_THRESHOLD (default 50).
#
# Usage:
#   COVERAGE_THRESHOLD=50 scripts/coverage-check.sh TestResults.xcresult
#
# Outputs (relative to the current working directory):
#   coverage-report.json  - raw `xccov view --report --json` output
#   coverage-report.txt   - human-readable per-file table
#
# Requires: xcrun (Xcode), python3.

set -euo pipefail

RESULT_BUNDLE="${1:-TestResults.xcresult}"
THRESHOLD="${COVERAGE_THRESHOLD:-50}"
JSON_REPORT="${COVERAGE_JSON_REPORT:-coverage-report.json}"
TEXT_REPORT="${COVERAGE_TEXT_REPORT:-coverage-report.txt}"

if [ ! -d "$RESULT_BUNDLE" ]; then
  echo "error: result bundle not found at '$RESULT_BUNDLE'" >&2
  exit 1
fi

if ! command -v xcrun >/dev/null 2>&1; then
  echo "error: xcrun not found (requires full Xcode, not just Command Line Tools)" >&2
  exit 1
fi

echo "Extracting coverage from $RESULT_BUNDLE ..."

# Human-readable per-file table (excludes nothing on its own; filtering for
# the pass/fail decision happens against the JSON below).
XCCOV_TEXT_ERR="$(mktemp)"
if ! xcrun xccov view --report "$RESULT_BUNDLE" >"$TEXT_REPORT" 2>"$XCCOV_TEXT_ERR"; then
  echo "error: failed to generate text coverage report" >&2
  cat "$XCCOV_TEXT_ERR" >&2
  rm -f "$XCCOV_TEXT_ERR"
  exit 1
fi
rm -f "$XCCOV_TEXT_ERR"

# Machine-readable report used for the actual threshold computation.
XCCOV_JSON_ERR="$(mktemp)"
if ! xcrun xccov view --report --json "$RESULT_BUNDLE" >"$JSON_REPORT" 2>"$XCCOV_JSON_ERR"; then
  echo "error: failed to generate JSON coverage report" >&2
  cat "$XCCOV_JSON_ERR" >&2
  rm -f "$XCCOV_JSON_ERR"
  exit 1
fi
rm -f "$XCCOV_JSON_ERR"

if ! command -v python3 >/dev/null 2>&1; then
  echo "error: python3 not found" >&2
  exit 1
fi

python3 - "$JSON_REPORT" "$THRESHOLD" <<'PYEOF'
import json
import sys

json_path, threshold_str = sys.argv[1], sys.argv[2]

try:
    threshold = float(threshold_str)
except ValueError:
    print(f"error: invalid COVERAGE_THRESHOLD '{threshold_str}'", file=sys.stderr)
    sys.exit(1)

with open(json_path) as f:
    data = json.load(f)

targets = data.get("targets", [])
if not targets:
    print("error: no targets found in coverage report", file=sys.stderr)
    sys.exit(1)


def is_test_target(name: str) -> bool:
    lowered = name.lower()
    return "tests" in lowered or "uitests" in lowered or lowered.endswith(".xctest")


app_targets = [t for t in targets if not is_test_target(t.get("name", ""))]
if not app_targets:
    print("error: no non-test targets found in coverage report", file=sys.stderr)
    sys.exit(1)

total_executable = 0
total_covered = 0
files = []

for target in app_targets:
    for f in target.get("files", []):
        executable = f.get("executableLines", 0)
        covered = f.get("coveredLines", 0)
        total_executable += executable
        total_covered += covered
        files.append(
            {
                "name": f.get("name", "?"),
                "path": f.get("path", "?"),
                "coverage": f.get("lineCoverage", 0.0) * 100,
                "executableLines": executable,
            }
        )

total_pct = (total_covered / total_executable * 100) if total_executable else 0.0

files_with_lines = [f for f in files if f["executableLines"] > 0]
least_covered = sorted(files_with_lines, key=lambda f: f["coverage"])[:10]

target_rows = []
for target in app_targets:
    t_executable = 0
    t_covered = 0
    for f in target.get("files", []):
        t_executable += f.get("executableLines", 0)
        t_covered += f.get("coveredLines", 0)
    t_pct = (t_covered / t_executable * 100) if t_executable else 0.0
    target_rows.append(
        {
            "name": target.get("name", "?"),
            "covered": t_covered,
            "executable": t_executable,
            "pct": t_pct,
        }
    )

summary_lines = []
summary_lines.append("| Target | Covered | Executable | Line coverage % |")
summary_lines.append("| --- | --- | --- | --- |")
for row in target_rows:
    summary_lines.append(
        f"| {row['name']} | {row['covered']} | {row['executable']} | {row['pct']:.2f}% |"
    )
summary_lines.append(
    f"| **Total** | **{total_covered}** | **{total_executable}** | **{total_pct:.2f}%** |"
)
summary_lines.append("")
summary_lines.append(f"App target line coverage: {total_pct:.2f}% (threshold: {threshold:.2f}%)")
summary_lines.append(f"Covered lines: {total_covered} / {total_executable}")
summary_lines.append("")
summary_lines.append("Least-covered files:")
for f in least_covered:
    summary_lines.append(f"  {f['coverage']:6.2f}%  {f['path']} ({f['executableLines']} lines)")

summary = "\n".join(summary_lines)
print(summary)

# Also write a small machine-parseable summary for CI steps that want to
# embed these numbers without re-parsing the full JSON report.
with open("coverage-summary.txt", "w") as f:
    f.write(summary + "\n")

if total_pct + 1e-9 < threshold:
    print(f"\nFAIL: coverage {total_pct:.2f}% is below threshold {threshold:.2f}%", file=sys.stderr)
    sys.exit(1)

print(f"\nPASS: coverage {total_pct:.2f}% meets threshold {threshold:.2f}%")
PYEOF
