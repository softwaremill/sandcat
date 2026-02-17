#!/bin/bash
#
# vscode-user tasks run via su from app-init.sh.
# /etc/profile.d/ is sourced by the login shell, providing
# GIT_USER_NAME, GIT_USER_EMAIL, and NODE_EXTRA_CA_CERTS.
#
set -e

if [ -n "${GIT_USER_NAME:-}" ]; then
    git config --global user.name "$GIT_USER_NAME"
fi
if [ -n "${GIT_USER_EMAIL:-}" ]; then
    git config --global user.email "$GIT_USER_EMAIL"
fi

# If Java is installed (via mise), import the mitmproxy CA into Java's trust
# store. Java uses its own cacerts and ignores the system CA store.
CA_CERT="/mitmproxy-config/mitmproxy-ca-cert.pem"
if command -v keytool >/dev/null 2>&1 && [ -f "$CA_CERT" ]; then
    JAVA_CACERTS="${JAVA_HOME:-}/lib/security/cacerts"
    if [ -f "$JAVA_CACERTS" ]; then
        if keytool -importcert -trustcacerts -noprompt \
            -alias mitmproxy \
            -file "$CA_CERT" \
            -keystore "$JAVA_CACERTS" \
            -storepass changeit >/dev/null 2>&1; then
            echo "Imported mitmproxy CA into Java trust store"
        else
            echo "Java not found, skipping import of mitmproxy CA into Java trust store" >&2
        fi
    fi
fi

# Best-effort: may fail if network isn't routed yet or CLI was just installed.
claude update || true
