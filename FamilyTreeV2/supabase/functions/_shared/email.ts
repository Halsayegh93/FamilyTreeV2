// قالب إيميل فاخر ومرتّب لتطبيق شجرة عائلة آل محمد علي
// RTL عربي، متوافق مع عملاء البريد (جداول + ستايل inline)، بهوية التطبيق

export const BRAND = {
  // لوحة فحمي + شمبانيا الفاخرة
  charcoal: "#1A1D21", // ترويسة فحمية غامقة
  charcoalEnd: "#2C3037", // نهاية تدرّج الترويسة (عمق خفيف)
  champagne: "#D8C3A5", // شمبانيا فاتحة — للمسات على الترويسة الفحمية فقط
  champagneSoft: "#E7DAC4", // شمبانيا أنعم للتسمية الفرعية
  gold: "#9C7C3A", // ذهبي/برونزي غامق — لمسات داخل الجسم الأبيض (مقروء)
  warn: "#9B3B3B", // أحمر فاخر هادئ — للتنبيه (تجميد)
  // أسماء قديمة (تشير الآن للذهبي للتوافق)
  blue: "#9C7C3A",
  emerald: "#9C7C3A",
  indigo: "#9C7C3A",
  ink: "#23262B",
  body: "#52565C",
  muted: "#9A9286",
  hair: "#ECE7DD",
  panel: "#FBFAF6",
  panelLine: "#ECE7DD",
  pageBg: "#ECE8E1",
  appName: "شجرة عائلة آل محمد علي",
  tagline: "تطبيق العائلة",
};

const FONT_STACK =
  "-apple-system,BlinkMacSystemFont,'SF Pro Rounded','Segoe UI','Geeza Pro','Dubai',Tahoma,Arial,sans-serif";

// حواف المحتوى الموحّدة — كل الأقسام تشترك بنفس الهوامش لتناسق تام
const PAD = "0 44px";

export function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

function tint(hex: string, alphaHex: string): string {
  return `${hex}${alphaHex}`;
}

/**
 * صف بيانات (مفتاح/قيمة) — أعمدة بعرض ثابت لمحاذاة دقيقة.
 */
export function dataRow(label: string, value: string, opts?: { accent?: string; bold?: boolean }): string {
  const valColor = opts?.accent ?? BRAND.ink;
  const weight = opts?.bold || opts?.accent ? "700" : "600";
  return `
    <tr>
      <td width="38%" class="dr" style="padding:15px 22px;color:${BRAND.muted};font-size:12.5px;font-weight:600;letter-spacing:.2px;vertical-align:middle;border-top:1px solid ${BRAND.panelLine}">${escapeHtml(label)}</td>
      <td class="dr" style="padding:15px 22px;color:${valColor};font-size:15px;font-weight:${weight};vertical-align:middle;border-top:1px solid ${BRAND.panelLine};text-align:left">${value}</td>
    </tr>`;
}

/**
 * لوحة بيانات مرتّبة — حاوية بإطار شعري وفواصل خفيفة، بلا حشو ملوّن.
 */
export function dataTable(rows: string): string {
  const cleaned = rows.replace(`border-top:1px solid ${BRAND.panelLine}`, "border-top:none");
  return `
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="width:100%;table-layout:fixed;border-collapse:separate;background:${BRAND.panel};border:1px solid ${BRAND.panelLine};border-radius:14px;overflow:hidden;margin:22px 0">
      ${cleaned}
    </table>`;
}

/**
 * فقرة نصّية.
 */
export function paragraph(text: string): string {
  return `<p style="margin:0 0 16px;color:${BRAND.body};font-size:15.5px;line-height:1.95">${text}</p>`;
}

/**
 * صندوق اقتباس راقٍ — شريط جانبي رفيع + تظليل ناعم + عنوان علوي.
 */
export function quoteBox(text: string, opts?: { label?: string; accent?: string; subtle?: boolean }): string {
  const accent = opts?.accent ?? BRAND.blue;
  const bg = opts?.subtle ? "#F7F9FC" : tint(accent, "0D");
  const labelHtml = opts?.label
    ? `<p style="margin:0 0 10px;color:${opts?.subtle ? BRAND.muted : accent};font-size:11px;font-weight:700;letter-spacing:2px;text-transform:uppercase">${escapeHtml(opts.label)}</p>`
    : "";
  return `
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:22px 0">
      <tr>
        <td style="width:3px;background:${accent}"></td>
        <td style="padding:18px 22px;background:${bg}">
          ${labelHtml}
          <p style="margin:0;color:${BRAND.ink};font-size:15px;line-height:1.9;white-space:pre-wrap;font-weight:500">${escapeHtml(text)}</p>
        </td>
      </tr>
    </table>`;
}

/**
 * ملاحظة باهتة أسفل المحتوى (فاصل علوي شعري).
 */
export function note(text: string): string {
  return `
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:26px 0 0">
      <tr><td style="border-top:1px solid ${BRAND.hair};padding-top:18px">
        <p style="margin:0;color:${BRAND.muted};font-size:13px;line-height:1.8">${escapeHtml(text)}</p>
      </td></tr>
    </table>`;
}

/**
 * زر دعوة لاتخاذ إجراء (اختياري).
 */
export function ctaButton(label: string, url: string, accent: string = BRAND.blue): string {
  return `
    <table role="presentation" cellpadding="0" cellspacing="0" style="margin:26px 0 6px">
      <tr><td style="border-radius:12px;background:${accent}">
        <a href="${escapeHtml(url)}" style="display:inline-block;padding:15px 38px;color:#fff;font-size:15px;font-weight:700;letter-spacing:.3px;text-decoration:none;border-radius:12px">${escapeHtml(label)}</a>
      </td></tr>
    </table>`;
}

interface RenderArgs {
  /** عنوان الإيميل */
  title: string;
  /** محتوى HTML للجسم — استخدم paragraph/dataTable/quoteBox/note */
  body: string;
  /** لون مميّز للعناوين الفرعية والتأكيد (افتراضي: أزرق العلامة) */
  accentColor?: string;
  /** عنوان فرعي صغير (eyebrow) فوق العنوان الرئيسي (اختياري) */
  badge?: string;
  /** متوافقية فقط — لا تُستخدم أيقونة في هذا التصميم */
  emoji?: string;
  /** نص تمهيدي مخفي يظهر في معاينة صندوق الوارد (اختياري) */
  preheader?: string;
}

/**
 * القالب الفاخر — ترويسة كتابية متناظرة بلا أيقونة + بطاقة محتوى + تذييل أنيق.
 */
export function renderEmail(args: RenderArgs): string {
  const accent = args.accentColor ?? BRAND.gold;
  const preheader = args.preheader ?? args.title;
  const eyebrow = args.badge
    ? `<div style="color:${accent};font-size:11px;font-weight:800;letter-spacing:3px;text-transform:uppercase;margin:0 0 12px">${escapeHtml(args.badge)}</div>`
    : "";

  return `<!doctype html>
<html lang="ar" dir="rtl" xmlns="http://www.w3.org/1999/xhtml">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <meta http-equiv="X-UA-Compatible" content="IE=edge">
  <meta name="color-scheme" content="light only">
  <meta name="supported-color-schemes" content="light">
  <title>${escapeHtml(args.title)}</title>
  <style>
    @media (max-width:620px){
      .card{border-radius:16px !important}
      .pad{padding-left:26px !important;padding-right:26px !important}
      .hero{padding:38px 26px !important}
      .h1{font-size:21px !important}
    }
  </style>
</head>
<body style="margin:0;padding:0;background:${BRAND.pageBg};font-family:${FONT_STACK};-webkit-font-smoothing:antialiased;text-size-adjust:100%">
  <div style="display:none;max-height:0;overflow:hidden;opacity:0;color:${BRAND.pageBg};font-size:1px;line-height:1px">${escapeHtml(preheader)}&#8203;&#8203;&#8203;&#8203;&#8203;&#8203;&#8203;&#8203;</div>
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:${BRAND.pageBg};padding:36px 16px">
    <tr><td align="center">
      <table role="presentation" width="600" cellpadding="0" cellspacing="0" class="card" style="width:100%;max-width:600px;background:#ffffff;border-radius:20px;overflow:hidden;box-shadow:0 12px 44px rgba(16,38,58,0.13)">

        <!-- الترويسة: فحمية فاخرة، كتابة متناظرة بلا أيقونة، لمسات شمبانيا -->
        <tr><td class="hero" style="padding:46px 44px 42px;background:${BRAND.charcoal};background:linear-gradient(160deg,${BRAND.charcoal} 0%,${BRAND.charcoalEnd} 100%);text-align:center;border-bottom:2px solid ${BRAND.champagne}">
          <div style="color:${BRAND.champagneSoft};font-size:11px;font-weight:700;letter-spacing:5px;text-transform:uppercase;margin:0 0 14px">${escapeHtml(BRAND.tagline)}</div>
          <div style="color:#ffffff;font-size:23px;font-weight:800;letter-spacing:.4px;line-height:1.35">${escapeHtml(BRAND.appName)}</div>
          <div style="width:46px;height:2px;background:${BRAND.champagne};margin:18px auto 0"></div>
        </td></tr>

        <!-- العنوان -->
        <tr><td class="pad" style="padding:40px 44px 0;text-align:right">
          ${eyebrow}
          <h1 class="h1" style="margin:0;color:${BRAND.ink};font-size:23px;font-weight:800;line-height:1.5;letter-spacing:.2px">${escapeHtml(args.title)}</h1>
          <div style="height:2px;width:40px;background:${accent};margin:18px 0 0"></div>
        </td></tr>

        <!-- الجسم -->
        <tr><td class="pad" style="padding:24px 44px 40px;text-align:right">${args.body}</td></tr>

        <!-- التذييل -->
        <tr><td style="padding:${PAD}"><div style="border-top:1px solid ${BRAND.hair}"></div></td></tr>
        <tr><td class="pad" style="padding:28px 44px 34px;text-align:center">
          <p style="margin:0 0 7px;color:${BRAND.ink};font-size:13px;font-weight:800;letter-spacing:1px">${escapeHtml(BRAND.appName)}</p>
          <p style="margin:0;color:${BRAND.muted};font-size:11.5px;line-height:1.75;letter-spacing:.2px">رسالة تلقائية من التطبيق — لا حاجة للرد عليها مباشرةً</p>
        </td></tr>

      </table>
      <p style="margin:20px 0 0;color:${BRAND.muted};font-size:11px;letter-spacing:.3px">© ${escapeHtml(BRAND.appName)}</p>
    </td></tr>
  </table>
</body></html>`;
}
