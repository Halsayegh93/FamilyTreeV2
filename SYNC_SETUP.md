# مزامنة iOS → Flutter تلقائياً (PR بالذكاء)

كيف تخلّي أي تعديل على مشروع الآيفون يُنقل تلقائياً لمشروع الأندرويد (Flutter) كـ **Pull Request تراجعه** قبل الدمج.

> ⚠️ **مهم:** هذا **شبه-تلقائي** — ينتج PR للمراجعة، **مو دمج أعمى**. السبب: السويفت والفلتر لغتان مختلفتان، فالنقل اجتهادي ويحتاج عين بشرية قبل الدمج. (أما تعديلات **Supabase** فتلقائية ١٠٠٪ للاثنين لأن القاعدة مشتركة.)

---

## شنو يصير
عند كل دمج لـ `main` في ريبو الآيفون يلمس ملفات `.swift` أو `supabase/migrations/`:
1. يحسب الـ workflow الـ diff لتعديلاتك.
2. يجيب مشروع Flutter، يشغّل **Claude Code** ينقل التعديلات المكافئة لـ `lib/`.
3. يشغّل `flutter analyze` ويصلّح الأخطاء.
4. يفتح **PR** على ريبو Flutter بملخص اللي تنقل والثغرات.

الملف: `.github/workflows/sync-to-flutter.yml` (أُنشئ — راجعه).

---

## اللي لازم تسويه (مرّة وحدة)

### 1) مفتاح Anthropic API
- روح https://console.anthropic.com → API Keys → أنشئ مفتاح.
- في ريبو الآيفون على GitHub: **Settings → Secrets and variables → Actions → New repository secret**
  - الاسم: `ANTHROPIC_API_KEY` — القيمة: المفتاح.

### 2) توكن وصول لريبو Flutter (PAT)
الـ workflow يحتاج يكتب فرع + يفتح PR على ريبو **ثاني** (`FamilyTreeV2-Flutter`)، فالتوكن الافتراضي ما يكفي.
- روح https://github.com/settings/tokens → **Fine-grained token**:
  - Repository access: **Only select repositories** → `Halsayegh93/FamilyTreeV2-Flutter`
  - Permissions: **Contents: Read and write** + **Pull requests: Read and write**
- أضفه كـ secret في ريبو الآيفون باسم: `FLUTTER_REPO_PAT`.

### 3) فعّل Actions
- في ريبو الآيفون: **Settings → Actions → General** → اسمح بتشغيل workflows + اسمح للـ Actions تكتب (Read and write permissions).

### 4) جرّبه
- ادفع الـ workflow + الـ secrets، ثم من تبويب **Actions** شغّل **"Sync iOS changes → Flutter (AI port)"** يدوياً (Run workflow) على آخر commit.
- شيك ريبو Flutter → بتلقى PR جديد "Sync from iOS ...".

---

## التكلفة والمخاطر
- **التكلفة:** كل تشغيل = استدعاءات Claude API (تُحتسب على مفتاحك). تعديل صغير = رخيص؛ تعديل كبير = أغلى. تقدر تحدّها بـ `paths:` (مضبوطة الآن على swift + migrations فقط).
- **الجودة:** النقل اجتهادي — **راجع كل PR** قبل الدمج. لو فيه ثغرة، Claude يحطّ `// TODO(parity)`.
- **ما يُنقل تلقائياً:** منطق Supabase (مشترك أصلاً)، وأي شي خارج `lib/`.

---

## نصيحة لتقليل النقل من الأساس
حط أكثر منطق ممكن في **Supabase** (RLS، functions، triggers، views) بدل كود التطبيق → يصير مشترك للآيفون والأندرويد والويب **تلقائياً وبدون نقل**. الواجهة فقط هي اللي تحتاج مزامنة.

---

## بديل أبسط (بدون CI)
لو ما تبي CI: بعد أي تعديل iOS، شغّل Claude Code محلياً وقل له *"انقل آخر تعديلات الآيفون لمشروع Flutter"* — نفس النتيجة يدوياً عند الطلب.
