// فحص حدّ المكتبة والتقطيع (Core/LibraryUpload.swift) — بلا محاكي:
//   xcrun swiftc -o /tmp/libupload FamilyTreeV2/FamilyTreeV2/Core/LibraryUpload.swift tests/library-upload/main.swift && /tmp/libupload
import Foundation
var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}
let MB = 1024 * 1024
// الحدّ من السيرفر
check(LibraryUpload.limitMB(fromConfig: nil), 25, "missing key → 25")
check(LibraryUpload.limitMB(fromConfig: 100), 100, "100")
check(LibraryUpload.limitMB(fromConfig: 40), 40, "40")
check(LibraryUpload.limitMB(fromConfig: 500), 100, "clamp high")
check(LibraryUpload.limitMB(fromConfig: 1), 5, "clamp low")
check(LibraryUpload.maxBytes(mb: 100), Int64(100 * MB), "bytes")
// العتبة
check(LibraryUpload.chunkSize, 6 * MB, "chunk = 6 MB")
check(LibraryUpload.usesResumable(size: Int64(6 * MB)), false, "6 MB simple")
check(LibraryUpload.usesResumable(size: Int64(6 * MB + 1)), true, "6 MB + 1 resumable")
// التقطيع
let c100 = LibraryUpload.chunks(total: Int64(100 * MB))
check(c100.count, 17, "100 MB → 17 chunks")
check(c100.last!.length, 4 * MB, "last chunk 4 MB")
check(c100.map { Int64($0.length) }.reduce(0, +), Int64(100 * MB), "sum")
check(c100.dropLast().allSatisfy { $0.length == 6 * MB }, true, "full chunks")
check(c100[1].offset, Int64(6 * MB), "offset 2")
check(LibraryUpload.chunks(total: Int64(12 * MB)).count, 2, "exact multiple")
check(LibraryUpload.chunks(total: 0).count, 0, "empty")
// مصدر البيانات
let d = Data((0..<20).map { UInt8($0) })
check(try! LibraryUploadSource.data(d).read(offset: 15, length: 10), Data([15, 16, 17, 18, 19]), "data tail")
let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("lu-\(UUID().uuidString).bin")
try! d.write(to: tmp)
check(LibraryUploadSource.file(tmp).size, 20, "file size")
check(try! LibraryUploadSource.file(tmp).read(offset: 4, length: 3), Data([4, 5, 6]), "file chunk")
try? FileManager.default.removeItem(at: tmp)
// النصوص
check(LibraryUpload.tooLargeText(mb: 100, arabic: true), "الملف أكبر من ١٠٠ ميغابايت — اختر ملفاً أصغر أو صورة مضغوطة.", "ar text")
check(LibraryUpload.tooLargeText(mb: 25, arabic: false).contains("25 MB"), true, "en text")
// النقطة والترويسة
check(LibraryUpload.resumableEndpoint(projectURL: URL(string: "https://poxyxsgvzwmnmewytsiw.supabase.co")!).absoluteString,
      "https://poxyxsgvzwmnmewytsiw.storage.supabase.co/storage/v1/upload/resumable", "endpoint")
check(LibraryUpload.resumableEndpoint(projectURL: URL(string: "http://localhost:54321")!).absoluteString,
      "http://localhost:54321/storage/v1/upload/resumable", "endpoint local")
check(LibraryUpload.uploadMetadata(bucket: "family-archive", objectName: "a/b.pdf", contentType: "application/pdf"),
      "bucketName ZmFtaWx5LWFyY2hpdmU=,objectName YS9iLnBkZg==,contentType YXBwbGljYXRpb24vcGRm,cacheControl MzYwMA==", "metadata")
print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
