#!/usr/bin/env bash
# Regenerate catalog/vulnhub-index.tsv from download.vulnhub.com's own file
# listing (a periodic snapshot). One clean OVA entry per box: id, path, url.
# shellcheck source-path=SCRIPTDIR source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

out="$CATALOG/vulnhub-index.tsv"
tmp=$(mktemp)
step "fetching download.vulnhub.com listing"
curl -s --fail --max-time 60 https://download.vulnhub.com/ -o "$tmp" || die "fetch failed"

awk '{
       $1=""; sub(/^ +/, ""); p=$0; sub(/^\.\//, "", p)
       if (p ~ /\.ova$/ && p !~ /(torrent|\/media\/|\/archive\/|checksum)/) print p
     }' "$tmp" |
  sort -u |
  awk '{
           path=$1; id=path; sub(/\.ova$/, "", id)
           gsub(/[^A-Za-z0-9]+/, "-", id); gsub(/^-|-$/, "", id); id=tolower(id)
           print id "\t" path "\t" "https://download.vulnhub.com/" path
         }' |
  sort -u >"$out"

rm -f "$tmp"
msg "wrote $(wc -l <"$out") boxes to ${out#"$ROOT"/}"
