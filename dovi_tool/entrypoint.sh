#!/usr/bin/env sh

set -e
IFS=$(echo -en "\n")

# Initialize variables for notification
NOTIFICATION_ENABLED=false
PROCESSED_FILES=0
FAILED_FILES=0
SKIPPED_FILES=0
TOTAL_FILES=0
FAILED_FILES_LIST=""
SKIPPED_FILES_LIST=""

# Function to send Telegram notification
send_telegram_notification() {
    if [ "$NOTIFICATION_ENABLED" = true ]; then
        local message="$1"
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
            -d "chat_id=${TELEGRAM_CHAT_ID}" \
            -d "text=${message}" \
            -d "parse_mode=HTML" > /dev/null || true
    fi
}

# Function to print summary
print_summary() {
    local summary="🎉 Dolby Vision Conversion Complete!\n\n"
    summary="${summary}📊 Summary:\n"
    summary="${summary}📁 Total files scanned: ${TOTAL_FILES}\n"
    summary="${summary}✅ Successfully processed: ${PROCESSED_FILES}\n"
    summary="${summary}❌ Failed: ${FAILED_FILES}\n"
    summary="${summary}⏭️ Skipped: ${SKIPPED_FILES}\n"
    summary="${summary}🎯 Target profile: ${PROFILE}\n\n"
    
    if [ -n "$FAILED_FILES_LIST" ]; then
        summary="${summary}❌ Failed files:\n${FAILED_FILES_LIST}\n\n"
    fi
    
    if [ -n "$SKIPPED_FILES_LIST" ]; then
        summary="${summary}⏭️ Skipped files:\n${SKIPPED_FILES_LIST}"
    fi
    
    echo -e "$summary"
}

# Check if Telegram notifications are enabled
if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
    NOTIFICATION_ENABLED=true
    echo "Telegram notifications enabled"
else
    echo "Telegram notifications disabled (TELEGRAM_BOT_TOKEN and/or TELEGRAM_CHAT_ID not set)"
fi

# Sanity check
if ! command -v mediainfo >/dev/null 2>&1; then
    echo "mediainfo could not be found"
    send_telegram_notification "❌ Error: mediainfo could not be found"
    exit 1
fi

if ! command -v dovi_tool >/dev/null 2>&1; then
    echo "dovi_tool could not be found"
    send_telegram_notification "❌ Error: dovi_tool could not be found"
    exit 1
fi

if ! command -v mkvmerge >/dev/null 2>&1; then
    echo "mkvmerge could not be found"
    send_telegram_notification "❌ Error: mkvmerge could not be found"
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "jq could not be found"
    send_telegram_notification "❌ Error: jq could not be found"
    exit 1
fi

# Ensure PROFILE environment variable is set
if [ -z "$PROFILE" ]; then
    echo "Error: PROFILE environment variable is not set"
    send_telegram_notification "❌ Error: PROFILE environment variable is not set"
    exit 1
fi

# Check if /opt/media exists and contains .mkv files
if [ ! -d "/opt/media" ]; then
    echo "/opt/media directory does not exist"
    send_telegram_notification "❌ Error: /opt/media directory does not exist"
    exit 1
fi

# Find all .mkv files before starting processing
mkv_files=$(find /opt/media -maxdepth 2 -type f -iname "*.mkv")

# Ensure that we found at least one .mkv file
if [ -z "$mkv_files" ]; then
    echo "No .mkv files found in /opt/media"
    send_telegram_notification "❌ Error: No .mkv files found in /opt/media"
    exit 1
fi

# Output list of files to be processed
echo "Files to be processed:"
echo "$mkv_files"

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
        return 0
    else
        echo "DVHE ${PROFILE} profile not found in $1. Skipping..."
        return 1
    fi
}

extract_mkv() {
    echo "Extracting $1..."
    if ! mkvextract "$1" tracks 0:"${1%.*}.hevc"; then
        echo "Failed to extract $1"
        send_telegram_notification "❌ Error: Failed to extract $(basename "$1")"
        cleanup "$1"
        return 1
    fi
}

convert_mkv() {
    echo "Converting $1..."
    if ! dovi_tool --edit-config /config/dovi_tool.config.json convert --discard "${1%.*}.hevc" -o "${1%.*}.dv8.hevc"; then
        echo "Failed to convert $1"
        send_telegram_notification "❌ Error: Failed to convert $(basename "$1")"
        cleanup "$1"
        return 1
    fi
}

extract_rpu() {
    echo "Extracting RPU from ${1%.*}.dv8.hevc..."
    if ! dovi_tool extract-rpu "${1%.*}.dv8.hevc" -o "${1%.*}.rpu.bin"; then
        echo "Failed to extract RPU from ${1%.*}.dv8.hevc"
        send_telegram_notification "❌ Error: Failed to extract RPU from $(basename "$1")"
        cleanup "$1"
        return 1
    fi
}

create_plot() {
    echo "Creating plot from RPU for $1..."
    if ! dovi_tool plot "${1%.*}.rpu.bin" -o "${1%.*}.l1_plot.png"; then
        echo "Failed to create plot from RPU"
        send_telegram_notification "❌ Error: Failed to create plot for $(basename "$1")"
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
        send_telegram_notification "❌ Error: Failed to remux $(basename "$1")"
        cleanup "$1"
        return 1
    fi
}

overwrite_file() {
    if ! ln "${1%.*}.mkv.tmp" "${1%.*}.mkv.copy"; then
        echo "Failed to copy ${1%.*}.mkv.tmp to ${1%.*}.mkv.copy"
        send_telegram_notification "❌ Error: Failed to copy temporary file for $(basename "$1")"
        cleanup "$1"
        return 1
    fi

    if ! mv "${1%.*}.mkv.copy" "$1"; then
        echo "Failed to overwrite $1"
        send_telegram_notification "❌ Error: Failed to overwrite $(basename "$1")"
        cleanup "$1"
        return 1
    fi

    if ! rm "${1%.*}.mkv.tmp"; then
        echo "Failed to remove ${1%.*}.mkv.tmp"
        send_telegram_notification "❌ Error: Failed to remove temporary file for $(basename "$1")"
        cleanup "$1"
        return 1
    fi
}

main() {
    TOTAL_FILES=$(echo "$mkv_files" | wc -l)
    
    echo "$mkv_files" | while IFS= read -r mkv_file; do
        echo "Processing $mkv_file..."
        if [ "$NOTIFICATION_ENABLED" = true ]; then
            send_telegram_notification "🎬 Starting to process: $(basename "$mkv_file")"
        fi
        
        if get_dvhe_profile "$mkv_file"; then
            if demux_file "$mkv_file" && remux_file "$mkv_file" && overwrite_file "$mkv_file"; then
                PROCESSED_FILES=$((PROCESSED_FILES + 1))
                if [ "$NOTIFICATION_ENABLED" = true ]; then
                    send_telegram_notification "✅ Successfully processed: $(basename "$mkv_file")"
                fi
            else
                FAILED_FILES=$((FAILED_FILES + 1))
                FAILED_FILES_LIST="${FAILED_FILES_LIST}\n• $(basename "$mkv_file")"
            fi
        else
            SKIPPED_FILES=$((SKIPPED_FILES + 1))
            SKIPPED_FILES_LIST="${SKIPPED_FILES_LIST}\n• $(basename "$mkv_file")"
            if [ "$NOTIFICATION_ENABLED" = true ]; then
                send_telegram_notification "⏭️ Skipped: $(basename "$mkv_file") (does not match target profile ${PROFILE})"
            fi
        fi
        cleanup "$mkv_file"
    done

    # Print summary to STDOUT
    print_summary

    # Send summary to Telegram if enabled
    if [ "$NOTIFICATION_ENABLED" = true ]; then
        summary_text=$(print_summary)
        send_telegram_notification "$summary_text"
    fi
}

main
