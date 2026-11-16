#!/usr/bin/env bash
# Run every headless test in tests/ and print a one-line summary per test.
#
#   GODOT=/path/to/godot tests/run_all.sh            # all tests
#   GODOT=/path/to/godot tests/run_all.sh slime      # only names containing "slime"
#
# Isolation: each test gets its own throw-away user-data dir and
# PIXELCAT_TEST_MODE=1 (ProgressionManager neither loads nor writes saves), so
# results never depend on earlier tests or on your real save.
# Tests that exercise real saving (REAL_SAVE_TESTS) run with test mode OFF, still
# in their own temp dir. profile_bootstrap additionally runs three stages
# (new, write, verify) that share that dir.
REAL_SAVE_TESTS=" menu_flow "
set -u
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."
filter="${1:-}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0; failed=()

run_one() { # name, extra args...
	local name="$1"; shift
	timeout 180 "$GODOT" --headless --path . --script "res://tests/$name.gd" "$@" 2>&1
}

for file in tests/*.gd; do
	name="$(basename "$file" .gd)"
	[[ -n "$filter" && "$name" != *"$filter"* ]] && continue
	if [[ "$name" == "profile_bootstrap" ]]; then
		ok=1
		for stage in new write verify; do
			out="$(XDG_DATA_HOME="$tmp/$name" run_one "$name" -- "$stage")" || ok=0
			grep -q "PROFILE_BOOTSTRAP_${stage^^}_PASSED" <<<"$out" || ok=0
		done
	else
		test_mode=1
		[[ "$REAL_SAVE_TESTS" == *" $name "* ]] && test_mode=0
		out="$(XDG_DATA_HOME="$tmp/$name" PIXELCAT_TEST_MODE=$test_mode run_one "$name")"; rc=$?
		ok=1
		[[ $rc -eq 0 ]] || ok=0
		grep -q '_PASSED' <<<"$out" || ok=0
		# Godot's exit-time "resources still in use" notice is engine noise.
		grep -v 'resources still in use at exit' <<<"$out" | grep -q '^SCRIPT ERROR\|^ERROR: ' && ok=0
	fi
	if [[ $ok -eq 1 ]]; then pass=$((pass+1)); echo "PASS  $name"
	else fail=$((fail+1)); failed+=("$name"); echo "FAIL  $name"; fi
done
echo "---- $pass passed, $fail failed"
[[ $fail -eq 0 ]] || { printf 'failed: %s\n' "${failed[*]}"; exit 1; }
