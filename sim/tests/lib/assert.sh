# Minimal assertion helpers for the hs-sim test scripts.
# Source this file, call assert_* functions, end with t_done.
T_PASS=0; T_FAIL=0

_t_ok()   { T_PASS=$((T_PASS+1)); printf '  ok   %s\n' "$1"; }
_t_fail() { T_FAIL=$((T_FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; }

assert_eq() {        # actual expected msg
  if [ "$1" = "$2" ]; then _t_ok "${3:-eq}"; else _t_fail "${3:-eq}" "expected [$2] got [$1]"; fi
}
assert_contains() {  # haystack needle msg
  case "$1" in *"$2"*) _t_ok "${3:-contains $2}";; *) _t_fail "${3:-contains $2}" "[$2] not in [$(printf %s "$1" | head -c 300)]";; esac
}
assert_ok()    { if "$@" >/dev/null 2>&1; then _t_ok "ok: $*"; else _t_fail "ok: $*" "exit $?"; fi; }
assert_fails() { if "$@" >/dev/null 2>&1; then _t_fail "fails: $*" "exited 0"; else _t_ok "fails: $*"; fi; }

t_done() {
  printf '%d passed, %d failed\n' "$T_PASS" "$T_FAIL"
  [ "$T_FAIL" -eq 0 ]
}
