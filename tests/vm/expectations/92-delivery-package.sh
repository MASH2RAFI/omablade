#!/usr/bin/env bash
set -euo pipefail
[[ $(hostname) == omarchy-test ]] || { printf '%s\n' 'Run only in the assigned Omarchy guest' >&2; exit 1; }
[[ $# == 2 ]] || { printf '%s\n' 'usage: 92-delivery-package.sh SOURCE PAYLOAD' >&2; exit 1; }
source_root=$(realpath -e -- "$1")
payload=$(realpath -e -- "$2")
native=$payload/tools/native
as_root() { sudo -S -p '' -- "$@" <<< omarchy; }
if pacman -Q omablade-native >/dev/null 2>&1; then printf '%s\n' 'Refusing to replace an existing package fixture' >&2; exit 1; fi
work=$(mktemp -d /tmp/omablade-delivery-92.XXXXXX)
package_installed=0
trap 'if [[ $package_installed == 1 ]] && pacman -Q omablade-native >/dev/null 2>&1; then as_root pacman -R --noconfirm omablade-native; fi; rm -rf -- "$work"' EXIT
cp -a -- "$payload" "$work/private-payload"
chmod 700 "$work/private-payload"
"$source_root/packaging/build" "$work/private-payload" "$work/package"
packages=("$work/package"/*.pkg.tar.*)
[[ ${#packages[@]} == 1 ]]
package=${packages[0]}
mkdir "$work/unpacked"
bsdtar -xf "$package" -C "$work/unpacked"
"$native" verify "$work/unpacked/usr/lib/omablade"
cmp -- "$payload/payload.json" "$work/unpacked/usr/lib/omablade/payload.json"
[[ $(stat -c %a "$work/unpacked/usr/lib/omablade") == 755 ]]
jq -r '.packages[]' "$payload/packaging/runtime.json" | sort > "$work/expected-dependencies"
sed -n 's/^depend = //p' "$work/unpacked/.PKGINFO" | sort > "$work/actual-dependencies"
cmp -- "$work/expected-dependencies" "$work/actual-dependencies"
[[ ! -e $work/unpacked/.INSTALL ]]
printf 'PASS E-92-01 package preserves payload and dependencies without install scripts\n'
export HOME=$work/home XDG_DATA_HOME=$work/data XDG_CONFIG_HOME=$work/config XDG_STATE_HOME=$work/state
mkdir -p "$HOME" "$XDG_CONFIG_HOME/xdg-desktop-portal"
printf 'keep file manager\n' > "$XDG_CONFIG_HOME/mimeapps.list"
printf 'keep chooser\n' > "$XDG_CONFIG_HOME/xdg-desktop-portal/portals.conf"
"$native" install "$payload"
installation=$XDG_DATA_HOME/omablade/installation
cp -- "$installation/active/receipt.json" "$work/receipt"
package_installed=1
as_root pacman -U --noconfirm "$package"
[[ $(pacman -Qoq /usr/bin/omablade) == omablade-native && $(pacman -Qoq /usr/lib/omablade/bin/omablade) == omablade-native ]]
"/usr/lib/omablade/tools/native" verify /usr/lib/omablade
cmp -- "$payload/payload.json" /usr/lib/omablade/payload.json
printf 'PASS E-92-02 installed files have pacman ownership and original inventory\n'
/usr/bin/omablade --help > "$work/idle-launch" 2>&1
exec 8</usr/share/omablade-native/lock
flock -s 8
if as_root pacman -R --noconfirm omablade-native > "$work/busy" 2>&1; then exit 1; fi
grep -F 'Checking Omablade native runtime is idle' "$work/busy"
pacman -Q omablade-native
flock -u 8
exec 8<&-
printf 'PASS E-92-05 package preflight refuses a held runtime lock\n'
mkdir "$work/hooks"
cat > "$work/check-launch" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ -e $(pacman-conf DBPath)/db.lck ]]
if runuser -u omarchy -- /usr/bin/omablade --help > "$1" 2>&1; then exit 1; fi
grep -Fx 'omablade: package database is unavailable or busy; retry after pacman finishes' "$1" || { cat "$1"; exit 1; }
EOF
chmod 755 "$work/check-launch"
cat > "$work/hooks/zz-omablade-launch-check.hook" <<EOF
[Trigger]
Operation = Upgrade
Operation = Remove
Type = Package
Target = omablade-native
[Action]
Description = Attempting an Omablade launch after idle preflight...
When = PreTransaction
Exec = $work/check-launch $work/transaction-launch
AbortOnFail
EOF
as_root pacman -U --noconfirm --hookdir "$work/hooks" "$package"
cmp -- "$payload/payload.json" /usr/lib/omablade/payload.json
printf 'PASS E-92-06 package upgrade excludes a launch after idle preflight\n'
if "$native" install "$payload" > "$work/collision" 2>&1; then exit 1; fi
if "$native" remove > "$work/remove-collision" 2>&1; then exit 1; fi
grep -F 'package-owned installation (omablade-native): use pacman' "$work/remove-collision"
grep -F 'package-owned installation (omablade-native): use pacman' "$work/collision"
cmp -- "$work/receipt" "$installation/active/receipt.json"
"$native" verify /usr/lib/omablade
[[ -L $HOME/.local/bin/omablade && $(readlink "$HOME/.local/bin/omablade") == "$installation/launcher" ]]
printf 'PASS E-92-03 direct update refuses package collision without changing either installation\n'
as_root pacman -R --noconfirm --hookdir "$work/hooks" omablade-native
package_installed=0
[[ ! -e /usr/bin/omablade && ! -e /usr/bin/omablade-bin && ! -e /usr/lib/omablade ]]
"$native" status
cmp -- "$work/receipt" "$installation/active/receipt.json"
[[ $(cat "$XDG_CONFIG_HOME/mimeapps.list") == 'keep file manager' && $(cat "$XDG_CONFIG_HOME/xdg-desktop-portal/portals.conf") == 'keep chooser' ]]
printf 'PASS E-92-04 package removal excludes new launch and preserves direct installation and personal defaults\n'
sha256sum "$package" "$payload/payload.json"
