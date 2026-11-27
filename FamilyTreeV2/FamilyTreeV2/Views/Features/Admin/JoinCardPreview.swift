#if DEBUG
import SwiftUI

// MARK: - معاينة بطاقة «طلب انضمام» بلا سيرفر (العيّنة ١٨ — للتصوير فقط، نسخ التطوير)
//
// `-uiPreviewJoinCard match|nomatch|female|box` عند التشغيل: البطاقة بحالاتها الثلاث بأسماء وهمية، و`box` = مربّع
// «المطابقات المحتملة» فوق بطاقة المطابق. لا نداءات شبكة ولا كتابة — الأزرار لا تفعل شيئاً.

enum JoinCardPreview {
    static var mode: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-uiPreviewJoinCard"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}

private enum JoinPreviewData {
    static func person(_ name: String, birth: String? = nil, female: Bool = false, pending: Bool = false,
                       phone: String? = nil, platform: String? = nil, minutesAgo: Double? = nil) -> FamilyMember {
        let created = minutesAgo.map { DateParsing.isoString(Date().addingTimeInterval(-$0 * 60)) }
        return FamilyMember(firstName: String(name.split(separator: " ").first ?? ""), fullName: name,
                            familyName: "الصايغ", phoneNumber: phone, birthDate: birth,
                            role: pending ? .pending : .member, status: pending ? .pending : .active,
                            gender: female ? "female" : "male", createdAt: created, registrationPlatform: platform)
    }

    static func entry(_ m: FamilyMember, depth: Int, of n: Int, gap: Int?, endsClean: Bool = false) -> JoinMatchTiers.Entry {
        let parts: [JoinMatchTiers.PartState] = (0..<n).map { $0 < depth ? .match : (endsClean ? .missing : .differ) }
        return JoinMatchTiers.Entry(member: m, depth: depth, parts: parts, endsClean: endsClean, gapYears: gap,
                                    birthYear: JoinMatchTiers.year(m.birthDate), isServer: false)
    }

    // ١) مطابق قوي
    static let yousef = person("يوسف خالد حسن عبدالله الصايغ", birth: "2009-03-14", pending: true,
                               phone: "96599004417", platform: "web", minutesAgo: 62)
    static let m1 = person("يوسف خالد حسن عبدالله الصايغ", birth: "2009-01-01")
    static let m2 = person("يوسف خالد محمد عبدالله الصايغ", birth: "2006-01-01")
    static let m3 = person("يوسف خليل حسن الصايغ", birth: "2003-01-01")
    static let w1 = person("يوسف خالد سعد الصايغ", birth: "1990-01-01")
    static let w2 = person("يوسف خالد ابراهيم الصايغ")
    static var matchTiers: JoinMatchTiers {
        JoinMatchTiers(applicantParts: ["يوسف", "خالد", "حسن", "عبدالله"], applicantYear: "2009",
                       exact: [entry(m1, depth: 4, of: 4, gap: 0)],
                       near: [entry(m2, depth: 3, of: 4, gap: 3, endsClean: true), entry(m3, depth: 3, of: 4, gap: 6)],
                       weak: [entry(w1, depth: 2, of: 4, gap: 19), entry(w2, depth: 2, of: 4, gap: nil)])
    }
    static var matchInfo: JoinCardInfo {
        let t = matchTiers
        return JoinCardInfo(member: yousef, tiers: t, selectedId: m1.id, showsWeak: false, requestAge: "اليوم",
                            chains: [m1.id: ["عبدالله", "حسن", "خالد", "يوسف"], m2.id: ["عبدالله", "محمد", "خالد", "يوسف"],
                                     m3.id: ["حسن", "خليل", "يوسف"], w1.id: ["سعد", "خالد", "يوسف"], w2.id: ["خالد", "يوسف"]],
                            probableFather: nil, female: nil)
    }

    // ٢) لا مطابقة
    static let abdulrahman = person("عبدالرحمن فهد ناصر الصايغ", birth: "1988-06-02", pending: true,
                                    phone: "96566002093", platform: "ios", minutesAgo: 60 * 26)
    static var noMatchInfo: JoinCardInfo {
        JoinCardInfo(member: abdulrahman, tiers: .empty, selectedId: nil, showsWeak: false, requestAge: "أمس",
                     chains: [:], probableFather: person("فهد ناصر الصايغ", birth: "1960-01-01"), female: nil)
    }

    // ٣) أنثى
    static let noura = person("نورة حسن صلاح عبدالحميد الصايغ", birth: "2001-09-20", female: true, pending: true,
                              phone: "96599002623", platform: "android", minutesAgo: 180)
    static var femaleInfo: JoinCardInfo {
        JoinCardInfo(member: noura, tiers: .empty, selectedId: nil, showsWeak: false, requestAge: "اليوم",
                     chains: [:], probableFather: nil,
                     female: JoinFemaleSteps(father: person("حسن صلاح عبدالحميد الصايغ"),
                                             daughters: ["مريم", "نورة", "سارة"], herIndex: 1, herTaken: false, name: "نورة"))
    }
}

/// مربّعات «الوارد» الجديدة (R2) بأسماء وهمية: `-uiPreviewJoinCard joinbox|joinbox-link|joinbox-ask`
private enum JoinBoxPreviewData {
    static let saud = FamilyMember(firstName: "سعود", fullName: "سعود محمد الصايغ", gender: "male")
    static let khalid = FamilyMember(firstName: "خالد", fullName: "خالد سعود محمد الصايغ", fatherId: saud.id, gender: "male")
    static let khalid2 = FamilyMember(firstName: "خالد", fullName: "خالد سعود علي الصايغ", fatherId: saud.id, gender: "male")
    static let applicant = FamilyMember(firstName: "عبدالله", fullName: "عبدالله خالد سعود محمد",
                                        familyName: "المحمدعلي", birthDate: "1999-04-22", role: .pending, status: .pending,
                                        gender: "male", createdAt: DateParsing.isoString(Date().addingTimeInterval(-3600)))
    static let c1 = FamilyMember(firstName: "عبدالله", fullName: "عبدالله خالد سعود محمد الصايغ",
                                 birthDate: "1999-01-01", fatherId: khalid.id, gender: "male")
    static let c2 = FamilyMember(firstName: "عبدالله", fullName: "عبدالله خالد سعود علي الصايغ",
                                 birthDate: "1987-01-01", fatherId: khalid2.id, gender: "male")
}

struct JoinCardPreviewScreen: View {
    let mode: String

    private var info: JoinCardInfo {
        switch mode {
        case "nomatch": return JoinPreviewData.noMatchInfo
        case "female": return JoinPreviewData.femaleInfo
        default: return JoinPreviewData.matchInfo
        }
    }

    var body: some View {
        if mode.hasPrefix("joinbox") {
            ZStack {
                DS.Hub.background.ignoresSafeArea()
                DSCenterPanel(onBackgroundTap: nil, hugsContent: true) {
                    AdminJoinBox(subject: .join(JoinBoxPreviewData.applicant, outside: false),
                                 suggestedMen: [JoinBoxPreviewData.c1, JoinBoxPreviewData.c2],
                                 preselected: JoinBoxPreviewData.c1.id, requestAge: "قبل ساعة",
                                 onReject: { _ in }, onDetails: {}, onDone: {}, onClose: {},
                                 knownPeople: [JoinBoxPreviewData.saud, JoinBoxPreviewData.khalid, JoinBoxPreviewData.khalid2],
                                 initialStep: mode == "joinbox-link" ? .link : mode == "joinbox-ask" ? .askMissing : .applicant)
                }
            }
            .dsSection(.admin)
        } else {
            legacy
        }
    }

    private var legacy: some View {
        ZStack {
            DS.Hub.background.ignoresSafeArea()
            ScrollView {
                card(info)
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.top, DS.Spacing.xl)
            }
            if mode == "box" {
                Color.black.opacity(DSCenterPanelDim.standard).ignoresSafeArea()
                JoinMatchesBox(info: info, onPick: { _ in }, onPickFromTree: {}, onClose: {})
                    .padding(DS.Spacing.lg)
            }
        }
        .dsSection(.admin)
    }

    private func card(_ info: JoinCardInfo) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            JoinRequestCard(info: info, avatar: AnyView(avatar(info)), onSelect: { _ in }, onToggleWeak: {},
                            onOpenMatches: {})
            DSDecisionRow(items: [
                DSDecisionItem(id: "approve", title: info.approveLabel, kind: .primary, tint: DS.Color.success, action: {}),
                DSDecisionItem(id: "details", title: L10n.t("التفاصيل", "Details"), action: {}),
                DSDecisionItem(id: "reject", title: L10n.t("رفض", "Reject"), icon: "xmark", kind: .destructive,
                               tint: DS.Color.reject, soft: true, action: {}),
            ], size: .compact)
        }
        .padding(DS.Spacing.md)
        .dsCard(padding: nil, radius: DS.Hub.tileRadius)
    }

    private func avatar(_ info: JoinCardInfo) -> some View {
        let ring = info.member.isFemale ? DS.Color.female : (info.pick != nil ? DS.Color.success : DS.Color.warning)
        return Text(String(info.firstName.prefix(1)))
            .dsFont(.headline)
            .foregroundColor(AppSection.admin.ink)
            .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
            .background(Circle().fill(AppSection.admin.ink.opacity(DS.Opacity.tintFillSoft)))
            .overlay(Circle().strokeBorder(ring.dsReadableGlyph, lineWidth: DS.Border.widthBold))
    }
}
#endif
