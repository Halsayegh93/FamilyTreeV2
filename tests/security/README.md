# Security regression checks

Run from the repository root:

```sh
npm ci --prefix tests/security --ignore-scripts
node tests/security/policies.mjs
node tests/security/reliability.mjs
deno test tests/security/functions_test.ts
bash tests/security/run-cache-tests.sh
```

The SQL tests use synthetic in-memory PostgreSQL data through PGlite. The Swift test compiles the actual CacheManager against a temporary directory. No production accounts, storage or notifications are used. Full RLS integration and authenticated UI flows still require a staging project and synthetic accounts.

Deployment order: verify the target project against the built app; apply the 2026090618 and 2026090620 migrations in timestamp order; deploy all affected shared-auth and delivery-guard callers; then install the iOS build. Preserve per-function JWT settings in config.toml. The manual FamilyTree migration workflow targets poxyxsgvzwmnmewytsiw and requires the existing SUPABASE_ACCESS_TOKEN repository secret. The World Cup workflow belongs to a separate project.
