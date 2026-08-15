# Maintainer: NightStars <nightstars@galaxistars.com>

pkgname=cursor-ai-bin
pkgver=3.16.17
pkgrel=1
pkgdesc='AI-first coding environment'
arch=('x86_64')
url="https://www.cursor.com"
license=('LicenseRef-Cursor_EULA')
install=cursor-ai-bin.install
depends=(xdg-utils ripgrep nodejs
  'gcc-libs' 'hicolor-icon-theme' 'libxkbfile')
options=(!strip !debug) # Don't break ext of VSCode
_commit=6b2afae0257df2bb5e1835f15165dc2f0de056b2
source=("https://downloads.cursor.com/production/${_commit}/linux/x64/deb/amd64/deb/cursor_${pkgver}_amd64.deb"
rg.sh)
sha512sums=('SKIP'
  'a66d01d7bffe84fc0ec7b31ca1a63e39484eff43b125ffcd5b5b2218280e24c30933bd9a49b243b83605c60e94e5e4f3e4173131f50bcaf05df52ff218c25ad5')
sha512sums[0]=d33b0269fa8ff4ac8780c1119024a84ca37cc884653aa0ae5e7f51f871ca0d85a52afa7faea441c09fd3e2695a52626521917b3dfc2f2477ac73db4563297735
noextract=(cursor_${pkgver}_amd64.deb) # avoid double tarball
_app=usr/share/cursor/resources/app
package() {
  # Keep upstream bundled runtime to avoid system-Electron mismatch issues.
  bsdtar -xOf ${noextract[0]} data.tar.xz | tar -xJf - -C "$pkgdir"
  cd "$pkgdir"
  if [[ -d usr/share/zsh/vendor-completions ]]; then
    install -d usr/share/zsh/site-functions
    cp -a usr/share/zsh/vendor-completions/. usr/share/zsh/site-functions/
    rm -rf usr/share/zsh/vendor-completions
  fi
  ln -sf /usr/bin/node ${_app}/resources/helpers/node
  install -Dm755 "${srcdir}/rg.sh" ${_app}/node_modules/@vscode/ripgrep/bin/rg
  ln -sf /usr/bin/xdg-open ${_app}/node_modules/open/xdg-open
  if [[ -f usr/share/cursor/chrome-sandbox ]]; then
    chmod 4755 usr/share/cursor/chrome-sandbox
  fi
  # Install a launcher wrapper (instead of exposing the raw Electron binary).
  # This honors cursor-flags.conf and delegates to Cursor's upstream trampoline at /usr/share/cursor/bin/cursor.
  install -Dm755 /dev/stdin usr/bin/cursor <<'EOF'
#!/bin/bash
set -euo pipefail

cursor_bin="/usr/share/cursor/bin/cursor"
fallback_bin="/usr/share/cursor/cursor"
flags_file="${XDG_CONFIG_HOME:-$HOME/.config}/cursor-flags.conf"

if [[ ! -x "$cursor_bin" ]]; then
  cursor_bin="$fallback_bin"
fi

cursor_flags=()
if [[ -f "$flags_file" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    cursor_flags+=("$line")
  done < "$flags_file"
fi

case "${1:-}" in
  agent)
    exec "$cursor_bin" "$@"
    ;;
  editor)
    shift
    ;;
esac

exec "$cursor_bin" "${cursor_flags[@]}" "$@"
EOF
}
