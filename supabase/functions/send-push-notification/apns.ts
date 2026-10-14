export type Environment = "sandbox" | "production";
export interface StoredNotification {
  id: string;
  user_id: string;
  type: "mention" | "activityComment" | string;
  activity_id: string | null;
  actor_user_id: string | null;
  is_read: boolean;
}
export interface Device {
  id: string;
  user_id: string;
  device_token: string;
  environment: Environment;
  version: string;
  last_seen_at: string;
}
export interface APNsResult {
  status: number;
  reason: string;
  timestamp?: number;
}

export function endpoint(environment: Environment): string {
  switch (environment) {
    case "sandbox":
      return "https://api.sandbox.push.apple.com";
    case "production":
      return "https://api.push.apple.com";
    default:
      throw new Error("Unsupported APNs environment");
  }
}
export function payload(notification: StoredNotification) {
  return {
    aps: {
      alert: {
        title: notification.type === "mention"
          ? "You were mentioned"
          : "New activity comment",
        body: "Open AfterWork to view the comment.",
      },
      sound: "default",
    },
    activity_id: notification.activity_id,
    notification_id: notification.id,
    type: notification.type,
  };
}
export function classify(result: APNsResult): "sent" | "retry" | "failed" {
  if (result.status === 200) return "sent";
  if (
    result.status === 0 || result.status === 429 || result.status >= 500 ||
    result.reason === "ExpiredProviderToken"
  ) return "retry";
  return "failed";
}
export function shouldRemoveToken(result: APNsResult, device: Device): boolean {
  return result.status === 410 && result.reason === "Unregistered" &&
    typeof result.timestamp === "number" &&
    Number.isFinite(result.timestamp) &&
    result.timestamp >= Date.parse(device.last_seen_at);
}
const safeReasons = new Set([
  "Success",
  "NetworkFailure",
  "BadDeviceToken",
  "DeviceTokenNotForTopic",
  "Unregistered",
  "ExpiredProviderToken",
  "InvalidProviderToken",
  "MissingProviderToken",
  "BadTopic",
  "TopicDisallowed",
  "TooManyRequests",
  "TooManyProviderTokenUpdates",
  "InternalServerError",
  "ServiceUnavailable",
  "Shutdown",
  "BadPayload",
  "PayloadEmpty",
  "PayloadTooLarge",
  "Forbidden",
  "IdleTimeout",
]);
export function safeReason(reason: unknown): string {
  return typeof reason === "string" && safeReasons.has(reason)
    ? reason
    : "UnknownAPNsError";
}

function base64url(data: Uint8Array): string {
  return btoa(String.fromCharCode(...data)).replaceAll("+", "-").replaceAll(
    "/",
    "_",
  ).replace(/=+$/, "");
}
export async function providerToken(
  privateKey: string,
  keyID: string,
  teamID: string,
  now = Date.now(),
): Promise<string> {
  const pem = privateKey.replaceAll("\\n", "\n").replace(
    /-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g,
    "",
  );
  const key = await crypto.subtle.importKey(
    "pkcs8",
    Uint8Array.from(atob(pem), (c) => c.charCodeAt(0)),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const encode = (object: unknown) =>
    base64url(new TextEncoder().encode(JSON.stringify(object)));
  const input = `${encode({ alg: "ES256", kid: keyID })}.${
    encode({ iss: teamID, iat: Math.floor(now / 1000) })
  }`;
  // WebCrypto ECDSA returns the JOSE-required IEEE P1363 r||s encoding.
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      { name: "ECDSA", hash: "SHA-256" },
      key,
      new TextEncoder().encode(input),
    ),
  );
  if (signature.length !== 64) {
    throw new Error("Unsupported ECDSA signature format");
  }
  return `${input}.${base64url(signature)}`;
}

export class APNsClient {
  private cached?: { token: string; created: number };
  constructor(
    private config: {
      keyID: string;
      teamID: string;
      privateKey: string;
      topic: string;
    },
    private transport: typeof fetch,
  ) {}

  async send(
    notification: StoredNotification,
    device: Device,
  ): Promise<APNsResult> {
    if (!this.cached || Date.now() - this.cached.created > 45 * 60 * 1000) {
      this.cached = {
        token: await providerToken(
          this.config.privateKey,
          this.config.keyID,
          this.config.teamID,
        ),
        created: Date.now(),
      };
    }
    try {
      const response = await this.transport(
        `${endpoint(device.environment)}/3/device/${device.device_token}`,
        {
          method: "POST",
          redirect: "error",
          signal: AbortSignal.timeout(10_000),
          headers: {
            authorization: `bearer ${this.cached.token}`,
            "apns-topic": this.config.topic,
            "apns-push-type": "alert",
            "apns-priority": "10",
            "apns-id": notification.id,
            "apns-collapse-id": notification.id,
            "apns-expiration": String(Math.floor(Date.now() / 1000) + 300),
            "content-type": "application/json",
          },
          body: JSON.stringify(payload(notification)),
        },
      );
      if (response.status === 200) return { status: 200, reason: "Success" };
      const error = await response.json().catch(() => ({}));
      const result = {
        status: response.status,
        reason: safeReason(error.reason),
        timestamp: typeof error.timestamp === "number"
          ? error.timestamp
          : undefined,
      };
      if (result.reason === "ExpiredProviderToken") this.cached = undefined;
      return result;
    } catch {
      return { status: 0, reason: "NetworkFailure" };
    }
  }
}
