# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Cloudflare Workers + Containers project that demonstrates FUSE (Filesystem in Userspace) on R2. It combines a small TypeScript Worker with a Go container application.

## Architecture

**Dual Runtime Model:**
- **Worker (TypeScript)**: Entry point that validates routes and proxies requests to one container instance
- **Container (Go)**: Containerized application that runs inside Cloudflare's container runtime via Durable Objects

**Key Components:**
- `src/index.ts`: Main Worker entry point and `FUSEDemo` class definition
- `container_src/main.go`: Go HTTP server that runs inside the container
- `container_src/startup.sh`: Mounts R2 and waits for FUSE readiness before starting Go
- `Dockerfile`: Multi-stage Go and tigrisfs build with a minimal Alpine runtime
- `wrangler.jsonc`: Configuration defining container bindings, Durable Object settings, and public bucket settings

**Container Pattern:**
The project uses `@cloudflare/containers` with the `Container` class pattern:
- `FUSEDemo` class extends `Container<Env>` base class
- Configures container behavior (port: 8080, sleep timeout: 10m)
- Passes AWS credentials and bucket configuration to the containerized Go app via `envVars`
- Note: Unlike the template, this implementation does not define custom lifecycle hooks

**Environment Variables Flow:**
Worker secrets and public values flow from Worker `Env` → Container `envVars` → Go process:
```typescript
envVars = {
  AWS_ACCESS_KEY_ID: this.env.AWS_ACCESS_KEY_ID,
  AWS_SECRET_ACCESS_KEY: this.env.AWS_SECRET_ACCESS_KEY,
  BUCKET_NAME: this.env.R2_BUCKET_NAME,
  BUCKET_PREFIX: this.env.R2_BUCKET_PREFIX,
  R2_ACCOUNT_ID: this.env.R2_ACCOUNT_ID,
}
```

**Current Routes:**
- `/` - List up to ten entries from the mounted bucket
- `/health` - Container health check

## Common Commands

**Development:**
```bash
npm run dev          # Start local development server on http://localhost:8787
npm run start        # Alias for dev
```

**Deployment:**
```bash
npm run deploy       # Deploy to Cloudflare Workers
```

**Type Generation:**
```bash
npm run cf-typegen   # Generate worker-configuration.d.ts types via wrangler types
```

**Validation:**
```bash
npm run check        # TypeScript check and Go tests
npm run test:e2e     # Test a running local or deployed Worker
```

## Configuration Details

**Container Configuration (wrangler.jsonc):**
- Project name: `fuse-on-r2`
- Container class: `FUSEDemo` (bound as `FUSEDemo`)
- Image source: `./Dockerfile`
- Max instances: 10
- Durable Object migration tag: `v1` with `new_sqlite_classes: ["FUSEDemo"]`

**Environment Variables (wrangler.jsonc):**
```jsonc
"vars": {
  "R2_BUCKET_NAME": "your-bucket-name",
  "R2_BUCKET_PREFIX": "",
  "R2_ACCOUNT_ID": "your-account-id"
}
```
Credentials are Worker secrets named `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`.

**Compatibility:**
- Date: `2026-08-21`
- Flags: `nodejs_compat` enabled
- Observability: enabled

**TypeScript Config:**
- Target: ES2021
- Module: ES2022 with Bundler resolution
- Strict mode enabled
- JSX support: react-jsx
- Types include `worker-configuration.d.ts` and `node`

## Container Communication

The Worker communicates with containers via:
1. Get the singleton Durable Object stub via `getContainer(env.FUSEDemo)`
2. Forward the original request via `container.fetch(request)`

Environment variables are passed from the `FUSEDemo` class's `envVars` property to the Go container, accessible via `os.Getenv()`.

## Development Notes

**Testing and linting:**
- Go unit tests and a Node.js end-to-end check are configured
- CI runs the type check, Go tests, ShellCheck, and a container image build
- No general-purpose lint command is configured
- `.github/workflows/bonk.yml` handles review comments separately

**Type Generation:**
- Run `npm run cf-typegen` after modifying `wrangler.jsonc` to regenerate `worker-configuration.d.ts`
- This file defines the `Env` interface with Durable Object namespace and variable bindings
