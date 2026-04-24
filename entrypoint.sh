#!/bin/bash
set -e

cd /data

echo "Installing behavior/resource packs..."

mkdir -p behavior_packs resource_packs

# Extract all packs
for file in /packs/*; do
  [ -e "$file" ] || continue

  echo "Processing $file"

  tmp="$(mktemp -d /tmp/pack.XXXXXX)"
  pack_name="$(basename "$file")"
  pack_stem="${pack_name%.*}"
  safe_pack_stem="$(echo "$pack_stem" | tr ' /' '__')"

  unzip -o "$file" -d "$tmp" >/dev/null

  # Detect pack type
  if [ -d "$tmp/behavior_packs" ]; then
    cp -r "$tmp/behavior_packs/"* behavior_packs/ || true
  fi

  if [ -d "$tmp/resource_packs" ]; then
    cp -r "$tmp/resource_packs/"* resource_packs/ || true
  fi

  # Fallback: pack root contains manifest.json.
  # Classify by module type and copy into a unique destination folder.
  if [ -f "$tmp/manifest.json" ]; then
    if grep -Eqi '"type"[[:space:]]*:[[:space:]]*"resources"' "$tmp/manifest.json"; then
      rm -rf "resource_packs/$safe_pack_stem"
      mkdir -p "resource_packs/$safe_pack_stem"
      cp -r "$tmp/"* "resource_packs/$safe_pack_stem/" || true
    else
      rm -rf "behavior_packs/$safe_pack_stem"
      mkdir -p "behavior_packs/$safe_pack_stem"
      cp -r "$tmp/"* "behavior_packs/$safe_pack_stem/" || true
    fi
  fi

  rm -rf "$tmp"

done

echo "Packs installed."

echo "Starting server..."

exec /usr/local/bin/start.sh
