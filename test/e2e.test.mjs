import assert from "node:assert/strict";
import test from "node:test";

const baseURL = process.env.E2E_BASE_URL ?? "http://localhost:8787";
const timeout = Number(process.env.E2E_TIMEOUT_MS ?? 120_000);

test("rejects unsupported requests", async () => {
  const notFoundResponse = await fetch(new URL("/missing", baseURL), {
    signal: AbortSignal.timeout(timeout),
  });
  assert.equal(notFoundResponse.status, 404);
  assert.deepEqual(await notFoundResponse.json(), { error: "Not found" });

  const methodResponse = await fetch(new URL("/", baseURL), {
    method: "POST",
    signal: AbortSignal.timeout(timeout),
  });
  assert.equal(methodResponse.status, 405);
  assert.equal(methodResponse.headers.get("allow"), "GET, HEAD");
  assert.deepEqual(await methodResponse.json(), {
    error: "Method not allowed",
  });
});

test("lists the mounted R2 bucket through the Worker and Container", async () => {
  const healthResponse = await fetch(new URL("/health", baseURL), {
    signal: AbortSignal.timeout(timeout),
  });
  assert.equal(healthResponse.status, 200);
  assert.equal(await healthResponse.text(), "ok\n");

  const response = await fetch(new URL("/", baseURL), {
    signal: AbortSignal.timeout(timeout),
  });
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^application\/json/);

  const body = await response.json();
  assert.equal(typeof body.bucketName, "string");
  assert.ok(body.bucketName.length > 0);
  assert.equal(typeof body.prefix, "string");
  assert.equal(typeof body.mountPath, "string");
  assert.ok(Array.isArray(body.files));
  assert.ok(body.files.length <= 10);
  assert.equal(body.returned, body.files.length);
  assert.equal(typeof body.truncated, "boolean");

  for (const file of body.files) {
    assert.equal(typeof file.name, "string");
    assert.equal(typeof file.isDir, "boolean");
    assert.equal(typeof file.size, "number");
  }
});
