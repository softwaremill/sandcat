"""
mitmproxy addon: substitute placeholder tokens with real secrets.

Loaded via: mitmweb -s /scripts/substitute_secrets.py

On startup, reads /secrets/secrets.json and writes placeholders.env so that
dev containers can export deterministic placeholder env vars. On each request,
replaces placeholders with real values — but only for allowed hosts. If a
placeholder appears in a request to a disallowed host, the request is blocked
with HTTP 403 (leak detection).
"""

import json
import logging
import os
from fnmatch import fnmatch

from mitmproxy import ctx, http

SECRETS_PATH = "/secrets/secrets.json"
PLACEHOLDERS_ENV_PATH = "/home/mitmproxy/.mitmproxy/placeholders.env"

logger = logging.getLogger(__name__)


class SubstituteSecrets:
    def __init__(self):
        self.secrets: dict[str, dict] = {}  # name -> {value, hosts, placeholder}

    def load(self, loader):
        if not os.path.isfile(SECRETS_PATH):
            logger.info("No secrets.json found — secret substitution disabled")
            return

        with open(SECRETS_PATH) as f:
            raw = json.load(f)

        for name, entry in raw.items():
            placeholder = f"SANDCAT_PLACEHOLDER_{name}"
            self.secrets[name] = {
                "value": entry["value"],
                "hosts": entry.get("hosts", []),
                "placeholder": placeholder,
            }

        # Write placeholders.env for dev containers to source
        lines = []
        for name, entry in self.secrets.items():
            lines.append(f'export {name}="{entry["placeholder"]}"')
        with open(PLACEHOLDERS_ENV_PATH, "w") as f:
            f.write("\n".join(lines) + "\n")

        ctx.log.info(
            f"Loaded {len(self.secrets)} secret(s), wrote {PLACEHOLDERS_ENV_PATH}"
        )

    def request(self, flow: http.HTTPFlow):
        if not self.secrets:
            return

        host = flow.request.pretty_host

        for name, entry in self.secrets.items():
            placeholder = entry["placeholder"]
            value = entry["value"]
            allowed_hosts = entry["hosts"]

            # Check if this placeholder appears anywhere in the request
            present = (
                placeholder in flow.request.url
                or placeholder in str(flow.request.headers)
                or (
                    flow.request.content
                    and placeholder.encode() in flow.request.content
                )
            )

            if not present:
                continue

            # Check host allowlist
            if not any(fnmatch(host, pattern) for pattern in allowed_hosts):
                flow.response = http.Response.make(
                    403,
                    f"Blocked: secret {name!r} not allowed for host {host!r}\n".encode(),
                    {"Content-Type": "text/plain"},
                )
                ctx.log.warn(
                    f"Blocked secret {name!r} leak to disallowed host {host!r}"
                )
                return

            # Substitute placeholder with real value.
            # Only touch each component if the placeholder is actually in it.
            # In transparent/wireguard mode, flow.request.url contains the raw
            # IP; assigning to it (even a no-op) re-parses the URL and clobbers
            # the Host header, breaking upstream routing.
            if placeholder in flow.request.url:
                flow.request.url = flow.request.url.replace(placeholder, value)
            for k, v in flow.request.headers.items():
                if placeholder in v:
                    flow.request.headers[k] = v.replace(placeholder, value)
            if flow.request.content and placeholder.encode() in flow.request.content:
                flow.request.content = flow.request.content.replace(
                    placeholder.encode(), value.encode()
                )


addons = [SubstituteSecrets()]
