// «الأخطاء» في لوحة الإدارة (طلب المالك ٢٠٢٦-١١-٢٦): يقرأ ما وصل Sentry من الآيفون والأندرويد والموقع — للمالك وحده.
//
// النداء: POST بجلسة المستخدم، الجسم {action:"list", days:1|7|30} أو {action:"detail", id:"<رقم الخطأ>"}.
// السرّ: SENTRY_READ_TOKEN في Edge Secrets (مفتاح قراءة فقط) — لا يخرج من السيرفر ولا يدخل التطبيق.
// بلا سرّ: {ok:true, configured:false} — الصفحة تقول «لم يُربط بعد».
// الأخطاء: {ok:false, error:{code}} — owner_only · bad_request · sentry_error · not_found.
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { handleCors, validatePost, json } from "../_shared/cors.ts";
import { authenticateRequest, parseBody } from "../_shared/auth.ts";
import { buildDetail, buildList, periodFor, PERIODS, type DiscoverRow, type RawEvent, type SentryIssue } from "./shape.ts";

const ORG = Deno.env.get("SENTRY_ORG") ?? "almohaliapp";
/** مشروع Sentry الواحد للمنصات الثلاث (familytree) */
const PROJECT_ID = Deno.env.get("SENTRY_PROJECT_ID") ?? "4512495138045952";
const API = "https://sentry.io/api/0";

class SentryError extends Error {
  constructor(readonly status: number) { super(`sentry ${status}`); }
}

async function sentry<T>(token: string, path: string): Promise<T> {
  const res = await fetch(`${API}${path}`, { headers: { Authorization: `Bearer ${token}` } });
  if (!res.ok) throw new SentryError(res.status);
  return await res.json() as T;
}

async function list(token: string, days: number) {
  const q = new URLSearchParams({ dataset: "errors", statsPeriod: PERIODS[days], project: PROJECT_ID, sort: "-count()", per_page: "100" });
  for (const f of ["issue.id", "app", "environment", "count()", "count_unique(user)", "max(timestamp)"]) q.append("field", f);
  const rows = (await sentry<{ data?: DiscoverRow[] }>(token, `/organizations/${ORG}/events/?${q}`)).data ?? [];
  const ids = [...new Set(rows.map((r) => r["issue.id"]).filter((v) => v != null).map(String))].slice(0, 100);
  if (!ids.length) return buildList(days, [], []);
  const g = new URLSearchParams({ project: PROJECT_ID, statsPeriod: PERIODS[days] });
  for (const id of ids) g.append("group", id);
  const issues = await sentry<SentryIssue[]>(token, `/organizations/${ORG}/issues/?${g}`);
  return buildList(days, rows, issues);
}

async function detail(token: string, id: string) {
  const [issue, event] = await Promise.all([
    sentry<SentryIssue>(token, `/organizations/${ORG}/issues/${id}/`),
    sentry<RawEvent>(token, `/organizations/${ORG}/issues/${id}/events/latest/`),
  ]);
  // نفس شكل صفّ القائمة (بعدّ الخطأ كله لا الفترة) + تفاصيل آخر حدث
  const row = buildList(30, [{ "issue.id": id, "count()": Number((issue as { count?: string }).count ?? 0),
                               "count_unique(user)": Number((issue as { userCount?: number }).userCount ?? 0),
                               "max(timestamp)": issue.lastSeen ?? undefined,
                               app: (event.tags ?? []).find((t) => t.key === "app")?.value ?? null,
                               environment: (event.tags ?? []).find((t) => t.key === "environment")?.value ?? null }],
                         [issue]).issues[0] ?? null;
  return { ok: true, configured: true, issue: row, event: buildDetail(event) };
}

serve(async (req) => {
  const cors = handleCors(req); if (cors) return cors;
  const method = validatePost(req); if (method) return method;
  const auth = await authenticateRequest(req, ["owner"]);
  if (auth instanceof Response) {
    return auth.status === 403 ? json(403, { ok: false, error: { code: "owner_only" } }) : auth;
  }
  const body = await parseBody<{ action?: string; days?: number; id?: string }>(req);
  if (body instanceof Response) return json(400, { ok: false, error: { code: "bad_request" } });

  const token = Deno.env.get("SENTRY_READ_TOKEN") ?? "";
  if (!token) return json(200, { ok: true, configured: false });

  try {
    if (body?.action === "detail") {
      const id = String(body.id ?? "");
      if (!/^\d{1,20}$/.test(id)) return json(400, { ok: false, error: { code: "bad_request" } });
      return json(200, await detail(token, id));
    }
    return json(200, await list(token, periodFor(body?.days)));
  } catch (e) {
    const status = e instanceof SentryError ? e.status : 0;
    if (status === 404) return json(404, { ok: false, error: { code: "not_found" } });
    console.error("[sentry-issues]", status || (e instanceof Error ? e.message : "error"));
    return json(502, { ok: false, error: { code: "sentry_error", sentry_status: status || null } });
  }
});
