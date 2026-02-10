# Dev Container Setup

All traffic from the rust dev container is routed through a transparent
[mitmproxy](https://mitmproxy.org/) via WireGuard. This captures HTTP/S,
DNS, and all other TCP/UDP traffic without per-tool proxy configuration.

The WireGuard tunnel and iptables kill switch run in a dedicated
`wg-client` container. The rust container shares its network namespace
via `network_mode: "service:wg-client"` and never receives `NET_ADMIN`,
so processes inside — even root — cannot modify routing, firewall rules,
or the tunnel itself. This is enforced by the kernel, not by capability
drops.

## Testing the proxy setup

A lightweight `test` container is included for verifying the proxy works.
Start it (from the `.devcontainer/` directory):

```sh
docker compose --profile test run --rm test bash
```

Inside the container, verify HTTPS works through the tunnel:

```sh
# Should return 200 (mitmproxy CA is trusted)
curl -s -o /dev/null -w '%{http_code}\n' https://example.com

# Traffic should appear in the mitmproxy web UI
curl https://httpbin.org/get
```

Then open http://localhost:8081 and log in with password `mitmproxy` to
confirm the requests show up in the web UI.

To verify the kill switch blocks direct traffic:

```sh
# Should fail — iptables blocks direct eth0 access
curl --max-time 3 --interface eth0 http://1.1.1.1

# Should fail — no NET_ADMIN to modify firewall
iptables -F OUTPUT
```

To inspect WireGuard state, exec into the wg-client container (which
has `NET_ADMIN`):

```sh
docker exec devcontainer-wg-client-1 wg show
```

## Settings

The sandcat addon (`sandcat_addon.py`) reads
`~/.config/sandcat/settings.json` and provides two features:

1. **Network access rules** — ordered allow/deny rules for outbound requests
2. **Secret substitution** — placeholder replacement so dev containers never see real secrets

### Setup

1. Create the config file:

```sh
mkdir -p ~/.config/sandcat
cp .devcontainer/settings.example.json ~/.config/sandcat/settings.json
```

2. Edit `~/.config/sandcat/settings.json` with your real values:

```json
{
  "secrets": {
    "ANTHROPIC_API_KEY": {
      "value": "sk-ant-real-key-here",
      "hosts": ["api.anthropic.com"]
    }
  },
  "network": [
    {"action": "allow", "host": "*", "method": "GET"},
    {"action": "allow", "host": "*.github.com", "method": "POST"},
    {"action": "deny", "host": "*", "method": "POST"},
    {"action": "allow", "host": "*"}
  ]
}
```

3. Rebuild the dev container.

## Network Access Rules

The `network` array defines ordered access rules evaluated top-to-bottom.
First matching rule wins (like iptables). If no rule matches, the request
is **denied**.

Each rule has:
- `action` — `"allow"` or `"deny"` (required)
- `host` — glob pattern via fnmatch (required)
- `method` — HTTP method to match; omit to match any method (optional)

### Example rules

```json
[
  {"action": "allow", "host": "*", "method": "GET"},
  {"action": "allow", "host": "*.github.com", "method": "POST"},
  {"action": "deny", "host": "*", "method": "POST"},
  {"action": "allow", "host": "*"}
]
```

With these rules:
- `GET` to any host → **allowed** (rule 1)
- `POST` to `api.github.com` → **allowed** (rule 2)
- `POST` to `example.com` → **denied** (rule 3)
- `PUT` to any host → **allowed** (rule 4)
- Empty network list → all requests **denied** (default deny)

## Secret Substitution

Dev containers never see real secret values. Instead, env vars contain
deterministic placeholders (`SANDCAT_PLACEHOLDER_<NAME>`), and the mitmproxy
addon replaces them with real values when requests pass through the proxy.

Inside the container, `echo $ANTHROPIC_API_KEY` will print
`SANDCAT_PLACEHOLDER_ANTHROPIC_API_KEY`. When a request containing that
placeholder reaches mitmproxy, it's replaced with the real key — but only
if the destination host matches the `hosts` allowlist.

### Claude Code

Claude Code requires onboarding before it will use an API key from the
environment. To skip the browser-based login flow, create `~/.claude.json`
inside the container:

```json
{"hasCompletedOnboarding": true}
```

With this in place and `ANTHROPIC_API_KEY` set (via secret substitution),
Claude Code will use the key directly.

### Host patterns

The `hosts` field accepts glob patterns via `fnmatch`:

- `"api.anthropic.com"` — exact match
- `"*.anthropic.com"` — any subdomain
- `"*"` — allow all hosts (use with caution)

### Leak detection

If a placeholder appears in a request to a host **not** in the allowlist,
mitmproxy blocks the request with HTTP 403 and logs a warning. This prevents
accidental secret leakage to unintended services.

### How it works internally

1. The mitmproxy container mounts `~/.config/sandcat/settings.json`
   (read-only) and the `sandcat_addon.py` addon script.
2. On startup, the addon reads `settings.json` and writes `placeholders.env`
   to the `mitmproxy-config` shared volume
   (`/home/mitmproxy/.mitmproxy/placeholders.env`). This file contains lines
   like `export ANTHROPIC_API_KEY="SANDCAT_PLACEHOLDER_ANTHROPIC_API_KEY"`.
3. The rust and test containers mount `mitmproxy-config` read-only at
   `/mitmproxy-config/`. Their shared entrypoint (`container-entrypoint.sh`)
   sources `placeholders.env` after installing the CA cert, so every process
   gets the placeholder values as env vars.
4. On each request, the addon first checks network access rules. If denied,
   the request is blocked with 403.
5. If allowed, the addon checks for secret placeholders in the request,
   verifies the destination host against the secret's allowlist, and either
   substitutes the real value or blocks the request with 403 (leak detection).

Real secrets never leave the mitmproxy container.

### Disabling

Delete or rename `~/.config/sandcat/settings.json`. If the file is absent,
the addon disables itself — no network rules are enforced and no placeholder
env vars are set.

## Architecture

```
                network_mode
┌──────────────┐  shares net  ┌──────────────┐  WG tunnel  ┌──────────────┐
│ rust / test  │ ──────────── │  wg-client   │ ─────────── │  mitmproxy   │ ── internet
│  (no NET_ADMIN)             │  (NET_ADMIN) │             │  (mitmweb)   │
└──────────────┘              └──────────────┘             └──────────────┘
                                                             localhost:8081
                                                             pw: mitmproxy
```

- **mitmproxy** runs `mitmweb --mode wireguard`, creating a WireGuard
  server and storing key pairs in `wireguard.conf`.
- **wg-client** is a dedicated networking container that derives a
  WireGuard client config from those keys, sets up the tunnel with `wg`
  and `ip` commands, and adds iptables kill-switch rules. Only this
  container has `NET_ADMIN`. No user code runs here.
- **rust / test** containers share `wg-client`'s network namespace via
  `network_mode`. They inherit the tunnel and firewall rules but cannot
  modify them (no `NET_ADMIN`). They install the mitmproxy CA cert into
  the system trust store at startup so TLS interception works.
- The mitmproxy web UI on port 8081 shows all intercepted traffic
  (password: `mitmproxy`).

### Why not wg-quick?

`wg-quick` calls `sysctl -w net.ipv4.conf.all.src_valid_mark=1`, which
fails in Docker because `/proc/sys` is read-only. The equivalent sysctl
is set via the `sysctls` option in `docker-compose.yml`, and the
entrypoint script handles interface, routing, and firewall setup manually.

## Rust TLS note

Rust programs using `rustls` with the `webpki-roots` crate bundle CA
certificates at compile time and will not trust the mitmproxy CA. This
project uses `rustls-tls-native-roots` in reqwest so it reads the system
CA store at runtime instead. If you add other HTTP client dependencies,
make sure they also use native cert roots.
