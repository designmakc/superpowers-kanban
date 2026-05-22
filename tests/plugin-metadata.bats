#!/usr/bin/env bats
# Verify plugin and marketplace metadata is well-formed.

ROOT="${BATS_TEST_DIRNAME}/.."

@test "plugin.json is valid JSON" {
  run python3 -c "import json,sys; json.load(open('${ROOT}/.claude-plugin/plugin.json'))"
  [ "$status" -eq 0 ]
}

@test "marketplace.json is valid JSON" {
  run python3 -c "import json,sys; json.load(open('${ROOT}/.claude-plugin/marketplace.json'))"
  [ "$status" -eq 0 ]
}

@test "plugin.json declares name superpowers-kanban" {
  run python3 -c "import json; print(json.load(open('${ROOT}/.claude-plugin/plugin.json'))['name'])"
  [ "$status" -eq 0 ]
  [ "$output" = "superpowers-kanban" ]
}

@test "marketplace.json references the local plugin" {
  run python3 -c "import json; m=json.load(open('${ROOT}/.claude-plugin/marketplace.json')); print(m['plugins'][0]['name'])"
  [ "$status" -eq 0 ]
  [ "$output" = "superpowers-kanban" ]
}

@test "kanban-init command file exists" {
  [ -f "${ROOT}/commands/kanban-init.md" ]
}

@test "superpowers-kanban skill exists" {
  [ -f "${ROOT}/skills/superpowers-kanban/SKILL.md" ]
}

@test "skill has YAML frontmatter with name and description" {
  run head -5 "${ROOT}/skills/superpowers-kanban/SKILL.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"name: superpowers-kanban"* ]]
  [[ "$output" == *"description:"* ]]
}
