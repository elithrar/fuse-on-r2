import { Container, getContainer } from "@cloudflare/containers";

export class FUSEDemo extends Container<Env> {
  defaultPort = 8080;
  pingEndpoint = "localhost/health";
  sleepAfter = "10m";
  envVars = {
    AWS_ACCESS_KEY_ID: this.env.AWS_ACCESS_KEY_ID,
    AWS_SECRET_ACCESS_KEY: this.env.AWS_SECRET_ACCESS_KEY,
    BUCKET_NAME: this.env.R2_BUCKET_NAME,
    BUCKET_PREFIX: this.env.R2_BUCKET_PREFIX,
    R2_ACCOUNT_ID: this.env.R2_ACCOUNT_ID,
  };
}

export default {
  async fetch(request, env) {
    const { pathname } = new URL(request.url);
    if (pathname !== "/" && pathname !== "/health") {
      return Response.json({ error: "Not found" }, { status: 404 });
    }

    if (request.method !== "GET" && request.method !== "HEAD") {
      return Response.json(
        { error: "Method not allowed" },
        {
          status: 405,
          headers: { Allow: "GET, HEAD" },
        },
      );
    }

    try {
      return await getContainer(env.FUSEDemo).fetch(request);
    } catch (error) {
      console.error("Container fetch failed", error);
      return Response.json(
        { error: "Failed to reach container" },
        { status: 502 },
      );
    }
  },
} satisfies ExportedHandler<Env>;
