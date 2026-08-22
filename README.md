# Cloudflare Containers + R2-backed FUSE mounts

This example mounts an R2 bucket inside a [Cloudflare Container](https://developers.cloudflare.com/containers/) with [tigrisfs](https://github.com/tigrisdata/tigrisfs). The application can then use normal filesystem APIs instead of an S3 client.

It includes:

- A Worker that routes requests to one container instance.
- A container that mounts R2 at `/root/mnt/r2/<bucket-name>`.
- A small Go server that returns up to ten entries from the mounted bucket as JSON.

This pattern is useful for existing applications that expect files, bootstrapping sandboxes with shared assets, and persisting state that does not belong in the container image.

## Run it locally

You need Node.js 22 or later and a running Docker-compatible engine. Go 1.26 or later is also required to run the Go tests outside the image build.

Install the dependencies:

```sh
npm install
```

Update these public values in `wrangler.jsonc`:

```jsonc
"R2_BUCKET_NAME": "your-bucket-name",
"R2_ACCOUNT_ID": "your-account-id",
```

Create local R2 credentials:

```sh
cp .dev.vars.example .dev.vars
```

Replace the placeholders in `.dev.vars` with an R2 Access Key ID and Secret Access Key. Use an [R2 API token](https://developers.cloudflare.com/r2/api/tokens/) scoped to only the bucket and permissions this container needs.

Start the Worker and container:

```sh
npm run dev
```

The first start builds the image. Once it is ready:

```sh
curl http://localhost:8787/
```

The response has this shape:

```json
{
  "bucketName": "your-bucket-name",
  "prefix": "",
  "mountPath": "/root/mnt/r2/your-bucket-name",
  "files": [
    {
      "name": "example.txt",
      "isDir": false,
      "size": 1234
    }
  ],
  "returned": 1,
  "truncated": false
}
```

## Mount a prefix

Set `R2_BUCKET_PREFIX` in `wrangler.jsonc` to expose only one prefix:

```jsonc
"R2_BUCKET_PREFIX": "assets/models",
```

tigrisfs receives this as `bucket-name:assets/models`. The mount path stays `/root/mnt/r2/<bucket-name>`.

## Deploy

Set the production secrets:

```sh
npx wrangler secret put AWS_ACCESS_KEY_ID
npx wrangler secret put AWS_SECRET_ACCESS_KEY
```

Then deploy the Worker and image:

```sh
npm run deploy
```

Docker must be running when Wrangler builds the image.

The example does not add authentication. Anyone who can reach the deployed Worker can list the mounted directory, so put access controls in front of it before exposing sensitive object names.

## Test

Run the type check and Go tests:

```sh
npm run check
```

With `npm run dev` running, exercise the complete Worker-to-container path:

```sh
npm run test:e2e
```

To test a deployed Worker instead:

```sh
E2E_BASE_URL=https://fuse-on-r2.<your-subdomain>.workers.dev npm run test:e2e
```

The end-to-end check waits up to two minutes for a cold container, verifies `/health`, and validates the file-list response.

## Tradeoffs

R2 is object storage, not a POSIX filesystem. Metadata operations and small random reads require network requests, renames are not atomic filesystem renames, and you should not expect local-SSD latency.

The example limits each response to ten directory entries so a request does not enumerate an entire large bucket. It routes all requests to one named container. Pass a stable instance name to `getContainer()` if your application needs one mount per tenant or workload.

Container filesystems are ephemeral. Only data written through the mounted bucket persists across container restarts.

## How it works

1. `src/index.ts` selects the singleton `FUSEDemo` Durable Object and forwards the request.
2. The container starts `tigrisfs` with the R2 S3 endpoint and waits until the mount appears in `/proc/mounts`.
3. The startup process supervises both tigrisfs and the Go server, stopping the container if either exits.
4. The Go server starts only after the mount is ready and reads the mounted directory with `os.File.ReadDir`.
5. After ten minutes without activity, the Container helper stops the instance.

See the [Containers documentation](https://developers.cloudflare.com/containers/), [Container class reference](https://developers.cloudflare.com/containers/container-class/), and [R2 FUSE example](https://developers.cloudflare.com/containers/examples/r2-fuse-mount/) for related patterns.

## License

Apache-2.0. Copyright 2025-2026 Cloudflare, Inc.
