#!/usr/bin/env bats

setup() {
	load test_helper

	# shellcheck source=../../libexec/edit/policy
	source "$SCT_LIBEXECDIR/edit/policy"

	mkdir -p "$BATS_TEST_TMPDIR/$SCT_PROJECT_DIR"
	POLICY_FILE="$BATS_TEST_TMPDIR/$SCT_PROJECT_DIR/settings.json"
	touch "$POLICY_FILE"
}

teardown() {
	unstub_all
}

@test "policy opens editor for default pattern" {
	unset -f open_editor
	stub open_editor \
		"$POLICY_FILE : :"

	cd "$BATS_TEST_TMPDIR"
	run policy
	assert_success
}

@test "policy restarts proxy when file modified and proxy running" {
	mkdir -p "$BATS_TEST_TMPDIR/.devcontainer"
	COMPOSE_FILE="$BATS_TEST_TMPDIR/.devcontainer/compose-all.yml"
	touch "$COMPOSE_FILE"

	unset -f open_editor
	stub open_editor \
		"$POLICY_FILE : sleep 1 && touch '$POLICY_FILE'"

	stub docker \
		"compose -f $COMPOSE_FILE ps mitmproxy --status running --quiet : echo 'proxy-container-id'" \
		"compose -f $COMPOSE_FILE restart mitmproxy : :" \
		"compose -f $COMPOSE_FILE restart wg-client : :"

	cd "$BATS_TEST_TMPDIR"
	run policy
	assert_output --partial "Restarting proxy"
}

@test "policy skips restart when file unchanged" {
	unset -f open_editor
	stub open_editor \
		"$POLICY_FILE : true"

	cd "$BATS_TEST_TMPDIR"
	run policy
	assert_success
	assert_output --partial "Policy file unchanged. Skipping restart."
}

@test "policy skips restart when proxy not running" {
	mkdir -p "$BATS_TEST_TMPDIR/.devcontainer"
	COMPOSE_FILE="$BATS_TEST_TMPDIR/.devcontainer/compose-all.yml"
	touch "$COMPOSE_FILE"

	unset -f open_editor
	stub open_editor \
		"$POLICY_FILE : sleep 1 && touch '$POLICY_FILE'"

	stub docker \
		"compose -f $COMPOSE_FILE ps mitmproxy --status running --quiet : :"

	cd "$BATS_TEST_TMPDIR"
	run policy
	assert_success
	assert_output --partial "proxy service is not running. Skipping restart."
}
