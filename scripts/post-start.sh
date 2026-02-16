#!/bin/bash
set -e

# The entrypoint writes NODE_EXTRA_CA_CERTS to /etc/profile.d/, but
# postStartCommand may not run in a login shell that sources it.
# Load it explicitly so Node.js trusts the mitmproxy CA for TLS interception.
[ -f /etc/profile.d/sandcat-node-ca.sh ] && . /etc/profile.d/sandcat-node-ca.sh

# Keep the CLI version of Claude Code up to date. The VS Code extension
# updates itself, but the CLI installed via the devcontainer feature does not.
sudo env PATH="$PATH" NODE_EXTRA_CA_CERTS="${NODE_EXTRA_CA_CERTS:-}" claude update
