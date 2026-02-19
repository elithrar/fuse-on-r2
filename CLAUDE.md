# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Cloudflare Workers + Containers project that demonstrates FUSE (Filesystem in Userspace) on R2. The project combines a TypeScript Worker (using Hono framework) with a Go-based container application that can mount R2 storage.

## Architecture

**Dual Runtime Model:**
- **Worker (TypeScript)**: Entry point that handles HTTP routing and container orchestration using Hono framework
- **Container (Go)**: Containerized application that runs inside Cloudflare's container runtime via Durable Objects

**Key Components:**
- `src/index.ts`: Main Worker entry point with Hono routes and `FUSEDemo` class definition
- `container_src/main.go`: Go HTTP server that runs inside the container
- `Dockerfile`: Multi-stage build (golang:1.24-alpine -> alpine:3.21) for the container image
- `wrangler.jsonc`: Configuration defining container bindings, Durable Object settings, and AWS credentials

**Container Pattern:**
The project uses `@cloudflare/containers` with the `Container` class pattern:
- `FUSEDemo` class extends `Container<Env>` base class
- Configures container behavior (port: 8080, sleep timeout: 10m)
- Passes AWS credentials and bucket configuration to the containerized Go app via `envVars`
- Note: Unlike the template, this implementation does not define custom lifecycle hooks

**Environment Variables Flow:**
AWS credentials flow from `wrangler.jsonc` → Worker `Env` → Container `envVars` → Go process:
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
- `GET /` - List files in the mounted R2 bucket (uses `getContainer`)

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
  "R2_BUCKET_NAME": "bin",
  "R2_BUCKET_PREFIX": "",
  "R2_ACCOUNT_ID": "..."
}
```
Note: `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` must be set as Wrangler secrets (`wrangler secret put <NAME>`), never in `wrangler.jsonc`.

**Compatibility:**
- Date: `2025-10-08`
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
1. Get Durable Object stub via `getContainer(c.env.FUSEDemo)` helper
2. Forward requests via `container.fetch(c.req.raw)`

Environment variables are passed from the `FUSEDemo` class's `envVars` property to the Go container, accessible via `os.Getenv()`.

## Development Notes

**No Testing/Linting:**
- This project has no test framework or linting configured
- No CI/CD pipelines are set up

**Type Generation:**
- Run `npm run cf-typegen` after modifying `wrangler.jsonc` to regenerate `worker-configuration.d.ts`
- This file defines the `Env` interface with Durable Object namespace and variable bindings
