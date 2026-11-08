#!/usr/bin/env python3
"""Deterministic selective source packs. Trust release.json through your release channel.

Build: release-packs.py build --version v1.2.3 --output /tmp/packs
Stage: release-packs.py install --manifest /tmp/packs/release.json \
       --pack /tmp/packs/afterburn-v1.2.3-base.tar.gz --destination /tmp/theme
Install selected base-live / edition-NAME packs the same way, then use the existing
installer from the staged tree. This tool does not activate themes or run code.
"""
import argparse
import gzip
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parents[1]
LIVE = {'.mp4', '.webm', '.mkv', '.mov'}
ROOT_FILES = {'colors.toml', 'hyprland.lua', 'icons.theme', 'preview.png', 'preview-unlock.png', 'unlock.png', 'LICENSE', 'README.md'}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def encoded(value):
    return (json.dumps(value, indent=2, sort_keys=True) + '\n').encode()


def safe_name(name):
    path = PurePosixPath(name)
    if not name or path.is_absolute() or '\\' in name or any(p in {'', '.', '..'} for p in name.split('/')):
        raise ValueError(f'unsafe member: {name!r}')
    return path


def make_pack(source, paths, output):
    contents = {}
    for path in sorted(paths):
        name = path.relative_to(source).as_posix()
        safe_name(name)
        if path.is_symlink() or not path.is_file():
            raise ValueError(f'not a regular source file: {name}')
        contents[name] = (path.read_bytes(), 0o755 if path.stat().st_mode & 0o111 else 0o644)
    manifest = {'schema': 1, 'files': {name: {'sha256': digest(body), 'mode': mode} for name, (body, mode) in contents.items()}}
    contents['MANIFEST.json'] = (encoded(manifest), 0o644)
    # Both gzip and tar headers have fixed timestamps, owners and modes.
    with output.open('wb') as raw, gzip.GzipFile(filename='', mode='wb', fileobj=raw, mtime=0, compresslevel=9) as gz, tarfile.open(fileobj=gz, mode='w', format=tarfile.USTAR_FORMAT) as archive:
        for name, (body, mode) in sorted(contents.items()):
            info = tarfile.TarInfo(name)
            info.size, info.mode, info.mtime = len(body), mode, 0
            archive.addfile(info, io.BytesIO(body))


def build(args):
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*', args.version):
        raise ValueError('version must contain only letters, digits, dot, dash or underscore')
    source, output = args.source.resolve(), args.output.resolve()
    if output == source or source in output.parents:
        raise ValueError('output must be outside source tree')
    groups = {'base': [], 'base-live': []}
    for path in sorted(source.iterdir()):
        if path.name in ROOT_FILES or path.name in {'backgrounds', 'extras'}:
            candidates = [path] if path.is_file() or path.is_symlink() else sorted(path.rglob('*'))
            for item in candidates:
                if item.is_symlink():
                    raise ValueError(f'source symlink: {item}')
                if item.is_file():
                    groups['base-live' if item.suffix.lower() in LIVE else 'base'].append(item)
    editions = source / '.editions'
    if editions.is_symlink():
        raise ValueError('source editions symlink')
    if editions.exists():
        for edition in sorted(editions.iterdir()):
            if edition.is_symlink():
                raise ValueError('source edition symlink')
            if not edition.is_dir():
                continue
            if not re.fullmatch(r'[a-z][a-z0-9-]*', edition.name):
                raise ValueError('unsafe edition name')
            entries = sorted(edition.rglob('*'))
            if any(p.is_symlink() for p in entries):
                raise ValueError('source edition contains symlink')
            groups[f'edition-{edition.name}'] = [p for p in entries if p.is_file()]
    output.mkdir(parents=True, exist_ok=True)
    candidate = args.source_commit
    if candidate is None:
        git = subprocess.run(['git', '-C', str(source), 'rev-parse', 'HEAD'], capture_output=True, text=True)
        candidate = git.stdout.strip() if git.returncode == 0 else None
    if candidate is not None and not re.fullmatch(r'[0-9a-f]{40}', candidate):
        raise ValueError('source commit must be a full lowercase Git SHA')
    dirty = subprocess.run(['git', '-C', str(source), 'status', '--porcelain'], capture_output=True, text=True)
    release = {'schema': 1, 'version': args.version, 'sourceCommit': candidate,
               'sourceDirty': bool(dirty.stdout.strip()) if dirty.returncode == 0 else None, 'packs': {}}
    for name, paths in groups.items():
        archive = output / f'afterburn-{args.version}-{name}.tar.gz'
        make_pack(source, paths, archive)
        release['packs'][archive.name] = {'sha256': digest(archive.read_bytes()), 'bytes': archive.stat().st_size}
    helper = output / 'afterburn-pack-tool.py'
    helper.write_bytes(Path(__file__).read_bytes())
    release['bootstrap'] = {'name': helper.name, 'sha256': digest(helper.read_bytes()), 'bytes': helper.stat().st_size}
    installer = output / 'install-afterburn.sh'
    installer.write_bytes(Path(__file__).with_name('install-release.sh').read_bytes())
    installer.chmod(0o755)
    release['installer'] = {'name': installer.name, 'sha256': digest(installer.read_bytes()), 'bytes': installer.stat().st_size}
    (output / 'release.json').write_bytes(encoded(release))
    sums = {name: record['sha256'] for name, record in release['packs'].items()}
    sums[helper.name] = release['bootstrap']['sha256']
    sums[installer.name] = release['installer']['sha256']
    (output / 'SHA256SUMS').write_text(''.join(f'{sha}  {name}\n' for name, sha in sorted(sums.items())))
    print(json.dumps(release, indent=2))


def verify_destination(path):
    # Check every component, including an explicitly supplied symlink destination.
    for parent in [path, *path.parents]:
        if parent.is_symlink():
            raise ValueError(f'destination symlink: {parent}')
        if parent.exists() and parent != path and not parent.is_dir():
            raise ValueError(f'destination parent is not directory: {parent}')


def install(args):
    release = json.loads(args.manifest.read_text())
    version = release.get('version', '')
    if release.get('schema') != 1 or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*', version):
        raise ValueError('unsupported release manifest')
    if not re.fullmatch(r'afterburn-' + re.escape(version) + r'-(?:base|base-live|edition-[a-z][a-z0-9-]*)\.tar\.gz', args.pack.name):
        raise ValueError('pack must have a versioned release name')
    record = release['packs'].get(args.pack.name)
    data = args.pack.read_bytes()
    if not record or digest(data) != record['sha256']:
        raise ValueError('archive SHA256 mismatch or unlisted pack')
    files = {}
    with tarfile.open(fileobj=io.BytesIO(data), mode='r:gz') as archive:
        for member in archive:
            safe_name(member.name)
            if not member.isfile() or member.name in files:
                raise ValueError('nonregular or duplicate archive member')
            if member.mode not in {0o644, 0o755}:
                raise ValueError('unsupported archive permissions')
            files[member.name] = (archive.extractfile(member).read(), member.mode)
    if 'MANIFEST.json' not in files:
        raise ValueError('missing file manifest')
    manifest = json.loads(files.pop('MANIFEST.json')[0])
    records = manifest.get('files', {})
    if manifest.get('schema') != 1 or set(records) != set(files):
        raise ValueError('file manifest membership mismatch')
    for name, (body, mode) in files.items():
        if records[name] != {'sha256': digest(body), 'mode': mode}:
            raise ValueError(f'file SHA256 or mode mismatch: {name}')
    for name in files:
        if any(parent.as_posix() in files for parent in PurePosixPath(name).parents):
            raise ValueError(f'archive file/parent collision: {name}')
    dest = Path(os.path.abspath(args.destination))
    verify_destination(dest)
    # Complete all verification before creating any destination content.
    for name, (body, mode) in files.items():
        target = dest / name
        verify_destination(target)
        if target.exists() and (not target.is_file() or target.read_bytes() != body or target.stat().st_mode & 0o777 != mode):
            raise ValueError(f'existing content collision (preserved): {name}')
    for name, (body, mode) in files.items():
        target = dest / name
        verify_destination(target)
        if target.exists():
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        # Exclusive creation also refuses a file/link introduced since preflight.
        fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, mode)
        with os.fdopen(fd, 'wb') as stream:
            stream.write(body)
            os.fchmod(stream.fileno(), mode)
    print(f'verified {args.pack.name}: {len(files)} files staged at {dest}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    builder = sub.add_parser('build')
    builder.add_argument('--source', type=Path, default=ROOT)
    builder.add_argument('--output', type=Path, required=True)
    builder.add_argument('--version', required=True)
    builder.add_argument('--source-commit', help='full candidate SHA (defaults to source Git HEAD)')
    installer = sub.add_parser('install')
    installer.add_argument('--manifest', type=Path, required=True)
    installer.add_argument('--pack', type=Path, required=True)
    installer.add_argument('--destination', type=Path, required=True)
    args = parser.parse_args()
    try:
        (build if args.command == 'build' else install)(args)
    except (OSError, ValueError, KeyError, TypeError, tarfile.TarError) as error:
        parser.exit(1, f'release-packs: {error}\n')

if __name__ == '__main__':
    main()
