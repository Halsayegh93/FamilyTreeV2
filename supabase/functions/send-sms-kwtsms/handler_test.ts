import { Webhook } from "https://esm.sh/standardwebhooks@1.0.0";
import { createHandler, messageFor, messageFrom, normalizePhone } from "./handler.ts";

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
  let reservation: unknown = "send";
  let result: unknown = {
    result: "OK",
    "msg-id": "test-id",
    numbers: 1,
    "points-charged": 1,
    "balance-after": 90,
  };
  let transportError = false;
  let storageError = false;
  // قاعدة قبل 20261020170000 (أو بعد تراجعه): PostgREST يرد 404 على معامل p_format غير المعروف
  let legacyDb = false;
  let reserveTimeout = false;
  // «محاولات الدخول»: ما يصل log_login_attempt، وطريقة فشله المصطنعة
  const logs: Record<string, unknown>[] = [];
  const detailLogs: Record<string, unknown>[] = [];
  let legacyAudit = false;
  let logMode: "ok" | "error" | "throw" | "hang" = "ok";
  // «اعرض الرمز» (20261021080000): ما يصل store_login_code، وطريقة فشله المصطنعة
  const codes: Record<string, unknown>[] = [];
  let codeMode: "ok" | "error" | "throw" | "hang" | "missing" = "ok";
  const handler = createHandler(
    () => config,
    // Preserve fetch's promise rejection behavior for the transport-error scenario.
    // deno-lint-ignore require-await
    (async (url, options) => {
      equal(options?.method, "POST");
      const body = JSON.parse(String(options?.body));
      requests.push({ url: String(url), body });
      if (String(url).endsWith("reserve_kwtsms_send")) {
        if (reserveTimeout) throw new DOMException("timed out", "TimeoutError");
        if (storageError) return new Response("private error", { status: 500 });
        equal(/^[a-f0-9]{64}$/.test(body.p_phone), true);
        equal(/^[a-f0-9]{64}$/.test(body.p_event), true);
        if (legacyDb && "p_format" in body) {
          return Response.json({
            code: "PGRST202",
            message: "Could not find the function",
          }, { status: 404 });
        }
        return Response.json(reservation);
      }
      if (String(url).endsWith("finish_kwtsms_send")) {
        return Response.json(null);
      }
      if (String(url).endsWith("log_sms_login_attempt") || String(url).endsWith("log_login_attempt")) {
        if (String(url).endsWith("log_sms_login_attempt")) {
          detailLogs.push(body);
          if (legacyAudit) return new Response(null, { status: 404 });
        }
        equal(
          new Headers(options?.headers).get("apikey"),
          "synthetic-service-key",
        );
        logs.push({ p_phone: body.p_phone, p_outcome: body.p_outcome });
        if (logMode === "error") {
          return new Response("private error", { status: 500 });
        }
        if (logMode === "throw") throw Error("private network failure");
        if (logMode === "hang") {
          // لا يرد أبداً — ينتهي فقط بمهلة الدالة (AbortSignal)
          return new Promise<Response>((_, reject) =>
            options?.signal?.addEventListener(
              "abort",
              () => reject(options.signal?.reason),
            )
          );
        }
        return new Response(null, { status: 204 }); // PostgREST: دالة void
      }
      if (String(url).endsWith("store_login_code")) {
        equal(
          new Headers(options?.headers).get("apikey"),
          "synthetic-service-key",
        );
        codes.push(body);
        if (codeMode === "error") {
          return new Response("private error", { status: 500 });
        }
        // قاعدة بعد التراجع: الدالة غير موجودة
        if (codeMode === "missing") {
          return Response.json({ code: "PGRST202" }, { status: 404 });
        }
        if (codeMode === "throw") throw Error("private network failure");
        if (codeMode === "hang") {
          return new Promise<Response>((_, reject) =>
            options?.signal?.addEventListener(
              "abort",
              () => reject(options.signal?.reason),
            )
          );
        }
        return new Response(null, { status: 204 });
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
    logs,
    detailLogs,
    codes,
    handler,
    logFailure: (v: typeof logMode) => logMode = v,
    codeFailure: (v: typeof codeMode) => codeMode = v,
    reserve: (v: unknown) => reservation = v,
    result: (v: unknown) => result = v,
    networkFailure: () => transportError = true,
    storageFailure: () => storageError = true,
    legacy: () => legacyDb = true,
    legacyAudit: () => legacyAudit = true,
    reserveHang: () => reserveTimeout = true,
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
    equal(f.requests.length, 5); // reserve, send, outcome, login-attempt log, owner code store; no balance polling
    equal(f.requests[2].body.p_balance, 90);
    // النجاح بنفس عقد finish القديم (خمسة أسماء) — بلا p_error_code
    equal("p_error_code" in f.requests[2].body, false);
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
    const [result, code] of [
      [{
        result: "ERROR",
        code: "ERR003",
        description: "private credentials and phone",
      }, "ERR003"],
      [{ result: "OK", numbers: 0, "msg-id": "id" }, "BAD_RESPONSE"],
      [{ result: "OK", numbers: 1 }, "BAD_RESPONSE"],
      ["OK:legacy", "BAD_RESPONSE"],
    ]
  ) {
    const f = fixture();
    f.result(result);
    const response = await f.handler(signed(payload));
    equal(response.status, 503);
    equal((await response.text()).includes("private"), false);
    equal(f.requests[2].body.p_outcome, "failed");
    equal(f.requests[2].body.p_error_code, code);
  }
  const f = fixture();
  f.networkFailure();
  equal((await f.handler(signed(payload))).status, 503);
  equal(f.requests.filter((r) => r.url.includes("kwtsms.com")).length, 1);
  equal(f.requests[2].body.p_outcome, "unknown");
  equal(f.requests[2].body.p_error_code, "NETWORK");
});
Deno.test("test mode uses test=1 and cannot report real delivery success; shared KWT-SMS sender allowed in production (owner 2026-10-19)", async () => {
  const f = fixture();
  f.config.test = true;
  f.config.sender = "KWT-SMS";
  equal((await f.handler(signed(payload))).status, 503);
  equal(f.requests[1].body.test, "1");
  f.config.test = false;
  equal((await f.handler(signed(payload))).status, 200);
  equal(f.requests.length, 9); // test run = reserve, send, outcome, log; real run + owner code store
  equal(f.requests[5].body.sender, "KWT-SMS");
  equal(f.requests[5].body.test, "0");
});

// ── «محاولات الدخول» (20261020160000) ──
type Fixture = ReturnType<typeof fixture>;
async function attempt(setup: (f: Fixture) => void = () => {}) {
  const f = fixture();
  setup(f);
  const response = await f.handler(signed(payload));
  return { f, status: response.status, body: await response.json() };
}
Deno.test("login attempts: every outcome is logged once with the plaintext Kuwait number and never the code", async () => {
  const cases: [string, (f: Fixture) => void, number, string | null][] = [
    ["sent", () => {}, 200, "sent"],
    [
      "provider error",
      (f) => f.result({ result: "ERROR", code: "ERR003" }),
      503,
      "failed",
    ],
    [
      "malformed success",
      (f) => f.result({ result: "OK", numbers: 1 }),
      503,
      "failed",
    ],
    ["transport failure", (f) => f.networkFailure(), 503, "unknown"],
    ["rate limited", (f) => f.reserve("blocked"), 429, "blocked"],
    // رد 200 فيه error ← Supabase Auth يرد للتطبيق 429 بنص «انتظر N ثانية»
    ["rate limited with wait", (f) => f.reserve("blocked:45"), 200, "blocked"],
    ["duplicate of an accepted event", (f) => f.reserve("accepted"), 200, null],
    ["reservation storage down", (f) => f.storageFailure(), 503, null],
    ["test mode send", (f) => f.config.test = true, 503, "test"],
    [
      "test mode provider error",
      (f) => {
        f.config.test = true;
        f.result({ result: "ERROR", code: "ERR003" });
      },
      503,
      "test",
    ],
    [
      "test mode transport failure",
      (f) => {
        f.config.test = true;
        f.networkFailure();
      },
      503,
      "test",
    ],
    [
      "test mode rate limited",
      (f) => {
        f.config.test = true;
        f.reserve("blocked");
      },
      429,
      "blocked",
    ],
  ];
  for (const [name, setup, status, outcome] of cases) {
    const { f, status: got } = await attempt(setup);
    equal([name, got], [name, status]);
    equal(
      [name, f.logs],
      [name, outcome ? [{ p_phone: "96550000000", p_outcome: outcome }] : []],
    );
    // الرمز يُحفظ للمالك بعد قبول KWT فقط (لا فشل، لا انقطاع، لا تجريبي، لا محجوب)
    equal(
      [name, f.codes],
      [
        name,
        name === "sent" ? [{ p_phone: "96550000000", p_code: "123456" }] : [],
      ],
    );
    // الرمز لا يصل أي سجل آخر، والرقم الصريح لا يصل جدول الإرسالات (بصمة فقط)
    for (const r of f.requests) {
      if (r.url.includes("kwtsms.com")) continue;
      if (r.url.endsWith("store_login_code")) continue;
      equal([name, JSON.stringify(r.body).includes("123456")], [name, false]);
      if (!r.url.endsWith("log_login_attempt") && !r.url.endsWith("log_sms_login_attempt")) {
        equal([name, JSON.stringify(r.body).includes("50000000")], [
          name,
          false,
        ]);
      }
    }
    if (outcome === "blocked") {
      equal(f.requests.some((r) => r.url.includes("kwtsms.com")), false);
    }
  }
});
Deno.test("login attempts: a failing or hanging log never changes the response or the outcome record", async () => {
  for (const mode of ["error", "throw"] as const) {
    let r = await attempt((f) => f.logFailure(mode));
    equal([mode, r.status, r.body], [mode, 200, {}]); // نفس رد النجاح حرفياً
    const finish = r.f.requests.find((x) =>
      x.url.endsWith("finish_kwtsms_send")
    )!;
    equal(finish.body.p_outcome, "accepted");
    equal(r.f.logs.length, 1);
    r = await attempt((f) => {
      f.logFailure(mode);
      f.reserve("blocked");
    });
    equal([mode, r.status], [mode, 429]);
    r = await attempt((f) => {
      f.logFailure(mode);
      f.networkFailure();
    });
    equal([mode, r.status], [mode, 503]);
    r = await attempt((f) => {
      f.logFailure(mode);
      f.result({ result: "ERROR", code: "ERR003" });
    });
    equal([mode, r.status], [mode, 503]);
  }
  // سجل معلّق: ينقطع بمهلته (٨٠٠ ملّي ثانية) ويجري بالتوازي مع حفظ النتيجة — الرد نفسه وبلا تأخير يُذكر
  const started = Date.now();
  const r = await attempt((f) => f.logFailure("hang"));
  const elapsed = Date.now() - started;
  equal([r.status, r.body], [200, {}]);
  equal(elapsed < 1500, true);
  equal(
    r.f.requests.find((x) => x.url.endsWith("finish_kwtsms_send"))!.body
      .p_outcome,
    "accepted",
  );
});

Deno.test("owner code store: failing, missing (after rollback) or hanging never changes the response or the records", async () => {
  for (const mode of ["error", "throw", "missing"] as const) {
    const r = await attempt((f) => f.codeFailure(mode));
    equal([mode, r.status, r.body], [mode, 200, {}]); // نفس رد النجاح حرفياً
    equal(
      r.f.requests.find((x) => x.url.endsWith("finish_kwtsms_send"))!.body
        .p_outcome,
      "accepted",
    );
    equal([mode, r.f.logs.length, r.f.codes.length], [mode, 1, 1]);
  }
  // حفظ معلّق: ينقطع بمهلته ويجري بالتوازي — بلا تأخير يُذكر
  const started = Date.now();
  const r = await attempt((f) => f.codeFailure("hang"));
  equal([r.status, r.body], [200, {}]);
  equal(Date.now() - started < 1500, true);
});

// ── الحدود يعدّلها المالك واسم المرسل (20261020170000) ──
const providerBody = (f: Fixture) =>
  f.requests.find((r) => r.url.includes("kwtsms.com"))?.body;
Deno.test("reservation asks for the detailed reply (p_format 3) with the same three hashed arguments", async () => {
  const f = fixture();
  equal((await f.handler(signed(payload))).status, 200);
  const reserve = f.requests[0];
  equal(
    reserve.url,
    "https://test.supabase.co/rest/v1/rpc/reserve_kwtsms_send",
  );
  equal(Object.keys(reserve.body), [
    "p_event",
    "p_phone",
    "p_test",
    "p_format",
  ]);
  equal([reserve.body.p_test, reserve.body.p_format], [false, 3]);
  equal(
    f.requests.filter((r) => r.url.endsWith("reserve_kwtsms_send")).length,
    1,
  );
});
Deno.test("stored sender from the reservation is used; anything odd falls back to the configured sender and still sends", async () => {
  const cases: [string, string][] = [
    ["send:MYAPP", "MYAPP"],
    ["send:MY APP-1", "MY APP-1"],
    ["send:KWT-SMS", "KWT-SMS"],
    ["send", "Family"],
    ["send:", "Family"],
    ["send:BAD!", "Family"],
    ["send:TWELVECHARSX", "Family"],
    ["send:A\nB", "Family"],
    ["send:عربي", "Family"],
    ["send:MYAPP:x", "Family"],
  ];
  for (const [reply, sender] of cases) {
    const { f, status, body } = await attempt((x) => x.reserve(reply));
    equal([reply, status, body], [reply, 200, {}]);
    // نفس طلب KWT القديم حرفياً — المرسل فقط من الإعدادات
    equal([reply, providerBody(f)], [reply, {
      username: "testuser",
      password: "testpass",
      sender,
      mobile: "96550000000",
      message: messageFor("123456", "ar"),
      test: "0",
    }]);
    equal([reply, f.requests.length], [reply, 5]);
    equal([reply, f.logs], [reply, [{
      p_phone: "96550000000",
      p_outcome: "sent",
    }]]);
  }
});
Deno.test("blocked:<seconds> → HTTP 200 with error 429 and a machine-parsable wait; nothing sent", async () => {
  for (
    const [reply, seconds] of [
      ["blocked:50", 50],
      ["blocked:120", 120],
      ["blocked:1", 1],
      ["blocked:0", 1],
      ["blocked:3599", 3599],
      ["blocked:999999", 3600],
    ] as [string, number][]
  ) {
    const { f, status, body } = await attempt((x) => x.reserve(reply));
    equal([reply, status], [reply, 200]);
    equal([reply, body], [reply, {
      error: {
        http_code: 429,
        message:
          `Please wait ${seconds} seconds before requesting another code`,
      },
    }]);
    equal(/wait (\d+) seconds/.exec(body.error.message)?.[1], String(seconds));
    equal(f.requests.some((r) => r.url.includes("kwtsms.com")), false);
    equal(f.requests.some((r) => r.url.endsWith("finish_kwtsms_send")), false);
    equal(f.logs, [{ p_phone: "96550000000", p_outcome: "blocked" }]);
  }
});
Deno.test("plain 'blocked' and any odd reply keep the old 429 response byte-for-byte", async () => {
  for (
    const reply of [
      "blocked",
      "blocked:",
      "blocked:abc",
      "blocked:-5",
      "blocked:1.5",
      "blocked:1234567",
      "sendx",
      " send",
      "nope",
      "",
    ]
  ) {
    const { f, status, body } = await attempt((x) => x.reserve(reply));
    equal([reply, status, body], [reply, 429, {
      error: {
        http_code: 429,
        message: "Please wait a minute before requesting another code",
      },
    }]);
    equal(f.requests.some((r) => r.url.includes("kwtsms.com")), false);
    equal(f.logs, [{ p_phone: "96550000000", p_outcome: "blocked" }]);
  }
});
Deno.test("database before the migration (or after rollback): 404 on p_format → one retry with the old contract", async () => {
  let r = await attempt((f) => {
    f.legacy();
    f.reserve("send");
  });
  equal([r.status, r.body], [200, {}]);
  const reserves = r.f.requests.filter((x) =>
    x.url.endsWith("reserve_kwtsms_send")
  );
  equal(reserves.length, 2);
  equal(Object.keys(reserves[0].body), [
    "p_event",
    "p_phone",
    "p_test",
    "p_format",
  ]);
  equal(Object.keys(reserves[1].body), ["p_event", "p_phone", "p_test"]);
  equal(reserves[1].body.p_event, reserves[0].body.p_event);
  equal(providerBody(r.f)?.sender, "Family");
  equal(r.f.requests.length, 6); // reserve 404, reserve, send, outcome, log, owner code store
  r = await attempt((f) => {
    f.legacy();
    f.reserve("blocked");
  });
  equal([r.status, r.body.error.message], [
    429,
    "Please wait a minute before requesting another code",
  ]);
  r = await attempt((f) => {
    f.legacy();
    f.reserve("accepted");
  });
  equal([r.status, r.body], [200, {}]);
});
Deno.test("reservation timeout or server error is never retried and nothing is sent", async () => {
  for (
    const setup of [
      (f: Fixture) => f.reserveHang(),
      (f: Fixture) => f.storageFailure(),
    ]
  ) {
    const { f, status, body } = await attempt(setup);
    equal([status, body.error.message], [
      503,
      "SMS service is temporarily unavailable",
    ]);
    equal(f.requests.length, 1);
    equal(f.logs, []);
  }
});

Deno.test("remote OTP template uses the current code and falls back on unsafe templates", () => {
  equal(messageFrom("عائلة المحمدعلي: رمزك {code}", "123456", "ar"), "عائلة المحمدعلي: رمزك 123456");
  for (const bad of [null, "no code", "{code}{code}", "x".repeat(70) + "{code}", "x\n{code}"]) {
    equal(messageFrom(bad, "123456", "ar"), messageFor("123456", "ar"));
  }
  equal(messageFrom("رمزك {code}", "123456", "en"), messageFor("123456", "en"));
});
Deno.test("detailed reservation applies configured sender and text in one provider call", async () => {
  const f = fixture();
  f.reserve(JSON.stringify({ action: "send", sender: "Family", template: "عائلة المحمدعلي: رمزك {code}", template_en: "Code {code}" }));
  const r = await f.handler(signed(payload));
  equal(r.status, 200);
  const sends = f.requests.filter(x => x.url === "https://www.kwtsms.com/API/send/");
  equal(sends.length, 1);
  equal(sends[0].body.message, "عائلة المحمدعلي: رمزك 123456");
  equal(sends[0].body.sender, "Family");
});

Deno.test("SMS audit records request time and provider metadata without the OTP", async () => {
  const f = fixture();
  const before = Date.now();
  equal((await f.handler(signed(payload))).status, 200);
  const audit = f.detailLogs[0];
  const d = audit.p_details as Record<string, unknown>;
  equal(audit.p_phone, "96550000000");
  equal(audit.p_outcome, "sent");
  equal(d.msgid, "test-id");
  equal(d.sender, "Family");
  equal(d.points, 1);
  equal(d.balance_after, 90);
  equal(d.http_status, 200);
  equal(d.test_mode, false);
  equal(Date.parse(String(d.requested_at)) >= before, true);
  equal(JSON.stringify(audit).includes("123456"), false);
});

Deno.test("SMS audit keeps rate-limit waits and failed-provider reasons distinct", async () => {
  const blocked = fixture();
  blocked.reserve("blocked:120");
  await blocked.handler(signed(payload));
  equal((blocked.detailLogs[0].p_details as Record<string, unknown>).retry_after_seconds, 120);
  equal(blocked.requests.some(r => r.url.includes("kwtsms.com")), false);
  const rejected = fixture();
  rejected.result({ result: "ERROR", code: "ERR003" });
  await rejected.handler(signed(payload));
  equal((rejected.detailLogs[0].p_details as Record<string, unknown>).error_code, "ERR003");
  const transport = fixture();
  transport.networkFailure();
  await transport.handler(signed(payload));
  equal((transport.detailLogs[0].p_details as Record<string, unknown>).error_code, "NETWORK");
});

Deno.test("only a missing audit RPC falls back to the old logger, with no extra SMS", async () => {
  const f = fixture();
  f.legacyAudit();
  equal((await f.handler(signed(payload))).status, 200);
  equal(f.requests.filter(r => r.url.endsWith("log_sms_login_attempt")).length, 1);
  equal(f.requests.filter(r => r.url.endsWith("log_login_attempt")).length, 1);
  equal(f.logs.length, 1);
  equal(f.requests.filter(r => r.url === "https://www.kwtsms.com/API/send/").length, 1);
  const broken = fixture();
  broken.logFailure("error");
  equal((await broken.handler(signed(payload))).status, 200);
  equal(broken.requests.some(r => r.url.endsWith("log_login_attempt")), false);
  equal(broken.codes.length, 1);
});
