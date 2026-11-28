// «الأخطاء» في لوحة الإدارة (طلب المالك ٢٠٢٦-١١-٢٦): تشكيل ردود Sentry لما يعرضه التطبيق — دوال صافية بلا شبكة
// (تجربتها `deno test supabase/functions/sentry-issues/shape_test.ts`).
//
// الخصوصية: لا يخرج من هنا معرّف جهاز ولا مستخدم ولا فتات ولا ترويسات — فقط نص الخطأ (مخفيّ الأرقام من التطبيقات)،
// مكانه (ملف · دالة · سطر)، المنصة، العدد، الأجهزة المتأثرة كرقم، والتواريخ، والإصدار ونظام التشغيل.

export type Platform = "ios" | "android" | "web" | "other";

/** صفّ من استعلام الأحداث (`/organizations/{org}/events/?dataset=errors`) مجمّعاً بالخطأ والعلامة والبيئة */
export type DiscoverRow = {
  "issue.id"?: number | string;
  app?: string | null;
  environment?: string | null;
  "count()"?: number;
  "count_unique(user)"?: number;
  "max(timestamp)"?: string;
};

/** خطأ من `/organizations/{org}/issues/?group=…` — الحقول التي نقرؤها فقط */
export type SentryIssue = {
  id: string;
  shortId?: string;
  title?: string;
  culprit?: string | null;
  platform?: string | null;
  level?: string | null;
  status?: string | null;
  firstSeen?: string | null;
  lastSeen?: string | null;
  metadata?: { value?: string; type?: string; filename?: string; function?: string; title?: string } | null;
};

export type IssueRow = {
  id: string;
  short_id: string;
  title: string;
  /** «MemberDetailsView.swift · loadPhoto» — الملف والدالة إن عُرفا */
  where: string | null;
  /** الصفحة في الموقع («/tree») */
  page: string | null;
  platform: Platform;
  count: number;
  users: number;
  first_seen: string | null;
  last_seen: string | null;
  level: string;
  /** كل أحداثه من نسخة تطوير/تجربة (لا من النسخة الرسمية) */
  test_only: boolean;
};

export type ListReply = {
  ok: true;
  configured: true;
  days: number;
  totals: Record<Platform, number>;
  issues: IssueRow[];
};

/** أقصى عدد أخطاء في الرد */
export const ISSUE_CAP = 50;

/** الفترات المسموحة بالأيام → `statsPeriod` في Sentry */
export const PERIODS: Record<number, string> = { 1: "24h", 7: "7d", 30: "30d" };

export function periodFor(days: unknown): number {
  const n = typeof days === "number" ? days : Number(days);
  return PERIODS[n] ? n : 7;
}

/** المنصة من علامتنا `app` أولاً (ios · android · web · flutter)، ثم من منصّة Sentry للخطأ */
export function platformOf(app: string | null | undefined, sentryPlatform?: string | null): Platform {
  switch ((app ?? "").toLowerCase()) {
    case "ios": return "ios";
    case "android": case "flutter": return "android";
    case "web": return "web";
  }
  switch ((sentryPlatform ?? "").toLowerCase()) {
    case "cocoa": case "swift": case "objc": return "ios";
    case "dart": case "java": case "android": return "android";
    case "javascript": case "node": return "web";
    default: return "other";
  }
}

/** اسم الملف وحده («app:///_next/static/chunks/a.js?x» → «a.js»، «/Users/…/X.swift» → «X.swift») */
export function baseName(path: string | null | undefined): string | null {
  if (!path) return null;
  const clean = path.split(/[?#]/)[0].replace(/\/+$/, "");
  const last = clean.split(/[\\/]/).pop() ?? "";
  return last.trim() || null;
}

function whereOf(issue: SentryIssue): string | null {
  const file = baseName(issue.metadata?.filename);
  const fn = issue.metadata?.function?.trim() || null;
  if (file && fn) return `${file} · ${fn}`;
  return file ?? fn;
}

/** صفحة الموقع من `culprit` (مسار يبدأ بـ «/») — للمنصات الأخرى لا صفحة */
function pageOf(issue: SentryIssue, platform: Platform): string | null {
  const c = (issue.culprit ?? "").trim();
  return platform === "web" && c.startsWith("/") ? c.split(/[?#]/)[0] : null;
}

function num(v: unknown): number {
  const n = typeof v === "number" ? v : Number(v);
  return Number.isFinite(n) && n > 0 ? Math.round(n) : 0;
}

const TEST_ENVIRONMENTS = new Set(["development", "preview", "dev", "test", "staging"]);

/**
 * يجمع صفوف الأحداث (قد يتكرر الخطأ الواحد لكل علامة/بيئة) مع بيانات الأخطاء: العدد والأجهزة في الفترة، آخر ظهور،
 * والمنصة (العلامة الأكثر أحداثاً). مرتّبة: الأكثر تكراراً ثم الأحدث.
 */
export function buildList(days: number, rows: DiscoverRow[], issues: SentryIssue[]): ListReply {
  type Acc = { count: number; users: number; last: string | null; apps: Map<string, number>; envs: Set<string> };
  const acc = new Map<string, Acc>();
  for (const r of rows) {
    const id = r["issue.id"] == null ? "" : String(r["issue.id"]);
    if (!id) continue;
    const a = acc.get(id) ?? { count: 0, users: 0, last: null, apps: new Map(), envs: new Set() };
    const c = num(r["count()"]);
    a.count += c;
    a.users += num(r["count_unique(user)"]);
    const ts = r["max(timestamp)"] ?? null;
    if (ts && (!a.last || ts > a.last)) a.last = ts;
    const app = (r.app ?? "").toLowerCase();
    if (app) a.apps.set(app, (a.apps.get(app) ?? 0) + c);
    a.envs.add((r.environment ?? "production").toLowerCase());
    acc.set(id, a);
  }

  const byId = new Map(issues.map((i) => [String(i.id), i]));
  const out: IssueRow[] = [];
  for (const [id, a] of acc) {
    const issue = byId.get(id);
    if (!issue) continue;
    const topApp = [...a.apps.entries()].sort((x, y) => y[1] - x[1])[0]?.[0] ?? null;
    const platform = platformOf(topApp, issue.platform);
    out.push({
      id,
      short_id: issue.shortId ?? id,
      title: issue.title?.trim() || issue.metadata?.title?.trim() || "—",
      where: whereOf(issue),
      page: pageOf(issue, platform),
      platform,
      count: a.count,
      users: a.users,
      first_seen: issue.firstSeen ?? null,
      last_seen: a.last ?? issue.lastSeen ?? null,
      level: issue.level ?? "error",
      test_only: a.envs.size > 0 && [...a.envs].every((e) => TEST_ENVIRONMENTS.has(e)),
    });
  }
  out.sort((x, y) => y.count - x.count || (y.last_seen ?? "").localeCompare(x.last_seen ?? ""));

  const totals: Record<Platform, number> = { ios: 0, android: 0, web: 0, other: 0 };
  for (const r of out) totals[r.platform] += 1;
  return { ok: true, configured: true, days, totals, issues: out.slice(0, ISSUE_CAP) };
}

// MARK: - التفاصيل

export type Frame = { file: string | null; function: string | null; line: number | null; in_app: boolean };

export type EventDetail = {
  release: string | null;
  environment: string | null;
  os: string | null;
  device: string | null;
  browser: string | null;
  frames: Frame[];
};

type RawFrame = {
  filename?: string | null; absPath?: string | null; module?: string | null; package?: string | null;
  function?: string | null; symbol?: string | null; lineNo?: number | null; inApp?: boolean | null;
};
type RawEntry = { type?: string; data?: { values?: Array<{ stacktrace?: { frames?: RawFrame[] } | null; crashed?: boolean; current?: boolean }> } };
export type RawEvent = {
  release?: { version?: string } | string | null;
  tags?: Array<{ key?: string; value?: string }>;
  contexts?: Record<string, Record<string, unknown> | undefined>;
  entries?: RawEntry[];
};

/** أقصى عدد أسطر من مسار الخطأ */
export const FRAME_CAP = 8;

function frameOf(f: RawFrame): Frame {
  return {
    file: baseName(f.filename ?? f.absPath ?? f.module ?? f.package ?? null),
    function: (f.function ?? f.symbol ?? null)?.toString().trim() || null,
    line: typeof f.lineNo === "number" ? f.lineNo : null,
    in_app: !!f.inApp,
  };
}

/** مسار الخطأ: من «exception» (آخر قيمة) وإلا من الخيط المتوقف/الحالي — الأحدث أولاً، أسطر التطبيق أولاً */
export function framesOf(event: RawEvent): Frame[] {
  const entries = event.entries ?? [];
  let raw: RawFrame[] = [];
  const exc = entries.find((e) => e.type === "exception")?.data?.values ?? [];
  if (exc.length) raw = exc[exc.length - 1]?.stacktrace?.frames ?? [];
  if (!raw.length) {
    const threads = entries.find((e) => e.type === "threads")?.data?.values ?? [];
    const t = threads.find((v) => v.crashed) ?? threads.find((v) => v.current) ?? threads[0];
    raw = t?.stacktrace?.frames ?? [];
  }
  const frames = [...raw].reverse().map(frameOf).filter((f) => f.file || f.function);
  const inApp = frames.filter((f) => f.in_app);
  return (inApp.length ? inApp : frames).slice(0, FRAME_CAP);
}

function ctx(event: RawEvent, name: string, ...keys: string[]): string | null {
  const c = event.contexts?.[name];
  if (!c) return null;
  const parts = keys.map((k) => c[k]).filter((v) => typeof v === "string" && v.trim()) as string[];
  return parts.length ? parts.join(" ") : null;
}

export function buildDetail(event: RawEvent): EventDetail {
  const release = typeof event.release === "string" ? event.release : event.release?.version ?? null;
  const tag = (k: string) => event.tags?.find((t) => t.key === k)?.value ?? null;
  return {
    release,
    environment: tag("environment"),
    os: ctx(event, "os", "name", "version"),
    device: ctx(event, "device", "model") ?? ctx(event, "device", "family"),
    browser: ctx(event, "browser", "name", "version"),
    frames: framesOf(event),
  };
}
