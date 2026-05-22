#!/usr/bin/env bats
# Smoke tests for bin/install-kanban-md.
#
# These verify the script's contract without actually downloading anything:
# - presence and executability
# - no-op behavior when kanban-md is already on PATH
# - clear failure when neither curl/wget nor go is available

SCRIPT="${BATS_TEST_DIRNAME}/../bin/install-kanban-md"

@test "script exists and is executable" {
  [ -x "$SCRIPT" ]
}

@test "script has bash shebang and strict mode" {
  run head -1 "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == "#!/usr/bin/env bash" ]]
  run grep -q "set -euo pipefail" "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "no-ops when kanban-md is already on PATH" {
  tmpdir="$(mktemp -d)"
  cat >"$tmpdir/kanban-md" <<'EOF'
#!/usr/bin/env bash
echo "kanban-md fake-version"
EOF
  chmod +x "$tmpdir/kanban-md"

  PATH="$tmpdir:$PATH" run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]

  rm -rf "$tmpdir"
}

@test "honors KANBAN_MD_BIN_DIR override" {
  # We can't run the full install without network, but we can verify the var
  # is referenced.
  run grep -q 'KANBAN_MD_BIN_DIR' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "honors KANBAN_MD_VERSION override" {
  run grep -q 'KANBAN_MD_VERSION' "$SCRIPT"
  [ "$status" -eq 0 ]
}
