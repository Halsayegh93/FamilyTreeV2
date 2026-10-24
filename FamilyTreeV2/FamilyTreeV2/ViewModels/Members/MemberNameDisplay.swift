import Foundation

// MARK: - اسم صاحب المحتوى بالعائلة المختارة (طلب المالك ٢٠٢٦-١٠-٢٤: «ليش مو بكل التطبيق يتطبق نفس الاختيار»)
// المشاريع والتعليقات وطلبات الشجرة تحفظ اسم صاحبها نصّاً وقت الإنشاء (والسيرفر يكتب بعضها من الاسم الكامل)،
// فلا يتبع العائلة التي يختارها لاحقاً. العرض يجد الشخص بمعرّفه ويعرض اسمه بالعائلة بالطول المناسب للمكان؛
// وإن لم يُعرف يبقى النص المحفوظ كما هو.

/// طول الاسم المعروض — كلها تنتهي بالعائلة المختارة (وقاعدة لقب العائلة بين قوسين)
nonisolated enum MemberNameLength: Sendable {
    /// الاسم الكامل — `displayFullName`
    case full
    /// الأول + الأب + الجد + العائلة — `fourPartName` (للصفوف والكبسولات بسطر واحد)
    case four
}

extension FamilyMember {
    /// الاسم بالعائلة المختارة بالطول المطلوب
    nonisolated func name(_ length: MemberNameLength) -> String {
        switch length {
        case .full: return displayFullName
        case .four: return fourPartName
        }
    }
}

extension MemberViewModel {
    /// اسم الشخص بالعائلة المختارة إن عُرف بمعرّفه، وإلا النص المحفوظ كما هو
    func displayName(id: UUID?, stored: String, _ length: MemberNameLength) -> String {
        guard let id, let m = member(byId: id), m.hasName else { return stored }
        return m.name(length)
    }

    /// اسم من يخصّه طلب تعديل الشجرة بالعائلة المختارة — السيرفر يكتب `targetMemberName` من الاسم الكامل بلا العائلة
    func treeEditTargetName(_ payload: TreeEditPayload?) -> String? {
        guard let payload else { return nil }
        if let id = payload.targetMemberId.flatMap(UUID.init(uuidString:)), let m = member(byId: id), m.hasName {
            return m.displayFullName
        }
        return payload.targetMemberName
    }
}
