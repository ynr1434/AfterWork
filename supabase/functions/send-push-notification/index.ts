import { APNsClient } from "./apns.ts";
import { makeHandler } from "./handler.ts";
import { SupabasePushStore } from "./store.ts";

// Explicit HTTP/2 only. Never silently send through HTTP/1 or switch APNs environments.
let handler: ((request: Request) => Promise<Response>) | undefined;
Deno.serve(async (request) => {
  if (!handler) {
    const required = (name: string) => {
      const value = Deno.env.get(name);
      if (!value) throw new Error("Missing server configuration");
      return value;
    };
    try {
      const secret = required("PUSH_WEBHOOK_SECRET");
      const topic = required("APNS_TOPIC");
      if (secret.length < 32 || topic !== "com.kingz.AfterWork.AfterWork") {
        throw new Error("Invalid server configuration");
      }
      const client = Deno.createHttpClient({ http2: true, http1: false });
      const apns = new APNsClient({
        keyID: required("APNS_KEY_ID"),
        teamID: required("APNS_TEAM_ID"),
        privateKey: required("APNS_PRIVATE_KEY"),
        topic,
      }, (url, init) => fetch(url, { ...init, client }));
      handler = makeHandler({
        secret,
        store: new SupabasePushStore(
          required("SUPABASE_URL"),
          required("SUPABASE_SERVICE_ROLE_KEY"),
        ),
        send: (notification, device) => apns.send(notification, device),
        log: (record) => console.log(JSON.stringify(record)),
      });
    } catch {
      return Response.json({ error: "Push delivery is not configured" }, {
        status: 503,
      });
    }
  }
  return await handler(request);
});
