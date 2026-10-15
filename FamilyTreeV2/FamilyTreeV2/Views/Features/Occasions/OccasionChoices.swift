import Foundation

// MARK: - اختيارات «بوستات المناسبات» — كل نص في البوست يطلع من اختيار بدل الكتابة
//
// نسخة مطابقة لقوائم الموقع: familytree-web/src/lib/occasions/choices.ts و compose.ts
// أي تعديل هنا لازم ينعكس هناك (والعكس).

enum OccasionChoices {

    // MARK: الصفة (لمن التهنئة)

    static func honorifics(_ g: OccasionGender) -> [String] {
        g == .male
            ? ["الأخ العزيز", "الابن العزيز", "العم العزيز", "الخال العزيز", "الجد العزيز", "الحاج", "الدكتور", "المهندس", "الأستاذ", "الشاب"]
            : ["الأخت العزيزة", "الابنة العزيزة", "العمة العزيزة", "الخالة العزيزة", "الجدة العزيزة", "الحاجة", "الدكتورة", "المهندسة", "الأستاذة", "الشابة"]
    }

    /// «الأخ العزيز» ← «للأخ العزيز»
    static func dative(_ honor: String) -> String {
        let h = honor.trimmingCharacters(in: .whitespaces)
        return h.hasPrefix("ال") ? "لل" + String(h.dropFirst(2)) : "ل" + h
    }

    /// {d} = الصفة مع لام الجر، {n} = الصفة كما هي
    private static let openingsById: [String: [String]] = [
        "wedding": ["تهنئة وتبريك {d}", "نتقدم بأحر التهاني {d}", "ألف مبروك {d}", "تتقدم عائلة المحمد علي بالتهنئة {d}"],
        "newborn": ["نتقدم بالتهنئة {d}", "تهنئة وتبريك {d}", "ألف مبروك {d}", "تتقدم عائلة المحمد علي بالتهنئة {d}"],
        "newbornGirl": ["نتقدم بالتهنئة {d}", "تهنئة وتبريك {d}", "ألف مبروك {d}", "تتقدم عائلة المحمد علي بالتهنئة {d}"],
        "recovery": ["نسألكم الدعاء {d}", "دعواتكم بالشفاء العاجل {d}", "الحمد لله على سلامة {n}", "نتمنى الشفاء العاجل {d}"],
        "graduation": ["نتقدم بالتهنئة {d}", "ألف مبروك {d}", "تهنئة وتبريك {d}", "تتقدم عائلة المحمد علي بالتهنئة {d}"],
    ]

    static func openings(_ templateId: String) -> [String] {
        openingsById[templateId] ?? openingsById["wedding"] ?? []
    }

    static func composeIntro(_ opening: String, honor: String) -> String {
        opening
            .replacingOccurrences(of: "{d}", with: dative(honor))
            .replacingOccurrences(of: "{n}", with: honor.trimmingCharacters(in: .whitespaces))
    }

    // MARK: سطر المناسبة

    static func occasions(_ templateId: String, _ g: OccasionGender) -> [String] {
        let m = g == .male
        switch templateId {
        case "newborn":
            return m ? ["لقدوم مولوده", "بمناسبة قدوم مولوده", "لرزقه بمولود"]
                     : ["لقدوم مولودها", "بمناسبة قدوم مولودها", "لرزقها بمولود"]
        case "newbornGirl":
            return m ? ["لقدوم مولودته", "بمناسبة قدوم مولودته", "لرزقه بمولودة"]
                     : ["لقدوم مولودتها", "بمناسبة قدوم مولودتها", "لرزقها بمولودة"]
        case "recovery":
            return m ? ["أجر وعافية", "سلامات ما تشوف شر", "شفاه الله وعافاه", "الحمد لله على السلامة"]
                     : ["أجر وعافية", "سلامات ما تشوفين شر", "شفاها الله وعافاها", "الحمد لله على السلامة"]
        default:
            return m ? ["بمناسبة عقد قرانه", "بمناسبة زواجه", "بمناسبة زفافه"]
                     : ["بمناسبة عقد قرانها", "بمناسبة زواجها", "بمناسبة زفافها"]
        }
    }

    // MARK: التخرج: المرحلة + الجهة

    static let degrees = ["الثانوية العامة", "الدبلوم", "البكالوريوس", "الماجستير", "الدكتوراه"]

    static let institutions = [
        "جامعة الكويت",
        "الهيئة العامة للتعليم التطبيقي والتدريب",
        "جامعة عبدالله السالم",
        "جامعة الخليج للعلوم والتكنولوجيا",
        "الجامعة الأمريكية في الكويت",
        "الجامعة الأمريكية في الشرق الأوسط",
        "الجامعة الأسترالية",
    ]

    /// يرجع (سطر المناسبة، السطر الثاني)
    static func composeGraduation(_ g: OccasionGender, degreeIndex: Int, institution: String) -> (String, String) {
        if degreeIndex <= 0 {
            return (g == .male ? "لتخرجه من" : "لتخرجها من", "المرحلة الثانوية")
        }
        let deg = degrees.indices.contains(degreeIndex) ? degrees[degreeIndex] : degrees[0]
        let verb = g == .male ? "لحصوله على" : "لحصولها على"
        let inst = institution.trimmingCharacters(in: .whitespacesAndNewlines)
        return ("\(verb) \(deg == "الدبلوم" ? "شهادة" : "درجة") \(deg)", inst.isEmpty ? "" : "من \(inst)")
    }

    // MARK: الدعاء

    static func duas(_ templateId: String, _ g: OccasionGender) -> [String] {
        let m = g == .male
        switch templateId {
        case "newborn":
            return [
                "نسأل الله تعالى أن يجعله قرة عين لوالديه الكريمين، وأن ينبته نباتا حسنا",
                "بارك الله لكم في الموهوب، وشكرتم الواهب، وبلغ أشده، ورزقتم بره",
                "جعله الله من الذرية الصالحة، وأقر به أعين والديه",
            ]
        case "newbornGirl":
            return [
                "نسأل الله تعالى أن يجعلها قرة عين لوالديها الكريمين، وأن ينبتها نباتا حسنا",
                "بارك الله لكم في الموهوبة، وشكرتم الواهب، وبلغت أشدها، ورزقتم برها",
                "جعلها الله من الذرية الصالحة، وأقر بها أعين والديها",
            ]
        case "recovery":
            return m
                ? ["اللهم ألبسه ثوب الصحة والعافية، واشفه شفاء لا يغادر سقما",
                   "أسأل الله العظيم رب العرش العظيم أن يشفيه ويعافيه",
                   "لا بأس طهور إن شاء الله، ومتعه الله بالصحة والعافية"]
                : ["اللهم ألبسها ثوب الصحة والعافية، واشفها شفاء لا يغادر سقما",
                   "أسأل الله العظيم رب العرش العظيم أن يشفيها ويعافيها",
                   "لا بأس طهور إن شاء الله، ومتعها الله بالصحة والعافية"]
        case "graduation":
            return m
                ? ["نسأل الله تعالى أن يجعله بوابة لمستقبل زاهر ومليء بالإنجازات، ويرزقه التوفيق",
                   "متمنين له دوام التوفيق والنجاح في حياته العلمية والعملية",
                   "ألف مبروك، وإلى مزيد من التفوق والنجاح"]
                : ["نسأل الله تعالى أن يجعله بوابة لمستقبل زاهر ومليء بالإنجازات، ويرزقها التوفيق",
                   "متمنين لها دوام التوفيق والنجاح في حياتها العلمية والعملية",
                   "ألف مبروك، وإلى مزيد من التفوق والنجاح"]
        case "solace":
            return m
                ? ["راجين المولى العلي القدير أن يتغمد الفقيد بواسع رحمته ويسكنه فسيح جناته، وأن يلهم ذويه الصبر والسلوان",
                   "سائلين المولى عز وجل أن يتغمده بواسع رحمته، وأن يلهمكم الصبر والسلوان",
                   "عظم الله أجوركم، وأحسن عزاءكم، وغفر لفقيدكم"]
                : ["راجين المولى العلي القدير أن يتغمد الفقيدة بواسع رحمته ويسكنها فسيح جناته، وأن يلهم ذويها الصبر والسلوان",
                   "سائلين المولى عز وجل أن يتغمدها بواسع رحمته، وأن يلهمكم الصبر والسلوان",
                   "عظم الله أجوركم، وأحسن عزاءكم، وغفر لفقيدتكم"]
        default: // عقد قران
            return m
                ? ["نسأل الله عز وجل أن يبارك له هذا الزواج، ويرزقه الذرية الصالحة",
                   "بارك الله لهما وبارك عليهما وجمع بينهما في خير",
                   "نسأل الله أن يجعله زواجاً مباركاً، وأن يديم بينهما المودة والرحمة"]
                : ["نسأل الله عز وجل أن يبارك لها هذا الزواج، ويرزقها الذرية الصالحة",
                   "بارك الله لهما وبارك عليهما وجمع بينهما في خير",
                   "نسأل الله أن يجعله زواجاً مباركاً، وأن يديم بينهما المودة والرحمة"]
        }
    }

    /// دعاء إعلان الوفاة: سطرين
    static func deathDuas(_ g: OccasionGender) -> [(String, String)] {
        g == .male
            ? [("نسأل الله تعالى أن يتغمده برحمته الواسعة وأن يلهم ذويه الصبر والسلوان", "وأن يحشره مع النبي المصطفى وآله الطاهرين"),
               ("تغمده الله بواسع رحمته وأسكنه فسيح جناته", "وألهم أهله وذويه الصبر والسلوان"),
               ("الفاتحة تسبقها الصلاة على محمد وآله الطيبين الطاهرين", "")]
            : [("نسأل الله تعالى أن يتغمدها برحمته الواسعة وأن يلهم ذويها الصبر والسلوان", "وأن يحشرها مع النبي المصطفى وآله الطاهرين"),
               ("تغمدها الله بواسع رحمته وأسكنها فسيح جناته", "وألهم أهلها وذويها الصبر والسلوان"),
               ("الفاتحة تسبقها الصلاة على محمد وآله الطيبين الطاهرين", "")]
    }

    // MARK: الوفاة

    static func deathLeads(_ g: OccasionGender) -> [String] {
        g == .male
            ? ["انتقل إلى رحمة الله تعالى", "انتقل إلى جوار ربه", "توفي إلى رحمة الله تعالى"]
            : ["انتقلت إلى رحمة الله تعالى", "انتقلت إلى جوار ربها", "توفيت إلى رحمة الله تعالى"]
    }

    static func deathTitles(_ g: OccasionGender) -> [String] {
        g == .male
            ? ["المرحوم الحاج", "المرحوم", "المرحوم الشاب", "المرحوم الطفل", "المغفور له بإذن الله"]
            : ["المرحومة الحاجة", "المرحومة", "المرحومة الشابة", "المرحومة الطفلة", "المغفور لها بإذن الله"]
    }

    static let funeralDays = ["اليوم", "غداً", "يوم السبت", "يوم الأحد", "يوم الاثنين", "يوم الثلاثاء", "يوم الأربعاء", "يوم الخميس", "يوم الجمعة"]
    static let funeralTimes = ["بعد صلاة الظهر", "بعد صلاة العصر", "بعد صلاة المغرب", "بعد صلاة العشاء", "صباحاً", "عصراً"]
    static let cemeteries = ["المقبرة الجعفرية", "مقبرة الصليبيخات", "مقبرة صبحان", "مقبرة الجهراء"]

    static func composeFuneral(day: String, time: String, cemetery: String) -> String {
        let cem = cemetery.trimmingCharacters(in: .whitespacesAndNewlines)
        return ["التشييع", day, time, cem.isEmpty ? "" : "في \(cem)"]
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: " ")
    }

    static let condolenceDurations = ["", "لمدة ثلاثة أيام", "لمدة يومين", "ليوم واحد فقط"]
    static var durationLabels: [String] {
        [L10n.t("بدون مدة", "No duration"), "ثلاثة أيام", "يومين", "يوم واحد"]
    }

    private static let weekdays = ["الأحد", "الاثنين", "الثلاثاء", "الأربعاء", "الخميس", "الجمعة", "السبت"]

    /// «العزاء ابتداء من يوم الاثنين 12/10/2026» — بالتقويم الميلادي وأرقام لاتينية مثل الموقع
    static func composeCondolence(_ date: Date, duration: String) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let c = cal.dateComponents([.year, .month, .day, .weekday], from: date)
        guard let y = c.year, let mo = c.month, let d = c.day, let wd = c.weekday,
              weekdays.indices.contains(wd - 1) else { return "" }
        let line = "العزاء ابتداء من يوم \(weekdays[wd - 1]) \(d)/\(mo)/\(y)"
        return duration.isEmpty ? line : "\(line) \(duration)"
    }

    // MARK: أماكن العزاء

    static func venuePresets(_ g: OccasionGender) -> [String] {
        g == .male ? ["ديوان العائلة", "منزل الفقيد"] : ["ديوان العائلة", "منزل الفقيدة"]
    }

    static let venueTimes = ["صباحاً ومساءً", "عصراً ومساءً", "مساءً", "بعد صلاة المغرب", ""]
    static var venueTimeLabels: [String] {
        ["صباحاً ومساءً", "عصراً ومساءً", "مساءً", "بعد صلاة المغرب", L10n.t("بدون وقت", "No time")]
    }

    /// مناطق الكويت حسب المحافظة (للاختيار السريع — والكتابة متاحة)
    static let areaGroups: [OccasionAreaGroup] = [
        OccasionAreaGroup(name: "العاصمة", areas: [
            "مدينة الكويت", "الشرق", "القبلة", "المرقاب", "الدسمة", "الدعية", "بنيد القار", "الشامية", "الشويخ", "كيفان", "الخالدية",
            "العديلية", "الفيحاء", "النزهة", "القادسية", "المنصورية", "الروضة", "قرطبة", "السرة", "اليرموك", "الصليبيخات", "الدوحة",
            "غرناطة", "القيروان", "جابر الأحمد", "عبدالله السالم",
        ]),
        OccasionAreaGroup(name: "حولي", areas: [
            "حولي", "السالمية", "الجابرية", "الرميثية", "بيان", "مشرف", "سلوى", "الشعب", "الشهداء", "حطين", "الصديق", "السلام",
            "الزهراء", "البدع", "ميدان حولي", "مبارك العبدالله",
        ]),
        OccasionAreaGroup(name: "الفروانية", areas: [
            "الفروانية", "خيطان", "الرابية", "العارضية", "الأندلس", "الرحاب", "الفردوس", "الضجيج", "جليب الشيوخ", "العمرية",
            "إشبيلية", "عبدالله المبارك", "صباح الناصر", "الرقعي",
        ]),
        OccasionAreaGroup(name: "مبارك الكبير", areas: [
            "مبارك الكبير", "القرين", "القصور", "العدان", "صباح السالم", "المسيلة", "أبو فطيرة", "الفنيطيس", "أبو الحصانية",
            "المسايل", "صبحان",
        ]),
        OccasionAreaGroup(name: "الأحمدي", areas: [
            "الأحمدي", "الفحيحيل", "المنقف", "أبو حليفة", "الفنطاس", "المهبولة", "الرقة", "الصباحية", "هدية", "جابر العلي",
            "العقيلة", "الظهر", "صباح الأحمد", "علي صباح السالم", "الخيران", "الوفرة", "فهد الأحمد",
        ]),
        OccasionAreaGroup(name: "الجهراء", areas: [
            "الجهراء", "القصر", "النعيم", "العيون", "النسيم", "الواحة", "تيماء", "الصليبية", "سعد العبدالله",
        ]),
    ]

    static let kuwaitAreas: [String] = areaGroups.flatMap(\.areas)

    /// المنطقة من عنوان الديوانية — أطول اسم منطقة موجود في العنوان («علي صباح السالم» قبل «صباح السالم»)
    static func area(inAddress address: String?) -> String? {
        guard let address, !address.isEmpty else { return nil }
        return kuwaitAreas.filter { address.contains($0) }.max { $0.count < $1.count }
    }

    // MARK: مشاركة العزاء

    static let solaceFrom = ["تتقدم عائلة المحمد علي", "يتقدم أبناء عائلة المحمد علي", "تتقدم أسرة المحمد علي"]
    static let solaceToFormats = ["عائلة {x} الكرام", "آل {x} الكرام", "أسرة {x} الكريمة"]

    static func composeSolaceTo(format: String, family: String) -> String {
        var x = family.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["عائلة ", "آل ", "أسرة "] where x.hasPrefix(prefix) {
            x = String(x.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        for suffix in [" الكرام", " الكريمة"] where x.hasSuffix(suffix) {
            x = String(x.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
        }
        return format.replacingOccurrences(of: "{x}", with: x.isEmpty ? "..." : x)
    }

    static func solaceLeads(_ g: OccasionGender) -> [String] {
        g == .male
            ? ["بوفاة المغفور له بإذن الله تعالى", "بوفاة فقيدهم الغالي", "بوفاة المرحوم"]
            : ["بوفاة المغفور لها بإذن الله تعالى", "بوفاة فقيدتهم الغالية", "بوفاة المرحومة"]
    }

    /// أسماء مفصولة بفواصل عربية — مثل نعي الجرايد: «محمد، حسن، مهدي»
    static func joinNames(_ names: [String]) -> String {
        names.filter { !$0.isEmpty }.joined(separator: "، ")
    }
}

struct OccasionAreaGroup: Identifiable {
    let name: String
    let areas: [String]
    var id: String { name }
}

// MARK: - صيغة الاسم (من شجرة العائلة) — نفس دوال الأسماء في FamilyMember

/// أقصى عدد أسماء في البوست (بعدها يصغر الخط كثير) — الافتراضي «سداسي»
enum OccasionNameFormat: String, CaseIterable, Identifiable {
    case three, four, five, six

    static let maxWords = 6
    static let defaultFormat: OccasionNameFormat = .six

    var id: String { rawValue }

    var label: String {
        switch self {
        case .three: return L10n.t("ثلاثي", "3 names")
        case .four: return L10n.t("رباعي", "4 names")
        case .five: return L10n.t("خماسي", "5 names")
        case .six: return L10n.t("سداسي", "6 names")
        }
    }

    func apply(_ m: FamilyMember) -> String {
        switch self {
        case .three: return m.shortFullName
        case .four: return m.fourPartName
        case .five: return m.fivePartName
        case .six: return Self.sixPartName(m)
        }
    }

    /// الخمسة الأولى + العائلة (نفس قاعدة fivePartName بكلمة زيادة)
    static func sixPartName(_ m: FamilyMember) -> String {
        let parts = m.nameWordsWithFamily
        guard parts.count > maxWords, let family = parts.last else {
            return parts.isEmpty ? m.fullName : parts.joined(separator: " ")
        }
        return (parts.prefix(maxWords - 1) + [family]).joined(separator: " ")
    }

    /// الصيغ المختلفة فقط (الاسم القصير يطلع نفسه بأكثر من صيغة)
    static func distinct(for m: FamilyMember) -> [(format: OccasionNameFormat, text: String)] {
        var out: [(format: OccasionNameFormat, text: String)] = []
        for f in allCases {
            let text = f.apply(m)
            if out.last?.text != text { out.append((format: f, text: text)) }
        }
        return out
    }

    /// الاسم المكتوب: أقصى شي ٦ أسماء (الخمسة الأولى + الأخير، وهو العائلة عادة)
    static func capped(_ name: String) -> String {
        let words = name.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count > maxWords, let last = words.last else { return words.joined(separator: " ") }
        return (words.prefix(maxWords - 1) + [last]).joined(separator: " ")
    }
}

// MARK: - حالة النموذج (اختيارات + نصوص)

/// sel: رقم الاختيار لكل مجموعة (‎-1 = «نص آخر» المكتوب في texts["<المجموعة>Custom"])
struct OccasionForm: Equatable {
    var gender: OccasionGender = .male
    var selections: [String: Int] = [:]
    var texts: [String: String] = [:]
    var condolenceDate = Date()

    /// المجموعات اللي اختيارها الافتراضي مو الأول
    static let defaultSelections: [String: Int] = ["men": 1, "women": 1, "funeral": 1, "cond": 1, "fTime": 1]

    func sel(_ key: String) -> Int { selections[key] ?? Self.defaultSelections[key] ?? 0 }
    func txt(_ key: String) -> String { texts[key] ?? "" }
}

// MARK: - تحويل الاختيارات إلى نصوص البوست (نفس compose.ts)

enum OccasionCompose {
    private static func clean(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// عنصر من القائمة حسب الاختيار؛ ‎-1 = النص المكتوب؛ خارج القائمة = فاضي («بدون»)
    private static func pick(_ list: [String], _ i: Int, custom: String) -> String {
        if i == -1 { return clean(custom) }
        return list.indices.contains(i) ? list[i] : ""
    }

    static func values(_ t: OccasionTemplate, _ f: OccasionForm, name: String) -> [String: String] {
        let g = f.gender
        var out: [String: String] = [:]

        switch t.kind {
        case .happy:
            let honors = OccasionChoices.honorifics(g)
            let honor = honors.indices.contains(f.sel("honor")) ? honors[f.sel("honor")] : honors[0]
            if f.sel("opening") == -1 {
                out["intro"] = clean(f.txt("introCustom"))
            } else {
                let openings = OccasionChoices.openings(t.id)
                let opening = openings.indices.contains(f.sel("opening")) ? openings[f.sel("opening")] : (openings.first ?? "")
                out["intro"] = OccasionChoices.composeIntro(opening, honor: honor)
            }
            let typed = OccasionNameFormat.capped(name)
            out["name"] = typed.isEmpty ? "[الاسم الكامل]" : typed
            if t.id == "graduation" {
                let inst = f.sel("inst") == -1
                    ? f.txt("instCustom")
                    : (OccasionChoices.institutions.indices.contains(f.sel("inst")) ? OccasionChoices.institutions[f.sel("inst")] : "")
                let degree = min(f.sel("degree"), OccasionChoices.degrees.count - 1)
                let (occ, sub) = OccasionChoices.composeGraduation(g, degreeIndex: degree, institution: inst)
                out["occasion"] = occ
                out["sub"] = sub
            } else {
                let list = OccasionChoices.occasions(t.id, g)
                out["occasion"] = pick(list, min(f.sel("occasion"), list.count - 1), custom: f.txt("occasionCustom"))
                if t.id == "newborn" || t.id == "newbornGirl" {
                    let baby = clean(f.txt("sub"))
                    out["sub"] = baby.isEmpty ? (t.id == "newborn" ? "[اسم المولود]" : "[اسم المولودة]") : baby
                }
            }
            out["dua"] = pick(OccasionChoices.duas(t.id, g), f.sel("dua"), custom: f.txt("duaCustom"))

        case .solace:
            out["from"] = pick(OccasionChoices.solaceFrom, f.sel("from"), custom: f.txt("fromCustom"))
            let formats = OccasionChoices.solaceToFormats
            let format = formats.indices.contains(f.sel("toFmt")) ? formats[f.sel("toFmt")] : formats[0]
            out["to"] = OccasionChoices.composeSolaceTo(format: format, family: f.txt("toFamily"))
            out["lead"] = pick(OccasionChoices.solaceLeads(g), f.sel("slead"), custom: f.txt("sleadCustom"))
            let typed = OccasionNameFormat.capped(name)
            out["name"] = typed.isEmpty ? (g == .male ? "[اسم الفقيد]" : "[اسم الفقيدة]") : typed
            out["dua"] = pick(OccasionChoices.duas("solace", g), f.sel("dua"), custom: f.txt("duaCustom"))

        case .death, .deathText:
            out["lead"] = pick(OccasionChoices.deathLeads(g), f.sel("lead"), custom: f.txt("leadCustom"))
            out["title"] = pick(OccasionChoices.deathTitles(g), f.sel("title"), custom: f.txt("titleCustom"))
            let typed = OccasionNameFormat.capped(name)
            out["name"] = typed.isEmpty ? (g == .male ? "[اسم الفقيد]" : "[اسم الفقيدة]") : typed

            if t.kind == .death {
                out["relation"] = clean(f.txt("relation"))
            } else {
                out["rel1"] = clean(f.txt("rel1"))
                out["rel2"] = clean(f.txt("rel2"))
                out["rel3"] = clean(f.txt("rel3"))
                if f.sel("funeral") == 1 {
                    let cem = f.sel("cem") == -1
                        ? f.txt("cemCustom")
                        : (OccasionChoices.cemeteries.indices.contains(f.sel("cem")) ? OccasionChoices.cemeteries[f.sel("cem")] : "")
                    let days = OccasionChoices.funeralDays
                    let times = OccasionChoices.funeralTimes
                    out["funeral"] = OccasionChoices.composeFuneral(
                        day: days.indices.contains(f.sel("fDay")) ? days[f.sel("fDay")] : "",
                        time: times.indices.contains(f.sel("fTime")) ? times[f.sel("fTime")] : "",
                        cemetery: cem
                    )
                } else {
                    out["funeral"] = ""
                }
                if f.sel("cond") == 1 {
                    let durations = OccasionChoices.condolenceDurations
                    out["condolence"] = OccasionChoices.composeCondolence(
                        f.condolenceDate,
                        duration: durations.indices.contains(f.sel("dur")) ? durations[f.sel("dur")] : ""
                    )
                } else {
                    out["condolence"] = ""
                }
            }

            for side in ["men", "women"] {
                if f.sel(side) == 1 {
                    let place = clean(f.txt("\(side)Place"))
                    out["\(side)Place"] = place.isEmpty ? "ديوان العائلة" : place
                    out["\(side)Area"] = clean(f.txt("\(side)Area"))
                    let times = OccasionChoices.venueTimes
                    out["\(side)Times"] = times.indices.contains(f.sel("\(side)Times")) ? times[f.sel("\(side)Times")] : ""
                } else {
                    out["\(side)Place"] = ""
                    out["\(side)Area"] = ""
                    out["\(side)Times"] = ""
                }
            }

            if f.sel("deathDua") == -1 {
                out["dua1"] = clean(f.txt("dua1Custom"))
                out["dua2"] = ""
            } else {
                let duas = OccasionChoices.deathDuas(g)
                let d = duas.indices.contains(f.sel("deathDua")) ? duas[f.sel("deathDua")] : ("", "")
                out["dua1"] = d.0
                out["dua2"] = d.1
            }
        }
        return out
    }
}

// MARK: - شجرة العائلة لاختيار الاسم والصورة وسطور القرابة

/// فهرس أعضاء الشجرة (جدول الأعضاء — رجال) بنفس ترتيب الشجرة.
struct OccasionFamilyIndex {
    let members: [FamilyMember]
    let byId: [UUID: FamilyMember]
    /// الأبناء بترتيب الشجرة (الأكبر أولاً)
    let childrenOf: [UUID: [FamilyMember]]
    private let searchKeys: [UUID: String]

    init(_ all: [FamilyMember]) {
        let list = all.filter { $0.isCountable && !$0.isFemale }
        members = list
        byId = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var kids: [UUID: [FamilyMember]] = [:]
        for m in list {
            if let f = m.fatherId { kids[f, default: []].append(m) }
        }
        for (k, v) in kids {
            kids[k] = v.sorted { a, b in
                if a.sortOrder != b.sortOrder { return a.sortOrder < b.sortOrder }
                // تاريخ ميلاد فاضي = غير معروف (آخر الترتيب) مثل الموقع
                let ab = a.birthDate.flatMap { $0.isEmpty ? nil : $0 } ?? "9999"
                let bb = b.birthDate.flatMap { $0.isEmpty ? nil : $0 } ?? "9999"
                if ab != bb { return ab < bb }
                return a.firstName < b.firstName
            }
        }
        childrenOf = kids
        searchKeys = Dictionary(list.map { ($0.id, Self.normalize($0.nameWordsWithFamily.joined(separator: " "))) },
                                uniquingKeysWith: { a, _ in a })
    }

    var isEmpty: Bool { members.isEmpty }

    /// توحيد الحروف للبحث: بدون تشكيل، أ/إ/آ ← ا، ة ← ه، ى ← ي
    static func normalize(_ s: String) -> String {
        var out = String(String.UnicodeScalarView(s.unicodeScalars.filter {
            !((0x064B...0x0652).contains($0.value) || $0.value == 0x0670 || $0.value == 0x0640)
        }))
        out = out.replacingOccurrences(of: "أ", with: "ا")
            .replacingOccurrences(of: "إ", with: "ا")
            .replacingOccurrences(of: "آ", with: "ا")
            .replacingOccurrences(of: "ة", with: "ه")
            .replacingOccurrences(of: "ى", with: "ي")
        return out.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    func search(_ query: String, preferDeceased: Bool, limit: Int = 60) -> [FamilyMember] {
        let tokens = Self.normalize(query).split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return [] }
        var found: [FamilyMember] = []
        for m in members {
            guard let key = searchKeys[m.id] else { continue }
            if tokens.allSatisfy({ key.contains($0) }) {
                found.append(m)
                if found.count >= 200 { break }
            }
        }
        if preferDeceased {
            // ترتيب مستقر: المتوفين أولاً
            found = found.filter { $0.isDeceased == true } + found.filter { $0.isDeceased != true }
        }
        return Array(found.prefix(limit))
    }

    func sonsOldestFirst(_ id: UUID) -> [FamilyMember] { childrenOf[id] ?? [] }

    /// الأحدث أولاً — اقتراحات اسم المولود
    func childrenNewestFirst(_ id: UUID) -> [FamilyMember] { Array((childrenOf[id] ?? []).reversed()) }

    func brothers(of m: FamilyMember) -> [FamilyMember] {
        guard let f = m.fatherId else { return [] }
        return sonsOldestFirst(f).filter { $0.id != m.id }
    }

    static func firstName(_ m: FamilyMember) -> String {
        m.nameWordsWithFamily.first ?? m.firstName
    }

    /// المتوفى يسبقه «المرحوم» مثل نعي الجرايد
    static func relativeName(_ m: FamilyMember) -> String {
        m.isDeceased == true ? "المرحوم \(firstName(m))" : firstName(m)
    }

    func sonsLine(_ m: FamilyMember) -> String {
        let sons = sonsOldestFirst(m.id)
        return sons.isEmpty ? "" : "والد كل من: " + OccasionChoices.joinNames(sons.map(Self.relativeName))
    }

    func brothersLine(_ m: FamilyMember) -> String {
        let b = brothers(of: m)
        return b.isEmpty ? "" : "شقيق كل من: " + OccasionChoices.joinNames(b.map(Self.relativeName))
    }

    func fatherLine(_ m: FamilyMember) -> String {
        guard let fid = m.fatherId, let father = byId[fid] else { return "" }
        return "ابن \(father.isDeceased == true ? "المرحوم " : "")\(father.shortFullName)"
    }
}
