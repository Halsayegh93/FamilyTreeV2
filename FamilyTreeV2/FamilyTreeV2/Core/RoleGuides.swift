import SwiftUI

// MARK: - مجالات الأدوار (تحديث 2026-09-21)
//
// مصدر واحد لتعريف كل دور: مجاله، وكل ما يقدر عليه، وكل ما لا يقدر عليه.
// يُعرض في «صلاحيات الأدوار» بلوحة الإدارة، وفي ورقة «تغيير الدور»، وعند تعيين دور
// لعضو، وفي «صلاحياتي» على «اليوم» — حتى يعرف كل مسؤول حدوده بالضبط.
// إعادة التصميم ٢٠٢٦-١١-٢٦ (U19): «المؤشرات» صار «الإحصاءات»، وسطر «حالة النظام» حُذف — الحالة كلمات على مربّعي
// «الفريق والأمان» و«التطبيق» (المالك)، و«مجدول اليوم N» على مربّع «المناسبات» (المدير).
// تحديث ٢٠٢٦-١١-٠٧ (مقترح «أدوار الإدارة» بموافقة المالك): كل دور يشوف مجاله كامل وما بعده ما يظهر له. ما يظهر
// لكل دور من الأقسام والبطاقات جدول على السيرفر (`AdminRoleMatrix` ← `app_config.admin_role_matrix`) — هذه النصوص
// تصف افتراضيه؛ إن غيّره المالك على السيرفر حدّث النصوص هنا.

struct RoleGuide: Identifiable {
    var id: String { title }
    let title: String
    let icon: String
    let color: Color
    /// جملة واحدة تعرّف مجال الدور — بضمير الغائب («مجاله: …») لصفحات «الأدوار» وورقة «تغيير الدور»
    let mandate: String
    /// الجملة نفسها لصاحب الدور («مجالك: …») — صفّ «صلاحياتي» على «اليوم» وصفحته. nil = `mandate` (جملة بلا ضمير)
    var ownMandate: String? = nil
    let can: [String]
    let cannot: [String]

    /// كل الأدوار بالترتيب — المالك ثم المدير ثم المراقب ثم المشرف ثم العضو
    static var all: [RoleGuide] {
        [
            RoleGuide(
                title: L10n.t("المالك", "Owner"),
                icon: "crown.fill",
                color: DS.Color.ownerRole,
                mandate: L10n.t("جميع الصلاحيات، والمالكان متساويان فيها", "Everything — both owners alike"),
                can: [
                    L10n.t("جميع صلاحيات المدير", "Everything an admin can do"),
                    L10n.t("الأقسام الستة كاملة، وحالة النظام على مربّعي «الفريق والأمان» و«التطبيق»",
                          "All six sections, and system status on the Team & security and App tiles"),
                    L10n.t("قسم «التطبيق»: كل إعدادات التطبيق والتشغيل", "The App section: every app and operations setting"),
                    L10n.t("قسم «الفريق والأمان»: فريق الإدارة، ورسائل الدخول ومحاولاته، والأجهزة، والتسجيل والمنع",
                          "The Team & security section: the admin team, sign-in messages and attempts, devices, sign-up and blocking"),
                    L10n.t("منح الأدوار وسحبها", "Assign and remove roles"),
                    L10n.t("إدارة الأجهزة المرتبطة بالحسابات", "Manage linked devices"),
                    L10n.t("منع الأرقام من التسجيل", "Block numbers from signing up")
                ],
                cannot: [
                    L10n.t("تغيير دور المالك الثاني أو حذفه من التطبيق", "Change the other owner's role or delete them in the app")
                ]
            ),
            RoleGuide(
                title: L10n.t("المدير", "Admin"),
                icon: "shield.lefthalf.filled",
                color: DS.Color.adminRole,
                mandate: L10n.t("جميع الصلاحيات عدا النظام", "Everything except the system"),
                can: [
                    L10n.t("اعتماد ورفض كل المحتوى: الأخبار، المكتبة، المشاريع، الديوانيات",
                          "Approve and reject all content: news, library, projects, diwaniyas"),
                    L10n.t("قبول ورفض كل طلبات الشجرة والأعضاء",
                          "Approve and reject all tree and member requests"),
                    L10n.t("تعديل بيانات الأعضاء ومعالجة مشاكل صحة الشجرة",
                          "Edit member data and fix tree health issues"),
                    L10n.t("تسجيل عضو جديد، حذف الأعضاء، إيقاف الحسابات",
                          "Register, delete and freeze members"),
                    L10n.t("إرسال الإشعارات للأعضاء", "Send notifications to members"),
                    L10n.t("حذف أي محتوى: أخبار، تعليقات، صور، ديوانيات",
                          "Delete any content: news, comments, photos, diwaniyas"),
                    L10n.t("إخفاء وإظهار عناصر المكتبة والمشاريع",
                          "Hide and show library items and projects"),
                    L10n.t("قراءة رسائل الأعضاء «تواصل مع الإدارة» والرد عليها", "Read and answer members' Contact admin messages"),
                    L10n.t("رؤية «الإحصاءات»: أرقام العائلة والموافقات",
                          "View Statistics: family numbers and approvals"),
                    L10n.t("رؤية «مجدول اليوم» على مربّع «المناسبات»",
                          "See “Scheduled today” on the Occasions tile"),
                    L10n.t("الاطلاع على «الفريق والأمان»: فريق الإدارة و«الاستخدام»",
                          "View Team & security: the admin team and Usage"),
                    L10n.t("الاطلاع على «إعدادات مسار الموافقات»", "View the approval path settings")
                ],
                cannot: [
                    L10n.t("قسم «التطبيق» (إعدادات التطبيق والتشغيل) — للمالك، ولا حتى للاطلاع",
                          "The App section (app and operations settings) — owner only, not even to view"),
                    L10n.t("رسائل الدخول ومحاولاته، والأجهزة، والتسجيل والمنع، وحالة النظام — للمالك",
                          "Sign-in messages and attempts, devices, sign-up and blocking, and system status — owner only"),
                    L10n.t("تعديل إعدادات مسار الموافقات — للمالك", "Change the approval path settings — owner only"),
                    L10n.t("منح الأدوار أو سحبها — للمالك", "Assign or remove roles — owner only"),
                    L10n.t("تغيير دور المالك أو حذفه", "Change or delete the owner")
                ]
            ),
            RoleGuide(
                title: L10n.t("المراقب", "Monitor"),
                icon: "person.2.badge.gearshape.fill",
                color: DS.Color.monitorRole,
                mandate: L10n.t("مجاله: الشجرة والأعضاء", "Scope: the family tree and members"),
                ownMandate: L10n.t("مجالك: الشجرة والأعضاء", "Your scope: the family tree and members"),
                can: [
                    L10n.t("قبول ورفض طلبات الشجرة: الانضمام، الوفاة، إضافة ابن، تعديل الاسم والرقم والميلاد",
                          "Approve and reject tree requests: join, deceased, add child, name/phone/birth edits"),
                    L10n.t("تعديل بيانات الأعضاء", "Edit member data"),
                    L10n.t("معالجة مشاكل صحة الشجرة (بدون أب، بلا اسم، أرقام مكررة)",
                          "Fix tree health issues (no father, no name, duplicate phones)"),
                    L10n.t("الصور المقترحة لملفات الأعضاء", "Suggested photos for member profiles"),
                    L10n.t("استكمال تواريخ الوفاة", "Complete death dates"),
                    L10n.t("رؤية أرقام العائلة في «اليوم» و«الإحصاءات»",
                          "See the family numbers on Today and in Statistics"),
                    L10n.t("الاطلاع على «المناسبات»: الذكرى والوفيات التي تاريخها غير مكتمل",
                          "View Occasions: memorials and deaths with incomplete dates")
                ],
                cannot: [
                    L10n.t("اعتماد أو رفض الأخبار والمكتبة والمشاريع والديوانيات — للإدارة",
                          "Approve or reject news, library, projects, diwaniyas — admins only"),
                    L10n.t("حذف المحتوى أو إخفاؤه (أخبار، تعليقات، صور) — مجال المشرف",
                          "Delete or hide content (news, comments, photos) — supervisor scope"),
                    L10n.t("التعامل مع البلاغات — مجال المشرف", "Handle reports — supervisor scope"),
                    L10n.t("حذف الأعضاء أو إيقاف حساباتهم", "Delete members or suspend their accounts"),
                    L10n.t("تسجيل عضو جديد مباشرة", "Register a new member directly"),
                    L10n.t("إرسال الإشعارات أو تصميم بطاقات التهنئة والتعزية", "Send notifications or design greeting and condolence cards"),
                    L10n.t("قراءة رسائل الأعضاء الخاصة — للمالك والمدير", "Read members' private messages — owner and admins"),
                    L10n.t("«الاستخدام» و«الموافقات» — للمالك والمدير",
                          "Usage and Approvals — owner and admins"),
                    L10n.t("منح الأدوار، الإعدادات، الأجهزة، منع الأرقام",
                          "Roles, settings, devices, blocked numbers")
                ]
            ),
            RoleGuide(
                title: L10n.t("المشرف", "Supervisor"),
                icon: "text.badge.checkmark",
                color: DS.Color.supervisorRole,
                mandate: L10n.t("مجاله: المحتوى والبلاغات", "Scope: content and reports"),
                ownMandate: L10n.t("مجالك: المحتوى والبلاغات", "Your scope: content and reports"),
                can: [
                    L10n.t("متابعة المحتوى المنتظر (الاعتماد للإدارة)",
                          "Follow pending content (approval is for admins)"),
                    L10n.t("التعامل مع البلاغات على المحتوى", "Handle content reports"),
                    L10n.t("حذف المخالف: أخبار، تعليقات، صور الأعضاء",
                          "Delete violations: news, comments, member photos"),
                    L10n.t("تصميم بطاقات التهنئة والتعزية، ورؤية الذكرى في «المناسبات»",
                          "Design greeting and condolence cards, and see memorials in Occasions"),
                    L10n.t("نشر أخباره مباشرة بلا مراجعة", "Publish their own news without review")
                ],
                cannot: [
                    L10n.t("اعتماد المحتوى نهائياً (أخبار، مكتبة، مشاريع، ديوانيات) — للإدارة",
                          "Final content approval (news, library, projects, diwaniyas) — admins only"),
                    L10n.t("قبول أو رفض طلبات الشجرة والأعضاء — مجال المراقب",
                          "Approve or reject tree and member requests — monitor scope"),
                    L10n.t("تعديل بيانات الأعضاء", "Edit member data"),
                    L10n.t("حذف الأعضاء أو إيقاف حساباتهم أو تسجيل عضو جديد",
                          "Delete, freeze or register members"),
                    L10n.t("حذف الديوانيات", "Delete diwaniyas"),
                    L10n.t("إرسال الإشعارات", "Send notifications"),
                    L10n.t("رؤية الأعضاء أو إحصاءاتهم، والصور المقترحة — مجال المراقب",
                          "See members or their statistics, or suggested photos — monitor scope"),
                    L10n.t("قراءة رسائل الأعضاء الخاصة — للمالك والمدير", "Read members' private messages — owner and admins"),
                    L10n.t("منح الأدوار، الإعدادات، الأجهزة، منع الأرقام",
                          "Roles, settings, devices, blocked numbers")
                ]
            ),
            RoleGuide(
                title: L10n.t("العضو", "Member"),
                icon: "person.fill",
                color: DS.Color.memberRole,
                mandate: L10n.t("مجاله: نفسه ومحتواه", "Scope: themselves and their own content"),
                ownMandate: L10n.t("مجالك: نفسك ومحتواك", "Your scope: yourself and your own content"),
                can: [
                    L10n.t("إضافة خبر أو عنصر مكتبة أو مشروع أو ديوانية — تنتظر موافقة الإدارة",
                          "Add news, library items, projects or diwaniyas — pending admin approval"),
                    L10n.t("التعليق والإعجاب والتصويت في الاستطلاعات",
                          "Comment, like and vote in polls"),
                    L10n.t("الإبلاغ عن محتوى غيره، وحذف محتواه هو",
                          "Report others' content, and delete their own"),
                    L10n.t("تعديل ملفه الشخصي (٣ مرات ثم بموافقة الإدارة)",
                          "Edit their profile (3 times, then needs approval)"),
                    L10n.t("طلب إضافة ابن أو تعديل بيانات في الشجرة",
                          "Request adding a child or editing tree data"),
                    L10n.t("مراسلة الإدارة من «التواصل»", "Message the admins from Contact")
                ],
                cannot: [
                    L10n.t("دخول لوحة الإدارة", "Access the admin panel"),
                    L10n.t("نشر أي شيء بدون موافقة الإدارة", "Publish anything without admin approval"),
                    L10n.t("تعديل بيانات غيره أو حذف محتوى غيره",
                          "Edit others' data or delete their content"),
                    L10n.t("رؤية أرقام الأعضاء الذين أخفوا أرقامهم",
                          "See phone numbers members chose to hide"),
                    L10n.t("رؤية الإحصاءات أو إشعارات الإدارة أو الطلبات",
                          "See statistics, admin notifications or requests")
                ]
            )
        ]
    }

    /// مجال الدور مخاطَباً به صاحبه («مجالك: المحتوى والبلاغات») — «صلاحياتي»
    var mandateForSelf: String { ownMandate ?? mandate }

    /// تعريف الدور المطابق لعضو — nil لغير الأدوار المعروفة
    /// (بالترتيب في `all` لا بالأيقونة — تغيير أيقونة لا يكسر المطابقة)
    static func forRole(_ role: FamilyMember.UserRole) -> RoleGuide? {
        let list = all
        switch role {
        case .owner:      return list[0]
        case .admin:      return list[1]
        case .monitor:    return list[2]
        case .supervisor: return list[3]
        case .member:     return list[4]
        case .pending:    return nil
        }
    }
}

/// خريطة المجالات: مين يشتغل وين — بلمحة واحدة
struct RoleDomain {
    let title: String
    let icon: String
    let color: Color
    let roles: [String]

    static var all: [RoleDomain] {
        [
            RoleDomain(title: L10n.t("الشجرة والأعضاء", "Tree & Members"),
                       icon: "point.3.filled.connected.trianglepath.dotted",
                       color: DS.Color.monitorRole,
                       roles: [L10n.t("المالك", "Owner"), L10n.t("مدير", "Admin"), L10n.t("مراقب", "Monitor")]),
            RoleDomain(title: L10n.t("المحتوى والبلاغات", "Content & Reports"),
                       icon: "doc.text.fill",
                       color: DS.Color.supervisorRole,
                       roles: [L10n.t("المالك", "Owner"), L10n.t("مدير", "Admin"), L10n.t("مشرف", "Supervisor")]),
            RoleDomain(title: L10n.t("النظام", "System"),
                       icon: "gearshape.fill",
                       color: DS.Color.ownerRole,
                       roles: [L10n.t("المالك", "Owner")])
        ]
    }
}
