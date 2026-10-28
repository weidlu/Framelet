"""Validate the public pages and stage a public-only asset directory for deployment.

Checks every local link / anchor / SVG reference, the release metadata against the
notarized DMG in `dist/`, then copies only public files into `dist/website`.
"""
from pathlib import Path
from html.parser import HTMLParser
from urllib.parse import urlsplit, unquote
import hashlib
import json
import shutil

SOURCE = Path(__file__).resolve().parent
PROJECT = SOURCE.parent
TARGET = PROJECT / "dist" / "website"

PAGES = ("index.html", "privacy.html", "releases.html")


class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids = set()
        self.duplicates = []
        self.references = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if attrs.get("id"):
            if attrs["id"] in self.ids:
                self.duplicates.append(attrs["id"])
            self.ids.add(attrs["id"])
        for key in ("src", "href"):
            if attrs.get(key):
                self.references.append(attrs[key])


parsed = {}
for name in PAGES:
    page = Page()
    page.feed((SOURCE / name).read_text())
    assert not page.duplicates, f"Duplicate IDs in {name}: {page.duplicates}"
    parsed[name] = page

for name, page in parsed.items():
    for ref in page.references:
        url = urlsplit(ref)
        if url.scheme or url.netloc or ref.startswith("mailto:"):
            continue
        if url.path:
            path = unquote(url.path.lstrip("/"))
            # Packages live in the project dist/, not in the source tree.
            target = PROJECT / "dist" / path[len("downloads/"):] if path.startswith("downloads/") else SOURCE / path
            assert target.is_file(), f"Missing file: {ref} (in {name})"
            continue
        if not url.fragment:
            continue
        assert url.fragment in page.ids, f"Missing anchor: {ref} (in {name})"
    # Anchors may point into another page; verify those too.
    for ref in page.references:
        url = urlsplit(ref)
        if url.fragment and url.path in PAGES:
            other = parsed[url.path]
            assert url.fragment in other.ids, f"Missing anchor: {ref} (from {name})"

release = json.loads((SOURCE / "release.json").read_text())
landing = (SOURCE / "index.html").read_text()
assert release["version"] in landing, "Refresh the static fallback copy when changing the version."
assert release["sha256"] in landing, "The static checksum fallback does not match release.json."
assert release["size"] in landing, "The static size fallback does not match release.json."

if TARGET.exists():
    shutil.rmtree(TARGET)
TARGET.mkdir(parents=True)
for name in (*PAGES, "style.css", "app.js", "release.json"):
    shutil.copy2(SOURCE / name, TARGET / name)
shutil.copytree(SOURCE / "assets", TARGET / "assets")

if release["available"]:
    assert release["notarized"] is True, "Only notarized builds may be published."
    download = TARGET / "downloads"
    download.mkdir()
    # Keep links to older public releases working; refuse to ship a package whose
    # hash does not match its recorded checksum.
    for item in (release, *release.get("previousReleases", [])):
        package = PROJECT / "dist" / item["fileName"]
        assert package.is_file(), f"Package missing from dist/: {package.name}"
        digest = hashlib.sha256(package.read_bytes()).hexdigest()
        assert digest == item["sha256"], f"Package hash does not match metadata: {package.name}"
        shutil.copy2(package, download / package.name)
        (download / (package.name + ".sha256")).write_text(f"{digest}  {package.name}\n")

files = sum(1 for p in TARGET.rglob("*") if p.is_file())
print(f"PASS: pages, links, anchors, release metadata and DMG checksums.")
print(f"Public assets: {TARGET} ({files} files)")
