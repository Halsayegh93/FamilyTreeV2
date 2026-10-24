// عميل KWT SMS المشترك (استُخرج حرفياً من kwtsms-admin ٢٠٢٦-١٠-٢٠ — نفس السلوك) — يستعمله kwtsms-admin وkwtsms-cron.
// رابط ثابت، POST JSON، مهلة لكل طلب، بلا إعادة محاولة. بيانات الدخول في جسم الطلب فقط — لا في الرابط ولا في أي سجل.
export const KWT_API = "https://www.kwtsms.com/API/";

export type KwtCredentials = { username: string; password: string };
// deno-lint-ignore no-explicit-any
export type KwtResult = { ok: boolean; status: number; data: any };

export async function readBounded(
  stream: ReadableStream<Uint8Array> | null,
  limit: number,
): Promise<string> {
  const reader = stream?.getReader();
  if (!reader) return "";
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > limit) {
        await reader.cancel();
        throw Error("too large");
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.length;
  }
  return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
}
// deno-lint-ignore no-explicit-any
export async function readJson(response: Response, limit = 65536): Promise<any> {
  return JSON.parse(await readBounded(response.body, limit));
}
export const num = (v: unknown): number | null => {
  const n = typeof v === "string" && /^[0-9]+(\.[0-9]+)?$/.test(v) ? Number(v) : v;
  return typeof n === "number" && Number.isFinite(n) && n >= 0 ? n : null;
};
export const providerCode = (data: unknown): string => {
  const code = (data as { code?: unknown } | null)?.code;
  return typeof code === "string" && /^ERR[0-9]{3}$/.test(code) ? code : "UNKNOWN";
};

// نداء KWT واحد: رابط ثابت، بلا إعادة محاولة. يرمي عند انقطاع/مهلة فقط.
export async function kwtCall(
  send: typeof fetch,
  creds: KwtCredentials,
  endpoint: string,
  extra: Record<string, string> = {},
  timeoutMs = 8000,
): Promise<KwtResult> {
  const response = await send(`${KWT_API}${endpoint}/`, {
    method: "POST",
    signal: AbortSignal.timeout(timeoutMs),
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    body: JSON.stringify({ username: creds.username, password: creds.password, ...extra }),
  });
  const data = await readJson(response).catch(() => null);
  return { ok: response.ok && data?.result === "OK", status: response.status, data };
}
