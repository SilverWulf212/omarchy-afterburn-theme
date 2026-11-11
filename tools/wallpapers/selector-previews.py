#!/usr/bin/env python3
"""Render theme-selector thumbnails from real default wallpapers; refresh old installs."""
import argparse
from datetime import datetime, timezone
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
ROOT = Path(__file__).resolve().parents[2]
# One folder per edition under tools/edition-extras/: that list is the only place the names live.
EDITIONS = sorted(p.parent.name for p in (ROOT/'tools/edition-extras').glob('*/edition.conf'))

def render(source, destination, backup=None):
    source, destination = Path(source), Path(destination)
    if destination.is_symlink():
        raise ValueError(f'Refusing to replace a symlink: {destination}')
    destination.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix='.afterburn-preview-', suffix='.png', dir=destination.parent)
    os.close(fd)
    temporary = Path(name)
    try:
        subprocess.run(['magick', str(source), '-resize', '1200x', '-strip',
                        '-define', 'png:exclude-chunk=tIME,date', 'PNG24:' + str(temporary)], check=True)
        exists = destination.exists()
        if exists and destination.read_bytes() == temporary.read_bytes():
            return False
        if backup is not None and exists:
            backup = Path(backup)
            backup.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(destination, backup)
        mode = stat.S_IMODE(destination.stat().st_mode) if exists else 0o644
        temporary.chmod(mode)
        os.replace(temporary, destination)
        return True
    finally:
        temporary.unlink(missing_ok=True)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    one = commands.add_parser('render')
    one.add_argument('source', type=Path)
    one.add_argument('destination', type=Path)
    commands.add_parser('build')
    installed = commands.add_parser('install', help='refresh only installed Afterburn preview.png files, with backups')
    config = Path(os.environ.get('XDG_CONFIG_HOME', Path.home()/'.config'))
    state = Path(os.environ.get('XDG_STATE_HOME', Path.home()/'.local/state'))
    installed.add_argument('--themes-home', type=Path, default=config/'omarchy/themes')
    installed.add_argument('--backup-root', type=Path, default=state/'afterburn/preview-backups')
    args = parser.parse_args()
    if args.command == 'render':
        render(args.source, args.destination)
    elif args.command == 'build':
        for theme in [ROOT, *[ROOT/'.editions'/edition for edition in EDITIONS]]:
            render(theme/'backgrounds/1-horizon.jpg', theme/'preview.png')
            print('Preview:', theme.relative_to(ROOT), flush=True)
    else:
        backup = args.backup_root / datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ')
        print('Backup root (created only for changed existing previews):', backup, flush=True)
        for name in ['afterburn', *['afterburn-'+edition for edition in EDITIONS]]:
            theme = args.themes_home/name
            source = theme/'backgrounds/1-horizon.jpg'
            if not source.is_file():
                print('Skipped (no default wallpaper):', name, flush=True)
                continue
            if (theme/'preview.png').is_symlink():
                print('Skipped (custom preview symlink):', name, flush=True)
                continue
            changed = render(source, theme/'preview.png', backup/name/'preview.png')
            print('Updated:' if changed else 'Already current:', name, flush=True)
        print('Close and reopen the theme selector. Each preview shows its installed default wallpaper.')
if __name__ == '__main__':
    main()
