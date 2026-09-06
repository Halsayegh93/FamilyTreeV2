export type SavedRequest = { id: string; requester_id: string | null; member_id: string | null; request_type: string; status: string };
export function ownsPendingRequest(row: SavedRequest | null, profileId: string): boolean {
  return !!row && row.status === "pending" && (row.requester_id ?? row.member_id) === profileId;
}
export const adminRoles = ["owner", "admin", "monitor", "supervisor"];
export function requestTitle(type: string): string {
  const labels: Record<string, string> = {
    join_request: "طلب انضمام جديد", link_request: "طلب ربط حساب", tree_edit: "طلب تعديل الشجرة",
    phone_change: "طلب تغيير الهاتف", name_change: "طلب تغيير الاسم", deceased_report: "بلاغ وفاة",
    photo_suggestion: "اقتراح صورة", content_report: "بلاغ محتوى", child_add: "طلب إضافة ابن", news_report: "بلاغ خبر",
  };
  return labels[type] ?? "طلب جديد للإدارة";
}
