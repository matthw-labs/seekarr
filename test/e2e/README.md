# E2E tier (tag: `e2e`)

Tier-6 headless tests (plan §7.6) that drive the **real** service clients over
real HTTP against Docker instances. They are **not** part of the offline
`flutter test` gate — `dart_test.yaml` auto-skips the `e2e` tag.

## Run

```bash
docker compose -f docker-compose.e2e.yml up -d   # from repo root
# wait for the containers' healthchecks / first boot
flutter test --tags e2e
docker compose -f docker-compose.e2e.yml down -v
```

## Coverage

| Service  | Covered here | Notes |
|----------|--------------|-------|
| SABnzbd  | ✅ | via `127.0.0.1` + `host_whitelist` in the seed .ini |
| NZBGet   | ✅ | Basic auth + positional JSON-RPC + Hi/Lo |
| Readarr  | ✅ | `X-Api-Key`, *arr v1 contract (image tag `develop`) |
| Unraid   | ❌ | no OS container — stays schema-only (tiers 2-3). See §7.6 |

Seed configs live under `test/e2e/seed/`; credentials are deterministic
(`api_key=test-key`, `nzbget:tegbzn6789`). Capturing a live response here is the
moment to refresh the committed fixtures/contract (plan §7.4).
