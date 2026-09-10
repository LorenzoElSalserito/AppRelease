#!/usr/bin/env bash
#
# build-repo.sh — Builds a signed APT + DNF/YUM repository from a directory of
# packages and lays out a static site ready for GitHub Pages.
#
# Inputs (environment variables):
#   ASSETS_DIR   Directory containing the downloaded release assets. Default: assets
#   SITE_DIR     Output directory for the static site.            Default: _site
#   BASE_URL     Public base URL of the site, no trailing slash.  Required.
#   GPG_KEY_ID   Fingerprint or key id used for signing.          Required.
#   GPG_PASSPHRASE_FILE  Optional file holding the key passphrase.
#   REPO_NAME    Human readable repository name.                  Default: AppRelease
#   APT_SUITE    APT suite/codename.                              Default: stable
#   APT_COMPONENT APT component.                                  Default: main
#
set -euo pipefail

ASSETS_DIR="${ASSETS_DIR:-assets}"
SITE_DIR="${SITE_DIR:-_site}"
REPO_NAME="${REPO_NAME:-AppRelease}"
APT_SUITE="${APT_SUITE:-stable}"
APT_COMPONENT="${APT_COMPONENT:-main}"
: "${BASE_URL:?BASE_URL must be set}"
: "${GPG_KEY_ID:?GPG_KEY_ID must be set}"

BASE_URL="${BASE_URL%/}"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

# ---------------------------------------------------------------------------
# GPG helpers
# ---------------------------------------------------------------------------
gpg_args=(--batch --yes --no-tty --armor --local-user "$GPG_KEY_ID")
have_passphrase=0
if [[ -n "${GPG_PASSPHRASE_FILE:-}" && -s "${GPG_PASSPHRASE_FILE:-}" ]]; then
  have_passphrase=1
  gpg_args+=(--pinentry-mode loopback --passphrase-file "$GPG_PASSPHRASE_FILE")
fi

gpg_sign() { gpg "${gpg_args[@]}" "$@"; }

# `rpmsign` drives gpg on its own and offers no way to hand it a passphrase, so
# when the key is protected we cache the passphrase in gpg-agent up front. This
# touches the gpg-agent configuration, hence it only runs when a passphrase file
# was explicitly provided.
preset_passphrase_in_agent() {
  (( have_passphrase )) || return 0

  local home="${GNUPGHOME:-$HOME/.gnupg}"
  local conf="$home/gpg-agent.conf"
  local preset_bin line
  mkdir -p "$home"; chmod 700 "$home"
  touch "$conf"

  for line in allow-loopback-pinentry allow-preset-passphrase \
              "default-cache-ttl 34560000" "max-cache-ttl 34560000"; do
    grep -qxF "$line" "$conf" || printf '%s\n' "$line" >> "$conf"
  done

  gpgconf --kill gpg-agent >/dev/null 2>&1 || true
  gpgconf --launch gpg-agent >/dev/null 2>&1 || true

  preset_bin=$(command -v gpg-preset-passphrase \
    || echo /usr/lib/gnupg/gpg-preset-passphrase)
  if [[ ! -x "$preset_bin" ]]; then
    log "WARNING: gpg-preset-passphrase not found; RPM signing may fail"
    return 0
  fi

  local grip
  while read -r grip; do
    [[ -n "$grip" ]] || continue
    "$preset_bin" --preset --passphrase "$(cat "$GPG_PASSPHRASE_FILE")" "$grip" \
      || log "WARNING: could not preset passphrase for keygrip $grip"
  done < <(gpg --batch --with-colons --with-keygrip --list-secret-keys "$GPG_KEY_ID" \
           | awk -F: '/^grp:/ {print $10}')
}

# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------
rm -rf "$SITE_DIR"
mkdir -p "$SITE_DIR/deb/pool/$APT_COMPONENT" "$SITE_DIR/rpm" "$SITE_DIR/files"

log "Exporting public key"
gpg --batch --yes --armor --export "$GPG_KEY_ID" > "$SITE_DIR/public-key.asc"
# Binary copy, handy for /etc/apt/keyrings and for `rpm --import`.
gpg --batch --yes --export "$GPG_KEY_ID" > "$SITE_DIR/public-key.gpg"
if [[ ! -s "$SITE_DIR/public-key.asc" ]]; then
  echo "ERROR: exported public key is empty — is GPG_KEY_ID correct?" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Collect assets
# ---------------------------------------------------------------------------
shopt -s nullglob nocaseglob globstar

deb_count=0
for f in "$ASSETS_DIR"/**/*.deb "$ASSETS_DIR"/*.deb; do
  [[ -f "$f" ]] || continue
  cp -f "$f" "$SITE_DIR/deb/pool/$APT_COMPONENT/"
  deb_count=$((deb_count + 1))
done

rpm_count=0
for f in "$ASSETS_DIR"/**/*.rpm "$ASSETS_DIR"/*.rpm; do
  [[ -f "$f" ]] || continue
  cp -f "$f" "$SITE_DIR/rpm/"
  rpm_count=$((rpm_count + 1))
done

# Everything else (AppImage, tarballs, checksums, ...) is published verbatim,
# preserving the release tag it came from.
other_count=0
while IFS= read -r -d '' f; do
  rel="${f#"$ASSETS_DIR"/}"
  case "${rel,,}" in
    *.deb|*.rpm) continue ;;
  esac
  mkdir -p "$SITE_DIR/files/$(dirname "$rel")"
  cp -f "$f" "$SITE_DIR/files/$rel"
  other_count=$((other_count + 1))
done < <(find "$ASSETS_DIR" -type f -print0 2>/dev/null || true)

shopt -u nocaseglob globstar

log "Collected: ${deb_count} deb, ${rpm_count} rpm, ${other_count} other file(s)"

# ---------------------------------------------------------------------------
# APT repository
# ---------------------------------------------------------------------------
build_apt() {
  local root="$SITE_DIR/deb"
  local dist_dir="$root/dists/$APT_SUITE"

  if (( deb_count == 0 )); then
    log "No .deb packages — skipping APT index"
    return 0
  fi

  log "Building APT index"
  mkdir -p "$dist_dir/$APT_COMPONENT"

  local all_packages
  all_packages="$(mktemp)"
  ( cd "$root" && apt-ftparchive packages "pool/$APT_COMPONENT" ) > "$all_packages"

  # Split the flat Packages file per architecture. Packages marked
  # `Architecture: all` are replicated into every concrete architecture index so
  # that clients always see them, regardless of their APT version.
  local arch_list
  arch_list="$(python3 - "$all_packages" "$dist_dir" "$APT_COMPONENT" <<'PY'
import os, sys

packages_file, dist_dir, component = sys.argv[1], sys.argv[2], sys.argv[3]

with open(packages_file, "r", encoding="utf-8") as fh:
    raw = fh.read()

stanzas = [s for s in raw.split("\n\n") if s.strip()]

def arch_of(stanza):
    for line in stanza.splitlines():
        if line.lower().startswith("architecture:"):
            return line.split(":", 1)[1].strip()
    return "all"

by_arch = {}
for stanza in stanzas:
    by_arch.setdefault(arch_of(stanza), []).append(stanza)

concrete = sorted(a for a in by_arch if a != "all")
if not concrete:
    concrete = ["all"]

for arch in concrete:
    entries = list(by_arch.get(arch, []))
    if arch != "all":
        entries += by_arch.get("all", [])
    target = os.path.join(dist_dir, component, "binary-" + arch)
    os.makedirs(target, exist_ok=True)
    with open(os.path.join(target, "Packages"), "w", encoding="utf-8") as fh:
        for stanza in entries:
            fh.write(stanza.rstrip("\n") + "\n\n")

print(" ".join(concrete))
PY
)"
  rm -f "$all_packages"

  log "Architectures: $arch_list"

  local arch
  for arch in $arch_list; do
    local bindir="$dist_dir/$APT_COMPONENT/binary-$arch"
    gzip -9 -k -f "$bindir/Packages"
    xz -9 -k -f "$bindir/Packages" 2>/dev/null || true
    # Minimal per-component Release file, required by strict APT clients.
    cat > "$bindir/Release" <<EOF
Archive: $APT_SUITE
Component: $APT_COMPONENT
Origin: $REPO_NAME
Label: $REPO_NAME
Architecture: $arch
EOF
  done

  rm -f "$dist_dir/Release" "$dist_dir/Release.gpg" "$dist_dir/InRelease"
  ( cd "$root" && apt-ftparchive \
      -o "APT::FTPArchive::Release::Origin=$REPO_NAME" \
      -o "APT::FTPArchive::Release::Label=$REPO_NAME" \
      -o "APT::FTPArchive::Release::Suite=$APT_SUITE" \
      -o "APT::FTPArchive::Release::Codename=$APT_SUITE" \
      -o "APT::FTPArchive::Release::Architectures=$arch_list" \
      -o "APT::FTPArchive::Release::Components=$APT_COMPONENT" \
      -o "APT::FTPArchive::Release::Description=$REPO_NAME package repository" \
      release "dists/$APT_SUITE" ) > "$dist_dir/Release"

  log "Signing APT Release"
  gpg_sign --detach-sign --output "$dist_dir/Release.gpg" "$dist_dir/Release"
  gpg_sign --clearsign  --output "$dist_dir/InRelease"    "$dist_dir/Release"
}

# ---------------------------------------------------------------------------
# RPM repository
# ---------------------------------------------------------------------------
build_rpm() {
  local root="$SITE_DIR/rpm"

  if (( rpm_count == 0 )); then
    log "No .rpm packages — skipping DNF index"
    return 0
  fi

  log "Signing RPM packages"
  preset_passphrase_in_agent

  # Macros are passed on the command line so that no state is written to
  # $HOME/.rpmmacros; `--addsign` replaces any pre-existing signature, which
  # makes re-running the build safe.
  local f
  for f in "$root"/*.rpm; do
    [[ -f "$f" ]] || continue
    rpmsign \
      --define "_signature gpg" \
      --define "_gpg_name $GPG_KEY_ID" \
      --define "_gpg_path ${GNUPGHOME:-$HOME/.gnupg}" \
      --addsign "$f" >/dev/null
  done

  log "Building DNF metadata"
  createrepo_c --update --database "$root"

  log "Signing repomd.xml"
  rm -f "$root/repodata/repomd.xml.asc"
  gpg_sign --detach-sign --output "$root/repodata/repomd.xml.asc" "$root/repodata/repomd.xml"
}

build_apt
build_rpm

# ---------------------------------------------------------------------------
# Client configuration snippets
# ---------------------------------------------------------------------------
log "Writing client configuration files"

# deb822 sources file (Debian 12+/Ubuntu 22.04+ and any modern APT).
cat > "$SITE_DIR/apprelease.sources" <<EOF
Types: deb
URIs: $BASE_URL/deb
Suites: $APT_SUITE
Components: $APT_COMPONENT
Signed-By: /etc/apt/keyrings/$REPO_NAME.asc
EOF

# One-line legacy format, for older APT.
cat > "$SITE_DIR/apprelease.list" <<EOF
deb [signed-by=/etc/apt/keyrings/$REPO_NAME.asc] $BASE_URL/deb $APT_SUITE $APT_COMPONENT
EOF

cat > "$SITE_DIR/apprelease.repo" <<EOF
[$REPO_NAME]
name=$REPO_NAME
baseurl=$BASE_URL/rpm
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=$BASE_URL/public-key.asc
EOF

# ---------------------------------------------------------------------------
# Landing page
# ---------------------------------------------------------------------------
KEY_FPR="$(gpg --batch --with-colons --fingerprint "$GPG_KEY_ID" 2>/dev/null \
  | awk -F: '/^fpr:/ {print $10; exit}')"
BUILT_AT="$(date -u '+%Y-%m-%d %H:%M UTC')"

python3 - "$SITE_DIR" "$BASE_URL" "$REPO_NAME" "$APT_SUITE" "$APT_COMPONENT" \
         "${KEY_FPR:-unknown}" "$BUILT_AT" <<'PY'
import html, os, sys

site, base, name, suite, component, fpr, built = sys.argv[1:8]

def listing(subdir, exts):
    root = os.path.join(site, subdir)
    out = []
    for dirpath, _dirnames, filenames in os.walk(root):
        for fn in sorted(filenames):
            if exts and not fn.lower().endswith(exts):
                continue
            full = os.path.join(dirpath, fn)
            rel = os.path.relpath(full, site)
            size = os.path.getsize(full)
            out.append((rel, fn, size))
    return sorted(out)

def human(n):
    for unit in ("B", "KiB", "MiB", "GiB"):
        if n < 1024 or unit == "GiB":
            return f"{n:.0f} {unit}" if unit == "B" else f"{n:.1f} {unit}"
        n /= 1024

def table(rows):
    if not rows:
        return "<p class='empty'>Nessun file pubblicato.</p>"
    body = "\n".join(
        f"<tr><td><a href='{html.escape(rel)}'>{html.escape(fn)}</a></td>"
        f"<td class='num'>{human(size)}</td></tr>"
        for rel, fn, size in rows
    )
    return f"<table><thead><tr><th>File</th><th class='num'>Dimensione</th></tr></thead><tbody>{body}</tbody></table>"

debs = listing("deb/pool", (".deb",))
rpms = listing("rpm", (".rpm",))
others = listing("files", None)

fpr_pretty = " ".join(fpr[i:i+4] for i in range(0, len(fpr), 4)) if fpr != "unknown" else fpr

page = f"""<!doctype html>
<html lang="it">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(name)} — repository pacchetti</title>
<style>
  :root {{ color-scheme: light dark; --fg:#1a1a1a; --bg:#fbfbfa; --mut:#666; --bd:#e0e0dc; --acc:#b45309; }}
  @media (prefers-color-scheme: dark) {{
    :root {{ --fg:#e8e8e6; --bg:#1a1a19; --mut:#a0a09c; --bd:#33332f; --acc:#f0a350; }}
  }}
  * {{ box-sizing: border-box; }}
  body {{ margin:0; padding:2rem 1rem 4rem; background:var(--bg); color:var(--fg);
         font:16px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif; }}
  main {{ max-width: 52rem; margin: 0 auto; }}
  h1 {{ font-size:1.9rem; margin:0 0 .25rem; letter-spacing:-.02em; }}
  h2 {{ font-size:1.2rem; margin:2.5rem 0 .75rem; padding-bottom:.35rem; border-bottom:1px solid var(--bd); }}
  p.sub {{ color:var(--mut); margin:0 0 2rem; }}
  pre {{ background:rgba(127,127,127,.10); border:1px solid var(--bd); border-radius:8px;
         padding:1rem; overflow-x:auto; font-size:.85rem; line-height:1.5; }}
  code {{ font-family: ui-monospace,SFMono-Regular,Menlo,monospace; }}
  table {{ width:100%; border-collapse:collapse; font-size:.9rem; }}
  th,td {{ text-align:left; padding:.45rem .6rem; border-bottom:1px solid var(--bd); }}
  th {{ color:var(--mut); font-weight:600; font-size:.78rem; text-transform:uppercase; letter-spacing:.04em; }}
  .num {{ text-align:right; white-space:nowrap; color:var(--mut); }}
  a {{ color:var(--acc); }}
  .empty {{ color:var(--mut); font-style:italic; }}
  footer {{ margin-top:3rem; color:var(--mut); font-size:.82rem; border-top:1px solid var(--bd); padding-top:1rem; }}
</style>
</head>
<body>
<main>
  <h1>{html.escape(name)}</h1>
  <p class="sub">Repository APT e DNF firmato GPG. Aggiungilo alla tua distribuzione e i pacchetti si aggiorneranno con il normale aggiornamento di sistema.</p>

  <h2>Debian / Ubuntu / Linux Mint (APT)</h2>
<pre><code>sudo install -d -m 0755 /etc/apt/keyrings
sudo curl -fsSL {base}/public-key.asc -o /etc/apt/keyrings/{name}.asc
sudo curl -fsSL {base}/apprelease.sources -o /etc/apt/sources.list.d/{name}.sources
sudo apt update</code></pre>

  <h2>Fedora / RHEL / CentOS (DNF)</h2>
<pre><code>sudo curl -fsSL {base}/apprelease.repo -o /etc/yum.repos.d/{name}.repo
sudo rpm --import {base}/public-key.asc
sudo dnf makecache</code></pre>

  <h2>openSUSE (zypper)</h2>
<pre><code>sudo rpm --import {base}/public-key.asc
sudo zypper addrepo --gpgcheck --refresh {base}/rpm {name}
sudo zypper refresh</code></pre>

  <h2>Pacchetti .deb</h2>
  {table(debs)}

  <h2>Pacchetti .rpm</h2>
  {table(rpms)}

  <h2>Altri file (AppImage, archivi, checksum)</h2>
  {table(others)}

  <footer>
    Chiave di firma: <code>{html.escape(fpr_pretty)}</code><br>
    <a href="public-key.asc">public-key.asc</a> ·
    <a href="apprelease.sources">apprelease.sources</a> ·
    <a href="apprelease.repo">apprelease.repo</a><br>
    Indice generato il {html.escape(built)}.
  </footer>
</main>
</body>
</html>
"""

with open(os.path.join(site, "index.html"), "w", encoding="utf-8") as fh:
    fh.write(page)
PY

# Prevent Jekyll from stripping directories that begin with an underscore.
touch "$SITE_DIR/.nojekyll"

log "Site ready in $SITE_DIR"
