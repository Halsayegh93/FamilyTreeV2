// تنبيه الأخطاء بالعربي (طلب المالك ٢٠٢٦-١١-٢٧: إيميلات Sentry إنجليزية — «ابيها بالعربي»).
// دوال صافية بلا شبكة ولا Deno — تُفحص بـ node:
//   node supabase/functions/sentry-alert-ar/arabic_test.mjs
//
// ١) `describeError` — نفس قواعد التطبيق `AdminErrorArabic.describe` (AdminErrorTitles.swift) حرفياً: أي تعديل هناك يُنقل هنا.
// ٢) `parseSentryPayload` — يقرأ شكلي Sentry: «WebHooks» القديم (Legacy Integrations) وتنبيه قاعدة بـ«إجراء webhook»
//    (event_alert من تكامل داخلي) وحدث «issue» — ويُرجع null لما ليس خطأً (تنبيه مقياس، installation…).
// ٣) `buildAlertEmail` — عنوان ونص وHTML بقالب العائلة الموحّد (`_shared/email.ts`).
//
// الخصوصية: لا يدخل الإيميل معرّف جهاز ولا مستخدم ولا فتات — العنوان والمنصة والعدد والتواريخ والإصدار ورابط الخطأ فقط.

import { BRAND, ctaButton, dataRow, dataTable, escapeHtml, note, paragraph, renderEmail } from "../_shared/email.ts";
import { platformOf, type Platform } from "../sentry-issues/shape.ts";

// MARK: - العنوان بالعربي (منقول من AdminErrorTitles.swift)

export type ErrorKind = "hang" | "killed" | "crash" | "network" | "web" | "unknown";
export type ArabicError = { kind: ErrorKind; title: string; line: string; showsOriginal: boolean };

const NETWORK_MARKERS = [
  "urlerror", "nsurlerrordomain", "failed to fetch", "networkerror", "network error", "network connection",
  "timed out", "timeout", "could not connect", "cannot connect", "not connected to the internet",
  "httperror", "http error", "status code", "statuscode", "functionsrelayerror", "fetcherror",
  "postgresterror", "socketexception", "unknownhostexception", "sockettimeoutexception", "connectexception",
  "load failed",
];

function make(kind: ErrorKind, title: string, line: string): ArabicError {
  return { kind, title, line, showsOriginal: kind !== "unknown" };
}

/** `rawTitle` من Sentry، و`platform` = ios · android · web · other */
export function describeError(rawTitle: string, platform = ""): ArabicError {
  const original = (rawTitle ?? "").trim();
  const lower = original.toLowerCase();
  const h = head(original);

  // ١) تعليق
  if (lower.startsWith("app hang") || lower.includes("app hanging") || lower.startsWith("applicationnotresponding") ||
      lower.startsWith("anr ") || lower.startsWith("anr:")) {
    return make("hang", hangTitle(lower), "الشاشة توقفت عن الاستجابة");
  }
  // ٢) النظام أغلق التطبيق
  if (lower.startsWith("watchdogtermination") || lower.includes("watchdog terminated")) {
    return make("killed", "النظام أغلق التطبيق", "غالباً استهلاك ذاكرة كبير، أو أُعيد تثبيت النسخة نفسها أثناء عملها");
  }
  // ٣) اتصال بالسيرفر (قبل «الموقع»)
  if (NETWORK_MARKERS.some((m) => lower.includes(m)) || /\bhttp ?[1-5][0-9]{2}\b/.test(lower)) {
    return make("network", "خطأ اتصال بالسيرفر", networkLine(lower));
  }
  // ٤) توقّف مفاجئ
  const why = crashReason(h, lower);
  if (why !== null) return make("crash", "توقّف التطبيق فجأة", why);
  // ٥) الموقع
  if (h === "Error" || (platform === "web" && (h.endsWith("Error") || h === "UnhandledRejection"))) {
    return make("web", "خطأ في الموقع", "صفحة في الموقع لم تعمل كما يجب");
  }
  return make("unknown", original === "" ? "—" : original, "خطأ غير مصنّف");
}

/** ما قبل أول «: » */
export function head(title: string): string {
  const i = title.indexOf(": ");
  return (i < 0 ? title : title.slice(0, i)).trim();
}

export function hangTitle(lower: string): string {
  const m = lower.match(/between ([0-9]+(?:\.[0-9]+)?) and ([0-9]+(?:\.[0-9]+)?) seconds/);
  if (m) {
    const a = Number(m[1]), b = Number(m[2]);
    return `التطبيق علّق ${seconds(a)}–${seconds(b)} ${secondsWord(b)}`;
  }
  const ms = lower.match(/at least ([0-9]+) ?ms/);
  if (ms) {
    const s = Number(ms[1]) / 1000;
    return `التطبيق علّق ${seconds(s)} ${secondsWord(s)} أو أكثر`;
  }
  return "التطبيق علّق";
}

export function seconds(v: number): string {
  return v === Math.round(v) ? String(Math.trunc(v)) : v.toFixed(1);
}

export function secondsWord(v: number): string {
  return v === Math.round(v) && v >= 3 && v <= 10 ? "ثوانٍ" : "ثانية";
}

function networkLine(lower: string): string {
  if (lower.includes("timed out") || lower.includes("timeout")) return "السيرفر تأخّر في الرد";
  if (lower.includes("not connected to the internet") || lower.includes("network connection") || lower.includes("unknownhost")) {
    return "الجهاز لم يكن متصلاً بالإنترنت أو انقطع الاتصال";
  }
  return "طلب للسيرفر لم يكتمل";
}

function crashReason(headText: string, lower: string): string | null {
  const h = headText.toLowerCase();
  if (lower.includes("unexpectedly found nil")) return "قيمة فارغة لم تكن متوقّعة في الكود";
  if (lower.includes("index out of range")) return "طلب عنصر خارج حدود القائمة";
  if (h === "fatal error") return "خطأ برمجي أوقف التطبيق";
  if (h.startsWith("exc_bad_access") || h === "sigsegv" || h === "sigbus") return "قراءة من ذاكرة غير صالحة";
  if (h === "sigabrt" || h.startsWith("exc_crash")) return "أوقف التطبيق نفسه بسبب خطأ داخلي";
  if (h.startsWith("exc_breakpoint") || h === "sigtrap") return "شرط في الكود لم يتحقّق فأوقف التطبيق";
  if (h === "sigkill") return "النظام أوقف التطبيق";
  if (h.endsWith("nsinvalidargumentexception")) return "قيمة غير صالحة مُرّرت للنظام";
  if (h.endsWith("nsrangeexception")) return "طلب عنصر خارج حدود القائمة";
  if (h.endsWith("nsinternalinconsistencyexception")) return "حالة غير متوقّعة داخل الشاشة";
  if (h.endsWith("nullpointerexception")) return "قيمة فارغة لم تكن متوقّعة في الكود";
  if (h.endsWith("outofmemoryerror")) return "نفدت الذاكرة";
  if (h.endsWith("illegalstateexception") || h.endsWith("illegalargumentexception")) return "حالة غير متوقّعة داخل التطبيق";
  if (h.startsWith("exc_") || h.startsWith("sig") || h.endsWith("exception")) return `السبب: ${headText}`;
  return null;
}

// MARK: - المنصة والوقت

export const PLATFORM_AR: Record<Platform, string> = { ios: "آيفون", android: "أندرويد", web: "الموقع", other: "غير معروفة" };

/** «27/11/2026 · 3:05 م» بتوقيت الكويت (UTC+3 طول السنة، بلا توقيت صيفي) — null لتاريخ غير صالح */
export function kuwaitTime(iso: string | null | undefined): string | null {
  if (!iso) return null;
  const t = Date.parse(iso);
  if (Number.isNaN(t)) return null;
  const d = new Date(t + 3 * 3600 * 1000);
  const h24 = d.getUTCHours();
  const h12 = h24 % 12 === 0 ? 12 : h24 % 12;
  const mm = String(d.getUTCMinutes()).padStart(2, "0");
  return `${d.getUTCDate()}/${d.getUTCMonth() + 1}/${d.getUTCFullYear()} · ${h12}:${mm} ${h24 < 12 ? "ص" : "م"}`;
}

/** «مرة واحدة» · «مرتين» · «3 مرات» · «11 مرة» */
export function timesAr(n: number): string {
  if (n === 1) return "مرة واحدة";
  if (n === 2) return "مرتين";
  if (n >= 3 && n <= 10) return `${n} مرات`;
  return `${n} مرة`;
}

/** «جهاز واحد» · «جهازين» · «3 أجهزة» · «11 جهازاً» */
export function devicesAr(n: number): string {
  if (n === 1) return "جهاز واحد";
  if (n === 2) return "جهازين";
  if (n >= 3 && n <= 10) return `${n} أجهزة`;
  return `${n} جهازاً`;
}

/** «Hasan.FamilyTreeV2@2.4 (312)» → «2.4 (312)» */
export function releaseAr(r: string): string {
  const i = r.lastIndexOf("@");
  return (i >= 0 ? r.slice(i + 1) : r).replace("+", " (") + (r.slice(i + 1).includes("+") ? ")" : "");
}

// MARK: - قراءة طلب Sentry

export type SentryAlert = {
  issueId: string | null;
  shortId: string | null;
  title: string;
  url: string | null;
  app: string | null;
  sentryPlatform: string | null;
  release: string | null;
  environment: string | null;
  level: string | null;
  /** آخر حدث (وقت الإرسال) */
  eventTime: string | null;
  count: number | null;
  userCount: number | null;
  firstSeen: string | null;
  lastSeen: string | null;
  /** حدث تجريبي (زر «Test» في Sentry أو sample_event) */
  isSample: boolean;
  /** مصدر الشكل: legacy · event_alert · issue */
  source: "legacy" | "event_alert" | "issue";
};

type Obj = Record<string, unknown>;
const obj = (v: unknown): Obj | null => (v && typeof v === "object" && !Array.isArray(v) ? v as Obj : null);
const str = (v: unknown): string | null => (typeof v === "string" && v.trim() !== "" ? v.trim() : typeof v === "number" ? String(v) : null);
const num = (v: unknown): number | null => {
  const n = typeof v === "number" ? v : typeof v === "string" && v.trim() !== "" ? Number(v) : NaN;
  return Number.isFinite(n) ? n : null;
};

/** العلامات: Sentry يرسلها [[key,value],…] أو [{key,value},…] */
export function tagsOf(v: unknown): Record<string, string> {
  const out: Record<string, string> = {};
  if (!Array.isArray(v)) return out;
  for (const t of v) {
    if (Array.isArray(t) && t.length >= 2) {
      const k = str(t[0]), val = str(t[1]);
      if (k && val) out[k] = val;
    } else {
      const o = obj(t);
      const k = str(o?.key), val = str(o?.value);
      if (k && val) out[k] = val;
    }
  }
  return out;
}

/** رقم الخطأ من رابطه («…/issues/12345/…») */
function issueIdFromUrl(url: string | null): string | null {
  return url?.match(/\/issues\/(\d+)/)?.[1] ?? null;
}

function eventTimeOf(ev: Obj): string | null {
  const dt = str(ev.datetime);
  if (dt) return dt;
  const ts = num(ev.timestamp);
  if (ts !== null) return new Date(ts * 1000).toISOString();
  return str(ev.timestamp);
}

function isSampleEvent(title: string, tags: Record<string, string>, issueId: string | null): boolean {
  return tags.sample_event === "yes" || /this is an example/i.test(title) || issueId === null;
}

/** null = ليس خطأً نرسله (تنبيه مقياس، تثبيت تكامل، جسم فارغ) */
export function parseSentryPayload(body: unknown): SentryAlert | null {
  const b = obj(body);
  if (!b) return null;
  const data = obj(b.data);

  // ٢) قاعدة تنبيه بإجراء webhook (تكامل داخلي، resource = event_alert)
  const alertEvent = obj(data?.event);
  if (alertEvent) {
    const tags = tagsOf(alertEvent.tags);
    const url = str(alertEvent.web_url) ?? str(alertEvent.issue_url) ?? str(alertEvent.url);
    const issueId = str(alertEvent.issue_id) ?? str(alertEvent.group_id) ?? issueIdFromUrl(url);
    const title = str(alertEvent.title) ?? str(alertEvent.message) ?? str(obj(alertEvent.metadata)?.title) ?? "";
    return {
      issueId: issueId && /^\d+$/.test(issueId) ? issueId : null, shortId: null, title,
      url: url && /^https:\/\//.test(url) && !/\/api\/0\//.test(url) ? url : null,
      app: tags.app ?? null, sentryPlatform: str(alertEvent.platform),
      release: str(alertEvent.release) ?? tags.release ?? null,
      environment: str(alertEvent.environment) ?? tags.environment ?? null,
      level: str(alertEvent.level) ?? tags.level ?? null, eventTime: eventTimeOf(alertEvent),
      count: null, userCount: null, firstSeen: null, lastSeen: null,
      isSample: isSampleEvent(title, tags, issueId && /^\d+$/.test(issueId) ? issueId : null), source: "event_alert",
    };
  }

  // ٣) حدث «issue» (تكامل داخلي، resource = issue: created · unresolved …)
  const issue = obj(data?.issue);
  if (issue) {
    const id = str(issue.id);
    const title = str(issue.title) ?? "";
    const url = str(issue.web_url) ?? str(issue.permalink);
    const validId = id && /^\d+$/.test(id) ? id : null;
    return {
      issueId: validId, shortId: str(issue.shortId), title,
      url: url && /^https:\/\//.test(url) ? url : null,
      app: null, sentryPlatform: str(issue.platform), release: null, environment: null, level: str(issue.level),
      eventTime: str(issue.lastSeen), count: num(issue.count), userCount: num(issue.userCount),
      firstSeen: str(issue.firstSeen), lastSeen: str(issue.lastSeen),
      isSample: isSampleEvent(title, {}, validId), source: "issue",
    };
  }
  if (data) return null; // metric_alert · installation · غيرها

  // ١) «WebHooks» القديم: {id, url, message, culprit, level, project_slug, event:{…}}
  const ev = obj(b.event);
  if (!ev && !("message" in b) && !("url" in b)) return null;
  const e = ev ?? {};
  const tags = tagsOf(e.tags);
  const url = str(b.url);
  const id = str(b.id) ?? str(e.group_id) ?? str(e.issue_id) ?? issueIdFromUrl(url);
  const validId = id && /^\d+$/.test(id) ? id : null;
  const title = str(e.title) ?? str(b.message) ?? str(e.message) ?? "";
  return {
    issueId: validId, shortId: null, title,
    url: url && /^https:\/\//.test(url) ? url : null,
    app: tags.app ?? null, sentryPlatform: str(e.platform),
    release: str(e.release) ?? tags.release ?? tags["sentry:release"] ?? null,
    environment: str(e.environment) ?? tags.environment ?? null,
    level: str(b.level) ?? str(e.level) ?? tags.level ?? null, eventTime: eventTimeOf(e),
    count: null, userCount: null, firstSeen: null, lastSeen: null,
    isSample: isSampleEvent(title, tags, validId), source: "legacy",
  };
}

/** رابط الخطأ: من الطلب، وإلا يُبنى من رقمه. لا يُقبل إلا رابط sentry.io */
export function issueLink(a: Pick<SentryAlert, "url" | "issueId">, org: string): string | null {
  if (a.url) {
    try {
      const u = new URL(a.url);
      if (u.protocol === "https:" && (u.hostname === "sentry.io" || u.hostname.endsWith(".sentry.io"))) {
        u.searchParams.delete("referrer");
        u.searchParams.set("referrer", "arabic_alert");
        return u.toString();
      }
    } catch { /* يُبنى من الرقم */ }
  }
  return a.issueId ? `https://${org}.sentry.io/issues/${a.issueId}/?referrer=arabic_alert` : null;
}

// MARK: - الإيميل

export type AlertEmail = { subject: string; text: string; html: string; push: { title: string; body: string } };

export function buildAlertEmail(a: SentryAlert, org: string): AlertEmail {
  const platform = platformOf(a.app, a.sentryPlatform);
  const platformAr = PLATFORM_AR[platform];
  const ar = describeError(a.title, platform);
  const link = issueLink(a, org);
  const first = kuwaitTime(a.firstSeen);
  const last = kuwaitTime(a.lastSeen ?? a.eventTime);
  const isNew = a.count !== null && a.count <= 1;
  const env = a.environment && a.environment !== "production" ? a.environment : null;

  const subject = `${isNew ? "خطأ جديد" : "خطأ"} في ${platform === "web" ? "الموقع" : `تطبيق ${platformAr}`}: ${ar.title}`;

  const rows: [string, string][] = [["المنصة", platformAr]];
  if (a.count !== null) rows.push(["تكرّر", timesAr(a.count)]);
  if (a.userCount !== null && a.userCount > 0) rows.push(["الأجهزة المتأثرة", devicesAr(a.userCount)]);
  if (first) rows.push(["أول ظهور", first]);
  if (last) rows.push(["آخر ظهور", last]);
  if (a.release) rows.push(["الإصدار", releaseAr(a.release)]);
  if (env) rows.push(["البيئة", env]);

  const where = "تجده أيضاً في التطبيق: الإدارة ← التطبيق ← الأخطاء.";
  const original = ar.showsOriginal && a.title ? `النص الأصلي: ${a.title}` : "";

  const text = [
    ar.title,
    ar.line,
    "",
    ...rows.map(([k, v]) => `${k}: ${v}`),
    "",
    link ? `افتح الخطأ: ${link}` : "",
    where,
    original,
  ].filter((l, i, all) => !(l === "" && (i === 0 || all[i - 1] === ""))).join("\n").trim();

  const body = `
    ${paragraph(`<strong style="color:${BRAND.ink}">${escapeHtml(ar.line)}</strong>`)}
    ${dataTable(rows.map(([k, v]) => dataRow(k, escapeHtml(v), { bold: k === "تكرّر" })).join(""))}
    ${link ? ctaButton("افتح الخطأ", link, BRAND.charcoal) : ""}
    ${note(where)}
    ${original ? `<p dir="ltr" style="margin:14px 0 0;color:${BRAND.muted};font-size:11.5px;line-height:1.6;text-align:left;font-family:Menlo,Consolas,monospace;word-break:break-word">${escapeHtml(a.title)}</p>` : ""}`;

  const html = renderEmail({
    title: ar.title,
    badge: isNew ? `خطأ جديد · ${platformAr}` : `خطأ · ${platformAr}`,
    accentColor: BRAND.warn,
    preheader: `${ar.line} — ${platformAr}`,
    body,
  });

  const countBit = a.count !== null ? ` · ${timesAr(a.count)}` : "";
  return {
    subject,
    text,
    html,
    push: { title: `خطأ في ${platformAr}: ${ar.title}`, body: `${ar.line}${countBit}` },
  };
}
