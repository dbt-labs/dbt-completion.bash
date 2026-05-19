#!/usr/bin/env zsh
# Tests for the zsh _dbt completion script.
#
# Covers the pure logic functions that don't require a running dbt binary or a
# live zsh completion context.  Run with:
#   zsh test.zsh

setopt NO_UNSET

# ─── mock zsh completion builtins ────────────────────────────────────────────
# These builtins are not available outside a real completion context, so we
# define lightweight stubs that capture what would have been offered.

typeset -ga _t_descs=()      # items added via _describe
typeset -ga _t_comps=()      # items added via compadd
typeset -gi _t_files=0       # number of _files calls
typeset -gi _t_compset_calls=0

_describe() {
    # _describe 'tag' array_name — access array by name via dynamic scope
    local list_name="$2"
    _t_descs+=("${(P@)list_name}")
}

compadd() {
    # capture items from: compadd -U -a varname
    local i=1
    while (( i <= $# )); do
        if [[ "${@[i]}" == "-a" ]]; then
            local vn="${@[i+1]}"
            _t_comps+=("${(P@)vn}")
            break
        fi
        i=$(( i + 1 ))
    done
}

_files()   { _t_files=$(( _t_files + 1 )) }
_values()  { : }  # used by _dbt_list_models, not tested here
compset()  { _t_compset_calls=$(( _t_compset_calls + 1 )) }

# ─── source the completion script ────────────────────────────────────────────
# The final bare `_dbt` call at the bottom of the file runs in a non-completion
# context ($words unset, CURRENT=0) so _dbt_bin_info returns 1 immediately.
# Redirect stderr to suppress any "command not found: dbt" noise.
source "${0:h}/_dbt" 2>/dev/null

# ─── test framework ──────────────────────────────────────────────────────────

typeset -gi _pass=0 _fail=0

_ok() {
    local msg="$1"
    _pass=$(( _pass + 1 ))
    print -r "  ok: $msg"
}

_fail() {
    local msg="$1" extra="${2:-}"
    _fail=$(( _fail + 1 ))
    print -r "FAIL: $msg${extra:+ — $extra}"
}

assert_eq() {
    local expected="$1" actual="$2" msg="$3"
    if [[ "$actual" == "$expected" ]]; then
        _ok "$msg"
    else
        _fail "$msg" "expected $(print -rn -- "$expected"), got $(print -rn -- "$actual")"
    fi
}

# assert that array $2..$n-1 contains element $1; last arg is the message
assert_in() {
    local needle="$1" msg="${@[-1]}"
    local -a hay=("${@[2,-2]}")
    if (( ${hay[(I)$needle]} > 0 )); then
        _ok "$msg"
    else
        _fail "$msg" "'$needle' not found in (${(j:, :)hay})"
    fi
}

assert_not_in() {
    local needle="$1" msg="${@[-1]}"
    local -a hay=("${@[2,-2]}")
    if (( ${hay[(I)$needle]} == 0 )); then
        _ok "$msg"
    else
        _fail "$msg" "'$needle' was unexpectedly present"
    fi
}

_reset_mocks() {
    _t_descs=()
    _t_comps=()
    _t_files=0
    _t_compset_calls=0
}

_section() { print "\n── $1 ──" }

# ─── _dbt_core_present_completions ───────────────────────────────────────────

_section "_dbt_core_present_completions"

# Builds a click-style response string; result is left in $_mr.
# Using a global avoids command substitution which strips trailing newlines.
# Usage: _make_response type val desc [type val desc ...]
typeset -g _mr=""
_make_response() {
    _mr=""
    while (( $# >= 3 )); do
        _mr+="$1"$'\n'"$2"$'\n'"$3"$'\n'
        shift 3
    done
}

# 1. No filter: all plain items appear in descriptions
_reset_mocks
_make_response plain --select "Select resources." plain --exclude "Exclude resources."
_dbt_core_present_completions "$_mr" ""
assert_in "--select:Select resources."  "${_t_descs[@]}" "no filter: --select present"
assert_in "--exclude:Exclude resources." "${_t_descs[@]}" "no filter: --exclude present"

# 2. Filter matches only items starting with prefix
_reset_mocks
_make_response \
    plain --select "Select resources." \
    plain --exclude "Exclude resources." \
    plain --selector "YAML selector."
_dbt_core_present_completions "$_mr" "--sel"
assert_in     "--select:Select resources."   "${_t_descs[@]}" "filter --sel: --select included"
assert_in     "--selector:YAML selector."    "${_t_descs[@]}" "filter --sel: --selector included"
assert_not_in "--exclude:Exclude resources." "${_t_descs[@]}" "filter --sel: --exclude excluded"

# 3. Multi-line description does not drop the following entry
#    (this was the --warn-error-options regression: fixed-stride-3 loop broke alignment)
_reset_mocks
multiline_response=$(printf '%s\n' \
    "plain" "--warn-error-options" \
    "First line of long description," \
    "second line of long description." \
    "plain" "--select" "Select resources.")
_dbt_core_present_completions "$multiline_response" "--sel"
assert_in "--select:Select resources." "${_t_descs[@]}" \
    "multi-line desc: --select still found after misaligned triplet"

# 4. Multi-line description on the last entry does not error or loop forever
_reset_mocks
last_multiline=$(printf '%s\n' \
    "plain" "--select" "Select resources." \
    "plain" "--warn-error-options" \
    "First line." "Second line.")
_dbt_core_present_completions "$last_multiline" "" 2>/dev/null
assert_in "--select:Select resources." "${_t_descs[@]}" \
    "multi-line last entry: earlier entry still present"

# 5. Empty description → item goes into plain compadd, not _describe
_reset_mocks
_make_response plain --no-desc ""
_dbt_core_present_completions "$_mr" ""
assert_in "--no-desc" "${_t_comps[@]}" "empty desc: item goes to compadd"

# 6. dir type triggers _files (response intentionally has no description line —
#    also tests the bounds guard added to handle truncated triplets)
_reset_mocks
_dbt_core_present_completions $'dir\n/some/path\n' ""
assert_eq "1" "$_t_files" "dir type: _files called"

# 7. Empty response returns 1 and adds nothing
_reset_mocks
_dbt_core_present_completions "" ""
assert_eq "0" "${#_t_descs[@]}" "empty response: no descs"
assert_eq "0" "${#_t_comps[@]}" "empty response: no comps"

# 8. Description line containing the word "plain" is not mistaken for a type marker
_reset_mocks
tricky=$(printf '%s\n' \
    "plain" "--flag-a" "Use plain text format for output." \
    "plain" "--flag-b" "Another option.")
_dbt_core_present_completions "$tricky" ""
assert_in "--flag-a:Use plain text format for output." "${_t_descs[@]}" \
    "desc containing 'plain' not treated as type marker"
assert_in "--flag-b:Another option." "${_t_descs[@]}" \
    "entry after tricky description still parsed"

# ─── _dbt_core_subcommand_path ───────────────────────────────────────────────

_section "_dbt_core_subcommand_path"

# helper: set words+CURRENT and call the function
_subpath() {
    local -a words=("${@[1,-2]}")
    local CURRENT="${@[-1]}"
    _dbt_core_subcommand_path
}

_subpath "dbt" "run" 3
assert_eq "dbt run" "${reply[1]}" "basic: sub_context is 'dbt run'"
assert_eq "2"       "${reply[2]}" "basic: sub_cword is 2"
assert_eq "0"       "${reply[3]}" "basic: no global flags"

_subpath "dbt" 2
assert_eq "dbt" "${reply[1]}" "bare dbt: sub_context is 'dbt'"
assert_eq "1"   "${reply[2]}" "bare dbt: sub_cword is 1"
assert_eq "0"   "${reply[3]}" "bare dbt: no global flags"

_subpath "dbt" "run" "--project-dir" "/foo" "--sel" 5
assert_eq "dbt run" "${reply[1]}" "flags stripped: sub_context stops before first flag"
assert_eq "2"       "${reply[2]}" "flags stripped: sub_cword is 2"
assert_eq "0"       "${reply[3]}" "flags stripped: no global flags (flag after subcommand)"

# words[2] = "--profiles-dir" → has_global_flags=1 because a flag appears before the subcommand
_subpath "dbt" "--profiles-dir" "/p" "run" 5
assert_eq "dbt"  "${reply[1]}" "global flag before subcommand: sub_context is just 'dbt'"
assert_eq "1"    "${reply[2]}" "global flag before subcommand: sub_cword is 1"
assert_eq "1"    "${reply[3]}" "global flag before subcommand: has_global_flags=1"

_subpath "dbt" "run" "-p" "/p" "--sel" 5
assert_eq "dbt run" "${reply[1]}" "short flag also stops traversal"
assert_eq "0"       "${reply[3]}" "short flag after subcommand: has_global_flags=0"

# CURRENT=2: current word is still being typed, so we never set has_global_flags
# even if it starts with '-' (the user is typing the first arg)
_subpath "dbt" "--sel" 2
assert_eq "dbt" "${reply[1]}" "CURRENT=2, typing flag: sub_context is 'dbt'"
assert_eq "0"   "${reply[3]}" "CURRENT=2: no has_global_flags (current word not yet committed)"

# ─── _dbt_core_build_comp_context ────────────────────────────────────────────

_section "_dbt_core_build_comp_context"

# flag-name: current starts with '-', normalised to '-', filter preserved
_dbt_core_build_comp_context "--sel" "run" "dbt run" "2"
assert_eq "dbt run -" "${reply[1]}" "flag-name: comp_words normalised to 'dbt run -'"
assert_eq "2"          "${reply[2]}" "flag-name: comp_cword = sub_cword"
assert_eq "--sel"      "${reply[3]}" "flag-name: filter_word = '--sel'"

# flag-name with bare '--'
_dbt_core_build_comp_context "--" "run" "dbt run" "2"
assert_eq "dbt run -" "${reply[1]}" "bare --: comp_words normalised"
assert_eq "--"         "${reply[3]}" "bare --: filter_word is '--'"

# flag-name with single '-'
_dbt_core_build_comp_context "-" "run" "dbt run" "2"
assert_eq "dbt run -" "${reply[1]}" "single -: normalises to same 'dbt run -'"
assert_eq "-"          "${reply[3]}" "single -: filter_word is '-'"

# flag-value: prev starts with '-'
_dbt_core_build_comp_context "text" "--log-format" "dbt run" "2"
assert_eq "dbt run --log-format text" "${reply[1]}" "flag-value: flag included in comp_words"
assert_eq "3"                          "${reply[2]}" "flag-value: comp_cword = sub_cword+1"
assert_eq ""                           "${reply[3]}" "flag-value: no filter_word"

# positional / subcommand
_dbt_core_build_comp_context "run" "dbt" "dbt" "1"
assert_eq "dbt run" "${reply[1]}" "positional: current word appended"
assert_eq "1"       "${reply[2]}" "positional: comp_cword = sub_cword"
assert_eq ""        "${reply[3]}" "positional: no filter_word"

# ─── _dbt_core_complete context routing ──────────────────────────────────────
#
# Tests that _dbt_core_complete builds the right comp_words_str / comp_cword
# depending on whether global flags are present.  We mock _dbt_bin_info and
# _dbt_core_fetch_completions so no real dbt binary is needed.

_section "_dbt_core_complete context routing"

# --- mocks ---------------------------------------------------------------
# Capture the last comp_words_str and comp_cword passed to _dbt_core_fetch_completions.
typeset -g  _t_fetch_words="" _t_fetch_cword=""
typeset -gi _t_fetch_calls=0

_dbt_bin_info() {
    # Pretend the binary is at /usr/bin/dbt with a fixed mtime.
    reply=("/usr/bin/dbt" "1234567890")
    return 0
}

_dbt_core_fetch_completions() {
    _t_fetch_words="$2"
    _t_fetch_cword="$3"
    _t_fetch_calls=$(( _t_fetch_calls + 1 ))
    _dbt_response=""   # empty — _dbt_core_present_completions will no-op
}

_reset_complete() {
    _t_fetch_words=""
    _t_fetch_cword=""
    _t_fetch_calls=0
    _t_descs=()
    _t_comps=()
}

# wrapper: sets words+CURRENT as locals (dynamic scope used by _dbt_core_complete)
_call_core_complete() {
    local -a words=("${@[1,-2]}")
    local CURRENT="${@[-1]}"
    _dbt_core_complete
}

# --- normal path (no global flags) ---------------------------------------

# Flag-name completion: "dbt run --<tab>"
# Expected: normalised to "dbt run -", cword=2, filter_word="--" (stripped locally)
_reset_complete
_call_core_complete "dbt" "run" "--" 3
assert_eq "dbt run -" "$_t_fetch_words" "normal path, flag-name: comp_words normalised"
assert_eq "2"          "$_t_fetch_cword" "normal path, flag-name: comp_cword=2"

# Flag-value completion: "dbt run --log-format text<tab>"
# Expected: "dbt run --log-format text", cword=3
_reset_complete
_call_core_complete "dbt" "run" "--log-format" "text" 4
assert_eq "dbt run --log-format text" "$_t_fetch_words" "normal path, flag-value: includes flag"
assert_eq "3"                          "$_t_fetch_cword"  "normal path, flag-value: comp_cword=3"

# Subcommand completion: "dbt run<tab>"
# Expected: "dbt run", cword=1
_reset_complete
_call_core_complete "dbt" "run" 2
assert_eq "dbt run" "$_t_fetch_words" "normal path, positional: current word appended"
assert_eq "1"        "$_t_fetch_cword" "normal path, positional: comp_cword=1"

# --- global-flag path ----------------------------------------------------

# Flag-name completion with global flag: "dbt --profiles-dir /p run --<tab>"
# words = (dbt --profiles-dir /p run --)  CURRENT=5
# Expected: full context "dbt --profiles-dir /p run -" (last word normalised to "-"),
#           cword = CURRENT-1 = 4, filter_word = "--"
_reset_complete
_call_core_complete "dbt" "--profiles-dir" "/p" "run" "--" 5
assert_eq "dbt --profiles-dir /p run -" "$_t_fetch_words" \
    "global-flag path, flag-name: full context with current normalised to -"
assert_eq "4" "$_t_fetch_cword" "global-flag path, flag-name: comp_cword=4"

# Positional completion with global flag: "dbt --profiles-dir /p run<tab>"
# words = (dbt --profiles-dir /p run)  CURRENT=4
# Expected: full context "dbt --profiles-dir /p run", cword=3
_reset_complete
_call_core_complete "dbt" "--profiles-dir" "/p" "run" 4
assert_eq "dbt --profiles-dir /p run" "$_t_fetch_words" \
    "global-flag path, positional: full context preserved"
assert_eq "3" "$_t_fetch_cword" "global-flag path, positional: comp_cword=3"

# ─── _get_project_root ───────────────────────────────────────────────────────

_section "_get_project_root"

# respects DBT_PROJECT_DIR
result=$(DBT_PROJECT_DIR=/custom/dir _get_project_root)
assert_eq "/custom/dir" "$result" "DBT_PROJECT_DIR used directly"

# walks up from a nested directory
tmpdir=$(mktemp -d)
tmpdir=$(cd "$tmpdir" && pwd -P)
mkdir -p "$tmpdir/a/b/c"
touch "$tmpdir/dbt_project.yml"
result=$(cd "$tmpdir/a/b/c" && _get_project_root)
result_canonical=$(cd "$result" 2>/dev/null && pwd -P)
assert_eq "$tmpdir" "$result_canonical" "walks up two levels to find dbt_project.yml"
rm -rf "$tmpdir"

# returns empty when no dbt_project.yml is found anywhere
tmpdir=$(mktemp -d)
result=$(cd "$tmpdir" && _get_project_root 2>/dev/null)
assert_eq "" "$result" "no dbt_project.yml: returns empty"
rm -rf "$tmpdir"

# ─── _dbt_manifest_path ──────────────────────────────────────────────────────

_section "_dbt_manifest_path"

# DBT_MANIFEST_PATH pointing to a real file
tmpfile=$(mktemp)
result=$(DBT_MANIFEST_PATH="$tmpfile" _dbt_manifest_path)
assert_eq "$tmpfile" "$result" "DBT_MANIFEST_PATH used when file exists"
rm -f "$tmpfile"

# DBT_MANIFEST_PATH pointing to a missing file → returns 1
result=$(DBT_MANIFEST_PATH="/no/such/file.json" _dbt_manifest_path 2>/dev/null)
rc=$?
assert_eq "1" "$rc" "DBT_MANIFEST_PATH missing file: returns 1"

# falls back to project root / target/manifest.json
tmpdir=$(mktemp -d)
tmpdir=$(cd "$tmpdir" && pwd -P)
mkdir -p "$tmpdir/target"
touch "$tmpdir/dbt_project.yml" "$tmpdir/target/manifest.json"
result=$(cd "$tmpdir" && _dbt_manifest_path)
result_canonical=$(cd "${result:h}" 2>/dev/null && echo "$(pwd -P)/${result:t}")
assert_eq "$tmpdir/target/manifest.json" "$result_canonical" "falls back to project root manifest"
rm -rf "$tmpdir"

# ─── _dbt --flag=value routing ───────────────────────────────────────────────

_section "_dbt --flag=value routing"

# Override the manifest-based functions so tests don't need a real project.
# These definitions shadow the ones from _dbt for the remainder of the file.
typeset -gi _t_list_models_calls=0 _t_list_selectors_calls=0

_dbt_list_models()    { _t_list_models_calls=$(( _t_list_models_calls + 1 )) }
_dbt_list_selectors() { _t_list_selectors_calls=$(( _t_list_selectors_calls + 1 )) }

_reset_routing() {
    _t_list_models_calls=0
    _t_list_selectors_calls=0
    _t_compset_calls=0
}

# Wrapper: sets words+CURRENT as locals so _dbt() can read them via dynamic scope.
# All non-option args become words; last arg is CURRENT.
_call_dbt() {
    local -a words=("${@[1,-2]}")
    local CURRENT="${@[-1]}"
    _dbt
}

# --select=<value>: compset strips prefix, models listed
_reset_routing
_call_dbt dbt run --select= 3
assert_eq "1" "$_t_compset_calls"     "--select=: compset called"
assert_eq "1" "$_t_list_models_calls" "--select=: models listed"
assert_eq "0" "$_t_list_selectors_calls" "--select=: selectors not listed"

# --exclude=<partial>
_reset_routing
_call_dbt dbt run --exclude=my_mod 3
assert_eq "1" "$_t_compset_calls"     "--exclude=: compset called"
assert_eq "1" "$_t_list_models_calls" "--exclude=: models listed"

# -m=<value> (short flag)
_reset_routing
_call_dbt dbt run -m= 3
assert_eq "1" "$_t_compset_calls"     "-m=: compset called"
assert_eq "1" "$_t_list_models_calls" "-m=: models listed"

# --selector=<partial>: selectors listed, not models
_reset_routing
_call_dbt dbt run --selector=nightly 3
assert_eq "1" "$_t_compset_calls"        "--selector=: compset called"
assert_eq "1" "$_t_list_selectors_calls" "--selector=: selectors listed"
assert_eq "0" "$_t_list_models_calls"    "--selector=: models not listed"

# --select value (space style) still works without compset
_reset_routing
_call_dbt dbt run --select foo 4
assert_eq "0" "$_t_compset_calls"     "--select value: no compset"
assert_eq "1" "$_t_list_models_calls" "--select value: models still listed"

# --selector value (space style)
_reset_routing
_call_dbt dbt run --selector nightly 4
assert_eq "0" "$_t_compset_calls"        "--selector value: no compset"
assert_eq "1" "$_t_list_selectors_calls" "--selector value: selectors still listed"

# ─── summary ─────────────────────────────────────────────────────────────────

print ""
if (( _fail > 0 )); then
    print "${_fail} test(s) FAILED, ${_pass} passed."
    exit 1
else
    print "All ${_pass} tests passed."
fi
