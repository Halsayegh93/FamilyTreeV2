// Explicit stages prevent success after partial failure; the SQL manifest survives retries.
export interface DeletionFile { bucket: string; path: string }
export interface DeletionBackend {
  prepare(): Promise<DeletionFile[]>;
  remove(bucket: string, paths: string[]): Promise<void>;
  finalize(): Promise<void>;
  deleteAuth(): Promise<void>;
}
export async function deleteAccountWorkflow(backend: DeletionBackend): Promise<void> {
  const files = await backend.prepare();
  const buckets = new Map<string, Set<string>>();
  for (const file of files) {
    if (!file.bucket || !file.path) throw new Error("Invalid cleanup manifest");
    if (!buckets.has(file.bucket)) buckets.set(file.bucket, new Set());
    buckets.get(file.bucket)!.add(file.path);
  }
  for (const [bucket, paths] of buckets) {
    const list = [...paths];
    for (let i = 0; i < list.length; i += 100) await backend.remove(bucket, list.slice(i, i + 100));
  }
  await backend.finalize();
  await backend.deleteAuth();
}
