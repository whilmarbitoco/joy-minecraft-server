#!/bin/bash
set -e

cd /data

echo "Installing behavior/resource packs..."

mkdir -p behavior_packs resource_packs

install_pack_from_manifest() {
  local manifest="$1"
  local pack_dir
  local root_dir
  local dest_root
  local pack_id
  local safe_pack_id

  pack_dir="$(dirname "$manifest")"

  pack_id="$(jq -r '.header.uuid // empty' "$manifest" 2>/dev/null || true)"

  if jq -e 'any(.modules[]?; .type=="resources")' "$manifest" >/dev/null 2>&1; then
    dest_root="resource_packs"
  else
    dest_root="behavior_packs"
  fi

  [ -n "$pack_id" ] || pack_id="$(basename "$pack_dir")"

  safe_pack_id="$(echo "$pack_id" | tr -cd 'A-Za-z0-9._-')"
  [ -n "$safe_pack_id" ] || safe_pack_id="pack"

  rm -rf "$dest_root/$safe_pack_id"
  mkdir -p "$dest_root/$safe_pack_id"

  # IMPORTANT FIX: flatten mcpack to actual manifest root
  root_dir="$(dirname "$(find "$pack_dir" -type f -name manifest.json | head -n 1)")"

  if [ -z "$root_dir" ]; then
    echo "WARN: no manifest root found in $pack_dir"
    return
  fi

  cp -r "$root_dir/"* "$dest_root/$safe_pack_id/" || true
}

# Extract packs
for file in /packs/*; do
  [ -e "$file" ] || continue

  echo "Processing $file"

  tmp="$(mktemp -d /tmp/pack.XXXXXX)"
  unzip -o "$file" -d "$tmp" >/dev/null

  while IFS= read -r manifest; do
    install_pack_from_manifest "$manifest"
  done < <(find "$tmp" -type f -name manifest.json)

  rm -rf "$tmp"
done

echo "Packs installed."

WORLD_NAME="${LEVEL_NAME:-world}"
WORLD_DIR="/data/worlds/$WORLD_NAME"

mkdir -p "$WORLD_DIR"

build_world_pack_file() {
  local src_dir="$1"
  local target_file="$2"
  local filter="$3"

  local tmp_json
  local tmp_out
  local manifest
  local entry

  tmp_json="$(mktemp /tmp/worldpacks.XXXXXX.json)"
  echo "[]" > "$tmp_json"

  for manifest in "$src_dir"/*/manifest.json; do
    [ -f "$manifest" ] || continue

    entry="$(jq -c "$filter" "$manifest" 2>/dev/null || true)"
    [ -n "$entry" ] || continue
    [ "$entry" = "null" ] && continue

    tmp_out="$(mktemp /tmp/worldpacks_out.XXXXXX.json)"
    jq --argjson item "$entry" '. + [$item]' "$tmp_json" > "$tmp_out"
    mv "$tmp_out" "$tmp_json"
  done

  mv "$tmp_json" "$target_file"
}

echo "Attaching packs to world: $WORLD_NAME"

build_world_pack_file \
  "behavior_packs" \
  "$WORLD_DIR/world_behavior_packs.json" \
  'if any(.modules[]?; .type=="data" or .type=="script")
   then {pack_id:.header.uuid, version:(.header.version // [1,0,0])}
   else null end'

build_world_pack_file \
  "resource_packs" \
  "$WORLD_DIR/world_resource_packs.json" \
  'if any(.modules[]?; .type=="resources")
   then {pack_id:.header.uuid, version:(.header.version // [1,0,0])}
   else null end'

echo "World pack files written."

# ---------------- SAFE OPERATOR SET ----------------
PERMISSIONS_FILE="/data/permissions.json"

echo "Ensuring operator permissions..."

if [ -f "$PERMISSIONS_FILE" ]; then
  tmp="$(mktemp)"
  jq 'if any(.[]; .xuid=="2535439809227743")
      then .
      else . + [{"permission":"operator","xuid":"2535439809227743"}]
      end' "$PERMISSIONS_FILE" > "$tmp" 2>/dev/null && mv "$tmp" "$PERMISSIONS_FILE" || true
else
  cat > "$PERMISSIONS_FILE" <<EOF
[
  {
    "permission": "operator",
    "xuid": "2535439809227743"
  }
]
EOF
fi

# ----------------------------------------------------

echo "Starting server..."

if command -v send-command >/dev/null 2>&1; then
(
  echo "Waiting for Bedrock server..."

  for _ in $(seq 1 45); do
    if send-command list >/dev/null 2>&1; then
      break
    fi
    sleep 2
  done

  echo "Applying gamerules..."
  send-command gamerule showcoordinates true || true
  send-command gamerule mobgriefing false || true
) &
fi

exec /opt/bedrock-entry.sh
