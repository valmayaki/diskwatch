#!/usr/bin/env bash
# One-shot disk health overview from diskwatch's cached index. Reads only the index,
# `df` and `diskutil` (no disk walk), so it finishes in seconds.
#   overview.sh            full overview
#   overview.sh --brief    free space, volumes, index age, top of / and ~
set -uo pipefail
command -v diskwatch >/dev/null || { echo "diskwatch not installed (expected ~/.local/bin/diskwatch)"; exit 1; }
brief=${1:-}
DB=${DISKWATCH_DATA:-$HOME/.local/share/diskwatch}/duc.db

section() { printf '\n== %s\n' "$1"; }

section "Free space (local volumes)"
vols=(/System/Volumes/Data)
while IFS= read -r v; do vols+=("$v"); done < <(mount | sed -nE 's#^/dev/[^ ]+ on (/Volumes/.*) \(apfs.*#\1#p' | grep -v Recovery)
df -h "${vols[@]}" 2>/dev/null |
  awk 'NR==1 || !seen[$NF]++'

section "APFS volumes sharing the internal container (reserve = space locked for that volume)"
# Only the container holding the data volume (simulator disk images are containers too).
ctr=$(diskutil info /System/Volumes/Data | awk -F': *' '/APFS Container:/{print $2}')
diskutil apfs list "$ctr" 2>/dev/null | awk '
  function val(l) { if (match(l, /\([0-9.]+ [KMGT]?B\)/)) return substr(l, RSTART+1, RLENGTH-2); sub(/^[^:]*: */, "", l); sub(/ \(.*/, "", l); return l }
  /Capacity Not Allocated/ {print "  container unallocated: " val($0)}
  /Name:/ {n=$0; sub(/.*Name: +/, "", n); sub(/ \(Case-.*/, "", n)}
  /Capacity Consumed:/ {used=val($0)}
  /Capacity Reserve:/ {print "  reserve " val($0) " on volume \"" n "\" (consumed " used ")"}
'
echo "  (no 'reserve' lines = no reserved volumes)"

section "Index"
if [[ -s $DB ]]; then
  age_h=$(( ($(date +%s) - $(stat -f %m "$DB")) / 3600 ))
  echo "  last scan: $(stat -f '%Sm' -t '%F %H:%M' "$DB") (${age_h}h ago)$( ((age_h > 48)) && echo '  ← stale: consider `diskwatch scan`')"
  pgrep -qf 'duc index.*diskwatch' && echo "  a scan is running now: diskwatch progress"
  diskwatch roots 2>/dev/null | sed 's/^/  /'
else
  echo "  no index yet — run: diskwatch scan   (≈15 min, background priority)"; exit 0
fi

section "Largest in /"
diskwatch ls / 10 | tail -n +2
section "Largest in home"
diskwatch ls ~ 12 | tail -n +2
[[ $brief == --brief ]] && exit 0

section "Common space hogs (from index)"
diskwatch du ~/Library/Caches ~/Library/Developer ~/Library/Android/sdk ~/.ollama ~/.cache ~/.npm \
  ~/Library/Containers/com.docker.docker "$HOME/Library/Application Support/Claude/vm_bundles" \
  /Library/Developer/CoreSimulator /System/Library/AssetsV2 /opt/homebrew \
  ~/Library/Application\ Support/Google/Chrome ~/.Trash 2>/dev/null | sort -hr | grep -v '^ *- '

section "Growth since previous scan"
diskwatch report 12 2>/dev/null | tail -n +2

section "Cloud drives (local disk used vs cloud size)"
diskwatch cloud 2>/dev/null | head -20

section "Large apps unused ≥90 days"
diskwatch apps --days 90 2>/dev/null | grep '← candidate' | head -10 || echo "  none flagged"
