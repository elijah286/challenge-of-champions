#!/usr/bin/env bash
# =============================================================================
# vidiff.sh — VIDiff comparison reports (Linux container)
# =============================================================================
# Usage:
#   CHANGED_FILES="path/to/a.vi\npath/to/b.vi" \
#   bash /workspace/.github/labview/vidiff.sh \
#       /workspace-base    # BaseDir
#       /workspace         # HeadDir
#       /report            # ReportDir
# =============================================================================
set -euo pipefail

BASE_DIR="${1:-/workspace-base}"
HEAD_DIR="${2:-/workspace}"
REPORT_DIR="${3:-/report}"

# LabVIEWCLI is on PATH in the NI Linux container
LABVIEWCLI="LabVIEWCLI"
# Discover labviewprofull dynamically (year varies by image tag)
LABVIEW_EXE=$(find /usr/local/natinst -name "labviewprofull" 2>/dev/null | head -1)
if [ -z "$LABVIEW_EXE" ]; then echo "ERROR: labviewprofull not found" >&2; exit 1; fi
echo "Using LabVIEW: $LABVIEW_EXE"
PRINT_TO_HTML_OP="${HEAD_DIR}/.github/labview"

mkdir -p "$REPORT_DIR"

# ── Magic-byte check for real LabVIEW files ──────────────────────────────────
# LabVIEW VIs have LVIN or LVCC at byte offset 8 (per NI's container examples)
is_labview_file() {
    local f="$1"
    [ -f "$f" ] || return 1
    local magic
    magic=$(dd if="$f" bs=1 skip=8 count=4 2>/dev/null)
    [[ "$magic" == "LVIN" || "$magic" == "LVCC" ]]
}

# ── Parse changed files ──────────────────────────────────────────────────────
IFS=$'\n' read -r -d '' -a FILES <<< "${CHANGED_FILES:-}" || true
VI_FILES=()
for f in "${FILES[@]}"; do
    f="${f#/}"   # strip leading slash
    [[ "$f" =~ \.(vi|ctl)$ ]] && VI_FILES+=("$f")
done

if [ "${#VI_FILES[@]}" -eq 0 ]; then
    echo "No .vi/.ctl files changed — nothing to diff."
    exit 0
fi

PROCESSED=0; ERRORS=0
MANIFEST="[]"
PROCESSED_PATHS=()

for REL_PATH in "${VI_FILES[@]}"; do
    BASE_PATH="${BASE_DIR}/${REL_PATH}"
    HEAD_PATH="${HEAD_DIR}/${REL_PATH}"
    SAFE_NAME="${REL_PATH//[\/]/-}"
    SAFE_NAME="${SAFE_NAME//[^a-zA-Z0-9._-]/_}"
    OUT_DIR="${REPORT_DIR}/${SAFE_NAME}"
    mkdir -p "$OUT_DIR"

    BASE_EXISTS=false; HEAD_EXISTS=false
    is_labview_file "$BASE_PATH" && BASE_EXISTS=true
    is_labview_file "$HEAD_PATH" && HEAD_EXISTS=true

    echo "── ${REL_PATH} (base=${BASE_EXISTS} head=${HEAD_EXISTS})"

    TYPE=""
    if $BASE_EXISTS && $HEAD_EXISTS; then
        TYPE="modified"
        "$LABVIEWCLI" \
            -OperationName    CreateComparisonReport \
            -LabVIEWPath      "$LABVIEW_EXE" \
            -VI1              "$BASE_PATH" \
            -VI2              "$HEAD_PATH" \
            -ReportType       html \
            -ReportPath       "${OUT_DIR}/index.html" \
            -LogToConsole     TRUE \
            -Headless || { echo "  ERROR: CreateComparisonReport failed"; ((ERRORS++)); continue; }

    elif $HEAD_EXISTS; then
        TYPE="added"
        "$LABVIEWCLI" \
            -OperationName                PrintToSingleFileHtml \
            -AdditionalOperationDirectory "$PRINT_TO_HTML_OP" \
            -LabVIEWPath                  "$LABVIEW_EXE" \
            -VI                           "$HEAD_PATH" \
            -OutputPath                   "${OUT_DIR}/index.html" \
            -o -c \
            -LogToConsole                 TRUE \
            -Headless || { echo "  ERROR: PrintToSingleFileHtml (added) failed"; ((ERRORS++)); continue; }

    elif $BASE_EXISTS; then
        TYPE="deleted"
        "$LABVIEWCLI" \
            -OperationName                PrintToSingleFileHtml \
            -AdditionalOperationDirectory "$PRINT_TO_HTML_OP" \
            -LabVIEWPath                  "$LABVIEW_EXE" \
            -VI                           "$BASE_PATH" \
            -OutputPath                   "${OUT_DIR}/index.html" \
            -o -c \
            -LogToConsole                 TRUE \
            -Headless || { echo "  ERROR: PrintToSingleFileHtml (deleted) failed"; ((ERRORS++)); continue; }
    else
        echo "  Skipping — not a valid LabVIEW binary"
        continue
    fi

    ((PROCESSED++))
done

echo ""
echo "=== VIDiff complete: ${PROCESSED} processed, ${ERRORS} errors ==="

# Write simple index page
{
cat << 'HTML'
<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"><title>VIDiff — challenge-of-champions</title>
<style>body{margin:0;padding:20px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:#0d1117;color:#e6edf3}
h1{font-size:1.3em}a{color:#58a6ff}</style></head>
<body><h1>VIDiff — challenge-of-champions</h1>
HTML
echo "<p style=\"color:#8b949e\">${PROCESSED} file(s) compared | ${ERRORS} error(s)</p>"
echo "<ul>"
for REL_PATH in "${VI_FILES[@]}"; do
    SAFE_NAME="${REL_PATH//[\/]/-}"
    SAFE_NAME="${SAFE_NAME//[^a-zA-Z0-9._-]/_}"
    echo "<li><a href=\"${SAFE_NAME}/index.html\">${REL_PATH}</a></li>"
done
echo "</ul></body></html>"
} > "${REPORT_DIR}/index.html"

[ "$ERRORS" -gt 0 ] && exit 1
exit 0
