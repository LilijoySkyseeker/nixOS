#!/usr/bin/env bash
# Exercises the tcr-* scripts against throwaway fixture git repos, covering
# the mechanical safety/enforcement properties from the TCR spec: baseline
# green/red, pre-existing-change isolation (both worktree and --in-place
# modes), pass->commit, fail->revert->verify, full-suite-vs-focused
# enforcement, the retry limit, and a clean multi-step completion.
#
# This tests the *scripts* (deterministic mechanics). It intentionally does
# not attempt to test the skill's own judgment calls (planning quality,
# anti-cheating reasoning) -- see reference.md's "Anti-cheating" section for
# why those are instructions, not mechanisms, and so aren't script-testable.
#
# Usage: bash run-fixture-tests.sh   (exits 0 iff every check passed)
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SCRIPTS="$(cd "$HERE/../scripts" && pwd -P)"
WORK="$(mktemp -d /tmp/tcr-fixture.XXXXXX)"

PASS=0
FAIL=0
ok()  { echo "  ok   - $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL - $1"; FAIL=$((FAIL + 1)); echo "$LAST_OUT" | sed 's/^/        | /'; }

# Runs a tcr-* script with $1 as cwd; sets LAST_OUT/LAST_RC.
run_in() {
  local d="$1"; shift
  LAST_OUT="$(cd "$d" && "$@" 2>&1)"
  LAST_RC=$?
}

work_root_from_last_out() {
  printf '%s\n' "$LAST_OUT" | sed -n 's/^  work root:[[:space:]]*//p' | head -n1
}

make_fixture_repo() {
  local dir="$1"
  mkdir -p "$dir/lib" "$dir/tests"
  # stack_pop mutates the global STACK array and reports its result via the
  # global STACK_LAST_POPPED, not stdout -- if it returned the value via
  # stdout for `x=$(stack_pop)` capture, the mutation would happen inside
  # command substitution's subshell and never reach the caller's STACK.
  cat > "$dir/lib/stack.sh" <<'LIBEOF'
STACK=()
STACK_LAST_POPPED=""
stack_push() { STACK+=("$1"); }
stack_pop() {
  local n=${#STACK[@]}
  [ "$n" -eq 0 ] && { STACK_LAST_POPPED=""; return 1; }
  STACK_LAST_POPPED="${STACK[$((n - 1))]}"
  unset 'STACK[$((n - 1))]'
  STACK=("${STACK[@]}")
}
stack_peek() {
  local n=${#STACK[@]}
  [ "$n" -eq 0 ] && return 1
  printf '%s\n' "${STACK[$((n - 1))]}"
}
stack_is_empty() { [ "${#STACK[@]}" -eq 0 ]; }
LIBEOF
  cat > "$dir/tests/test_stack.sh" <<'TESTEOF'
#!/usr/bin/env bash
set -e
cd "$(dirname "$0")/.."
. lib/stack.sh
stack_is_empty || { echo "expected empty stack initially"; exit 1; }
stack_push a
stack_push b
[ "$(stack_peek)" = "b" ] || { echo "peek mismatch"; exit 1; }
stack_pop; [ "$STACK_LAST_POPPED" = "b" ] || { echo "pop mismatch (b)"; exit 1; }
stack_pop; [ "$STACK_LAST_POPPED" = "a" ] || { echo "pop mismatch (a)"; exit 1; }
stack_is_empty || { echo "expected empty after popping all"; exit 1; }
echo "test_stack: ok"
TESTEOF
  cat > "$dir/run_tests.sh" <<'RUNEOF'
#!/usr/bin/env bash
set -e
for f in tests/test_*.sh; do
  echo "== $f =="
  bash "$f"
done
RUNEOF
  ( cd "$dir" && git init -q && git config user.email t@t.test && git config user.name Test \
      && git add -A && git commit -q -m "chore: initial stack implementation" )
}

echo "fixture workspace: $WORK"

# ============================================================== Scenario 1 =
echo; echo "--- 1: baseline RED is refused, and --allow-red-baseline overrides ---"
redrepo="$WORK/baseline-red"
mkdir -p "$redrepo/tests"
printf '#!/usr/bin/env bash\nexit 1\n' > "$redrepo/run_tests.sh"
( cd "$redrepo" && git init -q && git config user.email t@t.test && git config user.name Test \
    && git add -A && git commit -q -m "chore: init (red)" ) >/dev/null

run_in "$redrepo" "$SCRIPTS/tcr-status" init --task "should refuse" --full-check "bash run_tests.sh"
[ "$LAST_RC" -ne 0 ] && ok "red baseline refused without --allow-red-baseline" \
  || bad "red baseline refused without --allow-red-baseline"
[ -f "$redrepo/.tcr/state.json" ] && bad "no leftover state after refused init" \
  || ok "no leftover state after refused init"

run_in "$redrepo" "$SCRIPTS/tcr-status" init --task "explicit override" --full-check "bash run_tests.sh" --allow-red-baseline
wr="$(work_root_from_last_out)"
[ "$LAST_RC" -eq 0 ] && [ -n "$wr" ] && ok "init succeeds with --allow-red-baseline" \
  || bad "init succeeds with --allow-red-baseline"

# ============================================================== Scenario 2 =
echo; echo "--- 2: pre-existing uncommitted changes survive (worktree mode) ---"
r2="$WORK/preexisting-worktree"
make_fixture_repo "$r2" >/dev/null
echo "# WIP comment from the user" >> "$r2/lib/stack.sh"
head_before_r2="$(git -C "$r2" rev-parse HEAD)"

run_in "$r2" "$SCRIPTS/tcr-status" init --task "pre-existing changes" --full-check "bash run_tests.sh"
wr2="$(work_root_from_last_out)"
[ "$LAST_RC" -eq 0 ] && ok "init succeeds despite dirty tree (worktree mode)" || bad "init succeeds despite dirty tree (worktree mode)"

if grep -q "WIP comment" "$r2/lib/stack.sh" 2>/dev/null; then
  ok "original working tree still has the user's uncommitted edit"
else
  bad "original working tree still has the user's uncommitted edit"
fi
if [ -n "$wr2" ] && [ -d "$wr2" ] && ! grep -q "WIP comment" "$wr2/lib/stack.sh" 2>/dev/null; then
  ok "isolated worktree is a clean copy of HEAD (no WIP comment)"
else
  bad "isolated worktree is a clean copy of HEAD (no WIP comment)"
fi
[ "$(git -C "$r2" rev-parse HEAD)" = "$head_before_r2" ] && ok "main repo HEAD untouched" || bad "main repo HEAD untouched"
[ -n "$(git -C "$r2" status --porcelain)" ] && ok "main repo still shows the dirty file" || bad "main repo still shows the dirty file"

# ============================================================== Scenario 3 =
echo; echo "--- 3: pre-existing uncommitted changes survive (--in-place / stash) ---"
r3="$WORK/preexisting-inplace"
make_fixture_repo "$r3" >/dev/null
echo "# another WIP edit" >> "$r3/lib/stack.sh"

run_in "$r3" "$SCRIPTS/tcr-status" init --task "in place" --in-place --full-check "bash run_tests.sh"
[ "$LAST_RC" -eq 0 ] && ok "init --in-place succeeds" || bad "init --in-place succeeds"
[ -z "$(git -C "$r3" status --porcelain -- . ':!.tcr')" ] && ok "working tree clean after stashing pre-existing edit" \
  || bad "working tree clean after stashing pre-existing edit"
[ -n "$(git -C "$r3" stash list)" ] && ok "pre-existing edit is recoverable from the stash" \
  || bad "pre-existing edit is recoverable from the stash"

# ============================================================== Scenario 4 =
echo; echo "--- 4: pass -> commit ---"
r4="$WORK/happy-path"
make_fixture_repo "$r4" >/dev/null
head_before_r4="$(git -C "$r4" rev-parse HEAD)"

run_in "$r4" "$SCRIPTS/tcr-status" init --task "add stack_clear" \
  --full-check "bash run_tests.sh" --fast-check "bash tests/test_stack.sh" --max-attempts 3
wr4="$(work_root_from_last_out)"
[ "$LAST_RC" -eq 0 ] && [ -n "$wr4" ] && ok "init succeeds on a green baseline" || bad "init succeeds on a green baseline"

# one coherent behavioral increment: add stack_clear + a test for it
cat >> "$wr4/lib/stack.sh" <<'EOF'
stack_clear() { STACK=(); }
EOF
cat > "$wr4/tests/test_stack_clear.sh" <<'EOF'
#!/usr/bin/env bash
set -e
cd "$(dirname "$0")/.."
. lib/stack.sh
stack_push x
stack_clear
stack_is_empty || { echo "expected empty after stack_clear"; exit 1; }
echo "test_stack_clear: ok"
EOF

run_in "$wr4" "$SCRIPTS/tcr-test" --step "add-stack-clear"
[ "$LAST_RC" -eq 0 ] && ok "tcr-test passes for a genuinely-green increment" || bad "tcr-test passes for a genuinely-green increment"

run_in "$wr4" "$SCRIPTS/tcr-commit" --step "add-stack-clear" -m "feat: add stack_clear"
[ "$LAST_RC" -eq 0 ] && ok "tcr-commit accepts a step that just passed" || bad "tcr-commit accepts a step that just passed"
commits_after_1="$(git -C "$wr4" rev-list --count HEAD)"
[ "$commits_after_1" -eq 2 ] && ok "exactly one new commit was created" || bad "exactly one new commit was created (got $commits_after_1)"
[ -z "$(git -C "$wr4" status --porcelain)" ] && ok "worktree is clean after commit" || bad "worktree is clean after commit"

run_in "$wr4" "$SCRIPTS/tcr-commit" --step "add-stack-clear" -m "should be refused: not tested again"
[ "$LAST_RC" -ne 0 ] && ok "tcr-commit refuses without a fresh passing tcr-test for that step" \
  || bad "tcr-commit refuses without a fresh passing tcr-test for that step"

# ============================================================== Scenario 5 =
echo; echo "--- 5: fail -> revert -> verify green, failure logged ---"
head_before_break="$(git -C "$wr4" rev-parse HEAD)"
# Break stack_pop so it always returns the wrong value; the existing suite
# in tests/test_stack.sh must catch this.
cat > "$wr4/lib/stack.sh" <<'EOF'
STACK=()
STACK_LAST_POPPED=""
stack_push() { STACK+=("$1"); }
stack_pop() { STACK_LAST_POPPED="WRONG"; }
stack_peek() {
  local n=${#STACK[@]}
  [ "$n" -eq 0 ] && return 1
  printf '%s\n' "${STACK[$((n - 1))]}"
}
stack_is_empty() { [ "${#STACK[@]}" -eq 0 ]; }
stack_clear() { STACK=(); }
EOF

run_in "$wr4" "$SCRIPTS/tcr-test" --step "break-pop"
[ "$LAST_RC" -ne 0 ] && ok "tcr-test fails when the suite regresses" || bad "tcr-test fails when the suite regresses"

run_in "$wr4" "$SCRIPTS/tcr-revert" --step "break-pop" --reason "broke stack_pop return value"
[ "$LAST_RC" -eq 0 ] && ok "tcr-revert succeeds and reports verified green" || bad "tcr-revert succeeds and reports verified green"
[ "$(git -C "$wr4" rev-parse HEAD)" = "$head_before_break" ] && ok "HEAD unchanged by the failed attempt" \
  || bad "HEAD unchanged by the failed attempt"
[ -z "$(git -C "$wr4" status --porcelain)" ] && ok "worktree clean after revert" || bad "worktree clean after revert"
if grep -q "stack_pop" "$wr4/lib/stack.sh" 2>/dev/null && ! grep -q "WRONG" "$wr4/lib/stack.sh" 2>/dev/null; then
  ok "broken code is actually gone from the working tree"
else
  bad "broken code is actually gone from the working tree"
fi
[ -f "$wr4/.tcr/failures.md" ] && grep -q "break-pop" "$wr4/.tcr/failures.md" \
  && ok "failure logged to .tcr/failures.md" || bad "failure logged to .tcr/failures.md"

run_in "$wr4" "$SCRIPTS/tcr-verify"
[ "$LAST_RC" -eq 0 ] && ok "tcr-verify independently confirms GREEN after revert" \
  || bad "tcr-verify independently confirms GREEN after revert"

# ============================================================== Scenario 6 =
echo; echo "--- 6: full-suite enforcement (focused/fast pass, full suite fails) ---"
cat > "$wr4/tests/test_broken_feature.sh" <<'EOF'
#!/usr/bin/env bash
echo "this new test always fails"
exit 1
EOF
run_in "$wr4" "$SCRIPTS/tcr-test" --step "new-feature-half-done" --fast
printf '%s\n' "$LAST_OUT" | grep -q "fast check: pass" \
  && ok "fast/focused check reports pass" || bad "fast/focused check reports pass"
[ "$LAST_RC" -ne 0 ] && ok "tcr-test still rejects because FULL_CHECK fails" \
  || bad "tcr-test still rejects because FULL_CHECK fails"
run_in "$wr4" "$SCRIPTS/tcr-commit" --step "new-feature-half-done" -m "should be impossible"
[ "$LAST_RC" -ne 0 ] && ok "tcr-commit cannot be forced through on a focused-only pass" \
  || bad "tcr-commit cannot be forced through on a focused-only pass"
run_in "$wr4" "$SCRIPTS/tcr-revert" --step "new-feature-half-done" --reason "half-finished feature, full suite red"
[ "$LAST_RC" -eq 0 ] && ok "cleaned back up to green" || bad "cleaned back up to green"

# ============================================================== Scenario 7 =
echo; echo "--- 7: stuck-agent protocol at the retry limit ---"
for i in 1 2 3; do
  cat > "$wr4/tests/test_always_fails.sh" <<EOF
#!/usr/bin/env bash
echo "attempt $i still fails"
exit 1
EOF
  run_in "$wr4" "$SCRIPTS/tcr-test" --step "risky-change"
done
printf '%s\n' "$LAST_OUT" | grep -q "STUCK-AGENT PROTOCOL" \
  && ok "stuck-agent banner appears once max_attempts is reached" \
  || bad "stuck-agent banner appears once max_attempts is reached"
run_in "$wr4" "$SCRIPTS/tcr-revert" --step "risky-change" --reason "abandoning after 3 failed attempts" --lesson "don't retry the same idea a 4th time"
[ "$LAST_RC" -eq 0 ] && ok "cleaned back up to green after the stuck step" || bad "cleaned back up to green after the stuck step"

# ============================================================== Scenario 8 =
echo; echo "--- 8: multi-step completion stays green commit after green commit ---"
commits_before="$(git -C "$wr4" rev-list --count HEAD)"
for n in 1 2; do
  echo "stack_noop_$n() { :; }" >> "$wr4/lib/stack.sh"
  run_in "$wr4" "$SCRIPTS/tcr-test" --step "noop-$n"
  [ "$LAST_RC" -eq 0 ] || bad "step noop-$n passes"
  run_in "$wr4" "$SCRIPTS/tcr-commit" --step "noop-$n" -m "chore: add stack_noop_$n"
  [ "$LAST_RC" -eq 0 ] || bad "step noop-$n commits"
done
commits_after="$(git -C "$wr4" rev-list --count HEAD)"
[ "$((commits_after - commits_before))" -eq 2 ] && ok "two more green commits landed" || bad "two more green commits landed"
run_in "$wr4" "$SCRIPTS/tcr-verify"
[ "$LAST_RC" -eq 0 ] && ok "final state is verified GREEN" || bad "final state is verified GREEN"

echo; echo "--- final: main repo was never touched by any of scenario 4-8's work ---"
[ "$(git -C "$r4" rev-parse HEAD)" = "$head_before_r4" ] && ok "main repo HEAD still at its original commit" \
  || bad "main repo HEAD still at its original commit"
[ -z "$(git -C "$r4" status --porcelain)" ] && ok "main repo working tree still clean" || bad "main repo working tree still clean"

# ============================================================== Scenario 9 =
echo; echo "--- 9: end deactivates the session; nothing acts on it afterward ---"
run_in "$wr4" "$SCRIPTS/tcr-status" end
[ "$LAST_RC" -eq 0 ] && ok "tcr-status end succeeds" || bad "tcr-status end succeeds"
run_in "$wr4" "$SCRIPTS/tcr-test" --step "should-not-work"
[ "$LAST_RC" -ne 0 ] && ok "tcr-test refuses to act on a deactivated session" \
  || bad "tcr-test refuses to act on a deactivated session"

echo
echo "================================================================"
echo "PASS: $PASS   FAIL: $FAIL"
if [ "$FAIL" -eq 0 ]; then
  echo "All checks passed. Removing fixture workspace."
  rm -rf "$WORK"
  exit 0
else
  echo "Fixture workspace preserved for inspection: $WORK"
  exit 1
fi
