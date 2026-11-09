import SwiftUI
import Supabase

// MARK: - «عائلتي في شجرة النساء» في «حسابي» عند البنت (طلب المالك ٢٠٢٦-١١-٠٩)
//
// كل شي اختياري: الأم (من زوجات أبيها أو اسم جديد)، والزوج (من العائلة أو من خارجها) وظهوره جنبها في الشجرة،
// والأبناء (الاسم الأول ويُكمَّل باسم الزوج تلقائياً). الحفظ عبر دوال السيرفر `women_family_*` — قبل تطبيقها
// يظهر «تعذّر الحفظ» بلا أي كتابة.

enum DaughterFamilyAPI {
    /// التعديل متى ما وصلت دوال السيرفر (`20261109200000_daughter_family_visibility`) — قبلها للعرض فقط،
    /// ونسخة التطوير تعرضه دائماً للعيّنات
    static var enabled: Bool {
        #if DEBUG
        return true
        #else
        return WomenStore.visibilitySupported
        #endif
    }
    /// رسالة السيرفر العربية كما هي (يجب إضافة الزوج أولاً…) أو رسالة عامة
    struct Failure: LocalizedError {
        var message: String?
        var errorDescription: String? {
            message ?? L10n.t("تعذّر الحفظ، يرجى المحاولة مرة أخرى لاحقاً.", "Couldn't save right now — try again later.")
        }
    }
    /// نتيجة الإضافة: نُفّذت الحين، أو صارت طلباً بانتظار موافقة الإدارة
    enum Outcome { case done, requested }

    /// ظهورها هي · زوجها جنبها · عيالها تحتها — nil = بلا تغيير
    static func setVisibility(me: Bool? = nil, spouse: Bool? = nil, children: Bool? = nil) async throws {
        var p: [String: AnyJSON] = [:]
        p["p_self"] = me.map { .bool($0) } ?? .null
        p["p_spouse"] = spouse.map { .bool($0) } ?? .null
        p["p_children"] = children.map { .bool($0) } ?? .null
        _ = try await call("women_family_set_visibility", p)
    }

    static func setChildVisible(_ id: UUID, _ visible: Bool) async throws {
        _ = try await call("women_family_set_child_visible", ["p_child_id": .string(id.uuidString), "p_visible": .bool(visible)])
    }

    static func reorderChildren(_ ids: [UUID]) async throws {
        _ = try await call("women_family_reorder_children", ["p_ids": .array(ids.map { .string($0.uuidString) })])
    }

    static func setHusband(familyId: UUID?, name: String, deceased: Bool, visible: Bool) async throws -> Outcome {
        var p: [String: AnyJSON] = ["p_name": .string(name), "p_deceased": .bool(deceased), "p_visible": .bool(visible)]
        p["p_family_id"] = familyId.map { .string($0.uuidString) } ?? .null
        return try await call("women_family_set_husband", p) ? .done : .requested
    }

    /// الأم: من زوجات أبيها (`set_self_mother` — مباشر) أو اسم جديد (`add_self_mother` — قد يصير طلباً)
    static func setMother(existingId: UUID?, name: String) async throws -> Outcome {
        if let existingId {
            _ = try await call("set_self_mother", ["p_mother_id": .string(existingId.uuidString)])
            return .done
        }
        return try await call("add_self_mother", ["p_name": .string(name)]) ? .done : .requested
    }

    static func addChild(firstName: String, female: Bool, birth: Date?, deceased: Bool) async throws -> Outcome {
        var p: [String: AnyJSON] = ["p_first_name": .string(firstName), "p_female": .bool(female),
                                    "p_deceased": .bool(deceased)]
        p["p_birth"] = birth.map { .string(DaughterFamilyAPI.day.string(from: $0)) } ?? .null
        return try await call("women_family_add_child", p) ? .done : .requested
    }

    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// يرجّع true إذا رجعت الدالة قيمة (نُفّذت)، و false إذا رجعت null (صارت طلباً)
    @discardableResult
    private static func call(_ fn: String, _ params: [String: AnyJSON]) async throws -> Bool {
        do {
            let res = try await SupabaseConfig.client.rpc(fn, params: params).execute()
            let body = String(data: res.data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return body != "null"
        } catch {
            Log.warning("[DaughterFamily] \(fn): \(error.localizedDescription)")
            let msg = (error as? PostgrestError)?.message
            let arabic = msg.flatMap { m in m.unicodeScalars.contains { (0x0600...0x06FF).contains($0.value) } ? m : nil }
            throw Failure(message: arabic)
        }
    }
}

/// محتوى البطاقة: الأب · الأم · الزوج (ظاهر/مخفي) · الأبناء · إضافة — كل صفّ «إضافة» اختياري
struct DaughterFamilyContent: View {
    let node: FamilyMember
    let rows: [FamilyMember]
    /// البنت نفسها (تعدّل) — غير ذلك للعرض فقط
    var editable: Bool = true
    var onOpen: (FamilyMember) -> Void = { _ in }
    var onChanged: () -> Void = {}

    @EnvironmentObject private var memberVM: MemberViewModel
    @State private var husbandVisible: Bool
    @State private var box: Box?
    @State private var errorText: String?

    enum Box: Identifiable { case mother, husband, child; var id: Self { self } }

    init(node: FamilyMember, rows: [FamilyMember], editable: Bool = true,
         onOpen: @escaping (FamilyMember) -> Void = { _ in }, onChanged: @escaping () -> Void = {}) {
        self.node = node
        self.rows = rows
        self.editable = editable
        self.onOpen = onOpen
        self.onChanged = onChanged
        // الأصل: مخفي — إلا الزوج من خارج العائلة الظاهر اليوم (مسعود عند وفيقة)
        let outside = node.husbandId.map { WomenStore.outsideFamilyIds.contains($0) } ?? false
        _husbandVisible = State(initialValue: outside)
    }

    private var byId: [UUID: FamilyMember] { Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }
    private var fatherName: String? {
        node.fatherId.flatMap { memberVM.member(byId: $0)?.displayFullName ?? byId[$0]?.fullName }
    }
    private var mother: FamilyMember? { node.motherId.flatMap { byId[$0] } }
    private var husband: FamilyMember? { node.husbandId.flatMap { byId[$0] } }
    private var husbandProfile: FamilyMember? { node.husbandId.flatMap { memberVM.member(byId: $0) } }
    private var husbandOutside: Bool { node.husbandId.map { WomenStore.outsideFamilyIds.contains($0) } ?? false }
    private var children: [FamilyMember] {
        rows.filter { $0.id != node.id && $0.motherId == node.id }.sorted { $0.sortOrder < $1.sortOrder }
    }
    private func name(_ m: FamilyMember) -> String { m.fullName.isEmpty ? m.firstName : m.fullName }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            if let fatherName, !fatherName.isEmpty {
                row(icon: "person.fill", tint: DS.Color.male, title: L10n.t("الأب", "Father"), value: fatherName)
            }
            // الأم
            if let mother {
                row(icon: "figure.stand.dress", tint: DS.Color.female, title: L10n.t("الأم", "Mother"), value: name(mother))
            } else if editable {
                addRow(icon: "figure.stand.dress", tint: DS.Color.female, title: L10n.t("الأم", "Mother")) { box = .mother }
            }
            // الزوج + ظهوره
            if let husband {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Button { if let p = husbandProfile { onOpen(p) } } label: {
                        DSRow(icon: "heart.fill", tint: DS.Color.male, title: L10n.t("الزوج", "Husband"),
                              subtitle: husbandProfile?.displayFullName ?? name(husband)) {
                            if husbandProfile != nil { DSChevron() }
                        }
                    }
                    .buttonStyle(DSPressStyle())
                    .disabled(husbandProfile == nil)
                    if editable {
                        DSSegmentedSwitch(options: [
                            DSSegmentOption(id: true, title: L10n.t("ظاهر في الشجرة", "Shown in the tree"), icon: "eye.fill"),
                            DSSegmentOption(id: false, title: L10n.t("مخفي", "Hidden"), icon: "eye.slash.fill")
                        ], selection: Binding(get: { husbandVisible }, set: { setVisible($0) }), size: .compact)
                    }
                }
            } else if editable {
                addRow(icon: "heart.fill", tint: DS.Color.male, title: L10n.t("الزوج", "Husband")) { box = .husband }
            }
            // الأبناء
            ForEach(children, id: \.id) { c in
                row(icon: c.isFemale ? "figure.stand.dress" : "person.fill",
                    tint: c.isFemale ? DS.Color.female : DS.Color.male,
                    title: c.isFemale ? L10n.t("ابنة", "Daughter") : L10n.t("ابن", "Son"), value: name(c))
            }
            if editable {
                if husband != nil && !husbandOutside {
                    // زوجها من العائلة: أبناؤها في شجرة العائلة تحت أبيهم
                    DSNoteCard(L10n.t("الأبناء في شجرة العائلة تحت أبيهم.", "Your children are in the family tree under their father."),
                               icon: "info.circle")
                } else {
                    Button { box = .child } label: {
                        Label(L10n.t("إضافة ابن أو ابنة", "Add a son or daughter"), systemImage: "plus")
                            .dsFont(.button)
                            .frame(maxWidth: .infinity, minHeight: DS.Icon.tapTarget)
                            .foregroundColor(DS.Color.palm)
                            .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                                .strokeBorder(DS.Color.palm.opacity(DS.Opacity.tintStroke),
                                              style: StrokeStyle(lineWidth: DS.Border.width, dash: [5, 4])))
                    }
                    .buttonStyle(DSPressStyle())
                }
                Text(L10n.t("جميع الخيارات اختيارية، ويظهر الأبناء في شجرة النساء عند ظهور الزوج.",
                            "All optional — your children show under you in the women tree while your husband is shown."))
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let errorText {
                DSNoteCard(errorText, icon: "exclamationmark.triangle.fill", tint: DS.Color.error)
            }
        }
        .dsCenterBox(item: $box) { b in
            switch b {
            case .mother: DaughterMotherBox(node: node, rows: rows, onDone: done)
            case .husband: DaughterHusbandBox(onDone: done)
            case .child: DaughterChildBox(husbandName: husband.map { husbandProfile?.fullName ?? name($0) }, onDone: done)
            }
        }
    }

    private func done() {
        box = nil
        onChanged()
    }

    private func setVisible(_ v: Bool) {
        let old = husbandVisible
        husbandVisible = v
        errorText = nil
        Task {
            do { try await DaughterFamilyAPI.setVisibility(spouse: v); onChanged() } catch {
                husbandVisible = old
                errorText = error.localizedDescription
            }
        }
    }

    private func row(icon: String, tint: Color, title: String, value: String) -> some View {
        DSRow(icon: icon, tint: tint, title: title, subtitle: value) { EmptyView() }
    }

    private func addRow(icon: String, tint: Color, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            DSRow(icon: icon, tint: tint, title: title, subtitle: L10n.t("لم يُضف", "Not added")) {
                Label(L10n.t("إضافة", "Add"), systemImage: "plus")
                    .dsFont(.chip)
                    .foregroundColor(DS.Color.palm)
            }
        }
        .buttonStyle(DSPressStyle())
    }
}

// MARK: - مربّعات الإضافة

/// الزوج: من العائلة (اختيار من الشجرة) أو من خارجها (الاسم الكامل)، حالته، وظهوره جنبها
struct DaughterHusbandBox: View {
    @State private var sentText: String?
    var onDone: () -> Void
    @EnvironmentObject private var memberVM: MemberViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var fromFamily = false
    @State private var name = ""
    @State private var picked: FamilyMember?
    @State private var search = ""
    @State private var deceased = false
    @State private var visible = false
    @State private var busy = false
    @State private var errorText: String?

    private var canSave: Bool { fromFamily ? picked != nil : name.split(separator: " ").count >= 2 }

    var body: some View {
        DSComposer(title: L10n.t("إضافة الزوج", "Add my husband"),
                   subtitle: L10n.t("اختياري", "Optional"),
                   icon: "heart.fill", tint: DS.Color.male,
                   actionTitle: L10n.t("حفظ", "Save"),
                   canSubmit: canSave && !busy, isBusy: busy,
                   onSubmit: save, onCancel: { dismiss() }) {
            DSComposerSection(title: L10n.t("الزوج من:", "Where is your husband from?"), icon: "person.2.fill",
                              tint: DS.Color.male, index: 0) {
                DSSegmentedSwitch(options: [
                    DSSegmentOption(id: true, title: L10n.t("من العائلة", "Family"), icon: "tree.fill"),
                    DSSegmentOption(id: false, title: L10n.t("من خارج العائلة", "Outside"), icon: "person.fill")
                ], selection: $fromFamily, size: .regular)
                if fromFamily {
                    if let picked {
                        DSRow(icon: "person.fill", tint: DS.Color.male, title: L10n.t("الزوج", "Your husband"),
                              subtitle: picked.displayFullName) {
                            Button(L10n.t("تغيير", "Change")) { self.picked = nil }.dsFont(.chip)
                        }
                    } else {
                        DSComposerField(icon: "magnifyingglass", label: L10n.t("البحث بالاسم", "Search his name"),
                                        placeholder: L10n.t("الاسم", "Name"), text: $search, tint: DS.Color.male)
                        ForEach(matches.prefix(5), id: \.id) { m in
                            Button { picked = m } label: {
                                DSRow(icon: "person.fill", tint: DS.Color.male, title: m.displayFullName) { DSChevron() }
                            }
                            .buttonStyle(DSPressStyle())
                        }
                    }
                } else {
                    DSComposerField(icon: "person.fill", label: L10n.t("اسم الزوج الكامل", "Husband's full name"),
                                    placeholder: L10n.t("مثال: يوسف علي العطار", "e.g. Yousef Ali Al-Attar"),
                                    text: $name, tint: DS.Color.male, required: true)
                }
            }
            if !fromFamily {
                DSComposerSection(title: L10n.t("الحالة", "Status"), icon: "heart.text.square", tint: DS.Color.male, index: 1) {
                    DSSegmentedSwitch(options: [
                        DSSegmentOption(id: false, title: L10n.t("حي", "Alive"), icon: "heart.fill"),
                        DSSegmentOption(id: true, title: L10n.t("متوفى", "Deceased"), icon: "leaf.fill")
                    ], selection: $deceased, size: .regular)
                }
            }
            DSComposerSection(title: L10n.t("ظهور الزوج في الشجرة", "Show him beside me?"), icon: "eye.fill",
                              tint: DS.Color.male, index: 2) {
                DSSegmentedSwitch(options: [
                    DSSegmentOption(id: true, title: L10n.t("إظهار", "Show"), icon: "eye.fill"),
                    DSSegmentOption(id: false, title: L10n.t("إخفاء", "Hide"), icon: "eye.slash.fill")
                ], selection: $visible, size: .regular)
            }
            if let errorText { DSNoteCard(errorText, icon: "exclamationmark.triangle.fill", tint: DS.Color.error) }
            if let sentText { DSNoteCard(sentText, icon: "paperplane.fill", tint: DS.Color.success) }
        }
    }

    private var matches: [FamilyMember] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return [] }
        return memberVM.allMembers.filter {
            !$0.isFemale && $0.role != .pending && $0.fullName.contains(q)
        }
    }

    private func save() {
        busy = true
        errorText = nil
        Task {
            defer { busy = false }
            do {
                let r = try await DaughterFamilyAPI.setHusband(familyId: fromFamily ? picked?.id : nil,
                                                               name: fromFamily ? (picked?.fullName ?? "") : name,
                                                               deceased: deceased, visible: visible)
                await DaughterRequestSent.finish(r, note: { sentText = $0 }, done: onDone)
            } catch { errorText = error.localizedDescription }
        }
    }
}

/// الابن/الابنة: الاسم الأول ويُكتب في الشجرة مع اسم الزوج تلقائياً
struct DaughterChildBox: View {
    @State private var sentText: String?
    let husbandName: String?
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var female = false
    @State private var firstName = ""
    @State private var hasBirth = false
    @State private var birth = Date()
    @State private var deceased = false
    @State private var busy = false
    @State private var errorText: String?

    private var fullName: String {
        let f = firstName.trimmingCharacters(in: .whitespaces)
        guard !f.isEmpty else { return "" }
        return [f, husbandName].compactMap { $0 }.joined(separator: " ")
    }

    var body: some View {
        DSComposer(title: L10n.t("إضافة ابن أو ابنة", "Add a son or daughter"),
                   subtitle: L10n.t("اختياري", "Optional"),
                   icon: "person.badge.plus", tint: DS.Color.palm,
                   actionTitle: L10n.t("إضافة", "Add"),
                   canSubmit: !fullName.isEmpty && !busy, isBusy: busy,
                   onSubmit: save, onCancel: { dismiss() }) {
            DSComposerSection(title: L10n.t("النوع", "Type"), icon: "person.2.fill", tint: DS.Color.palm, index: 0) {
                DSSegmentedSwitch(options: [
                    DSSegmentOption(id: false, title: L10n.t("ابن", "Son"), icon: "person.fill"),
                    DSSegmentOption(id: true, title: L10n.t("ابنة", "Daughter"), icon: "figure.stand.dress")
                ], selection: $female, size: .regular)
            }
            DSComposerSection(title: L10n.t("الاسم", "Name"), icon: "textformat", tint: DS.Color.palm, index: 1) {
                DSComposerField(icon: "person.fill", label: L10n.t("الاسم الأول", "First name"),
                                placeholder: L10n.t("مثال: خالد", "e.g. Khaled"), text: $firstName,
                                tint: DS.Color.palm, required: true)
                if !fullName.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        Text(L10n.t("يُكتب في الشجرة", "Shown in the tree as")).dsFont(.caption).foregroundColor(DS.Color.accent)
                        Text(fullName).dsFont(.headline).foregroundColor(DS.Color.textPrimary)
                        Text(husbandName == nil
                             ? L10n.t("الاسم الأول فقط، ويُكمَّل باسم الزوج بعد إضافته", "First name only — completed once you add your husband")
                             : L10n.t("الاسم الأول + اسم الزوج تلقائياً", "First name + your husband's name, automatically"))
                            .dsFont(.caption).foregroundColor(DS.Color.textTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DS.Spacing.md)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Color.cardBackgroundSoft))
                }
            }
            DSComposerSection(title: L10n.t("تاريخ الميلاد (اختياري)", "Birth date (optional)"), icon: "gift.fill",
                              tint: DS.Color.palm, index: 2) {
                Toggle(L10n.t("تاريخ الميلاد معروف", "I know the birth date"), isOn: $hasBirth).dsFont(.body)
                if hasBirth {
                    DatePicker("", selection: $birth, in: ...Date(), displayedComponents: .date)
                        .datePickerStyle(.compact).labelsHidden()
                }
            }
            DSComposerSection(title: L10n.t("الحالة", "Status"), icon: "heart.text.square", tint: DS.Color.palm, index: 3) {
                DSSegmentedSwitch(options: [
                    DSSegmentOption(id: false, title: L10n.t("حي", "Alive"), icon: "heart.fill"),
                    DSSegmentOption(id: true, title: L10n.t("متوفى", "Deceased"), icon: "leaf.fill")
                ], selection: $deceased, size: .regular)
            }
            if let errorText { DSNoteCard(errorText, icon: "exclamationmark.triangle.fill", tint: DS.Color.error) }
            if let sentText { DSNoteCard(sentText, icon: "paperplane.fill", tint: DS.Color.success) }
        }
    }

    private func save() {
        busy = true
        errorText = nil
        Task {
            defer { busy = false }
            do {
                let r = try await DaughterFamilyAPI.addChild(firstName: firstName.trimmingCharacters(in: .whitespaces),
                                                             female: female, birth: hasBirth ? birth : nil, deceased: deceased)
                await DaughterRequestSent.finish(r, note: { sentText = $0 }, done: onDone)
            } catch { errorText = error.localizedDescription }
        }
    }
}

/// الأم: من زوجات أبيها في شجرة النساء، أو اسم جديد
struct DaughterMotherBox: View {
    @State private var sentText: String?
    let node: FamilyMember
    let rows: [FamilyMember]
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var picked: UUID?
    @State private var name = ""
    @State private var busy = false
    @State private var errorText: String?

    private var fatherWives: [FamilyMember] {
        guard let f = node.fatherId else { return [] }
        return rows.filter { $0.isFemale && $0.husbandId == f }
    }

    var body: some View {
        DSComposer(title: L10n.t("إضافة الأم", "Add my mother"),
                   subtitle: L10n.t("اختياري", "Optional"),
                   icon: "figure.stand.dress", tint: DS.Color.female,
                   actionTitle: L10n.t("حفظ", "Save"),
                   canSubmit: (picked != nil || name.split(separator: " ").count >= 2) && !busy, isBusy: busy,
                   onSubmit: save, onCancel: { dismiss() }) {
            if !fatherWives.isEmpty {
                DSComposerSection(title: L10n.t("زوجات الأب", "Your father's wives"), icon: "heart.fill",
                                  tint: DS.Color.female, index: 0) {
                    ForEach(fatherWives, id: \.id) { w in
                        Button { picked = (picked == w.id ? nil : w.id); name = "" } label: {
                            DSRow(icon: "figure.stand.dress", tint: DS.Color.female,
                                  title: w.fullName.isEmpty ? w.firstName : w.fullName) {
                                Image(systemName: picked == w.id ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(picked == w.id ? DS.Color.female : DS.Color.textTertiary)
                            }
                        }
                        .buttonStyle(DSPressStyle())
                    }
                }
            }
            DSComposerSection(title: fatherWives.isEmpty ? L10n.t("اسم الأم الكامل", "Mother's full name")
                                                         : L10n.t("أو كتابة الاسم", "Or type the name"),
                              icon: "textformat", tint: DS.Color.female, index: 1) {
                DSComposerField(icon: "figure.stand.dress", label: L10n.t("الاسم الكامل", "Full name"),
                                placeholder: L10n.t("الاسم", "Name"), text: $name, tint: DS.Color.female)
            }
            if let errorText { DSNoteCard(errorText, icon: "exclamationmark.triangle.fill", tint: DS.Color.error) }
            if let sentText { DSNoteCard(sentText, icon: "paperplane.fill", tint: DS.Color.success) }
        }
        .onChange(of: name) { v in if !v.isEmpty { picked = nil } }
    }

    private func save() {
        busy = true
        errorText = nil
        Task {
            defer { busy = false }
            do {
                let r = try await DaughterFamilyAPI.setMother(existingId: picked, name: name.trimmingCharacters(in: .whitespaces))
                await DaughterRequestSent.finish(r, note: { sentText = $0 }, done: onDone)
            } catch { errorText = error.localizedDescription }
        }
    }
}

/// بعد الحفظ: نُفّذ → يُغلق المربّع؛ صار طلباً → سطر «انرسل طلبك» لحظة ثم يُغلق
enum DaughterRequestSent {
    @MainActor
    static func finish(_ r: DaughterFamilyAPI.Outcome, note: (String) -> Void, done: () -> Void) async {
        if r == .requested {
            note(L10n.t("تم إرسال الطلب إلى الإدارة، وسيصل الرد في الإشعارات.", "Sent to the administration — you'll get the reply in notifications."))
            try? await Task.sleep(nanoseconds: 1_800_000_000)
        }
        done()
    }
}
