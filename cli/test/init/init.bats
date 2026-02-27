#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031

setup() {
	load test_helper
	# shellcheck source=../../libexec/init/init
	source "$SCT_LIBEXECDIR/init/init"

	PROJECT_DIR="$BATS_TEST_TMPDIR/project"
	mkdir -p "$PROJECT_DIR"
}

teardown() {
	unstub_all
}

@test "init rejects invalid --agent value" {
	run init --name my-project --agent "invalid" --path "$PROJECT_DIR"
	assert_failure
	assert_output --partial "Invalid agent: invalid"
}

@test "init rejects invalid --mode value" {
	run init --name my-project --agent claude --mode "invalid" --path "$PROJECT_DIR"
	assert_failure
	assert_output --partial "Invalid mode: invalid"
}

@test "init rejects invalid --ide value" {
	run init --agent claude --mode devcontainer --ide "invalid" --name test --path "$PROJECT_DIR"
	assert_failure
	assert_output --partial "Invalid IDE: invalid (expected: vscode jetbrains none)"
}

@test "init accepts valid --agent and --mode values" {
	skip 'FIXME: cli mode not supported'
	stub policy "$PROJECT_DIR/.sandcat/policy-cli-claude.yaml claude : :"
	stub cli "--policy-file .sandcat/policy-cli-claude.yaml --project-path $PROJECT_DIR --agent claude --name test : :"

	run init --agent claude --mode cli --name test --path "$PROJECT_DIR"
	assert_success
}

@test "init accepts valid --ide value for devcontainer mode" {
	stub policy "$PROJECT_DIR/.sandcat/settings.json claude jetbrains : :"
	stub devcontainer "--policy-file .sandcat/settings.json --project-path $PROJECT_DIR --agent claude --ide jetbrains --name test : :"

	run init --agent claude --mode devcontainer --ide jetbrains --name test --path "$PROJECT_DIR"
	assert_success
}

@test "init interactive flow (cli mode)" {
	skip 'FIXME: cli mode not supported'
	unset -f read_line
	unset -f select_option

	stub read_line "'Project name [empty for default]:' : echo my-interactive-project"
	stub select_option \
		"'Select agent:' claude copilot codex : echo claude" \
		"'Select mode:' cli devcontainer : echo cli"

	local policy_file=".sandcat/policy-cli-claude.yaml"
	stub policy "$PROJECT_DIR/$policy_file claude : :"
	stub cli "--policy-file $policy_file --project-path $PROJECT_DIR --agent claude --name my-interactive-project : :"

	run init --path "$PROJECT_DIR"

	assert_success
}

@test "init interactive flow (devcontainer mode)" {
	unset -f read_line
	unset -f select_option

	stub read_line "'Project name [empty for default]:' : echo ''"
	stub select_option \
		"'Select agent:' claude : echo claude" \
		"'Select mode:' devcontainer cli : echo devcontainer" \
		"'Select IDE:' vscode jetbrains none : echo vscode"

	local expected_name
	expected_name=$(basename "$PROJECT_DIR")-sandbox-devcontainer
	local policy_file=".sandcat/settings.json"

	stub policy "$PROJECT_DIR/$policy_file claude vscode : :"
	stub devcontainer "--policy-file $policy_file --project-path $PROJECT_DIR --agent claude --ide vscode --name $expected_name : :"

	run init --path "$PROJECT_DIR"

	assert_success
}
