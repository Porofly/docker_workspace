#!/bin/bash
# network_capture.sh - Packet capture tool (tcpdump wrapper)
# Captures raw traffic on a chosen interface to a pcap file.
# Analysis is handled by a separate tool.
#
# Usage: ./network_capture.sh [COMMAND] [OPTIONS]

set -euo pipefail

# ── Config ───────────────────────────────────────────────────────────────────
CAPTURE_DIR="${CAPTURE_DIR:-$(dirname "$0")/captures}"
PID_FILE="/tmp/network_capture.pid"

# Active Zenoh router config (used only to parse external_ifaces for --scope external)
ZENOH_ROUTER_CONFIG="${ZENOH_ROUTER_CONFIG_URI:-$(dirname "$0")/zenoh_config/router_config.json5}"

# Default capture scope: external (inter-drone link), internal (lo), all (any)
DEFAULT_SCOPE="${CAPTURE_SCOPE:-external}"

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

# ── Helpers ──────────────────────────────────────────────────────────────────
info()  { echo -e "${GREEN}[INFO]${RESET}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error() { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
die()   { error "$*"; exit 1; }

require_cmd() {
    command -v "$1" &>/dev/null || die "Command '$1' not found. Install: sudo apt install $1"
}

# Parse external interface names from the active Zenoh router config.
# Looks up the `external_ifaces` subject and returns its `interfaces: [...]`
# list as a space-separated string. Prints nothing on failure.
parse_external_ifaces_from_config() {
    local cfg="${1:-$ZENOH_ROUTER_CONFIG}"
    [ -f "$cfg" ] || return 0
    awk '
        /id:[[:space:]]*"external_ifaces"/ { found = 1; next }
        found && /interfaces:[[:space:]]*\[/ {
            line = $0
            sub(/.*\[/, "", line)
            sub(/\].*/, "", line)
            n = split(line, parts, ",")
            for (i = 1; i <= n; i++) {
                s = parts[i]
                gsub(/[[:space:]"]/, "", s)
                if (length(s) > 0) printf "%s ", s
            }
            exit
        }
    ' "$cfg"
}

# wireless 우선 → 첫 UP 인터페이스 → any 폴백
detect_iface() {
    for iface in /sys/class/net/*/wireless; do
        [ -d "$iface" ] && basename "$(dirname "$iface")" && return
    done
    for iface in /sys/class/net/*/operstate; do
        name=$(basename "$(dirname "$iface")")
        [ "$name" = "lo" ] && continue
        [ "$(cat "$iface" 2>/dev/null)" = "up" ] && echo "$name" && return
    done
    echo "any"
}

# Resolve scope -> single interface name (tcpdump accepts only one -i).
#   external: first UP interface from router_config external_ifaces,
#             fallback to detect_iface on miss.
#   internal: lo
#   all:      any
resolve_scope_iface() {
    local scope="$1"
    case "$scope" in
        internal) echo "lo"; return ;;
        all)      echo "any"; return ;;
        external)
            local ifaces up_iface="" skipped=()
            # shellcheck disable=SC2207
            ifaces=($(parse_external_ifaces_from_config))
            if [ "${#ifaces[@]}" -gt 0 ]; then
                for name in "${ifaces[@]}"; do
                    local state="down"
                    [ -r "/sys/class/net/$name/operstate" ] && \
                        state=$(cat "/sys/class/net/$name/operstate" 2>/dev/null)
                    if [ -z "$up_iface" ] && [ "$state" = "up" ]; then
                        up_iface="$name"
                    elif [ -n "$up_iface" ]; then
                        skipped+=("$name")
                    fi
                done
                if [ -n "$up_iface" ]; then
                    if [ "${#skipped[@]}" -gt 0 ]; then
                        warn "External scope: using '${up_iface}', skipping: ${skipped[*]} (tcpdump accepts one interface)" >&2
                    fi
                    echo "$up_iface"
                    return
                fi
                warn "External scope: none of [${ifaces[*]}] are UP; falling back to auto-detect" >&2
            fi
            detect_iface
            ;;
        *)
            die "Unknown scope: $scope (expected external|internal|all)"
            ;;
    esac
}

# ── Command: capture ─────────────────────────────────────────────────────────
cmd_capture() {
    local iface="${OPT_IFACE:-$(resolve_scope_iface "$OPT_SCOPE")}"
    local duration="${OPT_DURATION:-}"
    require_cmd tcpdump

    mkdir -p "$CAPTURE_DIR"
    local timestamp
    timestamp=$(date +"%Y%m%d_%H%M%S")
    local outfile="${CAPTURE_DIR}/capture_${OPT_SCOPE}_${iface}_${timestamp}.pcap"

    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        warn "Capture already running. (PID: $(cat "$PID_FILE"))"
        warn "To stop: $0 stop"
        exit 1
    fi

    info "Starting packet capture"
    echo -e "  Scope:      ${CYAN}${OPT_SCOPE}${RESET}"
    echo -e "  Interface:  ${CYAN}${iface}${RESET}"
    echo -e "  Output:     ${CYAN}${outfile}${RESET}"
    [ -n "$duration" ] && echo -e "  Duration:   ${CYAN}${duration}s${RESET}"
    echo ""

    local tcpdump_args=(-i "$iface" -w "$outfile" -s 0 --immediate-mode)
    [ -n "$duration" ] && tcpdump_args+=(-G "$duration" -W 1)

    if [ "${OPT_BG:-false}" = "true" ]; then
        sudo tcpdump "${tcpdump_args[@]}" &>/dev/null &
        echo $! | sudo tee "$PID_FILE" > /dev/null
        info "Background capture started (PID: $(cat "$PID_FILE"))"
        info "Stop: $0 stop"
    else
        info "Press Ctrl+C to stop capture"
        sudo tcpdump "${tcpdump_args[@]}"
        info "Capture complete: ${outfile}"
    fi
}

# ── Command: stop ────────────────────────────────────────────────────────────
cmd_stop() {
    if [ ! -f "$PID_FILE" ]; then
        warn "No background capture is running."
        exit 0
    fi
    local pid
    pid=$(cat "$PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
        sudo kill -SIGTERM "$pid"
        for i in $(seq 1 10); do
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.5
        done
        sudo rm -f "$PID_FILE"
        info "Capture stopped (PID: ${pid})"
    else
        warn "Process already terminated."
        sudo rm -f "$PID_FILE"
    fi
}

# ── Command: list ────────────────────────────────────────────────────────────
cmd_list() {
    if [ ! -d "$CAPTURE_DIR" ] || [ -z "$(ls -A "$CAPTURE_DIR" 2>/dev/null)" ]; then
        info "No capture files found. (directory: ${CAPTURE_DIR})"
        return
    fi

    echo -e "${BOLD}Saved capture files:${RESET}"
    echo ""
    printf "%-50s %10s %s\n" "Filename" "Size" "Created"
    printf "%-50s %10s %s\n" "$(printf -- '-%.0s' {1..50})" "----------" "-------------------"
    while IFS= read -r -d '' f; do
        local name size mtime
        name=$(basename "$f")
        size=$(du -sh "$f" 2>/dev/null | cut -f1)
        mtime=$(stat -c "%y" "$f" 2>/dev/null | cut -d'.' -f1)
        printf "%-50s %10s %s\n" "$name" "$size" "$mtime"
    done < <(find "$CAPTURE_DIR" -name "*.pcap" -print0 | sort -z)
}

# ── Command: status ──────────────────────────────────────────────────────────
cmd_status() {
    echo -e "${BOLD}Network Capture Status${RESET}"
    echo ""

    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        echo -e "Background capture: ${GREEN}running${RESET} (PID: $(cat "$PID_FILE"))"
    else
        echo -e "Background capture: ${YELLOW}stopped${RESET}"
    fi

    echo ""
    echo -e "${BOLD}tcpdump:${RESET}"
    if command -v tcpdump &>/dev/null; then
        echo -e "  ${GREEN}+${RESET} tcpdump  ($(command -v tcpdump))"
    else
        echo -e "  ${RED}x${RESET} tcpdump  (not installed)"
    fi

    echo ""
    echo -e "${BOLD}Network interfaces:${RESET}"
    for iface in /sys/class/net/*; do
        local name state wireless
        name=$(basename "$iface")
        state=$(cat "$iface/operstate" 2>/dev/null || echo "unknown")
        wireless=$([ -d "$iface/wireless" ] && echo " [WiFi]" || echo "")
        echo -e "  ${name}${CYAN}${wireless}${RESET}  (${state})"
    done

    echo ""
    echo -e "${BOLD}Zenoh router config:${RESET}"
    if [ -f "$ZENOH_ROUTER_CONFIG" ]; then
        echo -e "  ${ZENOH_ROUTER_CONFIG}  ${GREEN}[found]${RESET}"
    else
        echo -e "  ${ZENOH_ROUTER_CONFIG}  ${YELLOW}[missing]${RESET}"
    fi

    local ext_ifaces
    ext_ifaces=$(parse_external_ifaces_from_config)
    if [ -n "$ext_ifaces" ]; then
        echo -e "  External interfaces (from config):"
        for name in $ext_ifaces; do
            local state="missing"
            [ -r "/sys/class/net/$name/operstate" ] && \
                state=$(cat "/sys/class/net/$name/operstate" 2>/dev/null)
            echo -e "    ${CYAN}${name}${RESET}  (${state})"
        done
    else
        echo -e "  External interfaces: ${YELLOW}not found in config${RESET}"
    fi
}

# ── Usage ────────────────────────────────────────────────────────────────────
usage() {
    echo -e "${BOLD}network_capture.sh${RESET} - Packet capture tool (tcpdump wrapper)

${BOLD}Usage:${RESET}
  $0 <command> [options]

${BOLD}Commands:${RESET}
  ${CYAN}capture${RESET}              Start packet capture (Ctrl+C to stop)
  ${CYAN}capture --bg${RESET}         Start capture in background
  ${CYAN}stop${RESET}                 Stop background capture
  ${CYAN}list${RESET}                 List saved capture files
  ${CYAN}status${RESET}               Show capture status and interfaces

${BOLD}Options:${RESET}
  -i <interface>           Interface to capture on (overrides --scope)
  --scope <name>           Capture scope: external|internal|all (default: ${DEFAULT_SCOPE})
  --config <path>          Zenoh router config path (used for --scope external)
                           Default: \$ZENOH_ROUTER_CONFIG_URI or ./zenoh_config/router_config.json5
  --duration <seconds>     Capture time limit (default: unlimited)
  --dir <directory>        Capture file output directory (default: ./captures/)
  --bg                     Run capture in background

${BOLD}Scopes:${RESET}
  ${CYAN}external${RESET}  First UP interface from router_config.json5 external_ifaces.
  ${CYAN}internal${RESET}  Loopback (lo).
  ${CYAN}all${RESET}       ${BOLD}-i any${RESET}: every interface including lo.

${BOLD}Examples:${RESET}
  $0 status
  $0 capture
  $0 capture --scope internal --duration 30
  $0 capture --scope all --duration 30
  $0 capture -i wlP1p1s0 --duration 60
  $0 capture -i eno1 --bg
  $0 stop
  $0 list
"
}

# ── Argument parsing ─────────────────────────────────────────────────────────
OPT_IFACE=""
OPT_DURATION=""
OPT_BG="false"
OPT_SCOPE="$DEFAULT_SCOPE"
COMMAND=""
POSITIONAL=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        capture|stop|list|status)
            COMMAND="$1"; shift ;;
        -i|--interface)
            OPT_IFACE="$2"; shift 2 ;;
        --duration)
            OPT_DURATION="$2"; shift 2 ;;
        --dir)
            CAPTURE_DIR="$2"; shift 2 ;;
        --bg)
            OPT_BG="true"; shift ;;
        --scope)
            OPT_SCOPE="$2"; shift 2 ;;
        --config)
            ZENOH_ROUTER_CONFIG="$2"; shift 2 ;;
        -h|--help)
            usage; exit 0 ;;
        *)
            POSITIONAL+=("$1"); shift ;;
    esac
done

[ -z "$COMMAND" ] && { usage; exit 0; }

case "$COMMAND" in
    capture)  cmd_capture ;;
    stop)     cmd_stop ;;
    list)     cmd_list ;;
    status)   cmd_status ;;
    *)        die "Unknown command: $COMMAND"; usage ;;
esac
