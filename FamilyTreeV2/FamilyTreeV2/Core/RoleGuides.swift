import SwiftUI

// MARK: - مجالات الأدوار (تحديث 2026-09-21)
//
// مصدر واحد لتعريف كل دور: مجاله، وكل ما يقدر عليه، وكل ما لا يقدر عليه.
// يُعرض في «الأدوار» بلوحة الإدارة، وفي ورقة «تغيير الدور»، وعند تعيين دور
// لعضو، وكبانر «مجالك» أعلى لوحة الإدارة — حتى يعرف كل مسؤول حدوده بالضبط.

struct RoleGuide: Identifiable {
    var id: String { title }
    let title: String
    let icon: String
    let color: Color
    /// جملة واحدة تعرّف مجال الدور
    let mandate: String
    let can: [String]
    let cannot: [String]

    /// كل الأدوار بالترتيب — المالك ثم المدير ثم المراقب ثم المشرف ثم العضو
    static var all: [RoleGuide] {
        [
            RoleGuide(
                title: L10n.t("المالك", "Owner"),
                icon: "crown.fill",
                color: DS.Color.ownerRole,
                mandate: L10n.t("صاحب النظام — كل الصلاحيات", "System owner — full control"),
                can: [
                    L10n.t("كل ما يقدر عليه المدير", "Everything an admin can do"),
                    L10n.t("منح الأدوار وسحبها", "Assign and remove roles"),
                    L10n.t("إعدادات النظام والأمان", "System and security settings"),
                    L10n.t("إدارة الأجهزة المرتبطة بالحسابات", "Manage linked devices"),
                    L10n.t("الأرقام المحظورة", "Banned phone numbers")
                ],
                cannot: [
                    L10n.t("لا شيء — كل صلاحيات التطبيق متاحة له", "Nothing — has every permission")
                ]
            ),
            RoleGuide(
                title: L10n.t("المدير", "Admin"),
                icon: "shield.lefthalf.filled",
                color: DS.Color.adminRole,
                mandate: L10n.t("إدارة كاملة — الشجرة والمحتوى والأعضاء",
                               "Full management — tree, content and members"),
                can: [
                    L10n.t("اعتماد ورفض كل المحتوى: الأخبار، المكتبة، المشاريع، الديوانيات",
                          "Approve and reject all content: news, library, projects, diwaniyas"),
                    L10n.t("قبول ورفض كل طلبات الشجرة والأعضاء",
                          "Approve and reject all tree and member requests"),
                    L10n.t("تعديل بيانات الأعضاء ومعالجة مشاكل صحة الشجرة",
                          "Edit member data and fix tree health issues"),
                    L10n.t("تسجيل عضو جديد، حذف الأعضاء، تجميد الحسابات",
                          "Register, delete and freeze members"),
                    L10n.t("إرسال الإشعارات للأعضاء", "Send notifications to members"),
                    L10n.t("حذف أي محتوى: أخبار، تعليقات، صور، ديوانيات",
                          "Delete any content: news, comments, photos, diwaniyas"),
                    L10n.t("إخفاء وإظهار عناصر المكتبة والمشاريع",
                          "Hide and show library items and projects"),
                    L10n.t("تصفّح «إعدادات النظام» للقراءة", "Browse system settings (read-only)")
                ],
                cannot: [
                    L10n.t("منح الأدوار أو سحبها — للمالك", "Assign or remove roles — owner only"),
                    L10n.t("تعديل إعدادات النظام والأمان — للمالك",
                          "Change system and security settings — owner only"),
                    L10n.t("إدارة الأجهزة المرتبطة — للمالك", "Manage linked devices — owner only"),
                    L10n.t("الأرقام المحظورة — للمالك", "Banned numbers — owner only"),
                    L10n.t("تغيير دور المالك أو حذفه", "Change or delete the owner")
                ]
            ),
            RoleGuide(
                title: L10n.t("المراقب", "Monitor"),
                icon: "person.2.badge.gearshape.fill",
                color: DS.Color.monitorRole,
                mandate: L10n.t("مجاله: الشجرة والأعضاء", "Scope: the family tree and members"),
                can: [
                    L10n.t("قبول ورفض طلبات الشجرة: الانضمام، الوفاة، إضافة ابن، تعديل الاسم والرقم والميلاد",
                          "Approve and reject tree requests: join, deceased, add child, name/phone/birth edits"),
                    L10n.t("تعديل بيانات الأعضاء", "Edit member data"),
                    L10n.t("معالجة مشاكل صحة الشجرة (بدون أب، بلا اسم، أرقام مكررة)",
                          "Fix tree health issues (no father, no name, duplicate phones)"),
                    L10n.t("رؤية إحصائيات الأعضاء", "View member statistics")
                ],
                cannot: [
                    L10n.t("اعتماد أو رفض الأخبار والمكتبة والمشاريع والديوانيات — للإدارة",
                          "Approve or reject news, library, projects, diwaniyas — admins only"),
                    L10n.t("حذف المحتوى أو إخفاؤه (أخبار، تعليقات، صور) — مجال المشرف",
                          "Delete or hide content (news, comments, photos) — supervisor scope"),
                    L10n.t("التعامل مع البلاغات — مجال المشرف", "Handle reports — supervisor scope"),
                    L10n.t("حذف الأعضاء أو تجميد حساباتهم", "Delete or freeze members"),
                    L10n.t("تسجيل عضو جديد مباشرة", "Register a new member directly"),
                    L10n.t("إرسال الإشعارات", "Send notifications"),
                    L10n.t("منح الأدوار، الإعدادات، الأجهزة، الأرقام المحظورة",
                          "Roles, settings, devices, banned numbers")
                ]
            ),
            RoleGuide(
                title: L10n.t("المشرف", "Supervisor"),
                icon: "text.badge.checkmark",
                color: DS.Color.supervisorRole,
                mandate: L10n.t("مجاله: المحتوى والبلاغات", "Scope: content and reports"),
                can: [
                    L10n.t("متابعة المحتوى المنتظر (الاعتماد للإدارة)",
                          "Follow pending content (approval is for admins)"),
                    L10n.t("التعامل مع البلاغات على المحتوى", "Handle content reports"),
                    L10n.t("حذف المخالف: أخبار، تعليقات، صور الأعضاء",
                          "Delete violations: news, comments, member photos"),
                    L10n.t("نشر أخباره مباشرة بلا مراجعة", "Publish their own news without review")
                ],
                cannot: [
                    L10n.t("اعتماد المحتوى نهائياً (أخبار، مكتبة، مشاريع، ديوانيات) — للإدارة",
                          "Final content approval (news, library, projects, diwaniyas) — admins only"),
                    L10n.t("قبول أو رفض طلبات الشجرة والأعضاء — مجال المراقب",
                          "Approve or reject tree and member requests — monitor scope"),
                    L10n.t("تعديل بيانات الأعضاء", "Edit member data"),
                    L10n.t("حذف الأعضاء أو تجميدهم أو تسجيل عضو جديد",
                          "Delete, freeze or register members"),
                    L10n.t("حذف الديوانيات", "Delete diwaniyas"),
                    L10n.t("إرسال الإشعارات", "Send notifications"),
                    L10n.t("رؤية إحصائيات الأعضاء", "View member statistics"),
                    L10n.t("منح الأدوار، الإعدادات، الأجهزة، الأرقام المحظورة",
                          "Roles, settings, devices, banned numbers")
                ]
            ),
            RoleGuide(
                title: L10n.t("العضو", "Member"),
                icon: "person.fill",
                color: DS.Color.memberRole,
                mandate: L10n.t("مجاله: نفسه ومحتواه", "Scope: themselves and their own content"),
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
                    L10n.t("رؤية الإحصائيات أو سجل النشاط أو الطلبات",
                          "See statistics, activity log or requests")
                ]
            )
        ]
    }

    /// تعريف الدور المطابق لعضو — nil لغير الأدوار المعروفة
    static func forRole(_ role: FamilyMember.UserRole) -> RoleGuide? {
        switch role {
        case .owner:      return all.first { $0.icon == "crown.fill" }
        case .admin:      return all.first { $0.icon == "shield.lefthalf.filled" }
        case .monitor:    return all.first { $0.icon == "person.2.badge.gearshape.fill" }
        case .supervisor: return all.first { $0.icon == "text.badge.checkmark" }
        case .member:     return all.first { $0.icon == "person.fill" }
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
                       roles: [L10n.t("مدير", "Admin"), L10n.t("مراقب", "Monitor")]),
            RoleDomain(title: L10n.t("المحتوى والبلاغات", "Content & Reports"),
                       icon: "doc.text.fill",
                       color: DS.Color.supervisorRole,
                       roles: [L10n.t("مدير", "Admin"), L10n.t("مشرف", "Supervisor")]),
            RoleDomain(title: L10n.t("النظام", "System"),
                       icon: "gearshape.fill",
                       color: DS.Color.ownerRole,
                       roles: [L10n.t("المالك", "Owner")])
        ]
    }
}
