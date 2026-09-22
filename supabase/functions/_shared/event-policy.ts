export function canSendEvent(type: string, role: string | null, status: string | null): boolean {
  if (type === "join_request") return status === "pending";
  if (status !== "active") return false;
  const roles: Record<string,string[]> = {
    role_changed: ["owner"], status_changed: ["owner","admin","monitor"],
    contact_reply: ["owner","admin","monitor"],
  };
  return (roles[type] ?? []).includes(role ?? "");
}
export function withVerifiedRecipient<T extends object>(body: T, target: { full_name: string; email: string | null; phone_number: string | null }) {
  return { ...body, member_name: target.full_name, member_email: target.email, member_phone: target.phone_number };
}
