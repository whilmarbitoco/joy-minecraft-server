#!/bin/bash
set -e

cd /data

echo "Installing behavior/resource packs..."

mkdir -p behavior_packs resource_packs

install_pack_from_manifest() {
  local manifest="$1"
  local pack_dir
  local pack_id
  local safe_pack_id
  local dest_root

  pack_dir="$(dirname "$manifest")"
  pack_id="$(jq -r '.header.uuid // empty' "$manifest" 2>/dev/null || true)"

  if jq -e 'any(.modules[]?; .type=="resources")' "$manifest" >/dev/null 2>&1; then
    dest_root="resource_packs"
  else
    dest_root="behavior_packs"
  fi

  if [ -z "$pack_id" ]; then
    pack_id="$(basename "$pack_dir")"
  fi

  safe_pack_id="$(echo "$pack_id" | tr -cd 'A-Za-z0-9._-')"
  [ -n "$safe_pack_id" ] || safe_pack_id="pack"

  rm -rf "$dest_root/$safe_pack_id"
  mkdir -p "$dest_root/$safe_pack_id"
  cp -r "$pack_dir/"* "$dest_root/$safe_pack_id/" || true
}

# Extract all packs
for file in /packs/*; do
  [ -e "$file" ] || continue

  echo "Processing $file"

  tmp="$(mktemp -d /tmp/pack.XXXXXX)"

  unzip -o "$file" -d "$tmp" >/dev/null

  # Find every manifest in the archive (covers nested-folder mcpack layouts).
  while IFS= read -r manifest; do
    install_pack_from_manifest "$manifest"
  done < <(find "$tmp" -type f -name manifest.json)

  rm -rf "$tmp"

done

echo "Packs installed."

WORLD_NAME="${LEVEL_NAME:-world}"
WORLD_DIR="/data/worlds/$WORLD_NAME"

build_world_pack_file() {
  local src_dir="$1"
  local target_file="$2"
  local jq_filter="$3"
  local tmp_json
  local tmp_out
  local manifest
  local entry

  tmp_json="$(mktemp /tmp/world-packs.XXXXXX.json)"
  echo "[]" > "$tmp_json"

  for manifest in "$src_dir"/*/manifest.json; do
    [ -f "$manifest" ] || continue

    entry="$(jq -c "$jq_filter" "$manifest" 2>/dev/null || true)"
    [ -n "$entry" ] || continue
    [ "$entry" = "null" ] && continue

    tmp_out="$(mktemp /tmp/world-packs-out.XXXXXX.json)"
    jq --argjson item "$entry" '. + [$item]' "$tmp_json" > "$tmp_out"
    mv "$tmp_out" "$tmp_json"
  done

  mv "$tmp_json" "$target_file"
}

if [ -d "$WORLD_DIR" ]; then
  echo "Attaching packs to world: $WORLD_NAME"

  build_world_pack_file \
    "behavior_packs" \
    "$WORLD_DIR/world_behavior_packs.json" \
    'if any(.modules[]?; .type=="data" or .type=="script") then {pack_id:.header.uuid, version:.header.version} else null end'

  build_world_pack_file \
    "resource_packs" \
    "$WORLD_DIR/world_resource_packs.json" \
    'if any(.modules[]?; .type=="resources") then {pack_id:.header.uuid, version:.header.version} else null end'

  echo "World pack files written."
else
  echo "World directory not found at $WORLD_DIR. It will be created by Bedrock on first run."
  echo "Restart once after first world creation so packs can be attached automatically."
fi

echo "Starting server..."

if command -v send-command >/dev/null 2>&1; then
  (
    echo "Waiting for Bedrock server to accept commands..."
    for _ in $(seq 1 45); do
      if send-command list >/dev/null 2>&1; then
        break
      fi
      sleep 2
    done

    echo "Applying gamerules..."
    send-command gamerule showcoordinates true || echo "WARN: failed to set showcoordinates"
    send-command gamerule mobgriefing false || echo "WARN: failed to set mobgriefing"
    echo "Adding operator..."
    send-command op "PH PH03NIX" || echo "WARN: failed to op player"
  ) &
fi

exec /opt/bedrock-entry.sh
