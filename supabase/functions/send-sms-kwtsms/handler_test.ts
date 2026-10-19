import { Webhook } from "https://esm.sh/standardwebhooks@1.0.0";
import { createHandler, messageFor, normalizePhone } from "./handler.ts";

function equal(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw Error(
      `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}
const secret = btoa("synthetic-local-hook-test-secret-123");
function signed(payload: unknown, date = new Date()) {
  const body = JSON.stringify(payload);
  return new Request("https://local.invalid", {
    method: "POST",
    body,
    headers: {
      "webhook-id": "evt-test",
      "webhook-timestamp": String(Math.floor(date.getTime() / 1000)),
      "webhook-signature": new Webhook(secret).sign("evt-test", date, body),
    },
  });
}
const payload = { user: { phone: "+96550000000" }, sms: { otp: "123456" } };
function fixture() {
  const config = {
    hookSecret: `v1,whsec_${secret}`,
    username: "testuser",
    password: "testpass",
    sender: "Family",
    test: false,
    language: "ar" as "ar" | "en",
    hashKey: "synthetic-hmac-key-at-least-32-bytes",
    supabaseURL: "https://test.supabase.co",
    serviceKey: "synthetic-service-key",
  };
  const requests: { url: string; body: Record<string, unknown> }[] = [];
  let reservation = "send";
  let result: unknown = {
    result: "OK",
    "msg-id": "test-id",
    numbers: 1,
    "points-charged": 1,
    "balance-after": 90,
  };
  let transportError = false;
  let storageError = false;
  const handler = createHandler(
    () => config,
    // Preserve fetch's promise rejection behavior for the transport-error scenario.
    // deno-lint-ignore require-await
    (async (url, options) => {
      equal(options?.method, "POST");
      const body = JSON.parse(String(options?.body));
      requests.push({ url: String(url), body });
      if (String(url).endsWith("reserve_kwtsms_send")) {
        if (storageError) return new Response("private error", { status: 500 });
        equal(/^[a-f0-9]{64}$/.test(body.p_phone), true);
        equal(/^[a-f0-9]{64}$/.test(body.p_event), true);
        return Response.json(reservation);
      }
      if (String(url).endsWith("finish_kwtsms_send")) {
        return Response.json(null);
      }
      equal(String(url), "https://www.kwtsms.com/API/send/");
      equal(
        new Headers(options?.headers).get("Content-Type"),
        "application/json",
      );
      if (transportError) throw Error("private credentials and phone");
      return Response.json(result);
    }) as typeof fetch,
  );
  return {
    config,
    requests,
    handler,
    reserve: (v: string) => reservation = v,
    result: (v: unknown) => result = v,
    networkFailure: () => transportError = true,
    storageFailure: () => storageError = true,
  };
}

Deno.test("Kuwait normalization rejects unsupported countries, junk, Unicode digits and non-mobile numbers", () => {
  for (const value of ["+96550000000", "0096550000000", "96550000000"]) {
    equal(normalizePhone(value), "96550000000");
  }
  for (
    const value of [
      null,
      96550000000,
      "+965٥٠٠٠٠٠٠٠",
      "96550000000junk",
      "96520000000",
      "+971500000000",
      "9655000000",
      "965 50000000",
    ]
  ) equal(normalizePhone(value), null);
});
Deno.test("signed Arabic and English deliveries preserve Supabase OTP and do not expose sensitive state", async () => {
  for (const language of ["ar", "en"] as const) {
    const f = fixture();
    f.config.language = language;
    const response = await f.handler(signed(payload));
    equal(response.status, 200);
    equal(await response.json(), {});
    const provider = f.requests.find((r) => r.url.includes("kwtsms.com"))!;
    equal(provider.body.mobile, "96550000000");
    equal(provider.body.message, messageFor("123456", language));
    equal(provider.body.test, "0");
    equal(f.requests.length, 3); // reserve, send, outcome; no balance polling
    equal(f.requests[2].body.p_balance, 90);
  }
});
Deno.test("unsigned, expired, tampered and invalid payloads never reach database or provider", async () => {
  const f = fixture();
  equal(
    (await f.handler(
      new Request("https://local.invalid", { method: "POST", body: "{}" }),
    )).status,
    401,
  );
  equal((await f.handler(signed(payload, new Date(0)))).status, 401);
  const original = signed(payload);
  equal(
    (await f.handler(
      new Request(original.url, {
        method: "POST",
        headers: original.headers,
        body: "{}",
      }),
    )).status,
    401,
  );
  for (
    const invalid of [null, {}, { ...payload, sms: { otp: 123456 } }, {
      ...payload,
      sms: { otp: "12345a" },
    }, { ...payload, user: { phone: "+96550000000,96550000001" } }]
  ) {
    equal((await f.handler(signed(invalid))).status, 400);
  }
  equal(f.requests.length, 0);
});
Deno.test("rate limits, duplicates and database failures fail closed before sending", async () => {
  const f = fixture();
  f.reserve("blocked");
  equal((await f.handler(signed(payload))).status, 429);
  f.reserve("accepted");
  equal((await f.handler(signed(payload))).status, 200);
  f.storageFailure();
  equal((await f.handler(signed(payload))).status, 503);
  equal(f.requests.some((r) => r.url.includes("kwtsms.com")), false);
});
Deno.test("provider errors and malformed success are not treated as sent; timeouts never retry", async () => {
  for (
    const result of [
      {
        result: "ERROR",
        code: "ERR003",
        description: "private credentials and phone",
      },
      { result: "OK", numbers: 0, "msg-id": "id" },
      { result: "OK", numbers: 1 },
      "OK:legacy",
    ]
  ) {
    const f = fixture();
    f.result(result);
    const response = await f.handler(signed(payload));
    equal(response.status, 503);
    equal((await response.text()).includes("private"), false);
    equal(f.requests[2].body.p_outcome, "failed");
  }
  const f = fixture();
  f.networkFailure();
  equal((await f.handler(signed(payload))).status, 503);
  equal(f.requests.filter((r) => r.url.includes("kwtsms.com")).length, 1);
  equal(f.requests[2].body.p_outcome, "unknown");
});
Deno.test("test mode uses test=1 and cannot report real delivery success; shared KWT-SMS sender allowed in production (owner 2026-10-19)", async () => {
  const f = fixture();
  f.config.test = true;
  f.config.sender = "KWT-SMS";
  equal((await f.handler(signed(payload))).status, 503);
  equal(f.requests[1].body.test, "1");
  f.config.test = false;
  equal((await f.handler(signed(payload))).status, 200);
  equal(f.requests.length, 6);
  equal(f.requests[4].body.sender, "KWT-SMS");
  equal(f.requests[4].body.test, "0");
});
