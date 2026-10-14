import {
  APNsClient,
  type APNsResult,
  classify,
  type Device,
  endpoint,
  payload,
  providerToken,
  shouldRemoveToken,
  type StoredNotification,
} from "./apns.ts";
import {
  authorized,
  makeHandler,
  notificationID,
  type PushStore,
} from "./handler.ts";

function assert(value: unknown, message = "Assertion failed"): asserts value {
  if (!value) throw new Error(message);
}
function equal(a: unknown, b: unknown) {
  assert(
    JSON.stringify(a) === JSON.stringify(b),
    `${JSON.stringify(a)} != ${JSON.stringify(b)}`,
  );
}
const id = "10000000-0000-0000-0000-000000000001";
const recipient = "20000000-0000-0000-0000-000000000001";
const actor = "20000000-0000-0000-0000-000000000002";
const activity = "30000000-0000-0000-0000-000000000001";
const secret = "test-webhook-secret-at-least-32-characters";
const notification: StoredNotification = {
  id,
  user_id: recipient,
  actor_user_id: actor,
  activity_id: activity,
  type: "mention",
  is_read: false,
};
const device: Device = {
  id: "40000000-0000-0000-0000-000000000001",
  user_id: recipient,
  device_token: "ab".repeat(32),
  environment: "sandbox",
  version: "50000000-0000-0000-0000-000000000001",
  last_seen_at: "2026-01-01T00:00:00Z",
};
const event = {
  type: "INSERT",
  schema: "public",
  table: "notifications",
  record: { id, user_id: "forged-recipient" },
};
function request(body: unknown = event, key: string | null = secret) {
  return new Request("https://function.invalid", {
    method: "POST",
    headers: key ? { "x-afterwork-webhook-secret": key } : {},
    body: JSON.stringify(body),
  });
}
class Store implements PushStore {
  record: StoredNotification | null = { ...notification };
  registered: Device[] = [{ ...device }];
  claims = new Set<string>();
  removed: string[] = [];
  outcomes: string[] = [];
  lookups = 0;
  notification(_id: string) {
    this.lookups++;
    equal(_id, id);
    return Promise.resolve(this.record);
  }
  devices(_id: string) {
    equal(_id, id);
    return Promise.resolve(this.registered);
  }
  claim(_id: string, device: Device) {
    const key = `${_id}:${device.id}`;
    if (this.claims.has(key)) return Promise.resolve(null);
    this.claims.add(key);
    return Promise.resolve("attempt");
  }
  finish(_id: string, _device: Device, _attempt: string, result: APNsResult) {
    this.outcomes.push(classify(result));
    return Promise.resolve();
  }
  remove(device: Device, _time: number) {
    this.removed.push(device.id);
    return Promise.resolve();
  }
}

Deno.test("authorization rejects absent/wrong/short secrets without database access", async () => {
  const store = new Store();
  const handler = makeHandler({
    secret,
    store,
    send: () => {
      throw new Error("No APNs expected");
    },
  });
  equal((await handler(request(event, null))).status, 401);
  equal((await handler(request(event, "wrong"))).status, 401);
  equal(store.lookups, 0);
  assert(!await authorized(secret, "short"));
  assert(await authorized(secret, secret));
});
Deno.test("invalid events and oversize bodies fail validation", async () => {
  const store = new Store();
  const handler = makeHandler({
    secret,
    store,
    send: () => {
      throw new Error("No APNs expected");
    },
  });
  for (
    const body of [
      null,
      {},
      { ...event, type: "UPDATE" },
      { ...event, schema: "auth" },
      { ...event, record: { id: "bad" } },
      { x: "x".repeat(70_000) },
    ]
  ) {
    equal((await handler(request(body))).status, 400);
  }
  equal(store.lookups, 0);
  equal(notificationID(event), id);
});
Deno.test("canonical recipient and multiple devices; replay is deduplicated", async () => {
  const store = new Store();
  store.registered.push({
    ...device,
    id: "40000000-0000-0000-0000-000000000002",
    environment: "production",
  });
  const sent: string[] = [];
  const handler = makeHandler({
    secret,
    store,
    send: (row, device) => {
      equal(row.user_id, recipient);
      sent.push(device.environment);
      return Promise.resolve({ status: 200, reason: "Success" });
    },
  });
  equal((await handler(request())).status, 200);
  equal(sent, ["sandbox", "production"]);
  const replay = await (await handler(request())).json();
  equal(replay.skipped, 2);
  equal(sent.length, 2);
});
Deno.test("missing/read/self/unsupported/deleted notifications do not push", async () => {
  for (
    const record of [
      null,
      { ...notification, is_read: true },
      { ...notification, actor_user_id: recipient },
      { ...notification, type: "broadcast" },
      { ...notification, activity_id: null },
    ]
  ) {
    const store = new Store();
    store.record = record;
    const handler = makeHandler({
      secret,
      store,
      send: () => {
        throw new Error("No APNs expected");
      },
    });
    equal((await handler(request())).status, 200);
    equal(store.claims.size, 0);
  }
});
Deno.test("rate limiting/network/server failures are retryable and retain devices", async () => {
  for (const status of [0, 429, 500, 503]) {
    const store = new Store();
    const handler = makeHandler({
      secret,
      store,
      send: () => Promise.resolve({ status, reason: "ServiceUnavailable" }),
    });
    equal((await handler(request())).status, 503);
    equal(store.removed.length, 0);
    equal(store.outcomes, ["retry"]);
  }
});
Deno.test("410 cleans up only registrations older than invalidation; credential errors retain tokens", async () => {
  const result = {
    status: 410,
    reason: "Unregistered",
    timestamp: Date.parse("2026-02-01T00:00:00Z"),
  };
  const store = new Store();
  const handler = makeHandler({
    secret,
    store,
    send: () => Promise.resolve(result),
  });
  equal((await handler(request())).status, 200);
  equal(store.removed, [device.id]);
  assert(
    !shouldRemoveToken(
      { ...result, timestamp: Date.parse("2025-01-01") },
      device,
    ),
  );
  assert(!shouldRemoveToken({ status: 400, reason: "BadDeviceToken" }, device));
  equal(classify({ status: 403, reason: "InvalidProviderToken" }), "failed");
  equal(classify({ status: 403, reason: "ExpiredProviderToken" }), "retry");
});
Deno.test("payload is small and contains no database record or profile/comment text", () => {
  const value = payload(notification);
  equal(value.notification_id, id);
  equal(value.activity_id, activity);
  equal(value.type, "mention");
  assert(!JSON.stringify(value).includes(recipient));
  assert(new TextEncoder().encode(JSON.stringify(value)).length < 4096);
  equal(endpoint("sandbox"), "https://api.sandbox.push.apple.com");
  equal(endpoint("production"), "https://api.push.apple.com");
});
Deno.test("native ES256 JWT is verifiable and uses kid/iss/iat with raw 64-byte signature", async () => {
  const keys = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );
  const pkcs8 = new Uint8Array(
    await crypto.subtle.exportKey("pkcs8", keys.privateKey),
  );
  const pem = `-----BEGIN PRIVATE KEY-----\n${
    btoa(String.fromCharCode(...pkcs8))
  }\n-----END PRIVATE KEY-----`;
  const token = await providerToken(
    pem,
    "TESTKEY123",
    "TESTTEAM12",
    1_800_000_000_000,
  );
  const parts = token.split(".");
  const decode = (part: string) =>
    Uint8Array.from(
      atob(part.replaceAll("-", "+").replaceAll("_", "/")),
      (c) => c.charCodeAt(0),
    );
  equal(JSON.parse(new TextDecoder().decode(decode(parts[0]))), {
    alg: "ES256",
    kid: "TESTKEY123",
  });
  equal(JSON.parse(new TextDecoder().decode(decode(parts[1]))), {
    iss: "TESTTEAM12",
    iat: 1_800_000_000,
  });
  equal(decode(parts[2]).length, 64);
  assert(
    await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      keys.publicKey,
      decode(parts[2]),
      new TextEncoder().encode(parts.slice(0, 2).join(".")),
    ),
  );
});
Deno.test("APNs transport sends correct environment/topic/alert headers and reuses provider JWT", async () => {
  const keys = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );
  const pkcs8 = new Uint8Array(
    await crypto.subtle.exportKey("pkcs8", keys.privateKey),
  );
  const pem = `-----BEGIN PRIVATE KEY-----\n${
    btoa(String.fromCharCode(...pkcs8))
  }\n-----END PRIVATE KEY-----`;
  const authorizations: string[] = [];
  const transport: typeof fetch = (input, init) => {
    assert(String(input).startsWith(endpoint(device.environment)));
    const headers = new Headers(init?.headers);
    equal(headers.get("apns-topic"), "com.kingz.AfterWork.AfterWork");
    equal(headers.get("apns-push-type"), "alert");
    equal(headers.get("apns-priority"), "10");
    authorizations.push(headers.get("authorization")!);
    return Promise.resolve(new Response(null, { status: 200 }));
  };
  const client = new APNsClient({
    keyID: "TESTKEY123",
    teamID: "TESTTEAM12",
    privateKey: pem,
    topic: "com.kingz.AfterWork.AfterWork",
  }, transport);
  equal((await client.send(notification, device)).status, 200);
  await client.send(notification, device);
  equal(authorizations[0], authorizations[1]);
});
