#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
CONFIG_FILE="${1:-$SCRIPT_DIR/build-mods.json}"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Config file not found: $CONFIG_FILE" >&2
    exit 1
fi

read_config_value() {
    python3 - "$CONFIG_FILE" "$1" <<'PY'
import json
import sys

config_path, key = sys.argv[1:]
with open(config_path, encoding="utf-8") as config_file:
    value = json.load(config_file)

for part in key.split("."):
    value = value[part]

if not isinstance(value, str):
    raise TypeError(f"{key} must be a string")
print(value)
PY
}

read_config_list() {
    python3 - "$CONFIG_FILE" "$1" <<'PY'
import json
import sys

config_path, key = sys.argv[1:]
with open(config_path, encoding="utf-8") as config_file:
    value = json.load(config_file)

for part in key.split("."):
    value = value[part]

if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
    raise TypeError(f"{key} must be an array of strings")
print("\n".join(value))
PY
}

expand_path() {
    local path=$1
    printf '%s\n' "${path//\$HOME/$HOME}"
}

WORKSHOP_DIR=$(expand_path "$(read_config_value paths.workshop_dir)")
INI_FILE=$(expand_path "$(read_config_value paths.ini_file)")
ARCHIVE=$(expand_path "$(read_config_value paths.archive)")
TEMP_DIR=$(expand_path "$(read_config_value paths.temp_dir)")
REMOTE_CONFIGS=$(read_config_value remote.configs)
REMOTE_ARCHIVE=$(read_config_value remote.archive)
mapfile -t PRIORITY_MODS < <(read_config_list mods.priority)
mapfile -t BLACKLIST_MODS < <(read_config_list mods.blacklist)

# Load blacklisted mod IDs
declare -A blacklisted
for bl in "${BLACKLIST_MODS[@]}"; do
    bl=$(echo "$bl" | tr -d '\r' | xargs)
    [ -n "$bl" ] && blacklisted[$bl]=1
done

# Build semicolon-delimited list of workshop item IDs
workshop_items=$(ls -1 "$WORKSHOP_DIR" | paste -sd';' -)

# Collect mod IDs from each workshop item's mods/*/mod.info
declare -A seen
mod_ids=()
for item_dir in "$WORKSHOP_DIR"/*/; do
    mods_dir="$item_dir/mods"
    [ -d "$mods_dir" ] || continue
    while IFS= read -r -d '' info; do
        id=$(grep -m1 '^id=' "$info" | cut -d= -f2- | tr -d '\r' | xargs)
        if [ -n "$id" ] && [ -z "${seen[$id]:-}" ] && [ -z "${blacklisted[$id]:-}" ]; then
            seen[$id]=1
            mod_ids+=("$id")
        fi
    done < <(find "$mods_dir" -mindepth 2 -name mod.info -print0 | sort -z)
done

# Order: priority mods first, then the rest
ordered=()
for prio in "${PRIORITY_MODS[@]}"; do
    prio=$(echo "$prio" | tr -d '\r' | xargs)
    [ -n "$prio" ] && [ -n "${seen[$prio]:-}" ] && ordered+=("$prio")
done
for id in "${mod_ids[@]}"; do
    skip=0
    for o in ${ordered[@]+"${ordered[@]}"}; do
        [ "$o" = "$id" ] && skip=1 && break
    done
    [ "$skip" -eq 0 ] && ordered+=("$id")
done

mods_line=""
mods_line_sed=""
for id in ${ordered[@]+"${ordered[@]}"}; do
    mods_line+="\\$id;"
    mods_line_sed+="\\\\$id;"
done
mods_line="${mods_line%;}"
mods_line_sed="${mods_line_sed%;}"

# Comment out existing lines and insert new values immediately after
sed -i \
    -e "s|^WorkshopItems=.*|#&\nWorkshopItems=$workshop_items|" \
    -e "s|^Mods=.*|#&\nMods=$mods_line_sed|" \
    "$INI_FILE"

# Build archive of workshop content and move to ~/zomboid-server
archive_dir=$(dirname -- "$ARCHIVE")
mkdir -p "$archive_dir"
tmp_archive=$(mktemp "$TEMP_DIR/zomboid-mods.XXXXXX.tar.gz")
tar -czvf "$tmp_archive" -C "$WORKSHOP_DIR" .
mv -f "$tmp_archive" "$ARCHIVE"

# Copy configs and tarball to remote host
scp "$(dirname -- "$INI_FILE")"/* "$REMOTE_CONFIGS"
scp "$ARCHIVE" "$REMOTE_ARCHIVE"

echo "Done. WorkshopItems=$workshop_items"
echo "Mods=$mods_line"
echo "Archive: $ARCHIVE"
