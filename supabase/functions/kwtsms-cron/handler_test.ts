// تجارب kwtsms-cron محلياً بـ fetch مزيّف — لا Supabase ولا KWT حقيقي.
// deno test --allow-env supabase/functions/kwtsms-cron/handler_test.ts
import { ACTION, createHandler } from "./handler.ts";

function equal(actual: unknown, expected: unknown, label = "") {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw Error(`${label} Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
  }
}
const SECRET = "synthetic-webhook-secret-0123456789abcdef";
type Call = { url: string; method: string; headers: Headers; body: Record<string, unknown> | null };

function fixture() {
  const config = {
    webhookSecret: SECRET,
    username: "testuser",
    password: "secret-pass-xyz",
    supabaseURL: "https://test.supabase.co",
    serviceKey: "synthetic-service-key",
  };
  const calls: Call[] = [];
  const state = {
    // deno-lint-ignore no-explicit-any
    balance: { result: "OK", available: 42, purchased: 1000 } as any,
    kwtStatus: 200,
    kwtThrows: null as Error | null,
    kwtRaw: null as string | null,
    rpcStatus: 200,
    rpcThrows: false,
    // deno-lint-ignore no-explicit-any
    rpcResult: { recorded: true, state: "low", alerted: true } as any,
  };
  const handler = createHandler(
    () => config,
    // deno-lint-ignore require-await
    (async (url, init) => {
      const u = String(url);
      const body = init?.body ? JSON.parse(String(init.body)) : null;
      calls.push({ url: u, method: String(init?.method), headers: new Headers(init?.headers), body });
      if (u === "https://www.kwtsms.com/API/balance/") {
        if (state.kwtThrows) throw state.kwtThrows;
        if (state.kwtRaw !== null) return new Response(state.kwtRaw, { status: state.kwtStatus });
        return Response.json(state.balance, { status: state.kwtStatus });
      }
      if (u === "https://test.supabase.co/rest/v1/rpc/kwtsms_balance_check") {
        if (state.rpcThrows) throw Error("network");
        if (state.rpcStatus !== 200) return new Response("private error", { status: state.rpcStatus });
        return Response.json(state.rpcResult);
      }
      throw Error(`unexpected fetch ${u}`);
    }) as typeof fetch,
  );
  return { config, calls, state, handler };
}
const call = (
  handler: (r: Request) => Promise<Response>,
  { secret = SECRET as string | null, body = { action: ACTION } as unknown, method = "POST" } = {},
) => {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (secret !== null) headers["x-webhook-secret"] = secret;
  return handler(
    new Request("https://edge.test/kwtsms-cron", {
      method,
      headers,
      body: method === "GET" ? undefined : typeof body === "string" ? body : JSON.stringify(body),
    }),
  );
};
// يلتقط console.error حتى نتأكد أن لا سرّ ولا بيانات دخول تُسجَّل
async function capture<T>(fn: () => Promise<T>): Promise<{ value: T; logs: string[] }> {
  const logs: string[] = [];
  const original = console.error;
  console.error = (...args: unknown[]) => logs.push(args.map(String).join(" "));
  try {
    return { value: await fn(), logs };
  } finally {
    console.error = original;
  }
}

Deno.test("auth: missing, wrong, prefix and longer secrets are rejected before KWT or storage", async () => {
  for (const secret of [null, "", "wrong", SECRET.slice(0, -1), SECRET + "x", SECRET.toUpperCase(), `Bearer ${SECRET}`]) {
    const f = fixture();
    const res = await call(f.handler, { secret });
    equal(res.status, 401, `secret=${secret}`);
    equal((await res.json()).error.code, "unauthorized");
    equal(f.calls.length, 0, "no outbound call");
  }
});

Deno.test("auth: a service-role or user JWT in Authorization is not enough", async () => {
  const f = fixture();
  const res = await f.handler(
    new Request("https://edge.test/kwtsms-cron", {
      method: "POST",
      headers: { Authorization: `Bearer ${f.config.serviceKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({ action: ACTION }),
    }),
  );
  equal(res.status, 401);
  equal(f.calls.length, 0);
});

Deno.test("not configured: no secret / short secret → 503 (never open), bad KWT or Supabase config → 503", async () => {
  for (const patch of [{ webhookSecret: "" }, { webhookSecret: "short" }]) {
    const f = fixture();
    Object.assign(f.config, patch);
    const res = await call(f.handler, { secret: patch.webhookSecret });
    equal(res.status, 503, JSON.stringify(patch));
    equal((await res.json()).error.code, "not_configured");
    equal(f.calls.length, 0);
  }
  for (const patch of [{ username: "" }, { password: "" }, { serviceKey: "" }, { supabaseURL: "http://evil.example" },
    { username: "x".repeat(16) }, { password: "x".repeat(31) }]) {
    const f = fixture();
    Object.assign(f.config, patch);
    const res = await call(f.handler);
    equal(res.status, 503, JSON.stringify(patch));
    equal(f.calls.length, 0);
  }
});

Deno.test("method and body: GET → 405, bad JSON / wrong action / oversized → 400, nothing called", async () => {
  let f = fixture();
  equal((await call(f.handler, { method: "GET" })).status, 405);
  for (const body of ["not json", { action: "send" }, {}, { action: ACTION, pad: "x".repeat(2000) }]) {
    f = fixture();
    const res = await call(f.handler, { body });
    equal(res.status, 400, JSON.stringify(body).slice(0, 40));
    equal(f.calls.length, 0);
  }
});

Deno.test("success: KWT balance (fixed URL, POST JSON, credentials only in body) → RPC with the balance → 200", async () => {
  const f = fixture();
  const res = await call(f.handler);
  equal(res.status, 200);
  equal(await res.json(), { ok: true, balance: 42, state: "low", alerted: true });
  equal(f.calls.length, 2);
  const [kwt, rpc] = f.calls;
  equal([kwt.url, kwt.method], ["https://www.kwtsms.com/API/balance/", "POST"]);
  equal(kwt.body, { username: "testuser", password: "secret-pass-xyz" });
  equal(kwt.headers.get("x-webhook-secret"), null, "secret never forwarded to KWT");
  equal(kwt.headers.get("authorization"), null, "no service key to KWT");
  equal([rpc.url, rpc.method], ["https://test.supabase.co/rest/v1/rpc/kwtsms_balance_check", "POST"]);
  equal(rpc.body, { p_balance: 42 });
  equal(rpc.headers.get("authorization"), "Bearer synthetic-service-key");
  equal(rpc.headers.get("apikey"), "synthetic-service-key");
  equal(JSON.stringify(rpc.body).includes("secret-pass"), false, "credentials not sent to storage");
});

Deno.test("success: string balance, zero balance and unknown RPC shape are handled", async () => {
  let f = fixture();
  f.state.balance = { result: "OK", available: "7.5" };
  f.state.rpcResult = { recorded: true, state: "urgent", alerted: false };
  let res = await call(f.handler);
  equal(await res.json(), { ok: true, balance: 7.5, state: "urgent", alerted: false });
  equal(f.calls[1].body, { p_balance: 7.5 });
  f = fixture();
  f.state.balance = { result: "OK", available: 0 };
  f.state.rpcResult = null;
  res = await call(f.handler);
  equal(res.status, 200);
  equal(await res.json(), { ok: true, balance: 0, state: null, alerted: false });
});

Deno.test("KWT failure → no storage call, no alert, no crash (provider error, bad balance, HTTP error, garbage)", async () => {
  const cases: Array<[string, (s: ReturnType<typeof fixture>["state"]) => void, number, string, string | null]> = [
    ["ERR003 wrong credentials", (s) => (s.balance = { result: "ERROR", code: "ERR003", description: "x" }), 502,
      "provider_error", "ERR003"],
    ["OK without available", (s) => (s.balance = { result: "OK" }), 502, "provider_error", "UNKNOWN"],
    ["negative balance", (s) => (s.balance = { result: "OK", available: -5 }), 502, "provider_error", "UNKNOWN"],
    ["non-numeric balance", (s) => (s.balance = { result: "OK", available: "12abc" }), 502, "provider_error", "UNKNOWN"],
    ["HTTP 500", (s) => (s.kwtStatus = 500), 502, "provider_error", "UNKNOWN"],
    ["HTML body", (s) => (s.kwtRaw = "<html>maintenance</html>"), 502, "provider_error", "UNKNOWN"],
    ["odd code text", (s) => (s.balance = { result: "ERROR", code: "<script>" }), 502, "provider_error", "UNKNOWN"],
  ];
  for (const [label, setup, status, code, providerCode] of cases) {
    const f = fixture();
    setup(f.state);
    const { value: res, logs } = await capture(() => call(f.handler));
    equal(res.status, status, label);
    const json = await res.json();
    equal(json.error.code, code, label);
    equal(json.error.provider_code ?? null, providerCode, label);
    equal(f.calls.map((x) => x.url), ["https://www.kwtsms.com/API/balance/"], `${label}: no storage`);
    equal(logs.some((l) => /secret-pass|testuser|synthetic/.test(l)), false, `${label}: no credentials logged`);
  }
});

Deno.test("KWT timeout / network → 504, single attempt (no retry), no storage", async () => {
  for (const err of [new DOMException("timed out", "TimeoutError"), new TypeError("network")]) {
    const f = fixture();
    f.state.kwtThrows = err;
    const { value: res, logs } = await capture(() => call(f.handler));
    equal(res.status, 504);
    equal((await res.json()).error.code, "provider_unavailable");
    equal(f.calls.length, 1, "exactly one KWT call");
    equal(logs, ["[kwtsms-cron] balance transport failure"]);
  }
});

Deno.test("storage failure → 503 with the balance, KWT called once, no crash, nothing secret logged", async () => {
  for (const setup of [(s: ReturnType<typeof fixture>["state"]) => (s.rpcStatus = 500), (s: ReturnType<typeof fixture>["state"]) => (s.rpcThrows = true)]) {
    const f = fixture();
    setup(f.state);
    const { value: res, logs } = await capture(() => call(f.handler));
    equal(res.status, 503);
    equal(await res.json(), { ok: false, error: { code: "storage_unavailable", balance: 42 } });
    equal(f.calls.filter((x) => x.url.includes("kwtsms.com")).length, 1);
    equal(logs, ["[kwtsms-cron] balance check persistence failed"]);
  }
});

Deno.test("timeouts are bounded on every outbound call", async () => {
  const f = fixture();
  const signals: Array<AbortSignal | null | undefined> = [];
  // deno-lint-ignore require-await
  const handler = createHandler(() => f.config, (async (url: string | URL | Request, init?: RequestInit) => {
    signals.push(init?.signal);
    return String(url).includes("kwtsms.com")
      ? Response.json({ result: "OK", available: 100 })
      : Response.json({ recorded: true, state: "ok", alerted: false });
  }) as typeof fetch);
  const res = await call(handler);
  equal(res.status, 200);
  equal(signals.length, 2);
  equal(signals.every((s) => s instanceof AbortSignal), true, "every call has an abort signal");
});

// ── فحص الوصول التلقائي (status_sweep، ٢٠٢٦-١٠-٢٣) ──
function sweepFixture(pending: unknown, statuses: Record<string, unknown>, recordOk = true) {
  const config = { webhookSecret: SECRET, username: "testuser", password: "secret-pass-xyz",
    supabaseURL: "https://test.supabase.co", serviceKey: "synthetic-service-key" };
  const recorded: Record<string, unknown>[] = [];
  const kwtCalls: Record<string, unknown>[] = [];
  const handler = createHandler(() => config, (async (url, init) => {
    const u = String(url);
    const body = init?.body ? JSON.parse(String(init.body)) : null;
    if (u === "https://test.supabase.co/rest/v1/rpc/kwtsms_pending_status_checks") return Response.json(pending);
    if (u === "https://test.supabase.co/rest/v1/rpc/record_kwtsms_delivery_status") {
      recorded.push(body);
      return Response.json(recordOk);
    }
    if (u === "https://www.kwtsms.com/API/status/") {
      kwtCalls.push(body);
      const s = statuses[body.msgid];
      if (s instanceof Error) throw s;
      return Response.json(s);
    }
    throw Error(`unexpected fetch ${u}`);
  }) as typeof fetch);
  return { handler, recorded, kwtCalls };
}

Deno.test("status_sweep: checks each pending message once and stores its status", async () => {
  const f = sweepFixture(["m1", "m2", "m3"], {
    m1: { result: "OK", status: "Delivered" },
    m2: { result: "ERROR", code: "ERR029" },
    m3: { result: "ERROR", code: "ERR003" },
  });
  const r = await call(f.handler, { body: { action: "status_sweep" } });
  equal(r.status, 200);
  equal(await r.json(), { ok: true, action: "status_sweep", pending: 3, checked: 2, stored: 2 });
  equal(f.recorded, [{ p_msgid: "m1", p_status: "Delivered" }, { p_msgid: "m2", p_status: "ERR029" }]);
  equal(f.kwtCalls.length, 3);
  // بيانات الدخول تُرسل لـ KWT فقط، لا تُسجَّل
  equal(f.kwtCalls.every((b) => b.username === "testuser"), true);
});

Deno.test("status_sweep: junk ids ignored, at most 20, transport failure skips without retry", async () => {
  const ids = Array.from({ length: 30 }, (_, i) => `id${i}`);
  const f = sweepFixture([...ids, "bad id!", 7], Object.fromEntries(ids.map((i) => [i, { result: "OK", status: "Sent" }])));
  const r = await call(f.handler, { body: { action: "status_sweep" } });
  const j = await r.json();
  equal([j.pending, j.checked, f.kwtCalls.length], [20, 20, 20]);
  const g = sweepFixture(["x1"], { x1: new Error("down") });
  const r2 = await call(g.handler, { body: { action: "status_sweep" } });
  equal(await r2.json(), { ok: true, action: "status_sweep", pending: 1, checked: 0, stored: 0 });
  equal(g.recorded.length, 0);
});

Deno.test("status_sweep: needs the secret like balance_check", async () => {
  const f = sweepFixture(["m1"], { m1: { result: "OK", status: "Delivered" } });
  const r = await call(f.handler, { secret: "wrong-secret-wrong-secret", body: { action: "status_sweep" } });
  equal(r.status, 401);
  equal(f.kwtCalls.length, 0);
});
