import { Webhook } from "https://esm.sh/standardwebhooks@1.0.0";

Deno.test("signed hook validates input and handles provider failures without exposing details", async () => {
  const secret = btoa("local-test-secret-for-hook-only-123");
  Deno.env.set("SEND_SMS_HOOK_SECRET", `v1,whsec_${secret}`);
  Deno.env.set("WHATSAPP_TOKEN", "local-test-token");
  Deno.env.set("WHATSAPP_PHONE_NUMBER_ID", "123456");
  let handler: (req: Request) => Promise<Response>;
  const originalServe = Deno.serve;
  const originalFetch = globalThis.fetch;
  let calls = 0;
  let mode = "success";
  // Capture the entry point without starting a network listener.
  Deno.serve = ((h: typeof handler) => { handler = h; }) as typeof Deno.serve;
  globalThis.fetch = (async (_url: unknown, options: RequestInit) => {
    calls++;
    const sent = JSON.parse(String(options.body));
    if (sent.to !== "96550000000" || sent.template.components[0].parameters[0].text !== "123456") throw Error("Unexpected template");
    if (mode === "network") throw Error("private provider details");
    if (mode === "failure") return Response.json({ error: { code: 131026, message: "private provider details" } }, { status: 400 });
    return Response.json({ messages: [{ id: "test" }] });
  }) as typeof fetch;
  const request = (payload: unknown, signed = true) => {
    const body = JSON.stringify(payload);
    const timestamp = new Date();
    return new Request("http://localhost", { method: "POST", body, headers: signed ? {
      "webhook-id": "test-event", "webhook-timestamp": String(Math.floor(timestamp.getTime() / 1000)),
      "webhook-signature": new Webhook(secret).sign("test-event", timestamp, body),
    } : {} });
  };
  const check = async (req: Request, expected: number) => {
    const response = await handler(req);
    if (response.status !== expected) throw Error(`Expected ${expected}, got ${response.status}`);
    if ((await response.text()).includes("private provider details")) throw Error("Provider detail leaked");
  };
  try {
    await import("./index.ts");
    const valid = { user: { phone: "+96550000000" }, sms: { otp: "123456" } };
    await check(request(valid, false), 401);
    await check(request(null), 400);
    await check(request({ user: { phone: 123 }, sms: { otp: "123456" } }), 400);
    await check(request({ user: { phone: "+96550000000junk" }, sms: { otp: "123456" } }), 400);
    await check(request({ user: { phone: "+96550000000" }, sms: { otp: 123456 } }), 400);
    if (calls !== 0) throw Error("Invalid request reached provider");
    await check(request(valid), 200);
    mode = "network";
    await check(request(valid), 503);
    mode = "failure";
    await check(request(valid), 400);
  } finally {
    Deno.serve = originalServe;
    globalThis.fetch = originalFetch;
    for (const key of ["SEND_SMS_HOOK_SECRET", "WHATSAPP_TOKEN", "WHATSAPP_PHONE_NUMBER_ID"]) Deno.env.delete(key);
  }
});
