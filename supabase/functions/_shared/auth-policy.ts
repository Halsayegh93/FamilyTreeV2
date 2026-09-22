// Pure policy shared by all service-role handlers and regression tests.
export type VerifiedUser = { id: string; app_metadata?: Record<string, unknown> };
export type ProfileIdentity = { id: string; role: string; status: string };
export type AuthOptions = { allowInactive?: boolean; allowMissingProfile?: boolean };
export function trustedProfileId(user: VerifiedUser): string {
  const linked = user.app_metadata?.profile_id;
  if (linked == null || linked === "") return user.id;
  if (typeof linked !== "string" || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(linked)) {
    throw new Error("Invalid server profile binding");
  }
  return linked;
}
export function profileAllowed(profile: ProfileIdentity | null, roles?: string[], options: AuthOptions = {}): boolean {
  if (!profile) return !!options.allowMissingProfile && !roles;
  if (!options.allowInactive && profile.status !== "active") return false;
  return !roles || roles.includes(profile.role);
}
