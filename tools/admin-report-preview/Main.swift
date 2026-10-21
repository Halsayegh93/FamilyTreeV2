import UIKit
import PDFKit
import SwiftUI

@main
final class App: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        return true
    }
    var output: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    func generate() throws {
        var assertions: [String] = []
        func check(_ condition: Bool, _ title: String) throws {
            if !condition { throw NSError(domain: title, code: 1) }
            assertions.append(title)
        }
        let root = UUID()
        let branch = UUID()
        let names = ["محمد عبدالعزيز عبدالرحمن حسن المحمدعلي", "عبدالله محمدعلي عبدالمحسن إبراهيم المحمدعلي", "أحمد حسن علي المحمدعلي", "عبدالرحمن عبدالله محمد حسن إبراهيم المحمدعلي"]
        func person(_ i: Int, id: UUID, father: UUID?) -> AdminReportPerson {
            AdminReportPerson(id: id, fatherId: father, name: names[i % names.count], firstName: "محمد",
                sortOrder: i, birth: i == 7 ? "1901-02-03" : "1984-07-08", birthHidden: i == 7,
                deceased: i % 6 == 0, death: i % 6 == 0 ? "2025-03-06" : nil, deathUnknown: false,
                frozen: false, countable: true, phone: "+965 9999 9999", phoneHidden: i % 9 == 0)
        }
        var people = [person(0, id: root, father: nil), person(1, id: branch, father: root)]
        for i in 2..<182 { people.append(person(i, id: UUID(), father: branch)) }
        let input = AdminReportInput(people: people, rootId: root, women: [], registered: Set(people.prefix(50).map(\.id)),
            branchNames: [branch: "فرع تجريبي للاختبار"], generatedBy: "بيانات تجريبية", date: Date())
        let legacy = try JSONDecoder().decode(AdminReportOptions.self, from: Data("{\"compactRows\":false}".utf8))
        try check(!legacy.compactRows && legacy.groupByBranch && legacy.includeCover, "older saved layout options retain defaults for new controls")
        try check(AdminReportKind.register.resolvedFields([]) == [.name], "required name cannot be omitted")
        var pageCounts: [String: Int] = [:]
        func export(_ name: String, _ options: AdminReportOptions, _ fields: Set<AdminReportField>?, kind: AdminReportKind = .register) throws -> AdminReportDoc {
            let doc = AdminReportBuilder.build(kind, input: input, filter: .init(), fields: fields, options: options)
            let result = try AdminReportPDF.render(doc)
            let pdf = PDFDocument(data: result.data)!
            try check(pdf.pageCount == result.pages && result.pages > 0, "\(name): pagination matches")
            try result.data.write(to: output.appendingPathComponent(name + ".pdf"))
            pageCounts[name] = result.pages
            return doc
        }
        var normal = AdminReportOptions(); normal.compactRows = false
        let full = Set(AdminReportKind.register.fields)
        _ = try export("regular", normal, full)
        let compactDoc = try export("compact-all-fields", .init(), full)
        try check(pageCounts["compact-all-fields"]! <= pageCounts["regular"]!, "compact does not increase page count")
        var list = AdminReportOptions(); list.includeSummary = false; list.includeBranchSummary = false
        _ = try export("list-with-cover", list, [.name, .age, .status, .phone])
        list.includeCover = false
        let listDoc = try export("list-without-cover", list, [.name, .age, .status, .phone])
        try check(pageCounts["list-without-cover"]! + 1 == pageCounts["list-with-cover"]!, "cover toggle removes exactly one page")
        let rows = compactDoc.blocks.compactMap { b -> AdminReportTable? in if case .table(let t) = b, t.columns.contains(where: \.fill) { return t }; return nil }
        try check(rows.flatMap(\.rows).count == people.count, "all exported members retained")
        let flat = rows.flatMap(\.rows)
        let birthColumn = rows[0].columns.firstIndex { $0.title == "الميلاد" }!
        let phoneColumn = rows[0].columns.firstIndex { $0.title == "رقم الهاتف" }!
        try check(flat[7].cells[birthColumn] == "مخفي", "hidden birth date stays hidden")
        try check(flat[0].cells[phoneColumn] == "مخفي", "hidden phone stays hidden")
        try check(!listDoc.blocks.contains { if case .tiles = $0 { return true }; return false }, "count summary can be omitted")
        let listTables = listDoc.blocks.compactMap { block -> AdminReportTable? in
            if case .table(let table) = block, table.columns.contains(where: \.fill) { return table }; return nil
        }
        try check(listTables.flatMap(\.rows).allSatisfy { !$0.cells.contains(where: { $0.contains("2025") }) }, "unchecked death date is absent even from status")
        var flatOptions = list
        flatOptions.groupByBranch = false
        let flatDoc = try export("flat-list", flatOptions, [.name, .branch, .status])
        let flatTables = flatDoc.blocks.compactMap { block -> AdminReportTable? in
            if case .table(let table) = block { return table }; return nil
        }
        try check(flatTables.count == 1 && flatTables[0].rows.count == people.count, "flat grouping produces one complete table")
        try check(flatTables[0].rows[1].cells[2] == "فرع تجريبي للاختبار", "flat list preserves the correct optional branch column")
        var sampleFilter = AdminReportFilter()
        sampleFilter.scope = .init(ids: Set(people.prefix(24).map(\.id)), title: "بيانات تجريبية للمعاينة")
        let specimen = AdminReportBuilder.build(.register, input: input, filter: sampleFilter,
            fields: [.name, .age, .status, .phone], options: flatOptions)
        let specimenPDF = try AdminReportPDF.render(specimen)
        try check(specimenPDF.pages == 1, "synthetic 24-member preview fits one page")
        try specimenPDF.data.write(to: output.appendingPathComponent("member-list-preview.pdf"))
        for kind in [AdminReportKind.stats, .memorial, .phones] { _ = try export("smoke-" + kind.rawValue, .init(), nil, kind: kind) }
        try JSONSerialization.data(withJSONObject: ["pages":pageCounts,"checks":assertions], options: [.prettyPrinted,.sortedKeys])
            .write(to: output.appendingPathComponent("checks.json"))
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        window = UIWindow(windowScene: scene)
        window?.rootViewController = UIViewController()
        window?.makeKeyAndVisible()
        let app = UIApplication.shared.delegate as! App
        do { try app.generate() } catch {
            try? String(describing: error).write(to: app.output.appendingPathComponent("failure.txt"), atomically: true, encoding: .utf8)
        }
    }
}
