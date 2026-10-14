import {
  type APNsResult,
  classify,
  type Device,
  safeReason,
  shouldRemoveToken,
  type StoredNotification,
} from "./apns.ts";

export interface PushStore {
  notification(id: string): Promise<StoredNotification | null>;
  devices(notificationID: string): Promise<Device[]>;
  claim(notificationID: string, device: Device): Promise<string | null>;
  finish(
    notificationID: string,
    device: Device,
    attemptID: string,
    result: APNsResult,
  ): Promise<void>;
  remove(device: Device, invalidatedAt: number): Promise<void>;
}
export const uuid = (value: unknown): value is string =>
  typeof value === "string" &&
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);

export function notificationID(event: unknown): string | null {
  if (!event || typeof event !== "object") return null;
  const value = event as Record<string, unknown>;
  if (
    value.type !== "INSERT" || value.schema !== "public" ||
    value.table !== "notifications" || !value.record ||
    typeof value.record !== "object"
  ) return null;
  const id = (value.record as Record<string, unknown>).id;
  return uuid(id) ? id : null;
}
export async function authorized(
  received: string | null,
  secret: string,
): Promise<boolean> {
  if (!received || secret.length < 32 || received.length > 1024) return false;
  const hash = async (value: string) =>
    new Uint8Array(
      await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)),
    );
  const [a, b] = await Promise.all([hash(received), hash(secret)]);
  return a.reduce(
    (difference, byte, index) => difference | (byte ^ b[index]),
    0,
  ) === 0;
}
async function readBody(request: Request): Promise<unknown> {
  if (!request.body) throw new Error("Empty body");
  const reader = request.body.getReader();
  let size = 0;
  const chunks: Uint8Array[] = [];
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > 65_536) {
        await reader.cancel();
        throw new Error("Oversized body");
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const data = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    data.set(chunk, offset);
    offset += chunk.length;
  }
  return JSON.parse(new TextDecoder().decode(data));
}

export function makeHandler(
  config: {
    secret: string;
    store: PushStore;
    send: (
      notification: StoredNotification,
      device: Device,
    ) => Promise<APNsResult>;
    log?: (record: Record<string, unknown>) => void;
  },
) {
  return async (request: Request): Promise<Response> => {
    if (request.method !== "POST") {
      return Response.json({ error: "Method not allowed" }, { status: 405 });
    }
    if (
      !await authorized(
        request.headers.get("x-afterwork-webhook-secret"),
        config.secret,
      )
    ) {
      return Response.json({ error: "Unauthorized" }, { status: 401 });
    }
    let id: string | null;
    try {
      id = notificationID(await readBody(request));
    } catch {
      return Response.json({ error: "Invalid notification event" }, {
        status: 400,
      });
    }
    if (!id) {
      return Response.json({ error: "Invalid notification event" }, {
        status: 400,
      });
    }
    try {
      // Treat record.user_id/type/actor/body supplied by the webhook as untrusted.
      const notification = await config.store.notification(id);
      if (
        !notification || !uuid(notification.user_id) ||
        !uuid(notification.activity_id) || notification.is_read ||
        notification.actor_user_id === notification.user_id ||
        !["mention", "activityComment"].includes(notification.type)
      ) {
        return Response.json({ notification_id: id, skipped: true });
      }
      const devices = await config.store.devices(id);
      let sent = 0;
      let skipped = 0;
      let retry = 0;
      let failed = 0;
      // Bounded concurrent workers; every device is visited, with no first-device assumption.
      const queue = [...devices];
      await Promise.all(
        Array.from({ length: Math.min(5, devices.length) }, async () => {
          for (;;) {
            const device = queue.shift();
            if (!device) break;
            if (
              device.user_id !== notification.user_id ||
              !["sandbox", "production"].includes(device.environment) ||
              !/^[0-9a-f]{2,512}$/.test(device.device_token) ||
              device.device_token.length % 2 !== 0
            ) {
              failed++;
              continue;
            }
            const attempt = await config.store.claim(id, device);
            if (!attempt) {
              skipped++;
              continue;
            }
            const response = await config.send(notification, device);
            const result = { ...response, reason: safeReason(response.reason) };
            const outcome = classify(result);
            await config.store.finish(id, device, attempt, result);
            if (shouldRemoveToken(result, device)) {
              await config.store.remove(device, result.timestamp!);
            }
            if (outcome === "sent") sent++;
            else if (outcome === "retry") retry++;
            else failed++;
            config.log?.({
              notification_id: id,
              outcome,
              apns_status: result.status,
              reason: result.reason,
              environment: device.environment,
            });
          }
        }),
      );
      config.log?.({
        notification_id: id,
        target_devices: devices.length,
        sent,
        retry,
        failed,
        skipped,
      });
      return Response.json({
        notification_id: id,
        devices: devices.length,
        sent,
        retry,
        failed,
        skipped,
      }, { status: retry ? 503 : 200 });
    } catch {
      config.log?.({ notification_id: id, outcome: "delivery_error" });
      return Response.json({
        notification_id: id,
        error: "Delivery unavailable",
      }, { status: 503 });
    }
  };
}
