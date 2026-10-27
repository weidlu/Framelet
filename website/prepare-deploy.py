"""Prepare a public-only asset directory and verify the notarized download hash."""
from pathlib import Path
import hashlib
import json
import shutil

source = Path(__file__).resolve().parent
project = source.parent
target = project / 'dist' / 'website'
if target.exists():
    shutil.rmtree(target)
target.mkdir(parents=True)
for name in ('index.html', 'privacy.html', 'releases.html', 'release.json'):
    shutil.copy2(source / name, target / name)
shutil.copytree(source / 'assets', target / 'assets')
metadata = json.loads((source / 'release.json').read_text())
if metadata['available']:
    assert metadata['notarized'] is True
    download = target / 'downloads'
    download.mkdir()
    # Preserve links for older publicly released versions. Refuse to deploy if
    # any expected package is missing or does not match its recorded checksum.
    for release in [metadata, *metadata.get('previousReleases', [])]:
        package = project / 'dist' / release['fileName']
        digest = hashlib.sha256(package.read_bytes()).hexdigest()
        assert digest == release['sha256'], f'Package hash does not match metadata: {package.name}'
        shutil.copy2(package, download / package.name)
        (download / (package.name + '.sha256')).write_text(f'{digest}  {package.name}\n')
print(f'Public assets: {target} ({sum(p.is_file() for p in target.rglob("*"))} files)')
