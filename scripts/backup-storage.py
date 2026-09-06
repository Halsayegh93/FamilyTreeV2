#!/usr/bin/env python3
"""Read-only Storage backup with size/hash verification; never writes to Supabase."""
import argparse, datetime, hashlib, json, os, pathlib, subprocess, sys
import urllib.request, urllib.parse, urllib.error
import time
import shutil, collections

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
    query = "select o.bucket_id,o.name,o.metadata,o.owner_id,b.public as bucket_public from storage.objects o join storage.buckets b on b.id=o.bucket_id order by o.bucket_id,o.name"
    before = json.loads(run(['db','query','--linked',query,'--output','json']))['rows']
    (dest/'storage-manifest.json').write_text(json.dumps(before, ensure_ascii=False, indent=2))
    # Validate all paths before passing object names to a download tool.
    for row in before:
        relative = pathlib.PurePosixPath(row['bucket_id']) / row['name']
        if relative.is_absolute() or '..' in relative.parts: raise RuntimeError('Unsafe storage path')
    # macOS commonly uses a case-insensitive filesystem; Storage keys are case-sensitive.
    # Hash the full key for disk paths so UUID.jpg and uuid.jpg never overwrite each other.
    def object_path(row):
        key = row['bucket_id']+'/'+row['name']
        return dest/'blobs'/hashlib.sha256(key.encode()).hexdigest()
    folded = collections.Counter((row['bucket_id']+'/'+row['name']).casefold() for row in before)
    (dest/'object-paths.json').write_text(json.dumps({row['bucket_id']+'/'+row['name']:str(object_path(row).relative_to(dest)) for row in before},indent=2))
    # Download individual keys so a missing legacy object does not abort its bucket.
    download_failures = {}
    def download(row):
        target = object_path(row)
        target.parent.mkdir(parents=True, exist_ok=True)
        expected = (row['metadata'] or {}).get('size')
        legacy = dest/'objects'/row['bucket_id']/row['name']
        if args.resume and not target.exists() and folded[(row['bucket_id']+'/'+row['name']).casefold()] == 1 and legacy.is_file() and expected is not None and legacy.stat().st_size == int(expected):
            shutil.copyfile(legacy,target)
        if args.resume and target.is_file() and (expected is None or target.stat().st_size == int(expected)): return
        # Public reads support legacy Unicode keys that the CLI's authenticated
        # download route rejects. Never use this route for a private bucket.
        if row['bucket_public']:
            url = 'https://poxyxsgvzwmnmewytsiw.supabase.co/storage/v1/object/public/' + urllib.parse.quote(row['bucket_id']+'/'+row['name'],safe='/') + '?backup=' + str(time.time_ns())
            try:
                with urllib.request.urlopen(urllib.request.Request(url, headers={"Cache-Control":"no-cache"}),timeout=45) as response:
                    with open(target,'wb') as file:
                        while True:
                            chunk=response.read(1024*1024)
                            if not chunk: break
                            file.write(chunk)
                return
            except urllib.error.HTTPError as error:
                error_body = error.read().decode(errors='replace')
                download_failures[row['bucket_id']+'/'+row['name']] = 'invalid_legacy_key' if 'InvalidKey' in error_body else ('not_found' if 'NoSuchKey' in error_body or error.code == 404 else 'download_failed')
                return
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
        file = object_path(row)
        if not file.is_file() or str(relative) in download_failures:
            missing.append(str(relative))
            continue
        expected = (row['metadata'] or {}).get('size')
        if expected is not None and file.stat().st_size != int(expected):
            missing.append(str(relative))
            download_failures[str(relative)] = 'size_mismatch'
            continue
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
    obsolete = dest/('INCOMPLETE.json' if not missing else 'COMPLETE.json')
    if obsolete.exists(): obsolete.unlink()
    (dest/marker).write_text(json.dumps({'files':len(hashes),'verified_at':datetime.datetime.now(datetime.timezone.utc).isoformat()}))
    print(json.dumps({'files':len(hashes),'verified':not missing,'missing':len(missing),'destination':str(dest)}))
    if missing: raise SystemExit(2)

if __name__ == '__main__':
    main()
