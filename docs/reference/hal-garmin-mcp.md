# Garmin MCP connector on hal

A read-only [garmin_mcp](https://github.com/Taxuspt/garmin_mcp) server on hal, reachable from
claude.ai as a custom connector. Set up 2026-11-10. Nothing here is installed by `./install`;
it lives in `david`'s home on hal.

**Re-authenticate about May 2027.** The Garmin tokens last roughly six months (issued
2026-11-10). On hal as `david`: `garmin-mcp-auth --force-reauth`, then restart the server.

## Request path

This repo is public, so the public hostname and mount path are not written here. Read them
on hal with `tailscale funnel status`.

```
claude.ai → https://<hal Funnel hostname>/<mount path>/mcp     (Tailscale Funnel, port 443)
          → Caddy 127.0.0.1:9141  (/mcp only; rewrites Host)
          → garmin-mcp 127.0.0.1:9140  (checks Authorization: Bearer)
```

- Funnel on 443 already served `/` → `127.0.0.1:9121` before this; the connector is an added
  path. Add or change a Funnel path with `tailscale funnel --bg --set-path …`, never
  `tailscale serve` on that port: `serve` turns Funnel off for it. Funnel's other ports (8443,
  10000) are in use tailnet-only. Config before the change:
  `~/.config/garmin-mcp/tailscale-serve.before-20261110.json`.
- Caddy is there because `tailscale serve` forwards the public `Host` header and the MCP SDK
  answers `421 Misdirected Request` to any non-localhost `Host` when bound to loopback.
- **Protocol-version shim.** claude.ai opens with MCP `2026-07-28` (`server/discover`, no
  `initialize`). The pinned server uses SDK `mcp` 1.30, which stops at `2025-11-25` and answers
  `400` with a legacy error body; claude.ai then reports "Couldn't connect to the server". An
  empty `400` did not make it fall back either. What works: Caddy answers any request whose
  `Mcp-Protocol-Version` is not a legacy version with the 2026-07-28
  `UnsupportedProtocolVersionError` (`-32022`, `data.supported: ["2025-11-25"]`, echoing the
  request `id`); claude.ai then retries with `initialize` on `2025-11-25`. Remove the
  `@modern` block once garmin_mcp ships on an SDK that speaks `2026-07-28`.
- **claude.ai connector settings:** Authentication "No sign-in", one request header
  `authorization: Bearer <token>`. The "Couldn't check the server" warning while adding it is
  expected (the server answers `401` until it gets the token); choose Continue anyway.
- `/healthz` and `/readyz` are not exposed publicly (Caddy returns 404); use them on
  `127.0.0.1:9140`.

## Files (hal, account `david`)

| What | Where |
|---|---|
| Server | `~/.local/bin/garmin-mcp`, `uv tool install` pinned to commit `a2ca5fc` |
| Settings, tool allowlist, bearer token | `~/.config/garmin-mcp/env` (mode 600) |
| Launcher | `~/.config/garmin-mcp/run.sh` |
| Garmin tokens | `~/.garminconnect/`, `~/.garminconnect_base64` (owner-only) |
| Caddy | `~/.local/bin/caddy` v2.11.9 (release tarball, sha512 checked), `~/.config/garmin-mcp/Caddyfile` |
| LaunchDaemons | `dev.hal.garmin-mcp`, `dev.hal.garmin-mcp-proxy` (`UserName` david); sources in `~/.config/garmin-mcp/` |
| Logs | `~/Library/Logs/garmin-mcp/` |

## Read-only

`GARMIN_ENABLED_TOOLS` is an explicit allowlist of 29 tools (no profile), all annotated
`readOnlyHint` by the server: activities, splits, strength sets, sleep, HRV, heart rate,
steps, stress, body battery, training readiness and status, weigh-ins, body composition, and
profile and units. After changing it, run `tools/list` and check nothing writes.

## Operate

- Restart (as `admin`): `sudo launchctl kickstart -k system/dev.hal.garmin-mcp` (and
  `…/dev.hal.garmin-mcp-proxy` for Caddy).
- Caddy has `admin off`, so a Caddyfile change needs a restart. As `david`:
  `pkill -u david -f 'caddy run'`; launchd starts it again within 30 seconds.
- What claude.ai asked and got: `~/Library/Logs/garmin-mcp/caddy-access.log` (JSON lines; filter
  on `User-Agent` `Claude-User`).
- Health: `curl -s 127.0.0.1:9140/readyz` → `{"status":"ready"}`; `failed` means re-auth.
- Upgrade: `uv tool install --force --python 3.12 git+https://github.com/Taxuspt/garmin_mcp@<sha>`,
  restart, re-check the tool list.
- Rotate the bearer token: replace `GARMIN_MCP_HTTP_TOKEN` in the env file, restart, and
  re-add the connector on claude.ai.
