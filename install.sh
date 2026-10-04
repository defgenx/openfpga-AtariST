#!/usr/bin/env bash
#
# install.sh - install the Atari ST core onto an Analogue Pocket microSD card.
#
#   ./install.sh                 find the SD card, then install
#   ./install.sh --sd /Volumes/POCKET
#   ./install.sh --dry-run       show what would be copied, change nothing
#
# Files already on the card are NEVER replaced: they are skipped and listed.
# To update a file, delete it from the card first and run the script again.
#
set -euo pipefail

REPO="defgenx/openfpga-AtariST"
CORE="defgenx.AtariST"
HERE="$(cd "$(dirname "$0")" && pwd)"

SD=""
DRY_RUN=0
while [ $# -gt 0 ]; do
	case "$1" in
		--sd) SD="${2:-}"; shift 2 ;;
		--sd=*) SD="${1#--sd=}"; shift ;;
		--dry-run|-n) DRY_RUN=1; shift ;;
		-h|--help) sed -n '3,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) echo "unknown option: $1 (see --help)" >&2; exit 1 ;;
	esac
done

say()  { printf '%s\n' "$*"; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 1. Files to install: local dist/ when it holds a built core, else the release
# ---------------------------------------------------------------------------

TMP=""
cleanup() { [ -n "$TMP" ] && rm -rf "$TMP"; }
trap cleanup EXIT

if [ -f "$HERE/dist/Cores/$CORE/atarist.rbf_r" ]; then
	SRC="$HERE/dist"
	say "Using the core from $SRC"
else
	command -v curl >/dev/null || die "curl is needed to download the release"
	command -v unzip >/dev/null || die "unzip is needed to unpack the release"
	TMP="$(mktemp -d)"
	# highest version among all releases, pre-releases included (/releases/latest skips those)
	url="$(curl -fsSL "https://api.github.com/repos/$REPO/releases?per_page=100" \
		| grep -o "https://[^\"]*/releases/download/v[0-9][^/\"]*/$CORE.zip" \
		| sed 's#.*/download/v\([^/]*\)/.*#\1 &#' \
		| sort -t. -k1,1n -k2,2n -k3,3n | tail -1 | cut -d' ' -f2)" || true
	[ -n "$url" ] || die "could not find a release of $REPO"
	say "Downloading $url"
	curl -fL --progress-bar -o "$TMP/core.zip" "$url" || die "download failed"
	unzip -q "$TMP/core.zip" -d "$TMP/core"
	SRC="$TMP/core"
fi
[ -f "$SRC/Cores/$CORE/atarist.rbf_r" ] || die "no core bitstream found in $SRC"

# ---------------------------------------------------------------------------
# 2. Find the SD card
# ---------------------------------------------------------------------------

is_pocket_card() {
	# An Analogue Pocket card has at least one of these at its root
	[ -d "$1/Cores" ] || [ -d "$1/Platforms" ] || [ -d "$1/Assets" ] || [ -d "$1/System" ]
}

if [ -z "$SD" ]; then
	candidates=()
	for base in /Volumes /media/"${USER:-}" /run/media/"${USER:-}" /media /mnt; do
		[ -d "$base" ] || continue
		for v in "$base"/*; do
			[ -d "$v" ] && [ -w "$v" ] || continue
			case "$v" in "/Volumes/Macintosh HD"*|/Volumes/Recovery|/Volumes/Preboot) continue ;; esac
			candidates+=("$v")
		done
	done

	pocket=()
	for v in ${candidates[@]+"${candidates[@]}"}; do is_pocket_card "$v" && pocket+=("$v"); done

	if [ ${#pocket[@]} -eq 1 ]; then
		SD="${pocket[0]}"
		say "Found Pocket SD card: $SD"
		read -r -p "Install there? [Y/n] " ok
		case "$ok" in [nN]*) die "aborted" ;; esac
	else
		list=("${pocket[@]+"${pocket[@]}"}")
		[ ${#list[@]} -eq 0 ] && list=("${candidates[@]+"${candidates[@]}"}")
		[ ${#list[@]} -eq 0 ] && die "no writable volume found - insert the SD card, or pass --sd PATH"
		[ ${#pocket[@]} -eq 0 ] && say "No card with Pocket folders found; mounted volumes:"
		[ ${#pocket[@]} -gt 1 ] && say "Several Pocket cards found:"
		i=1
		for v in "${list[@]}"; do say "  $i) $v"; i=$((i + 1)); done
		read -r -p "Number of the SD card to install to: " n
		[[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le ${#list[@]} ] || die "invalid choice"
		SD="${list[$((n - 1))]}"
	fi
fi

[ -d "$SD" ] || die "$SD is not a directory"
[ -w "$SD" ] || die "$SD is not writable"
is_pocket_card "$SD" || say "Note: $SD has no Cores/Platforms/Assets folders yet; they will be created."

# ---------------------------------------------------------------------------
# 3. Copy, never replacing anything
# ---------------------------------------------------------------------------

# macOS: -X skips extended attributes, so no ._ AppleDouble files land on the FAT card
CP=(cp)
[ "$(uname)" = "Darwin" ] && CP=(cp -X)

copied=0
skipped=()
cd "$SRC"
while IFS= read -r -d '' f; do
	rel="${f#./}"
	case "$(basename "$rel")" in .DS_Store|._*|.keep) continue ;; esac
	dst="$SD/$rel"
	if [ -e "$dst" ]; then
		skipped+=("$rel")
		continue
	fi
	if [ $DRY_RUN -eq 1 ]; then
		say "would copy  $rel"
	else
		mkdir -p "$(dirname "$dst")"
		"${CP[@]}" "$f" "$dst"
		say "copied      $rel"
	fi
	copied=$((copied + 1))
done < <(find . -type f -print0 | sort -z)

# the install guide goes along, under a name that cannot clash with Pocket files
guide="$HERE/INSTALL.md"
[ -f "$guide" ] || guide="$SRC/AtariST-INSTALL.md"
if [ -f "$guide" ] && [ "$guide" != "$SD/AtariST-INSTALL.md" ]; then
	if [ -e "$SD/AtariST-INSTALL.md" ]; then
		skipped+=("AtariST-INSTALL.md")
	elif [ $DRY_RUN -eq 1 ]; then
		say "would copy  AtariST-INSTALL.md"; copied=$((copied + 1))
	else
		"${CP[@]}" "$guide" "$SD/AtariST-INSTALL.md"; say "copied      AtariST-INSTALL.md"; copied=$((copied + 1))
	fi
fi

say ""
if [ $DRY_RUN -eq 1 ]; then say "Dry run: $copied file(s) would be copied to $SD"; else say "Copied $copied file(s) to $SD"; fi
if [ ${#skipped[@]} -gt 0 ]; then
	say "Left untouched (already on the card, not replaced): ${#skipped[@]}"
	for s in "${skipped[@]}"; do say "  - $s"; done
	case " ${skipped[*]} " in
		*"Cores/$CORE/atarist.rbf_r"*)
			say "The core itself was already installed. To update it, delete"
			say "  $SD/Cores/$CORE/  and run this script again." ;;
	esac
fi
[ $DRY_RUN -eq 1 ] && exit 0

# ---------------------------------------------------------------------------
# 4. Eject
# ---------------------------------------------------------------------------

sync
read -r -p "Eject the SD card now? [Y/n] " ej
case "$ej" in
	[nN]*) say "Remember to eject the card before removing it." ;;
	*)
		if [ "$(uname)" = "Darwin" ]; then
			diskutil eject "$SD" && say "Ejected. Put the card in the Pocket and start openFPGA -> Atari ST."
		elif command -v udisksctl >/dev/null; then
			dev="$(df --output=source "$SD" | tail -1)"
			udisksctl unmount -b "$dev" && udisksctl power-off -b "$dev" && say "Ejected."
		else
			umount "$SD" && say "Unmounted."
		fi ;;
esac
