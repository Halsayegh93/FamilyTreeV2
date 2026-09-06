#!/usr/bin/env python3
"""Read-only Storage backup with size/hash verification; never writes to Supabase."""
import argparse, datetime, hashlib, json, os, pathlib, subprocess, sys

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--workdir', required=True, help='Supabase CLI workdir linked to the intended project')
    parser.add_argument('--destination', required=True, help='Private directory outside the repository')
    parser.add_argument('--resume', action='store_true', help='Resume a partial backup in the same private directory')
    args = parser.parse_args()
    os.umask(0o077)
    dest = pathlib.Path(args.destination).expanduser().resolve()
    repo = pathlib.Path(__file__).resolve().parents[1]
    if dest == repo or repo in dest.parents:
        raise SystemExit('Backups must be outside the repository')
    linked = pathlib.Path(args.workdir) / 'supabase/.temp/project-ref'
    if linked.read_text().strip() != 'poxyxsgvzwmnmewytsiw':
        raise SystemExit('Workdir is not linked to the FamilyTree project')
    dest.mkdir(parents=True, exist_ok=args.resume)
    log = open(dest/'backup.log', 'a')
    def run(arguments, allow_failure=False):
        result = subprocess.run(['supabase', *arguments, '--workdir', args.workdir], capture_output=True, text=True)
        log.write(result.stdout + result.stderr); log.flush()
        if result.returncode and not allow_failure: raise RuntimeError('Supabase command failed; see private backup.log')
        return (result.returncode, result.stdout + result.stderr) if allow_failure else result.stdout
    query = "select bucket_id,name,metadata,owner_id from storage.objects order by bucket_id,name"
    before = json.loads(run(['db','query','--linked',query,'--output','json']))['rows']
    (dest/'storage-manifest.json').write_text(json.dumps(before, ensure_ascii=False, indent=2))
    # Validate all paths before passing object names to a download tool.
    for row in before:
        relative = pathlib.PurePosixPath(row['bucket_id']) / row['name']
        if relative.is_absolute() or '..' in relative.parts: raise RuntimeError('Unsafe storage path')
    # Download individual keys so a missing legacy object does not abort its bucket.
    download_failures = {}
    def download(row):
        target = dest/'objects'/row['bucket_id']/row['name']
        target.parent.mkdir(parents=True, exist_ok=True)
        expected = (row['metadata'] or {}).get('size')
        if args.resume and target.is_file() and (expected is None or target.stat().st_size == int(expected)): return
        code, output = run(['storage','cp','--linked','--experimental','ss:///'+row['bucket_id']+'/'+row['name'],str(target)], allow_failure=True)
        if code:
            download_failures[row['bucket_id']+'/'+row['name']] = 'not_found' if 'NoSuchKey' in output else 'download_failed'
    # CLI commands share a temporary database login; run serially to avoid
    # rotating that login while another command is still using it.
    for row in before: download(row)
    hashes = {}
    missing = []
    for row in before:
        relative = pathlib.PurePosixPath(row['bucket_id']) / row['name']
        if relative.is_absolute() or '..' in relative.parts: raise RuntimeError('Unsafe storage path')
        file = dest/'objects'/relative
        if not file.is_file() or str(relative) in download_failures:
            missing.append(str(relative))
            continue
        expected = (row['metadata'] or {}).get('size')
        if expected is not None and file.stat().st_size != int(expected): raise RuntimeError('Object size changed during backup')
        digest = hashlib.sha256()
        with open(file,'rb') as stream:
            for chunk in iter(lambda: stream.read(1024*1024), b''): digest.update(chunk)
        hashes[str(relative)] = digest.hexdigest()
    after = json.loads(run(['db','query','--linked',query,'--output','json']))['rows']
    if before != after: raise RuntimeError('Storage changed during backup; retry into a new directory')
    (dest/'sha256.json').write_text(json.dumps(hashes,indent=2))
    (dest/'download-failures.json').write_text(json.dumps(download_failures,indent=2))
    (dest/'missing-objects.json').write_text(json.dumps(missing,indent=2))
    marker = 'COMPLETE.json' if not missing else 'INCOMPLETE.json'
    (dest/marker).write_text(json.dumps({'files':len(hashes),'verified_at':datetime.datetime.now(datetime.timezone.utc).isoformat()}))
    print(json.dumps({'files':len(hashes),'verified':not missing,'missing':len(missing),'destination':str(dest)}))
    if missing: raise SystemExit(2)

if __name__ == '__main__':
    main()
