// تجارب kwtsms-admin محلياً بـ fetch مزيّف — لا Supabase ولا KWT حقيقي.
// deno test --allow-env supabase/functions/kwtsms-admin/handler_test.ts
import { createHandler, digest, normalizePhone, TEST_MESSAGE } from "./handler.ts";
import { normalizePhone as hookNormalizePhone } from "../send-sms-kwtsms/handler.ts";

function equal(actual: unknown, expected: unknown, label = "") {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw Error(`${label} Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
  }
}
const OWNER = "11111111-1111-4111-8111-111111111111";
const LINKED = "22222222-2222-4222-8222-222222222222";
const JWT = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ4In0.c2lnbmF0dXJl";
type Call = { url: string; method: string; headers: Headers; body: Record<string, unknown> | null };

function fixture() {
  const config = {
    username: "testuser",
    password: "secret-pass-xyz",
    sender: "KWT-SMS",
    test: false,
    hashKey: "synthetic-hmac-key-at-least-32-bytes",
    supabaseURL: "https://test.supabase.co",
    serviceKey: "synthetic-service-key",
  };
  const calls: Call[] = [];
  const state = {
    userStatus: 200,
    authThrows: false,
    // deno-lint-ignore no-explicit-any
    user: { id: OWNER, app_metadata: {} } as any,
    // deno-lint-ignore no-explicit-any
    profile: { id: OWNER, role: "owner", status: "active", phone_number: "+96590000001" } as any,
    reservation: "send" as unknown,
    rpcFail: false,
    kwtThrows: null as Error | null,
    // app_settings.sms_sender (20261020170000): القيمة المحفوظة، وحالة القراءة (400 = قاعدة قبل الترحيل)
    storedSender: null as unknown,
    settingsStatus: 200,
    kwt: {
      balance: { result: "OK", available: 150, purchased: 1000 },
      senderid: { result: "OK", senderid: ["KWT-SMS", "MYAPP", "<script>", 5] },
      coverage: { result: "OK", prefixes: ["965", "971", "x9"] },
      status: { result: "OK", status: "sent", description: "Message successfully sent to gateway" },
      validate: { result: "OK", mobile: { OK: ["96550000000"], ER: [], NR: [] } },
      send: { result: "OK", "msg-id": "f4c8abc123", numbers: 1, "points-charged": 1, "balance-after": 149 },
    // deno-lint-ignore no-explicit-any
    } as Record<string, any>,
  };
  const handler = createHandler(
    () => config,
    // deno-lint-ignore require-await
    (async (url, init) => {
      const u = String(url);
      const body = init?.body ? JSON.parse(String(init.body)) : null;
      calls.push({ url: u, method: String(init?.method), headers: new Headers(init?.headers), body });
      if (u === "https://test.supabase.co/auth/v1/user") {
        if (state.authThrows) throw Error("network");
        return state.userStatus === 200
          ? Response.json(state.user)
          : Response.json({ msg: "invalid JWT" }, { status: state.userStatus });
      }
      if (u.startsWith("https://test.supabase.co/rest/v1/profiles?")) {
        return Response.json(state.profile ? [state.profile] : []);
      }
      if (u === "https://test.supabase.co/rest/v1/app_settings?select=sms_sender&order=updated_at.desc&limit=1") {
        if (state.settingsStatus !== 200) {
          return Response.json({ code: "42703", message: "column does not exist" }, { status: state.settingsStatus });
        }
        return Response.json([{ sms_sender: state.storedSender }]);
      }
      if (u.startsWith("https://test.supabase.co/rest/v1/rpc/")) {
        if (state.rpcFail) return new Response("private error", { status: 500 });
        const name = u.split("/rpc/")[1];
        if (name === "reserve_kwtsms_admin_test") return Response.json(state.reservation);
        if (name === "record_kwtsms_delivery_status") return Response.json(true);
        if (name === "set_kwtsms_sender") {
          state.storedSender = body?.p_sender ?? null;
          return Response.json(state.storedSender);
        }
        return Response.json(null);
      }
      if (u.startsWith("https://www.kwtsms.com/API/")) {
        if (state.kwtThrows) throw state.kwtThrows;
        return Response.json(state.kwt[u.slice("https://www.kwtsms.com/API/".length, -1)]);
      }
      throw Error("unexpected url " + u);
    }) as typeof fetch,
    () => 1760000000000,
  );
  const call = (action: unknown, extra: Record<string, unknown> = {}, token: string | null = JWT) =>
    handler(
      new Request("https://local.invalid", {
        method: "POST",
        headers: token === null ? {} : { Authorization: `Bearer ${token}` },
        body: JSON.stringify({ action, ...extra }),
      }),
    );
  const kwtCalls = () => calls.filter((c) => c.url.startsWith("https://www.kwtsms.com/"));
  const rpcCalls = (name: string) => calls.filter((c) => c.url.endsWith(`/rpc/${name}`));
  return { config, calls, state, handler, call, kwtCalls, rpcCalls };
}
async function body(response: Response) {
  const text = await response.text();
  if (text.includes("secret-pass-xyz") || text.includes("testuser") || text.includes("synthetic")) {
    throw Error("credentials leaked in response: " + text);
  }
  return JSON.parse(text);
}

Deno.test("phone rule is identical to the Send SMS hook (Kuwait mobiles only)", () => {
  for (
    const v of ["+96550000000", "0096550000000", "96550000000", "96520000000", "+971500000000", "965 50000000", null, 9655, "+965٥٠٠٠٠٠٠٠"]
  ) equal(normalizePhone(v), hookNormalizePhone(v), String(v));
});

Deno.test("method, configuration and missing or malformed tokens are rejected before any network call", async () => {
  const f = fixture();
  equal((await f.call("balance", {}, null)).status, 401);
  equal((await f.call("balance", {}, "not-a-jwt")).status, 401);
  equal((await f.call("balance", {}, "a.b.c d")).status, 401);
  equal(
    (await f.handler(new Request("https://local.invalid", { method: "GET" }))).status,
    405,
  );
  f.config.password = "";
  equal((await f.call("balance")).status, 503);
  equal(f.calls.length, 0);
});

Deno.test("auth rejection: Supabase Auth refuses the token → 401, nothing else is called", async () => {
  const f = fixture();
  f.state.userStatus = 401;
  const response = await f.call("balance");
  equal(response.status, 401);
  equal((await body(response)).error.code, "unauthorized");
  equal(f.calls.length, 1);
  equal(f.calls[0].method, "GET");
  equal(f.calls[0].headers.get("Authorization"), `Bearer ${JWT}`);
  f.state.userStatus = 200;
  f.state.user = { id: "not-a-uuid" };
  equal((await f.call("balance")).status, 401);
  f.state.authThrows = true;
  equal((await f.call("balance")).status, 503);
  equal(f.kwtCalls().length, 0);
});

Deno.test("role rejection: monitor, supervisor, member, frozen admin, missing profile and bad binding → 403", async () => {
  for (
    const profile of [
      { id: OWNER, role: "monitor", status: "active" },
      { id: OWNER, role: "supervisor", status: "active" },
      { id: OWNER, role: "member", status: "active" },
      { id: OWNER, role: "admin", status: "frozen" },
      null,
    ]
  ) {
    const f = fixture();
    f.state.profile = profile;
    const response = await f.call("balance");
    equal(response.status, 403, JSON.stringify(profile));
    equal((await body(response)).error.code, "forbidden");
    equal(f.kwtCalls().length, 0);
  }
  const f = fixture();
  f.state.user = { id: OWNER, app_metadata: { profile_id: "x' or 1=1" } };
  equal((await f.call("balance")).status, 403);
  equal(f.calls.length, 1);
});

Deno.test("identity comes from app_metadata.profile_id (server-set), never user_metadata", async () => {
  const f = fixture();
  f.state.user = { id: OWNER, app_metadata: { profile_id: LINKED }, user_metadata: { profile_id: OWNER } };
  equal((await f.call("balance")).status, 200);
  const lookup = f.calls.find((c) => c.url.includes("/rest/v1/profiles?"))!;
  equal(lookup.url.includes(`id=eq.${LINKED}`), true);
  equal(lookup.url.includes("phone_number"), false); // الرقم يُقرأ لـ test_send فقط
  equal(lookup.headers.get("Authorization"), "Bearer synthetic-service-key");
});

Deno.test("unknown action and oversized body are rejected; unknown action only after auth", async () => {
  const f = fixture();
  equal((await f.call("delete_everything")).status, 400);
  equal(f.kwtCalls().length, 0);
  f.state.userStatus = 401;
  equal((await f.call("delete_everything")).status, 401);
  const big = await f.handler(
    new Request("https://local.invalid", {
      method: "POST",
      headers: { Authorization: `Bearer ${JWT}` },
      body: JSON.stringify({ action: "balance", pad: "x".repeat(5000) }),
    }),
  );
  equal(big.status, 400);
});

Deno.test("balance: live KWT balance (admin allowed), fixed URL, credentials only in POST body, stored as latest", async () => {
  const f = fixture();
  f.state.profile = { id: OWNER, role: "admin", status: "active" };
  const response = await f.call("balance");
  equal(response.status, 200);
  equal(await body(response), {
    ok: true,
    balance: 150,
    purchased: 1000,
    test_mode: false,
    sender: "KWT-SMS",
    stored: true,
  });
  const k = f.kwtCalls();
  equal(k.length, 1);
  equal(k[0].url, "https://www.kwtsms.com/API/balance/");
  equal(k[0].method, "POST");
  equal(k[0].headers.get("Content-Type"), "application/json");
  equal(k[0].body, { username: "testuser", password: "secret-pass-xyz" });
  equal(f.rpcCalls("record_kwtsms_balance")[0].body, { p_balance: 150 });
  // حفظ فاشل لا يمنع عرض الرصيد
  f.state.rpcFail = true;
  equal((await body(await f.call("balance"))).stored, false);
  // خطأ من المزوّد: رمزه فقط، بلا وصفه
  f.state.kwt.balance = { result: "ERROR", code: "ERR003", description: "Wrong secret-pass-xyz" };
  const err = await f.call("balance");
  equal(err.status, 502);
  equal((await body(err)).error, { code: "provider_error", provider_code: "ERR003" });
});

Deno.test("senderid and coverage are sanitised", async () => {
  const f = fixture();
  equal(await body(await f.call("senderid")), {
    ok: true,
    senders: ["KWT-SMS", "MYAPP"],
    in_use: "KWT-SMS",
    in_use_listed: true,
  });
  equal(await body(await f.call("coverage")), { ok: true, prefixes: ["965", "971"], kuwait: true });
  equal(f.kwtCalls().map((c) => c.url), [
    "https://www.kwtsms.com/API/senderid/",
    "https://www.kwtsms.com/API/coverage/",
  ]);
});

Deno.test("status: by msgid, stored on the delivery; ERR029/ERR030 stored as status; other errors not stored", async () => {
  const f = fixture();
  equal(await body(await f.call("status", { msgid: "f4c8abc123" })), {
    ok: true,
    msgid: "f4c8abc123",
    status: "sent",
    stored: true,
  });
  equal(f.kwtCalls()[0].body, { username: "testuser", password: "secret-pass-xyz", msgid: "f4c8abc123" });
  equal(f.rpcCalls("record_kwtsms_delivery_status")[0].body, { p_msgid: "f4c8abc123", p_status: "sent" });
  f.state.kwt.status = { result: "ERROR", code: "ERR030", description: "stuck" };
  equal((await body(await f.call("status", { msgid: "f4c8abc123" }))).status, "ERR030");
  f.state.kwt.status = { result: "ERROR", code: "ERR003" };
  equal((await f.call("status", { msgid: "f4c8abc123" })).status, 502);
  equal(f.rpcCalls("record_kwtsms_delivery_status").length, 2);
  for (const msgid of [undefined, "", "a/b", "x".repeat(65), 12]) {
    equal((await f.call("status", { msgid })).status, 400);
  }
  equal(f.kwtCalls().length, 3);
});

Deno.test("validate: one Kuwaiti number, verdict only (number not echoed)", async () => {
  const f = fixture();
  const ok = await body(await f.call("validate", { phone: "+96550000000" }));
  equal(ok, { ok: true, verdict: "valid" });
  equal(f.kwtCalls()[0].body?.mobile, "96550000000");
  f.state.kwt.validate = { result: "OK", mobile: { OK: [], ER: [], NR: ["96550000000"] } };
  equal((await body(await f.call("validate", { phone: "96550000000" }))).verdict, "no_route");
  f.state.kwt.validate = { result: "OK", mobile: { OK: [], ER: ["96550000000"], NR: [] } };
  equal((await body(await f.call("validate", { phone: "96550000000" }))).verdict, "invalid");
  for (const phone of ["+971500000000", "96550000000,96550000001", "", null]) {
    const r = await f.call("validate", { phone });
    equal(r.status, 400);
    equal((await body(r)).error.code, "kuwait_only");
  }
  equal(f.kwtCalls().length, 3);
});

Deno.test("test_send: owner only, to the owner's own profile phone, fixed text, hashed reservation, recorded", async () => {
  const f = fixture();
  const response = await f.call("test_send", { phone: "+96599999999" }); // رقم من الطلب يُتجاهل
  equal(response.status, 200);
  equal(await body(response), { ok: true, test_mode: false, msgid: "f4c8abc123", points: 1, balance: 149 });
  equal(f.calls.find((c) => c.url.includes("/rest/v1/profiles?"))!.url.includes("phone_number"), true);
  const reserve = f.rpcCalls("reserve_kwtsms_admin_test")[0].body!;
  equal(/^[a-f0-9]{64}$/.test(String(reserve.p_event)), true);
  equal(reserve.p_phone, await digest("synthetic-hmac-key-at-least-32-bytes", "phone:96590000001"));
  equal(reserve.p_test, false);
  const sent = f.kwtCalls();
  equal(sent.length, 1);
  equal(sent[0].url, "https://www.kwtsms.com/API/send/");
  equal(sent[0].body, {
    username: "testuser",
    password: "secret-pass-xyz",
    sender: "KWT-SMS",
    mobile: "96590000001",
    message: TEST_MESSAGE,
    test: "0",
  });
  equal(TEST_MESSAGE, "رسالة اختبار من تطبيق عائلة المحمدعلي");
  equal(f.rpcCalls("finish_kwtsms_send")[0].body, {
    p_event: reserve.p_event,
    p_outcome: "accepted",
    p_msgid: "f4c8abc123",
    p_charged: 1,
    p_balance: 149,
  });
  // الوضع التجريبي ← test=1
  const t = fixture();
  t.config.test = true;
  equal((await body(await t.call("test_send"))).test_mode, true);
  equal(t.kwtCalls()[0].body?.test, "1");
  equal(t.rpcCalls("reserve_kwtsms_admin_test")[0].body?.p_test, true);
});

Deno.test("test_send rejections: admin (not owner), no Kuwaiti phone on profile", async () => {
  const f = fixture();
  f.state.profile = { id: OWNER, role: "admin", status: "active", phone_number: "+96590000001" };
  const r = await f.call("test_send");
  equal(r.status, 403);
  equal((await body(r)).error.code, "owner_only");
  f.state.profile = { id: OWNER, role: "owner", status: "active", phone_number: null };
  equal((await body(await f.call("test_send"))).error.code, "no_phone");
  f.state.profile = { id: OWNER, role: "owner", status: "active", phone_number: "+971500000000" };
  equal((await f.call("test_send")).status, 400);
  equal(f.kwtCalls().length, 0);
  equal(f.rpcCalls("reserve_kwtsms_admin_test").length, 0);
});

Deno.test("test_send rate limit: once per 10 minutes (wait), other limits (blocked), storage down → nothing sent", async () => {
  const f = fixture();
  f.state.reservation = "wait";
  const r = await f.call("test_send");
  equal(r.status, 429);
  equal((await body(r)).error.code, "wait_10_minutes");
  f.state.reservation = "blocked";
  equal((await body(await f.call("test_send"))).error.code, "rate_limited");
  f.state.rpcFail = true;
  equal((await f.call("test_send")).status, 503);
  equal(f.kwtCalls().length, 0);
  equal(f.rpcCalls("finish_kwtsms_send").length, 0);
});

Deno.test("test_send provider failures are recorded with their code; timeouts never retry", async () => {
  const f = fixture();
  f.state.kwt.send = { result: "ERROR", code: "ERR010", description: "zero balance secret-pass-xyz" };
  const r = await f.call("test_send");
  equal(r.status, 502);
  equal((await body(r)).error.provider_code, "ERR010");
  equal(f.rpcCalls("finish_kwtsms_send")[0].body?.p_outcome, "failed");
  equal(f.rpcCalls("finish_kwtsms_send")[0].body?.p_error_code, "ERR010");
  f.state.kwt.send = { result: "OK", numbers: 0 };
  await f.call("test_send");
  equal(f.rpcCalls("finish_kwtsms_send")[1].body?.p_error_code, "BAD_RESPONSE");
  f.state.kwtThrows = new DOMException("timed out", "TimeoutError");
  equal((await f.call("test_send")).status, 504);
  equal(f.rpcCalls("finish_kwtsms_send")[2].body?.p_outcome, "unknown");
  equal(f.rpcCalls("finish_kwtsms_send")[2].body?.p_error_code, "TIMEOUT");
  f.state.kwtThrows = Error("socket");
  await f.call("test_send");
  equal(f.rpcCalls("finish_kwtsms_send")[3].body?.p_error_code, "NETWORK");
  equal(f.kwtCalls().length, 4); // طلب واحد لكل محاولة، بلا إعادة
  // انقطاع في الإجراءات الأخرى ← 504 بلا إعادة
  equal((await f.call("balance")).status, 504);
  equal(f.kwtCalls().length, 5);
});

// ── اسم المرسل (20261020170000) ──
Deno.test("set_sender: owner only — admin, monitor and frozen owner are rejected before KWT or storage", async () => {
  for (
    const profile of [
      { id: OWNER, role: "admin", status: "active" },
      { id: OWNER, role: "monitor", status: "active" },
      { id: OWNER, role: "owner", status: "frozen" },
    ]
  ) {
    const f = fixture();
    f.state.profile = profile;
    const r = await f.call("set_sender", { sender: "MYAPP" });
    equal(r.status, 403, JSON.stringify(profile));
    equal((await body(r)).error.code, profile.role === "admin" ? "owner_only" : "forbidden");
    equal(f.kwtCalls().length, 0);
    equal(f.rpcCalls("set_kwtsms_sender").length, 0);
    equal(f.state.storedSender, null);
  }
});

Deno.test("set_sender: malformed or missing sender → 400 before KWT", async () => {
  const f = fixture();
  for (const extra of [{}, { sender: 5 }, { sender: "" }, { sender: "BAD!" }, { sender: "TWELVECHARSX" }, { sender: "A\nB" }, { sender: "MY.APP" }, { sender: ["MYAPP"] }]) {
    const r = await f.call("set_sender", extra);
    equal(r.status, 400, JSON.stringify(extra));
    equal((await body(r)).error.code, "bad_sender");
  }
  equal(f.kwtCalls().length, 0);
  equal(f.rpcCalls("set_kwtsms_sender").length, 0);
});

Deno.test("set_sender: a sender not in the account's approved list (exact match) is rejected and not stored", async () => {
  const f = fixture();
  for (const sender of ["OTHER", "myapp", "MYAPP ", "KWT"]) {
    const r = await f.call("set_sender", { sender });
    equal(r.status, 409, sender);
    equal(await body(r), { ok: false, error: { code: "sender_not_approved", senders: ["KWT-SMS", "MYAPP"] } });
  }
  equal(f.kwtCalls().every((c) => c.url === "https://www.kwtsms.com/API/senderid/"), true);
  equal(f.kwtCalls()[0].body, { username: "testuser", password: "secret-pass-xyz" });
  equal(f.rpcCalls("set_kwtsms_sender").length, 0);
});

Deno.test("set_sender: an approved sender is stored via the service RPC and then used everywhere", async () => {
  const f = fixture();
  const r = await f.call("set_sender", { sender: "MYAPP" });
  equal(r.status, 200);
  equal(await body(r), {
    ok: true,
    sender: "MYAPP",
    in_use: "MYAPP",
    default: "KWT-SMS",
    source: "settings",
    senders: ["KWT-SMS", "MYAPP"],
  });
  const rpc = f.rpcCalls("set_kwtsms_sender")[0];
  equal(rpc.body, { p_sender: "MYAPP", p_by: OWNER });
  equal(rpc.headers.get("Authorization"), "Bearer synthetic-service-key");
  // «اختبار إرسال لرقمي» والرصيد وقائمة المرسلين تستخدم المحفوظ
  const t = await body(await f.call("test_send"));
  equal(t.ok, true);
  equal(f.kwtCalls().find((c) => c.url.endsWith("/send/"))!.body?.sender, "MYAPP");
  equal((await body(await f.call("balance"))).sender, "MYAPP");
  equal(await body(await f.call("senderid")), {
    ok: true,
    senders: ["KWT-SMS", "MYAPP"],
    in_use: "MYAPP",
    in_use_listed: true,
  });
  // المالك عبر ربط app_metadata (حساب منقول) ← p_by = معرّف ملفه
  const g = fixture();
  g.state.user = { id: OWNER, app_metadata: { profile_id: LINKED } };
  g.state.profile = { id: LINKED, role: "owner", status: "active" };
  await g.call("set_sender", { sender: "KWT-SMS" });
  equal(g.rpcCalls("set_kwtsms_sender")[0].body, { p_sender: "KWT-SMS", p_by: LINKED });
});

Deno.test("set_sender: null resets to the default even when KWT is unreachable", async () => {
  for (const kwt of ["ok", "error", "throws"] as const) {
    const f = fixture();
    f.state.storedSender = "MYAPP";
    if (kwt === "error") f.state.kwt.senderid = { result: "ERROR", code: "ERR003" };
    if (kwt === "throws") f.state.kwtThrows = Error("socket");
    const r = await f.call("set_sender", { sender: null });
    equal(r.status, 200, kwt);
    equal(await body(r), {
      ok: true,
      sender: null,
      in_use: "KWT-SMS",
      default: "KWT-SMS",
      source: "default",
      senders: kwt === "ok" ? ["KWT-SMS", "MYAPP"] : null,
    });
    equal(f.rpcCalls("set_kwtsms_sender")[0].body, { p_sender: null, p_by: OWNER });
    equal(f.state.storedSender, null);
  }
});

Deno.test("set_sender: KWT failure or storage failure → nothing stored", async () => {
  let f = fixture();
  f.state.kwt.senderid = { result: "ERROR", code: "ERR003", description: "secret-pass-xyz" };
  let r = await f.call("set_sender", { sender: "MYAPP" });
  equal(r.status, 502);
  equal((await body(r)).error, { code: "provider_error", provider_code: "ERR003" });
  equal(f.rpcCalls("set_kwtsms_sender").length, 0);
  f = fixture();
  f.state.kwtThrows = new DOMException("timed out", "TimeoutError");
  r = await f.call("set_sender", { sender: "MYAPP" });
  equal(r.status, 504);
  equal(f.rpcCalls("set_kwtsms_sender").length, 0);
  f = fixture();
  f.state.rpcFail = true;
  r = await f.call("set_sender", { sender: "MYAPP" });
  equal(r.status, 503);
  equal((await body(r)).error.code, "storage_unavailable");
  equal(f.state.storedSender, null);
});

Deno.test("sender in use falls back to the configured default: none stored, odd value, unreadable or column missing", async () => {
  for (const [stored, status] of [[null, 200], ["BAD!", 200], [5, 200], ["TWELVECHARSX", 200], ["MYAPP", 400], ["MYAPP", 500]] as const) {
    const f = fixture();
    f.state.storedSender = stored;
    f.state.settingsStatus = status;
    equal((await body(await f.call("test_send"))).ok, true, `${stored}/${status}`);
    equal(f.kwtCalls()[0].body?.sender, "KWT-SMS", `${stored}/${status}`);
    equal((await body(await f.call("senderid"))).in_use, "KWT-SMS");
  }
});
