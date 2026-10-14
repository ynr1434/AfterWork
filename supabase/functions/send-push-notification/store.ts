import {
  type APNsResult,
  classify,
  type Device,
  type StoredNotification,
} from "./apns.ts";
import type { PushStore } from "./handler.ts";

/** Server-only REST calls using the Edge Function's built-in service credential. */
export class SupabasePushStore implements PushStore {
  constructor(
    private url: string,
    private serviceKey: string,
    private transport: typeof fetch = fetch,
  ) {}
  private async request(
    path: string,
    method = "GET",
    body?: unknown,
    extraHeaders?: Record<string, string>,
  ): Promise<unknown> {
    const response = await this.transport(`${this.url}/rest/v1/${path}`, {
      method,
      redirect: "error",
      signal: AbortSignal.timeout(10_000),
      headers: {
        apikey: this.serviceKey,
        Authorization: `Bearer ${this.serviceKey}`,
        "Content-Type": "application/json",
        ...extraHeaders,
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    if (!response.ok) throw new Error("Push store request failed");
    const text = await response.text();
    return text ? JSON.parse(text) : null;
  }
  async notification(id: string): Promise<StoredNotification | null> {
    const rows = await this.request(
      `notifications?id=eq.${id}&select=id,user_id,type,activity_id,actor_user_id,is_read&limit=1`,
    ) as StoredNotification[];
    return rows[0] ?? null;
  }
  async devices(notificationID: string): Promise<Device[]> {
    // RPC checks session validity and recipient ownership server-side. Page all devices.
    const devices: Device[] = [];
    for (let offset = 0;; offset += 100) {
      const page = await this.request(
        `rpc/push_recipient_devices?order=id.asc&offset=${offset}&limit=100`,
        "POST",
        { p_notification_id: notificationID },
      ) as Device[];
      devices.push(...page);
      if (page.length < 100) return devices;
    }
  }
  async claim(notificationID: string, device: Device): Promise<string | null> {
    return await this.request("rpc/claim_push_delivery", "POST", {
      p_notification_id: notificationID,
      p_device_id: device.id,
      p_version: device.version,
    }) as string | null;
  }
  async finish(
    notificationID: string,
    device: Device,
    attemptID: string,
    result: APNsResult,
  ): Promise<void> {
    await this.request(
      `push_deliveries?notification_id=eq.${notificationID}&device_id=eq.${device.id}&attempt_id=eq.${attemptID}&status=eq.sending`,
      "PATCH",
      {
        status: classify(result),
        apns_status: result.status,
        reason: result.reason,
        updated_at: new Date().toISOString(),
        lease_until: new Date(Date.now() + 60_000).toISOString(),
      },
    );
  }
  async remove(device: Device, invalidatedAt: number): Promise<void> {
    // Protect tokens re-registered/rotated since this send began.
    await this.request(
      `push_device_tokens?id=eq.${device.id}&version=eq.${device.version}&last_seen_at=lte.${
        encodeURIComponent(new Date(invalidatedAt).toISOString())
      }`,
      "DELETE",
    );
  }
}
