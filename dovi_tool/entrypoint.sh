#!/usr/bin/env sh

set -eo pipefail
IFS=$(echo -en "\n\b")

# Sanity check
if ! command -v mediainfo >/dev/null 2>&1; then
    echo "mediainfo could not be found"
    exit 1
fi

if ! command -v dovi_tool >/dev/null 2>&1; then
    echo "dovi_tool could not be found"
    exit 1
fi

if ! command -v mkvmerge >/dev/null 2>&1; then
    echo "mkvmerge could not be found"
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "jq could not be found"
    exit 1
fi

# Ensure PROFILE environment variable is set
if [ -z "$PROFILE" ]; then
    echo "Error: PROFILE environment variable is not set"
    exit 1
fi

# Check if /opt/media exists and contains .mkv files
if [ ! -d "/opt/media" ]; then
    echo "/opt/media directory does not exist"
    exit 1
fi

# Find all .mkv files before starting processing
mkv_files=()
while IFS= read -r -d '' mkv_file; do
    mkv_files+=("$mkv_file")
done < <(find /opt/media -maxdepth 2 -type f -iname "*.mkv" -print0)

# Ensure that we found at least one .mkv file
if [ ${#mkv_files[@]} -eq 0 ]; then
    echo "No .mkv files found in /opt/media"
    exit 1
fi

# Output list of files to be processed
echo "Files to be processed:"
for file in "${mkv_files[@]}"; do
    echo "$file"
done

echo "Starting processing..."

# Cleanup function to remove any leftover files
cleanup() {
    echo "Cleaning up working files for $1..."
    rm -f "${1%.*}.hevc" "${1%.*}.mkv.tmp" "${1%.*}.mkv.copy" "${1%.*}.dv8.hevc" "${1%.*}.rpu.bin"
}

# Get DV profile information using mediainfo
get_dvhe_profile() {
    echo "Checking for Dolby Vision ${PROFILE} profile in $1..."
    echo "------------------"
    DVHE_PROFILE=$(mediainfo --Output=JSON "$1" | jq '.media.track[].HDR_Format_Profile' | grep "${PROFILE}" || true)

    if [ -n "${DVHE_PROFILE}" ]; then
        echo "DVHE ${PROFILE} profile found in $1"
    else
        echo "DVHE ${PROFILE} profile not found in $1. Skipping..."
        return 1
    fi
}

extract_mkv() {
    echo "Extracting $1..."
    if ! mkvextract "$1" tracks 0:"${1%.*}.hevc"; then
        echo "Failed to extract $1"
        cleanup "$1"
        return 1
    fi
}

convert_mkv() {
    echo "Converting $1..."
    if ! dovi_tool --edit-config /config/dovi_tool.config.json convert --discard "${1%.*}.hevc" -o "${1%.*}.dv8.hevc"; then
        echo "Failed to convert $1"
        cleanup "$1"
        return 1
    fi
}

extract_rpu() {
    echo "Extracting RPU from ${1%.*}.dv8.hevc..."
    if ! dovi_tool extract-rpu "${1%.*}.dv8.hevc" -o "${1%.*}.rpu.bin"; then
        echo "Failed to extract RPU from ${1%.*}.dv8.hevc"
        cleanup "$1"
        return 1
    fi
}

create_plot() {
    echo "Creating plot from RPU for $1..."
    if ! dovi_tool plot "${1%.*}.rpu.bin" -o "${1%.*}.l1_plot.png"; then
        echo "Failed to create plot from RPU"
        cleanup "$1"
        return 1
    fi
}

demux_file() {
    extract_mkv "$1" || return 1
    convert_mkv "$1" || return 1
    extract_rpu "$1" || return 1
    create_plot "$1" || return 1
}

remux_file() {
    echo "Remuxing $1..."
    if ! mkvmerge -o "${1%.*}.mkv.tmp" -D "$1" "${1%.*}.dv8.hevc" --track-order 1:0; then
        echo "Failed to remux $1"
        cleanup "$1"
        return 1
    fi
}

overwrite_file() {
    if ! ln "${1%.*}.mkv.tmp" "${1%.*}.mkv.copy"; then
        echo "Failed to copy ${1%.*}.mkv.tmp to ${1%.*}.mkv.copy"
        cleanup "$1"
        return 1
    fi

    if ! mv "${1%.*}.mkv.copy" "$1"; then
        echo "Failed to overwrite $1"
        cleanup "$1"
        return 1
    fi

    if ! rm "${1%.*}.mkv.tmp"; then
        echo "Failed to remove ${1%.*}.mkv.tmp"
        cleanup "$1"
        return 1
    fi
}

main() {
    trap 'echo "Error: $0:$LINENO: Command \`$BASH_COMMAND\` on line $LINENO failed with exit code $?" >&2; cleanup $1' ERR
    
    for mkv_file in "${mkv_files[@]}"; do
        echo "Processing $mkv_file..."
        get_dvhe_profile "$mkv_file" || continue
        demux_file "$mkv_file" || continue
        remux_file "$mkv_file" || continue
        overwrite_file "$mkv_file" || continue
        cleanup "$mkv_file"
    done
}

main
