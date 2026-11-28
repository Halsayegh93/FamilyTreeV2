import { baseName, buildDetail, buildList, framesOf, periodFor, platformOf } from "./shape.ts";

function equal(actual: unknown, expected: unknown, label = "") {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw Error(`${label} expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
  }
}

Deno.test("period: 1 · 7 · 30, anything else → 7", () => {
  equal([1, 7, 30, 3, "30", undefined].map(periodFor), [1, 7, 30, 7, 30, 7]);
});

Deno.test("platform: our app tag first, then Sentry's platform", () => {
  equal(platformOf("ios", "javascript"), "ios");
  equal(platformOf("flutter", null), "android");
  equal(platformOf(null, "cocoa"), "ios");
  equal(platformOf("", "dart"), "android");
  equal(platformOf(undefined, "node"), "web");
  equal(platformOf(null, "python"), "other");
});

Deno.test("baseName strips scheme, folders and query", () => {
  equal(baseName("app:///_next/static/chunks/2uy7.js?v=1"), "2uy7.js");
  equal(baseName("/Users/x/FamilyTreeV2/Views/MemberDetailsView.swift"), "MemberDetailsView.swift");
  equal(baseName("package:family_tree/core/a.dart"), "a.dart");
  equal(baseName(""), null);
});

Deno.test("list: merges rows per issue, sorts by count, totals per platform, flags test-only", () => {
  const rows = [
    { "issue.id": 1, app: "web", environment: "production", "count()": 4, "count_unique(user)": 2, "max(timestamp)": "2026-11-26T01:00:00Z" },
    { "issue.id": 2, app: "ios", environment: "production", "count()": 9, "count_unique(user)": 3, "max(timestamp)": "2026-11-26T02:00:00Z" },
    { "issue.id": 2, app: "ios", environment: "development", "count()": 3, "count_unique(user)": 1, "max(timestamp)": "2026-11-26T03:00:00Z" },
    { "issue.id": 3, app: "android", environment: "development", "count()": 1, "count_unique(user)": 1, "max(timestamp)": "2026-11-25T10:00:00Z" },
    { "issue.id": 4, app: "web", environment: "production", "count()": 1 }, // لا خطأ مطابق — يُترك
  ];
  const issues = [
    { id: "1", shortId: "FT-1", title: "Error: load failed", culprit: "/tree?x=1", platform: "javascript",
      metadata: { filename: "app:///_next/static/chunks/a.js", function: "n" } },
    { id: "2", shortId: "FT-2", title: "Crash", culprit: "", platform: "cocoa", level: "fatal", firstSeen: "2026-11-20T00:00:00Z" },
    { id: "3", shortId: "FT-3", title: "", platform: "dart", metadata: { title: "StateError" } },
  ];
  const r = buildList(7, rows, issues);
  equal(r.issues.map((i) => i.short_id), ["FT-2", "FT-1", "FT-3"], "order");
  equal(r.issues[0].count, 12, "merged count");
  equal(r.issues[0].users, 4, "merged users");
  equal(r.issues[0].last_seen, "2026-11-26T03:00:00Z", "latest");
  equal(r.issues[0].test_only, false, "mixed env is real");
  equal(r.issues[2].test_only, true, "dev only");
  equal(r.issues[1].where, "a.js · n");
  equal(r.issues[1].page, "/tree");
  equal(r.issues[2].title, "StateError", "title fallback");
  equal(r.totals, { ios: 1, android: 1, web: 1, other: 0 });
});

Deno.test("list: empty", () => {
  const r = buildList(1, [], []);
  equal([r.issues.length, r.totals.ios, r.days], [0, 0, 1]);
});

Deno.test("detail: newest in-app frames first, no user data", () => {
  const event = {
    release: { version: "Hasan.FamilyTreeV2@1.0.1+51" },
    tags: [{ key: "environment", value: "production" }, { key: "app", value: "ios" }],
    contexts: { os: { name: "iOS", version: "27.2" }, device: { model: "iPhone19,2" } },
    user: { id: "device-id-should-not-leak" },
    entries: [
      { type: "breadcrumbs", data: { values: [] } },
      { type: "exception", data: { values: [{ stacktrace: { frames: [
        { function: "main", filename: "main.swift", lineNo: 1, inApp: true },
        { function: "UIKit", package: "/System/UIKitCore", inApp: false },
        { function: "loadPhoto", absPath: "/src/Views/MemberDetailsView.swift", lineNo: 214, inApp: true },
      ] } }] } },
    ],
  };
  const d = buildDetail(event);
  equal(d.release, "Hasan.FamilyTreeV2@1.0.1+51");
  equal(d.environment, "production");
  equal(d.os, "iOS 27.2");
  equal(d.device, "iPhone19,2");
  equal(d.frames.map((f) => `${f.file}:${f.line}`), ["MemberDetailsView.swift:214", "main.swift:1"]);
  equal(JSON.stringify(d).includes("device-id-should-not-leak"), false, "no user id");
});

Deno.test("detail: falls back to the crashed thread, then all frames when none are in-app", () => {
  const frames = framesOf({ entries: [{ type: "threads", data: { values: [
    { current: true, stacktrace: { frames: [{ function: "a", inApp: false }] } },
    { crashed: true, stacktrace: { frames: [{ function: "x", inApp: false }, { function: "y", inApp: false }] } },
  ] } }] });
  equal(frames.map((f) => f.function), ["y", "x"]);
});
