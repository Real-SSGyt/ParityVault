#!/usr/bin/env bash

#==============================================================================
# ParityVault - Backup and Restore Utility
# Version: 1.0.0
# Author: Real-SSGyt
# License: MIT
# AI-assisted development (see README)
#==============================================================================

set -euo pipefail
umask 077

VERSION="1.0.0"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="parityvault_v${VERSION}_${TIMESTAMP}.log"

show_banner() {
    echo "============================================================"
    echo "                  ParityVault v${VERSION}"
    echo "           Backup and Restore Utility"
    echo "============================================================"
    echo
}

log_output() {
    exec > >(tee -a "$LOG_FILE")
    exec 2>&1
}

print_message() {
    echo -e "${1}${2}${NC}"
}

print_header() {
    echo
    echo "========================================================================"
    echo "$1"
    echo "========================================================================"
    echo
}

ask_with_default() {
    local result
    read -e -p "$1 [$2]: " result
    echo "${result:-$2}"
}

parse_size_to_bytes() {
    local size="$1"
    if [[ "$size" =~ ^([0-9]+)([KMGTP]?)$ ]]; then
        local num="${BASH_REMATCH[1]}"
        local unit="${BASH_REMATCH[2]}"
        case "$unit" in
            K) echo $((num * 1024)) ;;
            M) echo $((num * 1024**2)) ;;
            G) echo $((num * 1024**3)) ;;
            T) echo $((num * 1024**4)) ;;
            P) echo $((num * 1024**5)) ;;
            *) echo "$num" ;;
        esac
    else
        return 1
    fi
}

check_dependencies() {
    print_header "Checking Dependencies"
    local missing=()

    for cmd in tar split; do
        command -v "$cmd" >/dev/null || missing+=("$cmd")
    done

    if command -v par2 >/dev/null; then
        PAR2_CMD="par2"
    elif command -v par2cmdline >/dev/null; then
        PAR2_CMD="par2cmdline"
    else
        missing+=("par2 / par2cmdline")
    fi

    if [ "${#missing[@]}" -gt 0 ]; then
        print_message "$RED" "Missing dependencies:"
        for m in "${missing[@]}"; do echo "  - $m"; done
        exit 1
    fi

    print_message "$GREEN" "All dependencies satisfied."
}

backup_mode() {
    print_header "BACKUP MODE"

    # -------------------------------------------------------------------------
    # INPUT COLLECTION
    # -------------------------------------------------------------------------
    print_message "$BLUE" "[INPUT] Awaiting source path to back up..."
    read -e -p "Source path: " SOURCE_PATH

    SOURCE_PATH="$(realpath "$SOURCE_PATH")"
    if [ ! -e "$SOURCE_PATH" ]; then
        print_message "$RED" "[ERROR] Source path does not exist!"
        exit 1
    fi

    print_message "$GREEN" "[OK] Source selected:"
    echo "      $SOURCE_PATH"
    echo ""

    print_message "$BLUE" "[INPUT] Awaiting output directory..."
    read -e -p "Output directory: " OUTPUT_DIR

    print_message "$BLUE" "[ACTION] Ensuring output directory exists..."
    mkdir -p "$OUTPUT_DIR"
    OUTPUT_DIR="$(realpath "$OUTPUT_DIR")"

    print_message "$GREEN" "[OK] Output directory:"
    echo "      $OUTPUT_DIR"
    echo ""

    BACKUP_NAME=$(ask_with_default "Backup name" "backup_${TIMESTAMP}")
    SPLIT_SIZE=$(ask_with_default "Split size (0 = no split)" "5G")
    PAR2_REDUNDANCY=$(ask_with_default "PAR2 redundancy %" "20")

    print_message "$GREEN" "[OK] Backup configuration:"
    echo "      Name        : $BACKUP_NAME"
    echo "      Split size  : $SPLIT_SIZE"
    echo "      Redundancy  : ${PAR2_REDUNDANCY}%"
    echo ""

    # -------------------------------------------------------------------------
    # SIZE ANALYSIS & SPLIT DECISION
    # -------------------------------------------------------------------------
    print_message "$BLUE" "[INFO] Calculating source size..."
    SOURCE_SIZE=$(du -sb "$SOURCE_PATH" | cut -f1)
    SOURCE_SIZE_HR=$(du -sh "$SOURCE_PATH" | cut -f1)

    print_message "$GREEN" "[OK] Source size:"
    echo "      $SOURCE_SIZE_HR ($SOURCE_SIZE bytes)"
    echo ""

    if [ "$SPLIT_SIZE" != "0" ]; then
        print_message "$BLUE" "[INFO] Evaluating split threshold..."

        SPLIT_BYTES=$(parse_size_to_bytes "$SPLIT_SIZE")
        TOLERANCE_PERCENT=15
        EFFECTIVE_LIMIT=$(( SPLIT_BYTES + (SPLIT_BYTES * TOLERANCE_PERCENT / 100) ))

        print_message "$BLUE" "[INFO] Split size details:"
        echo "      Raw split size      : $SPLIT_SIZE ($(numfmt --to=iec "$SPLIT_BYTES"))"
        echo "      Tolerance applied   : ${TOLERANCE_PERCENT}%"
        echo "      Effective threshold : $(numfmt --to=iec "$EFFECTIVE_LIMIT")"
        echo ""

        if [ "$SOURCE_SIZE" -le "$EFFECTIVE_LIMIT" ]; then
            print_message "$YELLOW" "[DECISION] Source within tolerance — splitting disabled."
            SPLIT_SIZE="0"
        else
            print_message "$GREEN" "[DECISION] Source exceeds threshold — splitting enabled."
        fi
        echo ""
    fi

    # -------------------------------------------------------------------------
    # BACKUP EXECUTION
    # -------------------------------------------------------------------------
    print_message "$BLUE" "[ACTION] Changing working directory to output location..."
    cd "$OUTPUT_DIR"

    # -------------------------------------------------------------------------
    # SINGLE TAR BACKUP
    # -------------------------------------------------------------------------
    if [ "$SPLIT_SIZE" = "0" ]; then
        print_header "Creating Single Tar Archive"

        TAR_FILE="${BACKUP_NAME}.tar"

        print_message "$BLUE" "[ACTION] Creating tar archive:"
        echo "      $TAR_FILE"
        echo ""

        tar -cvf "$TAR_FILE" -C "$(dirname "$SOURCE_PATH")" "$(basename "$SOURCE_PATH")"

        print_message "$GREEN" "[OK] Tar archive created:"
        echo "      Size: $(du -h "$TAR_FILE" | cut -f1)"
        echo ""

        print_header "Generating PAR2 Recovery Data"

        print_message "$BLUE" "[ACTION] Creating PAR2 (index + 1 recovery volume)..."
        "$PAR2_CMD" create -n1 -r"$PAR2_REDUNDANCY" "$TAR_FILE"

        print_message "$GREEN" "[OK] PAR2 files created:"
        ls -lh "${TAR_FILE}".par2 "${TAR_FILE}".vol*.par2 2>/dev/null | sed 's/^/      /'

    # -------------------------------------------------------------------------
    # SPLIT TAR BACKUP
    # -------------------------------------------------------------------------
    else
        print_header "Creating Split Tar Archive"

        PART_PREFIX="${BACKUP_NAME}.tar.part"

        print_message "$BLUE" "[ACTION] Streaming tar archive into split files..."
        echo "      Prefix     : $PART_PREFIX"
        echo "      Chunk size : $SPLIT_SIZE"
        echo ""

        tar -cvf - -C "$(dirname "$SOURCE_PATH")" "$(basename "$SOURCE_PATH")" |
            split -d -b "$SPLIT_SIZE" - "$PART_PREFIX"

        mapfile -t PARTS < <(ls "${PART_PREFIX}"* | sort)

        print_message "$GREEN" "[OK] Split completed:"
        echo "      Parts created: ${#PARTS[@]}"
        for p in "${PARTS[@]}"; do
            echo "      - $(basename "$p") ($(du -h "$p" | cut -f1))"
        done
        echo ""

        print_header "Generating PAR2 Recovery Data for Each Part"

        part_num=0
        for part in "${PARTS[@]}"; do
            part_num=$((part_num + 1))

            print_message "$BLUE" "[${part_num}/${#PARTS[@]}] Processing part:"
            echo "      $(basename "$part")"
            echo "      → Creating PAR2 (index + 1 recovery volume)..."

            "$PAR2_CMD" create -n1 -r"$PAR2_REDUNDANCY" "$part"

            print_message "$GREEN" "      ✓ PAR2 created"
            echo ""
        done
    fi

    # -------------------------------------------------------------------------
    # FINAL SUMMARY
    # -------------------------------------------------------------------------
    print_header "Backup Complete"

    print_message "$GREEN" "✔ Backup successfully created"
    print_message "$BLUE" "Location: $OUTPUT_DIR"
    echo ""

    print_message "$BLUE" "Backup files:"
    ls -lh "$OUTPUT_DIR"/"$BACKUP_NAME"* | sed 's/^/      /'
    echo ""
}

restore_mode() {
    print_header "RESTORE MODE"

    print_message "$BLUE" "[INPUT] Awaiting backup file selection..."
    read -e -p "Backup file (.tar or .tar.partXX): " BACKUP_FILE

    BACKUP_FILE="$(realpath "$BACKUP_FILE")"
    BACKUP_DIR="$(dirname "$BACKUP_FILE")"

    print_message "$GREEN" "[OK] Backup file selected:"
    echo "      $BACKUP_FILE"
    echo "      Directory: $BACKUP_DIR"
    echo ""

    print_message "$BLUE" "[INPUT] Awaiting destination directory..."
    read -e -p "Destination directory: " DEST_DIR

    print_message "$BLUE" "[ACTION] Ensuring destination directory exists..."
    mkdir -p "$DEST_DIR"
    DEST_DIR="$(realpath "$DEST_DIR")"

    print_message "$GREEN" "[OK] Restore destination:"
    echo "      $DEST_DIR"
    echo ""

    print_message "$BLUE" "[ACTION] Changing working directory to backup location..."
    cd "$BACKUP_DIR"

    print_message "$GREEN" "[OK] Current working directory:"
    pwd
    echo ""

    # -------------------------------------------------------------------------
    # SPLIT ARCHIVE RESTORE
    # -------------------------------------------------------------------------
    if [[ "$BACKUP_FILE" == *.tar.part* ]]; then
        print_header "Detected Split Archive Restore"

        BASE="${BACKUP_FILE%.tar.part*}.tar.part"
        print_message "$BLUE" "[INFO] Split archive base pattern:"
        echo "      ${BASE}*"
        echo ""

        print_message "$BLUE" "[ACTION] Searching for split parts..."
        mapfile -t PARTS < <(ls "${BASE}"* 2>/dev/null | grep -v ".par2" | sort)

        if [ "${#PARTS[@]}" -eq 0 ]; then
            print_message "$RED" "[ERROR] No split parts found!"
            exit 1
        fi

        print_message "$GREEN" "[OK] Found ${#PARTS[@]} split parts:"
        for p in "${PARTS[@]}"; do
            echo "      - $(basename "$p") ($(du -h "$p" | cut -f1))"
        done
        echo ""

        print_header "Verifying & Repairing Split Parts"

        part_num=0
        for p in "${PARTS[@]}"; do
            part_num=$((part_num + 1))
            PAR2_FILE="${p}.par2"

            print_message "$BLUE" "[${part_num}/${#PARTS[@]}] Processing:"
            echo "      Data file : $(basename "$p")"
            echo "      PAR2 file : $(basename "$PAR2_FILE")"

            if [ ! -f "$PAR2_FILE" ]; then
                print_message "$RED" "[ERROR] Missing PAR2 file for $(basename "$p")"
                exit 1
            fi

            print_message "$BLUE" "      → Verifying integrity..."
            if "$PAR2_CMD" verify "$PAR2_FILE" >/dev/null 2>&1; then
                print_message "$GREEN" "      ✓ Verification successful"
            else
                print_message "$YELLOW" "      ⚠ Verification failed — attempting repair..."
                "$PAR2_CMD" repair "$PAR2_FILE"

                print_message "$GREEN" "      ✓ Repair completed"
            fi
            echo ""
        done

        print_header "Reassembling Tar Archive"

        TEMP_TAR="restored_$$.tar"
        print_message "$BLUE" "[ACTION] Concatenating split parts into temporary tar:"
        echo "      $TEMP_TAR"
        echo ""

        cat "${PARTS[@]}" > "$TEMP_TAR"

        print_message "$GREEN" "[OK] Reassembly complete:"
        echo "      Size: $(du -h "$TEMP_TAR" | cut -f1)"
        echo ""

        print_header "Extracting Archive"

        print_message "$BLUE" "[ACTION] Extracting tar archive to destination..."
        tar -xvf "$TEMP_TAR" -C "$DEST_DIR"

        print_message "$BLUE" "[CLEANUP] Removing temporary tar file..."
        rm -f "$TEMP_TAR"

    # -------------------------------------------------------------------------
    # SINGLE TAR RESTORE
    # -------------------------------------------------------------------------
    else
        print_header "Detected Single Tar Archive Restore"

        PAR2_FILE="${BACKUP_FILE}.par2"

        print_message "$BLUE" "[INFO] Archive:"
        echo "      $(basename "$BACKUP_FILE") ($(du -h "$BACKUP_FILE" | cut -f1))"
        echo ""

        print_message "$BLUE" "[INFO] Associated PAR2 file:"
        echo "      $(basename "$PAR2_FILE")"
        echo ""

        if [ ! -f "$PAR2_FILE" ]; then
            print_message "$RED" "[ERROR] PAR2 file not found!"
            exit 1
        fi

        print_message "$BLUE" "[ACTION] Verifying archive integrity..."
        if "$PAR2_CMD" verify "$PAR2_FILE" >/dev/null 2>&1; then
            print_message "$GREEN" "[OK] Archive verified successfully"
        else
            print_message "$YELLOW" "[WARN] Verification failed — attempting repair..."
            "$PAR2_CMD" repair "$PAR2_FILE"
            print_message "$GREEN" "[OK] Archive repaired successfully"
        fi
        echo ""

        print_header "Extracting Archive"

        print_message "$BLUE" "[ACTION] Extracting archive to destination..."
        tar -xvf "$BACKUP_FILE" -C "$DEST_DIR"
    fi

    print_header "Restore Complete"
    print_message "$GREEN" "✔ Files restored successfully"
    print_message "$BLUE" "Destination: $DEST_DIR"
    echo ""

    print_message "$BLUE" "Top-level restored contents:"
    ls -lh "$DEST_DIR" | head -20
    echo ""
}

log_output
show_banner
check_dependencies

echo "ParityVault Options:"
echo "1) Create Backup"
echo "2) Restore Backup"
read -p "Choose mode: " MODE

case "$MODE" in
    1) backup_mode ;;
    2) restore_mode ;;
    *) exit 1 ;;
esac
