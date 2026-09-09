#!/usr/bin/env bash
# Runs the headless asteroid-splitting regression check and fails when the
# engine reports physics-server flush errors, which GDScript cannot observe
# from inside the running game.
#
# Usage:  tests/run_split_stress.sh
#         GODOT_BIN=/path/to/godot tests/run_split_stress.sh
set -uo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
godot_bin="${GODOT_BIN:-godot}"

log="$(mktemp)"
trap 'rm -f "$log"' EXIT

"$godot_bin" --headless --path "$project_dir" --script res://tests/split_stress.gd >"$log" 2>&1
status=$?

cat "$log"

if grep -qiE "flushing queries|blocked during in/out signal" "$log"; then
  echo "run_split_stress: FAIL: physics server reported flush errors" >&2
  exit 1
fi

if (( status != 0 )); then
  echo "run_split_stress: FAIL: godot exited with status $status" >&2
  exit "$status"
fi

echo "run_split_stress: OK"
