import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.4";

// ---- Types ----
type Action =
  | "chat"
  | "generate_bio"
  | "generate_news"
  | "admin_summary"
  | "analyze_tree";

interface AIRequest {
  action: Action;
  user_id: string;
  message?: string;
  conversation_history?: { role: string; content: string }[];
  member_id?: string;
  topic?: string;
  news_type?: string;
}

// deno-lint-ignore no-explicit-any
type ProfileRow = Record<string, any>;

// ---- CORS + JSON (same pattern as push-admins) ----
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// ---- Supabase admin client ----
function getSupabaseAdmin() {
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

// ---- Rate limiting (in-memory, resets on cold start) ----
const rateLimitMap = new Map<string, number[]>();

function checkRateLimit(userId: string, maxPerMinute = 10): boolean {
  const now = Date.now();
  const timestamps = (rateLimitMap.get(userId) ?? []).filter(
    (t) => now - t < 60_000
  );
  if (timestamps.length >= maxPerMinute) return false;
  timestamps.push(now);
  rateLimitMap.set(userId, timestamps);
  return true;
}

// ---- Claude API caller ----
async function callClaude(
  systemPrompt: string,
  userMessage: string,
  model = "claude-haiku-4-5",
  conversationHistory?: { role: string; content: string }[]
): Promise<string> {
  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!apiKey) throw new Error("Missing ANTHROPIC_API_KEY");

  const messages = [
    ...(conversationHistory ?? []),
    { role: "user", content: userMessage },
  ];

  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model,
      max_tokens: 2048,
      system: systemPrompt,
      messages,
    }),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`Claude API error ${response.status}: ${errorText}`);
  }

  const result = await response.json();
  return result.content?.[0]?.text ?? "";
}

// ---- Helper: build readable tree text ----
function buildFamilyTreeText(members: ProfileRow[]): string {
  const byId = new Map(members.map((m) => [m.id, m]));
  const lines: string[] = [];

  for (const m of members) {
    const fatherName = m.father_id
      ? byId.get(m.father_id)?.full_name ?? "غير معروف"
      : "لا يوجد (جذر)";
    const deceased = m.is_deceased ? "متوفى" : "حي";
    const birthYear = m.birth_date
      ? String(m.birth_date).substring(0, 4)
      : "غير محدد";
    const children = members
      .filter((c) => c.father_id === m.id)
      .map((c) => c.first_name)
      .join("، ");

    lines.push(
      `- ${m.full_name} (ID: ${String(m.id).substring(0, 8)}) | الأب: ${fatherName} | ${deceased} | مواليد: ${birthYear} | الأبناء: ${children || "لا يوجد"}`
    );
  }

  return lines.join("\n");
}

// ---- Action Handlers ----

async function handleChat(payload: AIRequest) {
  const supabase = getSupabaseAdmin();

  const { data: members, error } = await supabase
    .from("profiles")
    .select(
      "id, full_name, first_name, father_id, birth_date, death_date, is_deceased, role, is_married, bio_json, created_at"
    )
    .eq("status", "active");

  if (error)
    return json(500, { ok: false, message: "Database operation failed" });

  const treeText = buildFamilyTreeText(members ?? []);
  const memberCount = (members ?? []).length;

  const systemPrompt = `أنت مساعد ذكي متخصص في شجرة العائلة.
لديك بيانات شجرة العائلة الكاملة أدناه. أجب على أسئلة المستخدم بالعربية فقط.
كن دقيقاً ومختصراً. إذا لم تجد المعلومة في البيانات، قل ذلك بوضوح.

بيانات الشجرة (${memberCount} عضو):
${treeText}

قواعد مهمة:
- أجب بالعربية دائماً
- استخدم البيانات أعلاه فقط، لا تخترع معلومات
- عند السؤال عن القرابة، تتبع سلسلة father_id
- الجد = أبو الأب، العم = أبناء الجد، ابن العم = أبناء العم
- إذا سُئلت عن شخص غير موجود في البيانات، أخبر المستخدم بذلك`;

  const reply = await callClaude(
    systemPrompt,
    payload.message ?? "",
    "claude-haiku-4-5",
    payload.conversation_history
  );

  return json(200, { ok: true, reply, action: "chat" });
}

async function handleGenerateBio(payload: AIRequest) {
  if (!payload.member_id) {
    return json(400, { ok: false, message: "member_id is required" });
  }

  const supabase = getSupabaseAdmin();

  const { data: member, error } = await supabase
    .from("profiles")
    .select("*")
    .eq("id", payload.member_id)
    .single();

  if (error || !member)
    return json(404, { ok: false, message: "Member not found" });

  const { data: children } = await supabase
    .from("profiles")
    .select("first_name, birth_date, is_deceased")
    .eq("father_id", payload.member_id);

  let fatherName = "غير معروف";
  if (member.father_id) {
    const { data: father } = await supabase
      .from("profiles")
      .select("full_name")
      .eq("id", member.father_id)
      .single();
    if (father) fatherName = father.full_name;
  }

  const existingBio = member.bio_json
    ? JSON.stringify(member.bio_json)
    : "لا توجد سيرة سابقة";

  const systemPrompt = `أنت كاتب سير ذاتية عائلية محترف. اكتب سيرة ذاتية جميلة ومختصرة بالعربية.
أنشئ محطات حياتية (bio stations) بصيغة JSON array.
كل محطة تحتوي: year (سنة اختيارية)، title (عنوان)، details (تفاصيل).
أرجع JSON array فقط بدون أي نص إضافي.`;

  const userMessage = `أنشئ سيرة ذاتية للعضو:
الاسم: ${member.full_name}
تاريخ الميلاد: ${member.birth_date ?? "غير محدد"}
الحالة: ${member.is_deceased ? "متوفى" + (member.death_date ? ` (${member.death_date})` : "") : "حي"}
متزوج: ${member.is_married ? "نعم" : "لا/غير محدد"}
الأب: ${fatherName}
الأبناء: ${(children ?? []).map((c: ProfileRow) => c.first_name).join("، ") || "لا يوجد"}
السيرة الحالية: ${existingBio}

أنشئ 3-5 محطات حياتية واقعية ومناسبة بصيغة JSON array:
[{"year": "1970", "title": "...", "details": "..."}, ...]`;

  const reply = await callClaude(systemPrompt, userMessage, "claude-haiku-4-5");

  let bioStations;
  try {
    const jsonMatch = reply.match(/\[[\s\S]*\]/);
    bioStations = jsonMatch ? JSON.parse(jsonMatch[0]) : [];
  } catch {
    bioStations = [];
  }

  return json(200, {
    ok: true,
    reply,
    bio_stations: bioStations,
    action: "generate_bio",
  });
}

async function handleGenerateNews(payload: AIRequest) {
  const supabase = getSupabaseAdmin();

  const { data: recentNews } = await supabase
    .from("news")
    .select("content, type")
    .eq("approval_status", "approved")
    .order("created_at", { ascending: false })
    .limit(5);

  const newsExamples = (recentNews ?? [])
    .map((n: ProfileRow) => `[${n.type}]: ${String(n.content).substring(0, 100)}`)
    .join("\n");

  const { data: user } = await supabase
    .from("profiles")
    .select("full_name, first_name")
    .eq("id", payload.user_id)
    .single();

  const systemPrompt = `أنت كاتب أخبار عائلية محترف. اكتب منشوراً إخبارياً بالعربية.
اكتب بأسلوب دافئ وعائلي. المنشور يجب أن يكون مختصراً (2-4 أسطر).
أرجع JSON object بالحقول: content (النص)، type (نوع الخبر: خبر/تهنئة/إعلان/تعزية).
أرجع JSON فقط بدون نص إضافي.`;

  const userMessage = `اكتب منشوراً إخبارياً عائلياً:
الموضوع: ${payload.topic ?? "خبر عام"}
النوع المطلوب: ${payload.news_type ?? "خبر"}
اسم الكاتب: ${user?.full_name ?? "عضو"}

أمثلة من أخبار سابقة:
${newsExamples || "لا توجد أمثلة"}

أرجع JSON: {"content": "...", "type": "..."}`;

  const reply = await callClaude(systemPrompt, userMessage, "claude-haiku-4-5");

  let newsData;
  try {
    const jsonMatch = reply.match(/\{[\s\S]*\}/);
    newsData = jsonMatch
      ? JSON.parse(jsonMatch[0])
      : { content: reply, type: "خبر" };
  } catch {
    newsData = { content: reply, type: "خبر" };
  }

  return json(200, {
    ok: true,
    reply,
    news_data: newsData,
    action: "generate_news",
  });
}

async function handleAdminSummary(payload: AIRequest) {
  const supabase = getSupabaseAdmin();

  // Verify admin role
  const { data: profile } = await supabase
    .from("profiles")
    .select("role")
    .eq("id", payload.user_id)
    .single();

  if (!profile || !["admin", "supervisor"].includes(profile.role)) {
    return json(403, { ok: false, message: "Admin access required" });
  }

  const { data: pendingRequests } = await supabase
    .from("admin_requests")
    .select("request_type, status, details, created_at, new_value")
    .eq("status", "pending")
    .order("created_at", { ascending: false });

  const { data: pendingNews } = await supabase
    .from("news")
    .select("content, type, author_name, created_at")
    .eq("approval_status", "pending");

  const { data: members } = await supabase
    .from("profiles")
    .select("role, status, is_deceased, created_at");

  const pendingMembers = (members ?? []).filter(
    (m: ProfileRow) => m.role === "pending"
  );
  const activeMembers = (members ?? []).filter(
    (m: ProfileRow) => m.status === "active"
  );
  const deceasedMembers = (members ?? []).filter(
    (m: ProfileRow) => m.is_deceased
  );

  const dataText = `
إحصائيات الأعضاء:
- إجمالي: ${(members ?? []).length}
- نشط: ${activeMembers.length}
- متوفى: ${deceasedMembers.length}
- بانتظار الموافقة: ${pendingMembers.length}

طلبات إدارية معلقة (${(pendingRequests ?? []).length}):
${(pendingRequests ?? []).map((r: ProfileRow) => `- ${r.request_type}: ${r.details ?? r.new_value ?? "بدون تفاصيل"} (${String(r.created_at ?? "").substring(0, 10)})`).join("\n")}

أخبار بانتظار النشر (${(pendingNews ?? []).length}):
${(pendingNews ?? []).map((n: ProfileRow) => `- [${n.type}] ${n.author_name}: ${String(n.content).substring(0, 80)}`).join("\n")}`;

  const systemPrompt = `أنت مساعد إداري ذكي لتطبيق شجرة عائلة.
قدم ملخصاً واضحاً ومنظماً بالعربية للمدير عن حالة التطبيق والمهام المعلقة.
رتب الأولويات واقترح إجراءات.`;

  const reply = await callClaude(systemPrompt, dataText, "claude-haiku-4-5");

  return json(200, {
    ok: true,
    reply,
    stats: {
      total_members: (members ?? []).length,
      active: activeMembers.length,
      pending_members: pendingMembers.length,
      pending_requests: (pendingRequests ?? []).length,
      pending_news: (pendingNews ?? []).length,
    },
    action: "admin_summary",
  });
}

async function handleAnalyzeTree(payload: AIRequest) {
  const supabase = getSupabaseAdmin();

  const { data: members, error } = await supabase
    .from("profiles")
    .select(
      "id, full_name, first_name, father_id, birth_date, death_date, is_deceased, is_married, role, created_at"
    )
    .eq("status", "active");

  if (error)
    return json(500, { ok: false, message: "Database operation failed" });

  const treeText = buildFamilyTreeText(members ?? []);

  const systemPrompt = `أنت محلل بيانات عائلية متخصص. حلل شجرة العائلة وقدم تقريراً شاملاً بالعربية.
قدم: إحصائيات عامة، أطول سلسلة أجيال، الفروع الأكبر، متوسط الأبناء لكل عضو،
أعضاء بدون أبناء، أقدم وأحدث الأعضاء، ونسبة المتوفين.
كن دقيقاً في الأرقام.`;

  const reply = await callClaude(
    systemPrompt,
    `حلل شجرة العائلة التالية:\n${treeText}`,
    "claude-haiku-4-5"
  );

  return json(200, {
    ok: true,
    reply,
    member_count: (members ?? []).length,
    action: "analyze_tree",
  });
}

// ---- Main Router ----
serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json(405, { ok: false, message: "Method not allowed" });
  }

  // JWT verification — require authenticated user
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return json(401, { ok: false, message: "Missing authorization header" });
  }
  const supabaseAuth = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_ANON_KEY") ?? ""
  );
  const { data: { user: authUser }, error: authError } = await supabaseAuth.auth.getUser(
    authHeader.replace("Bearer ", "")
  );
  if (authError || !authUser) {
    return json(401, { ok: false, message: "Invalid or expired token" });
  }

  let payload: AIRequest;
  try {
    payload = await req.json();
  } catch {
    return json(400, { ok: false, message: "Invalid JSON body" });
  }

  const { action, user_id } = payload;
  if (!action || !user_id) {
    return json(400, {
      ok: false,
      message: "action and user_id are required",
    });
  }

  // Verify user_id matches the authenticated user
  if (user_id !== authUser.id) {
    return json(403, { ok: false, message: "User ID mismatch" });
  }

  // Rate limiting
  if (!checkRateLimit(user_id)) {
    return json(429, {
      ok: false,
      message: "تم تجاوز الحد المسموح. انتظر قليلاً ثم حاول مرة أخرى.",
    });
  }

  try {
    switch (action) {
      case "chat":
        return await handleChat(payload);
      case "generate_bio":
        return await handleGenerateBio(payload);
      case "generate_news":
        return await handleGenerateNews(payload);
      case "admin_summary":
        return await handleAdminSummary(payload);
      case "analyze_tree":
        return await handleAnalyzeTree(payload);
      default:
        return json(400, { ok: false, message: `Unknown action: ${action}` });
    }
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error(`[claude-ai] Error for action=${action}:`, msg);
    return json(500, { ok: false, message: "An internal error occurred. Please try again." });
  }
});
