"""Package reviewed files only; never archive a local game or runtime directory."""
from pathlib import Path
import argparse
import hashlib
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]
FILES = [
    'VERSION', 'README.md', 'CHANGELOG.md', 'CONTRIBUTING.md', 'SECURITY.md',
    'VALIDATION.md', 'LICENSE.txt', 'INSTALL.cmd', 'UNINSTALL.cmd',
    'Install-HydroFixes.ps1', 'Uninstall-HydroFixes.ps1',
    'Setup-FasterRuntime.ps1', 'FASTER-RUNTIME.md',
    'Licenses/ReShade-LICENSE.md', 'Licenses/Bezel-NOTICE.md',
    'Tools/PatchGlide.cs', 'Tools/Build-Release.py',
    'payload/d3d11.dll', 'payload/HydroSave.dll', 'payload/bezel.png',
    'payload/ReShade.ini', 'payload/HydroBezel.ini',
    'payload/reshade-shaders/Shaders/HydroBezel.fx',
    'source/build.cmd', 'source/HydroSave.cpp', 'source/HydroSave.def',
    'source/HydroSaveCore.cpp', 'source/HydroSaveCore.h', 'source/README.md',
    'tests/HydroSaveTests.cpp', 'tests/SmallStackSmoke.cpp',
    'tests/Test-Installer.ps1', 'tests/TEST-RESULTS.md',
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir', type=Path, default=ROOT / 'dist')
    args = parser.parse_args()
    version = (ROOT / 'VERSION').read_text(encoding='ascii').strip()
    if not re.fullmatch(r'\d+\.\d+\.\d+', version):
        parser.error('VERSION must contain a stable three-part release number')
    files = sorted(FILES + [f'RELEASE-NOTES-v{version}.md'])
    if len(files) != len(set(files)):
        raise RuntimeError('Duplicate allowlisted filename')
    snapshots = {}
    for name in files:
        path = ROOT / name
        if not path.is_file() or path.is_symlink() or not path.resolve().is_relative_to(ROOT):
            raise RuntimeError('Missing or unsafe allowlisted file: ' + name)
        snapshots[name] = path.read_bytes()
    manifest = ''.join(hashlib.sha256(snapshots[name]).hexdigest() + '  ' + name + '\n'
                       for name in files).encode('utf-8')
    archive_root = 'HydroThunder-Fixes-' + version
    destination = args.output_dir.resolve() / (archive_root + '.zip')
    checksum_path = destination.with_suffix('.zip.sha256')
    if destination.exists() or checksum_path.exists():
        raise RuntimeError('Release output already exists; choose a fresh output directory')
    destination.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(destination, 'x', zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, data in list(snapshots.items()) + [('SHA256SUMS.txt', manifest)]:
            # Fixed ZIP metadata avoids local timestamps, ownership, and file modes.
            info = zipfile.ZipInfo(archive_root + '/' + name, date_time=(1980, 1, 1, 0, 0, 0))
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            archive.writestr(info, data, compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
    with zipfile.ZipFile(destination) as archive:
        expected = {archive_root + '/' + name for name in files + ['SHA256SUMS.txt']}
        if set(archive.namelist()) != expected or len(archive.namelist()) != len(expected):
            raise RuntimeError('Archive contents differ from the allowlist')
        if archive.testzip() is not None:
            raise RuntimeError('Archive integrity check failed')
        for name, data in snapshots.items():
            if archive.read(archive_root + '/' + name) != data:
                raise RuntimeError('Archived bytes differ: ' + name)
        if archive.read(archive_root + '/SHA256SUMS.txt') != manifest:
            raise RuntimeError('Archived manifest differs')
    digest = hashlib.sha256(destination.read_bytes()).hexdigest()
    with checksum_path.open('x', encoding='ascii', newline='\n') as checksum_file:
        checksum_file.write(digest + '  ' + destination.name + '\n')
    print(destination)
    print(f'Files: {len(files) + 1}; bytes: {destination.stat().st_size}')
    print('SHA256: ' + digest)


if __name__ == '__main__':
    main()
