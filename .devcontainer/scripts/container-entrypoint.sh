#!/bin/bash
#
# Entrypoint for containers that share the wg-client's network namespace.
# Installs the mitmproxy CA cert and loads placeholder env vars for secret
# substitution before handing off to the container's main command.
#
set -e

CA_CERT="/mitmproxy-config/mitmproxy-ca-cert.pem"

# The CA cert should already exist (wg-client depends_on mitmproxy healthy),
# but wait briefly in case of a slight race on the shared volume.
elapsed=0
while [ ! -f "$CA_CERT" ]; do
    if [ "$elapsed" -ge 30 ]; then
        echo "Timed out waiting for mitmproxy CA cert" >&2
        exit 1
    fi
    sleep 1
    elapsed=$((elapsed + 1))
done

cp "$CA_CERT" /usr/local/share/ca-certificates/mitmproxy.crt
update-ca-certificates

# Source placeholder env vars for secret substitution (if available)
PLACEHOLDERS_ENV="/mitmproxy-config/placeholders.env"
if [ -f "$PLACEHOLDERS_ENV" ]; then
    . "$PLACEHOLDERS_ENV"
    count=$(grep -c '^export ' "$PLACEHOLDERS_ENV" 2>/dev/null || echo 0)
    echo "Loaded $count secret placeholder(s) from $PLACEHOLDERS_ENV"
    grep '^export ' "$PLACEHOLDERS_ENV" | sed 's/=.*//' | sed 's/^export /  /'
else
    echo "No $PLACEHOLDERS_ENV found — secret substitution disabled"
fi

exec "$@"
