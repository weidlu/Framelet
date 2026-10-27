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
    package = project / 'dist' / metadata['fileName']
    digest = hashlib.sha256(package.read_bytes()).hexdigest()
    assert digest == metadata['sha256'], 'Published package hash does not match release metadata'
    download = target / 'downloads'
    download.mkdir()
    shutil.copy2(package, download / package.name)
    (download / (package.name + '.sha256')).write_text(f'{digest}  {package.name}\n')
print(f'Public assets: {target} ({sum(p.is_file() for p in target.rglob("*"))} files)')
