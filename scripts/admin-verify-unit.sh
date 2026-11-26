#!/bin/zsh
# تحقق وحدة من إعادة تصميم الإدارة على المحاكي (T0، الخطة 2026-11-26-admin-redesign): بناء ← تثبيت ← تشغيل بالأعلام ←
# لقطات فاتح / داكن / AX3 (+ أفقي للجذور) ← أسطر الفحص (STACK · DRY-RUN · FAIL-STORE · DEBUG-PROBE) من مخرج التطبيق.
#
#   scripts/admin-verify-unit.sh <unit> <screen> [options] [-- <extra launch args>]
#
#   --sim <name|udid>   المحاكي (أو SIM=…). بلا قيمة: أول iPhone مُشغَّل، وإلا أحدث iPhone «Pro» (يشغّله السكربت)
#   --no-build          بلا بناء (آخر .app في مجلد البناء)
#   --no-launch         بلا تثبيت ولا تشغيل: لقطات ما على الشاشة الآن (بعد تنقّل يدوي إلى الصفحة)
#   --role <r>          -tmpAdminRole owner|admin|monitor|supervisor
#   --matrix '<json>'   -tmpRoleMatrix
#   --fail <list>       -tmpFailStores sms,devices@20,…
#   --stack             -tmpStackDepth -tmpStackCheck — رمز الخروج 3 إن كان في الأسطر FAIL
#   --push <name>       يرسل إشعاراً تجريبياً بعد التشغيل (اضغط الشعار لتتبّع المسار): request · join · inbox ·
#                       messages · tree_edit · tree_edit_id · sms_balance_low · sms_suspicious  (REQUEST_ID=<uuid> لطلب حقيقي)
#   --wait <s>          انتظار بعد التشغيل/الإشعار قبل اللقطات (8)
#   --landscape         لقطة أفقية أيضاً (لجذور الأقسام؛ تحتاج إذن «تسهيلات الاستخدام» للطرفية — أفضل جهد)
#   --shutdown          يطفئ المحاكي في الآخر إن كان السكربت هو من شغّله
#   --sign none         بناء بلا توقيع (CODE_SIGNING_ALLOWED=NO) بدل التوقيع المحلي «-» (adhoc، الافتراضي)
#   --out <dir>         مجلد الناتج (/private/tmp/claude-501/verify/<unit>)
#   --dd <dir>          مجلد البناء (/private/tmp/claude-501/dd-verify)
#
# مثال: scripts/admin-verify-unit.sh U16 team-root --role admin --fail sms --stack
# الناتج: <out>/<screen>-light.png · -dark.png · -ax3.png (· -landscape.png) · <screen>-probe.log · app-console.log · build.log
# أول تثبيت على محاكٍ جديد يُظهر طلب إذن الإشعارات فوق الشاشة: أجبه مرة ثم أعد التشغيل.
# تذكير الخطة: لا تفتح «طلبات رمز الدخول» ولا أرقام هواتف كاملة ببيانات حقيقية؛ احذف لقطات الفريق/الرسائل بعد المراجعة.

set -o pipefail
SELF=${0:A}
ROOT=${SELF:h:h}
SCHEME=FamilyTreeV2
SPM=/private/tmp/claude-501/spm

usage() { sed -n '2,26p' "$SELF" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }
[[ $1 == -h || $1 == --help ]] && usage
[[ $# -lt 2 ]] && usage 1
UNIT=$1; SCREEN=${2//[^A-Za-z0-9._-]/-}; shift 2

SIM=${SIM:-}; BUILD=1; LAUNCH=1; WAIT=8; LANDSCAPE=0; SHUTDOWN=0; SIGN=adhoc; STACK=0; PUSH=""
OUT=""; DD=/private/tmp/claude-501/dd-verify
typeset -a FLAGS EXTRA
while [[ $# -gt 0 ]]; do
  case $1 in
    --sim) SIM=$2; shift 2 ;;
    --no-build) BUILD=0; shift ;;
    --no-launch) LAUNCH=0; BUILD=0; shift ;;
    --role) FLAGS+=(-tmpAdminRole "$2"); shift 2 ;;
    --matrix) FLAGS+=(-tmpRoleMatrix "$2"); shift 2 ;;
    --fail) FLAGS+=(-tmpFailStores "$2"); shift 2 ;;
    --stack) FLAGS+=(-tmpStackDepth -tmpStackCheck); STACK=1; shift ;;
    --push) PUSH=$2; shift 2 ;;
    --wait) WAIT=$2; shift 2 ;;
    --landscape) LANDSCAPE=1; shift ;;
    --shutdown) SHUTDOWN=1; shift ;;
    --sign) SIGN=$2; shift 2 ;;
    --out) OUT=$2; shift 2 ;;
    --dd) DD=$2; shift 2 ;;
    --) shift; EXTRA=("$@"); break ;;
    *) echo "unknown option: $1" >&2; usage 1 ;;
  esac
done
OUT=${OUT:-/private/tmp/claude-501/verify/$UNIT}
mkdir -p "$OUT/payloads" || exit 1
# مخرج التطبيق لكل وحدة (يبقى يُكتب ما دام التطبيق يعمل — تلتقطه تشغيلات --no-launch اللاحقة)
CONSOLE="$OUT/app-console.log"
STAMP="$OUT/.launched"

say() { print -r -- "▸ $*"; }
die() { print -r -- "✗ $*" >&2; exit 1; }

# ── المحاكي ───────────────────────────────────────────────────────────────────────────────
PICK=$(xcrun simctl list devices available -j | /usr/bin/python3 -I -c '
import json, re, sys
want = sys.argv[1]
rows = []
for runtime, devices in json.load(sys.stdin)["devices"].items():
    m = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not m:
        continue
    ver = (int(m.group(1)), int(m.group(2)))
    for d in devices:
        rows.append((ver, d["name"], d["udid"], d["state"]))
rows.sort(key=lambda r: r[0], reverse=True)
def out(r):
    print("%s|%s|%s|%d.%d" % (r[2], r[1], r[3], r[0][0], r[0][1])); sys.exit(0)
if want:
    for r in sorted(rows, key=lambda r: r[3] != "Booted"):
        if want in (r[2], r[1]):
            out(r)
    sys.exit(1)
phones = [r for r in rows if r[1].startswith("iPhone")]
for r in phones:
    if r[3] == "Booted":
        out(r)
for r in phones:
    if r[1].endswith(" Pro"):
        out(r)
if phones:
    out(phones[0])
sys.exit(1)
' "$SIM") || die "no available simulator${SIM:+ matching \"$SIM\"} (xcrun simctl list devices available)"
UDID=${PICK%%|*}; REST=${PICK#*|}; SIMNAME=${REST%%|*}; REST=${REST#*|}; STATE=${REST%%|*}; RUNTIME=${REST#*|}
say "simulator: $SIMNAME (iOS $RUNTIME) $UDID [$STATE]"
BOOTED_HERE=0
if [[ $STATE != Booted ]]; then
  [[ $LAUNCH == 0 ]] && die "--no-launch needs a booted simulator"
  xcrun simctl boot "$UDID" || die "boot failed"
  BOOTED_HERE=1
fi
xcrun simctl bootstatus "$UDID" -b >/dev/null || die "simulator did not finish booting"

# ── البناء ────────────────────────────────────────────────────────────────────────────────
APP="$DD/Build/Products/Debug-iphonesimulator/$SCHEME.app"
if [[ $BUILD == 1 ]]; then
  typeset -a SIGNARGS
  if [[ $SIGN == none ]]; then SIGNARGS=(CODE_SIGNING_ALLOWED=NO)
  else SIGNARGS=(CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=); fi
  say "building ($SIGN signing) → $OUT/build.log"
  xcodebuild -project "$ROOT/FamilyTreeV2.xcodeproj" -scheme "$SCHEME" -configuration Debug \
    -destination "id=$UDID" -derivedDataPath "$DD" -clonedSourcePackagesDirPath "$SPM" \
    "${SIGNARGS[@]}" build >"$OUT/build.log" 2>&1
  rc=$?
  grep -E "error:|BUILD (SUCCEEDED|FAILED)" "$OUT/build.log" | tail -20
  [[ $rc == 0 ]] || die "build failed (exit $rc) — $OUT/build.log"
fi
if [[ $LAUNCH == 1 ]]; then
  [[ -d $APP ]] || die "no app at $APP (build first)"
  BUNDLE=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Info.plist") || die "no bundle id"
else
  BUNDLE=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Info.plist" 2>/dev/null || echo Hasan.FamilyTreeV2)
fi

# ── إشعارات تجريبية (.apns لـ xcrun simctl push) ─────────────────────────────────────────────
RID=${REQUEST_ID:-00000000-0000-4000-8000-0000000000a1}
apns() { # <name> <title> <body> <json-extra>
  print -r -- "{\"Simulator Target Bundle\": \"$BUNDLE\", \"aps\": {\"alert\": {\"title\": \"$2\", \"body\": \"$3\"}, \"sound\": \"default\"}, $4}" >"$OUT/payloads/$1.apns"
}
apns request         "طلب جديد"              "تجربة: طلب ينتظر قرارك"             "\"kind\": \"admin_request\", \"request_id\": \"$RID\", \"request_type\": \"deceased_report\""
apns join            "طلب انضمام"            "تجربة: طلب انضمام ينتظر قرارك"      "\"kind\": \"admin_request\", \"request_id\": \"$RID\", \"request_type\": \"join_request\""
apns inbox           "طلبات بانتظارك"         "تجربة: إشعار بلا معرّف طلب"          "\"kind\": \"admin_request\""
apns messages        "رسالة جديدة"            "تجربة: رسالة من عضو"                "\"kind\": \"contact_message\""
apns tree_edit       "تعديل على الشجرة"       "تجربة: طلبات الشجرة بلا معرّف"       "\"kind\": \"tree_edit\""
apns tree_edit_id    "تعديل على الشجرة"       "تجربة: طلب شجرة بعينه"              "\"kind\": \"tree_edit\", \"request_id\": \"$RID\", \"request_type\": \"tree_edit\""
apns sms_balance_low "رصيد رسائل الدخول منخفض" "تجربة: الرصيد تحت حدّ التنبيه"      "\"kind\": \"sms_balance_low\""
apns sms_suspicious  "محاولات دخول مريبة"     "تجربة: طلبات رمز متكررة من رقم"      "\"kind\": \"sms_suspicious\""

# ── التثبيت والتشغيل ──────────────────────────────────────────────────────────────────────
PREV_SIZE=$(xcrun simctl ui "$UDID" content_size 2>/dev/null)
[[ $PREV_SIZE == accessibility-* || -z $PREV_SIZE || $PREV_SIZE == unknown || $PREV_SIZE == unsupported ]] && PREV_SIZE=large
if [[ $LAUNCH == 1 ]]; then
  xcrun simctl ui "$UDID" appearance light
  xcrun simctl ui "$UDID" content_size "$PREV_SIZE"
  say "install $APP"
  xcrun simctl install "$UDID" "$APP" || die "install failed"
  : >"$CONSOLE"
  print -r -- "$UDID $(date '+%Y-%m-%d %H:%M:%S')" >"$STAMP"
  say "launch $BUNDLE ${FLAGS[*]} ${EXTRA[*]}"
  # أسطر الفحص تُلتقط بطريقتين: `simctl launch --console` في الخلفية (يبقى ما دام التطبيق يعمل) وسجل os_log لفئة
  # DebugProbe (`log show` أدناه). `--stdout=<ملف>` لم يلتقط شيئاً على iOS 26.5 (تشغيل T0 الأول)
  xcrun simctl launch --console --terminate-running-process "$UDID" "$BUNDLE" "${FLAGS[@]}" "${EXTRA[@]}" \
    >>"$CONSOLE" 2>&1 </dev/null &!
  sleep "$WAIT"
  grep -q "^$BUNDLE: [0-9]" "$CONSOLE" || say "warning: launch not confirmed in $CONSOLE"
  say "first install on a fresh simulator shows the notification-permission alert: answer it once, then re-run"
fi
if [[ -n $PUSH ]]; then
  [[ -f $OUT/payloads/$PUSH.apns ]] || die "unknown payload \"$PUSH\" (see $OUT/payloads)"
  xcrun simctl push "$UDID" "$BUNDLE" "$OUT/payloads/$PUSH.apns" || die "push failed"
  say "pushed $PUSH — tap the banner to follow its route"
  sleep "$WAIT"
fi

# ── اللقطات ───────────────────────────────────────────────────────────────────────────────
shoot() { xcrun simctl io "$UDID" screenshot --type=png "$OUT/$SCREEN-$1.png" >/dev/null 2>&1 && say "shot $OUT/$SCREEN-$1.png"; }
xcrun simctl ui "$UDID" appearance light; sleep 2; shoot light
xcrun simctl ui "$UDID" appearance dark;  sleep 2; shoot dark
xcrun simctl ui "$UDID" appearance light
xcrun simctl ui "$UDID" content_size accessibility-extra-large; sleep 3; shoot ax3
xcrun simctl ui "$UDID" content_size "$PREV_SIZE"; sleep 1
if [[ $LANDSCAPE == 1 ]]; then
  if osascript -e 'tell application "Simulator" to activate' \
               -e 'tell application "System Events" to key code 124 using {command down}' >/dev/null 2>&1; then
    sleep 3; shoot landscape
    osascript -e 'tell application "System Events" to key code 123 using {command down}' >/dev/null 2>&1
  else
    say "landscape skipped: rotate the Simulator by hand (⌘→), then: $SELF $UNIT $SCREEN-landscape --no-launch --sim $UDID"
  fi
fi

# ── أسطر الفحص ────────────────────────────────────────────────────────────────────────────
PROBE="$OUT/$SCREEN-probe.log"
SINCE=""
[[ -f $STAMP && $(cut -d' ' -f1 "$STAMP") == $UDID ]] && SINCE=$(cut -d' ' -f2- "$STAMP")
{
  [[ -f $CONSOLE ]] && grep -oE "(STACK|DEBUG-PROBE|DRY-RUN|FAIL-STORE) .*" "$CONSOLE"
  [[ -n $SINCE ]] && xcrun simctl spawn "$UDID" log show --style compact --start "$SINCE" \
      --predicate "subsystem == \"$BUNDLE\" AND category == \"DebugProbe\"" 2>/dev/null \
    | grep -oE "(STACK|DEBUG-PROBE|DRY-RUN|FAIL-STORE) .*"
} | awk '!seen[$0]++' >"$PROBE"
if [[ -s $PROBE ]]; then say "probe lines ($PROBE):"; cat "$PROBE"; fi
if [[ $BOOTED_HERE == 1 && $SHUTDOWN == 1 ]]; then xcrun simctl shutdown "$UDID"; say "simulator shut down"; fi
if [[ $STACK == 1 ]] && grep -q "^STACK .* FAIL" "$PROBE" 2>/dev/null; then
  say "STACK FAIL present"; exit 3
fi
exit 0
