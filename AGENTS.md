# AGENTS.md - Developer Guide for Coding Agents

## Build/Test/Lint Commands
- **Dev**: `npm run dev` - Start local Wrangler dev server on http://localhost:8787
- **Deploy**: `npm run deploy` - Deploy to Cloudflare Workers
- **Type Generation**: `npm run cf-typegen` - Regenerate worker-configuration.d.ts after wrangler.jsonc changes
- **Check**: `npm run check` - Run TypeScript and Go checks
- **Go Tests**: `npm run test:go` - Run the Go unit tests
- **E2E**: `npm run test:e2e` - Validate a running local or deployed Worker
- **No lint command configured**

## Code Style Guidelines

**TypeScript (src/):**
- ES2021 target, ES2022 modules with Bundler resolution, strict mode enabled
- Use Wrangler-generated `Env` bindings; augment secret-only bindings in `src/env.d.ts`
- Container classes extend `Container<Env>` with properties such as `defaultPort`, `requiredPorts`, `sleepAfter`, and `envVars`
- Use `getContainer()` for Durable Object stubs and forward the original `Request`

**Go (container_src/):**
- Standard library formatting, grouped imports (stdlib → external → internal)
- JSON struct tags for API responses (camelCase in JSON via backticks)
- HTTP handlers: Check env vars first, return structured JSON responses, log warnings (not errors) for non-critical issues
- Main: Use graceful shutdown with signal handling (SIGINT/SIGTERM) and 5s timeout context

**Error Handling:**
- TypeScript: Return explicit JSON 404 and 405 responses before proxying
- Go: Return structured JSON errors, use `log.Printf()` for warnings, and use `log.Fatal()` only in main

**Environment Variables:** Public values come from `wrangler.jsonc`; credentials come from Worker secrets. Both flow through Worker Env → Container envVars → Go process. Never hardcode secrets.
