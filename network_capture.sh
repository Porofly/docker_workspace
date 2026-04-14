#!/bin/bash
# network_capture.sh - DDS + Zenoh Dual-Protocol Network Analysis Tool
# Protocols: Fast-DDS/RTPS (rmw_fastrtps_cpp), uXRCE-DDS (MicroXRCEAgent), Zenoh router
# Real-time monitoring: bmon | Packet capture: tcpdump | Analysis: tshark/Wireshark
#
# Usage: ./network_capture.sh [COMMAND] [OPTIONS]

set -euo pipefail

# ── Config ───────────────────────────────────────────────────────────────────
CAPTURE_DIR="${CAPTURE_DIR:-$(dirname "$0")/captures}"
PID_FILE="/tmp/network_capture.pid"

# Zenoh port constants
ZENOH_SCOUTING_PORT=7446
ZENOH_SESSION_PORT=7447
ZENOH_REST_PORT=8000
ZENOH_MCAST_GROUP="224.0.0.224"

# Active Zenoh router config (matches ZENOH_ROUTER_CONFIG_URI in docker-compose.yml)
ZENOH_ROUTER_CONFIG="${ZENOH_ROUTER_CONFIG_URI:-$(dirname "$0")/zenoh_config/router_config.json5}"

# ── DDS / Fast-DDS (RTPS) constants ──────────────────────────────────────────
# ROS_DOMAIN_ID default is 0; override via environment.
ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-0}"
RMW_IMPLEMENTATION="${RMW_IMPLEMENTATION:-rmw_fastrtps_cpp}"

# Fast-DDS RTPS port formula (domain 0 defaults):
#   Metatraffic multicast : 7400 + 250*domain
#   Metatraffic unicast   : 7401 + 250*domain
#   User data multicast   : 7410 + 250*domain
#   User data unicast     : 7411 + 250*domain
DDS_META_MCAST_PORT=$(( 7400 + 250 * ROS_DOMAIN_ID ))
DDS_META_UCAST_PORT=$(( 7401 + 250 * ROS_DOMAIN_ID ))
DDS_USER_MCAST_PORT=$(( 7410 + 250 * ROS_DOMAIN_ID ))
DDS_USER_UCAST_PORT=$(( 7411 + 250 * ROS_DOMAIN_ID ))
DDS_MCAST_GROUP="239.255.0.1"

# ── uXRCE-DDS (MicroXRCEAgent) ───────────────────────────────────────────────
# Load DRONE_ID from .env in the script's directory if not already set in env.
_ENV_FILE="$(dirname "$0")/.env"
if [ -z "${DRONE_ID:-}" ] && [ -f "$_ENV_FILE" ]; then
    DRONE_ID=$(grep -E '^DRONE_ID=[0-9]+' "$_ENV_FILE" | head -1 | cut -d= -f2 | tr -d '[:space:]')
fi
DRONE_ID="${DRONE_ID:-1}"
UXRCE_PORT=$(( 8888 + DRONE_ID ))

# ── Capture scope & mode ─────────────────────────────────────────────────────
# Default capture scope: external (inter-drone link), internal (lo), all (any)
DEFAULT_SCOPE="${CAPTURE_SCOPE:-external}"
# Default capture mode: dds (RTPS+uXRCE only), zenoh (Zenoh only), all (both)
DEFAULT_MODE="${CAPTURE_MODE:-all}"

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

# Build a tcpdump BPF filter string based on capture mode.
# Modes:
#   dds    — Fast-DDS RTPS ports + uXRCE-DDS agent ports (all drones)
#   zenoh  — Zenoh scouting + session ports
#   all    — union of both (default)
#
# Fast-DDS unicast port allocation (RTPS spec §9.6.1.1):
#   Metatraffic unicast per participant: 7400 + 250*domain + 1 + 2*participant_id
#   User data unicast per participant:   7410 + 250*domain + 1 + 2*participant_id
#
#   Per-node participant IDs are assigned at runtime starting from 0.
#   For this setup: 2 nodes × up to 5 drones = 10 participants → offset up to +20
#   → Metatraffic unicast: 7401–7421, User data unicast: 7411–7431
#   A portrange of 7400–7435 covers all cases with headroom.
#
# uXRCE-DDS: one MicroXRCEAgent per drone, port = 8888 + DRONE_ID (1–5) → 8889–8893
build_bpf_filter() {
    local mode="${1:-$DEFAULT_MODE}"
    local with_rest="${2:-false}"

    # Fast-DDS RTPS: portrange covering multicast bases + all participant unicast offsets
    local dds_meta_range_lo=$(( DDS_META_MCAST_PORT ))           # 7400
    local dds_user_range_hi=$(( DDS_USER_MCAST_PORT + 35 ))      # 7410 + 35 = 7445 (충분한 여유)
    local dds_parts=(
        "(udp portrange ${dds_meta_range_lo}-${dds_user_range_hi})"
        "(udp portrange 8889-8893)"
    )
    local zenoh_parts=(
        "(udp port ${ZENOH_SCOUTING_PORT})"
        "(tcp port ${ZENOH_SESSION_PORT})"
        "(udp port ${ZENOH_SESSION_PORT})"
    )
    local parts=()
    case "$mode" in
        dds)
            parts=("${dds_parts[@]}")
            ;;
        zenoh)
            parts=("${zenoh_parts[@]}")
            [ "$with_rest" = "true" ] && parts+=("(tcp port ${ZENOH_REST_PORT})")
            ;;
        all|*)
            parts=("${dds_parts[@]}" "${zenoh_parts[@]}")
            [ "$with_rest" = "true" ] && parts+=("(tcp port ${ZENOH_REST_PORT})")
            ;;
    esac
    local IFS=' or '
    echo "${parts[*]}"
}

# Parse external interface names from the active Zenoh router config.
# Looks up the `external_ifaces` subject (see zenoh_config/router_config.json5)
# and returns its `interfaces: [...]` list as a space-separated string.
# Prints nothing on failure so callers can fall back.
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

# Auto-detect interface for Zenoh traffic
# Zenoh often runs locally (e.g. ROS 2 SITL), so we check where Zenoh
# traffic actually exists rather than blindly skipping loopback.
detect_iface() {
    # 1) Probe: find an interface that carries known protocol traffic right now
    if command -v tcpdump &>/dev/null; then
        local probe_filter probe_iface
        probe_filter="$(build_bpf_filter "all" "false")"
        probe_iface=$(sudo timeout 2 tcpdump -i any -nn -c 1 \
            "$probe_filter" 2>/dev/null \
            | awk '{print $1}' | head -1)
        if [ -n "$probe_iface" ]; then
            echo "$probe_iface"
            return
        fi
    fi
    # 2) prefer wireless interface
    for iface in /sys/class/net/*/wireless; do
        [ -d "$iface" ] && basename "$(dirname "$iface")" && return
    done
    # 3) first non-lo UP interface
    for iface in /sys/class/net/*/operstate; do
        name=$(basename "$(dirname "$iface")")
        [ "$name" = "lo" ] && continue
        [ "$(cat "$iface" 2>/dev/null)" = "up" ] && echo "$name" && return
    done
    # 4) fallback to 'any' (captures all interfaces including lo)
    echo "any"
}

# ── Command: monitor ─────────────────────────────────────────────────────────
cmd_monitor() {
    local iface="${OPT_IFACE:-$(resolve_scope_iface "$OPT_SCOPE")}"
    require_cmd bmon

    info "Starting real-time bandwidth monitoring (scope: ${CYAN}${OPT_SCOPE}${RESET}, interface: ${CYAN}${iface}${RESET})"
    echo -e "  ${BOLD}Keys:${RESET} q=quit / d=detail / arrows=switch interface"
    echo ""
    exec bmon -p "$iface"
}

# ── Command: capture ─────────────────────────────────────────────────────────
cmd_capture() {
    local iface="${OPT_IFACE:-$(resolve_scope_iface "$OPT_SCOPE")}"
    local filter
    if [ -n "$OPT_FILTER" ]; then
        filter="$OPT_FILTER"
    else
        filter="$(build_bpf_filter "$OPT_MODE" "$OPT_WITH_REST")"
    fi
    local duration="${OPT_DURATION:-}"
    require_cmd tcpdump

    mkdir -p "$CAPTURE_DIR"
    local timestamp
    timestamp=$(date +"%Y%m%d_%H%M%S")
    local outfile="${CAPTURE_DIR}/capture_${OPT_MODE}_${OPT_SCOPE}_${iface}_${timestamp}.pcap"

    # warn if already running
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        warn "Capture already running. (PID: $(cat "$PID_FILE"))"
        warn "To stop: $0 stop"
        exit 1
    fi

    info "Starting packet capture (mode: ${CYAN}${OPT_MODE}${RESET})"
    echo -e "  Scope:      ${CYAN}${OPT_SCOPE}${RESET}"
    echo -e "  Interface:  ${CYAN}${iface}${RESET}"
    echo -e "  BPF filter: ${CYAN}${filter}${RESET}"
    echo -e "  Output:     ${CYAN}${outfile}${RESET}"
    [ -n "$duration" ] && echo -e "  Duration:   ${CYAN}${duration}s${RESET}"
    case "$OPT_SCOPE" in
        external) echo -e "  ${YELLOW}Note:${RESET} Zenoh access_control blocks fmu/**, rosout/**, tf/** on external interfaces — only swarm/** visible here." ;;
        internal) echo -e "  ${YELLOW}Note:${RESET} loopback: DDS unicast sessions, fmu/**, uXRCE-DDS agent, and Zenoh client<->router sessions." ;;
        all)      echo -e "  ${YELLOW}Note:${RESET} scope=all (-i any): captures all interfaces including loopback; packets may appear duplicated." ;;
    esac
    echo ""

    local tcpdump_args=(-i "$iface" -w "$outfile" -s 0 --immediate-mode "$filter")
    [ -n "$duration" ] && tcpdump_args+=(-G "$duration" -W 1)

    if [ "${OPT_BG:-false}" = "true" ]; then
        # background capture
        sudo tcpdump "${tcpdump_args[@]}" &>/dev/null &
        echo $! | sudo tee "$PID_FILE" > /dev/null
        info "Background capture started (PID: $(cat "$PID_FILE"))"
        info "Stop: $0 stop"
    else
        # foreground capture (Ctrl+C to stop)
        info "Press Ctrl+C to stop capture"
        sudo tcpdump "${tcpdump_args[@]}"
        info "Capture complete: ${outfile}"
        echo ""
        info "Analyze with Wireshark: wireshark ${outfile}"
        info "Terminal summary: $0 summary ${outfile}"
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
        # wait for termination (max 5s)
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
    echo ""
    info "Analyze: wireshark <file>  or  $0 summary <file>"
}

# ── Command: summary ─────────────────────────────────────────────────────────
cmd_summary() {
    local pcap_file="${1:-}"
    [ -z "$pcap_file" ] && die "Usage: $0 summary <file.pcap>"
    [ -f "$pcap_file" ] || die "File not found: $pcap_file"
    require_cmd tcpdump

    # Build BPF filter based on current mode
    local SUMMARY_FILTER
    SUMMARY_FILTER="$(build_bpf_filter "${OPT_MODE:-all}" "$OPT_WITH_REST")"

    echo -e "${BOLD}Capture file summary: $(basename "$pcap_file")${RESET}"
    echo ""

    # ---- Overall Statistics (capinfos if available, else tcpdump) ----
    echo -e "${CYAN}-- Overall Statistics ---------------------${RESET}"
    if command -v capinfos &>/dev/null; then
        capinfos -cduaeyxz "$pcap_file" 2>/dev/null | tail -n +2 | sed 's/^/  /'
    else
        tcpdump -r "$pcap_file" -q 2>/dev/null | tail -3
    fi
    # min / max packets per second (appended to overall stats)
    tcpdump -r "$pcap_file" -nn -tt "$SUMMARY_FILTER" 2>/dev/null \
        | awk '{
            ts = int($1)
            pps[ts]++
            if (NR == 1) first = ts
            last = ts
          }
          END {
            if (NR == 0) exit
            min_pps = -1; max_pps = 0
            for (t = first; t <= last; t++) {
                v = (t in pps) ? pps[t] : 0
                if (min_pps < 0 || v < min_pps) min_pps = v
                if (v > max_pps) max_pps = v
            }
            printf "  Min packet rate:     %d packets/sec\n", min_pps
            printf "  Max packet rate:     %d packets/sec\n", max_pps
          }'

    # ---- Packet Size Statistics ----
    echo ""
    echo -e "${CYAN}-- Packet Size Statistics -----------------${RESET}"
    tcpdump -r "$pcap_file" -nn "$SUMMARY_FILTER" 2>/dev/null \
        | awk '{
            # extract "length <N>" at end of line
            for (i = 1; i <= NF; i++) {
                if ($i == "length") { len = $(i+1)+0; break }
            }
            if (len > 0) {
                count++
                total += len
                if (count == 1 || len > max) max = len
                if (count == 1 || len < min) min = len
            }
          }
          END {
            if (count > 0) {
                printf "  Total packets: %d\n", count
                printf "  Total bytes:   %d\n", total
                printf "  Min size:      %d bytes\n", min
                printf "  Max size:      %d bytes\n", max
                printf "  Avg size:      %d bytes\n", total / count
            } else {
                print "  No matching packets found."
            }
          }'

    # ---- Packets by Service (port categories) ----
    echo ""
    echo -e "${CYAN}-- Packets by Service ---------------------${RESET}"
    echo -e "  ${BOLD}By service:${RESET}"
    for label_port in \
        "Zenoh Scouting (UDP ${ZENOH_SCOUTING_PORT}):${ZENOH_SCOUTING_PORT}" \
        "Zenoh Session (TCP/UDP ${ZENOH_SESSION_PORT}):${ZENOH_SESSION_PORT}" \
        "DDS Meta Mcast (UDP ${DDS_META_MCAST_PORT}):${DDS_META_MCAST_PORT}" \
        "DDS Meta Ucast (UDP ${DDS_META_UCAST_PORT}):${DDS_META_UCAST_PORT}" \
        "DDS User Mcast (UDP ${DDS_USER_MCAST_PORT}):${DDS_USER_MCAST_PORT}" \
        "DDS User Ucast (UDP ${DDS_USER_UCAST_PORT}):${DDS_USER_UCAST_PORT}" \
        "uXRCE-DDS Agent (UDP ${UXRCE_PORT}):${UXRCE_PORT}"; do
        local label="${label_port%%:*}"
        local p="${label_port##*:}"
        local count
        count=$(tcpdump -r "$pcap_file" -nn "port $p" 2>/dev/null | wc -l)
        printf "    %-36s %d packets\n" "$label" "$count"
    done
    echo ""
    echo -e "  ${BOLD}By destination port (top 20):${RESET}"
    tcpdump -r "$pcap_file" -nn "$SUMMARY_FILTER" 2>/dev/null \
        | awk '{
            for (i = 1; i <= NF; i++) {
                if ($i == ">") {
                    dst = $(i+1)
                    sub(/:$/, "", dst)
                    n = split(dst, a, ".")
                    if (n >= 5) ports[a[5]]++
                    break
                }
            }
          }
          END {
            for (p in ports) print ports[p], "packets  port", p
          }' \
        | sort -rn | head -20

    # ---- Traffic Graph (packets per second) ----
    echo ""
    echo -e "${CYAN}-- Traffic Graph (packets/sec) ------------${RESET}"
    tcpdump -r "$pcap_file" -nn -tt "$SUMMARY_FILTER" 2>/dev/null \
        | awk '{
            ts = int($1)
            pps[ts]++
            if (NR == 1) first = ts
            last = ts
          }
          END {
            if (NR == 0) { print "  No matching packets found."; exit }
            # find max for scaling
            max = 0
            for (t in pps) if (pps[t] > max) max = pps[t]
            if (max == 0) { print "  No matching packets found."; exit }

            width = 50
            # print each second
            count = 0
            for (t = first; t <= last; t++) {
                v = (t in pps) ? pps[t] : 0
                bar_len = int(v * width / max + 0.5)
                bar = ""
                for (i = 0; i < bar_len; i++) bar = bar "#"
                printf "  %s |%-*s| %d pkt/s\n", strftime("%H:%M:%S", t), width, bar, v
                count++
                if (count >= 60) {
                    printf "  ... (%d more seconds omitted)\n", (last - first + 1) - count
                    break
                }
            }
            printf "\n  Peak: %d pkt/s\n", max
          }'
}

# ── Command: detail ──────────────────────────────────────────────────────────
cmd_detail() {
    local pcap_file="${1:-}"
    [ -z "$pcap_file" ] && die "Usage: $0 detail <file.pcap>"
    [ -f "$pcap_file" ] || die "File not found: $pcap_file"
    require_cmd tshark

    # Build tshark display filters (Wireshark syntax, not BPF)
    local DDS_TSHARK_FILTER="udp.port == ${DDS_META_MCAST_PORT} || udp.port == ${DDS_META_UCAST_PORT} || udp.port == ${DDS_USER_MCAST_PORT} || udp.port == ${DDS_USER_UCAST_PORT} || udp.port == ${UXRCE_PORT}"
    local ZENOH_TSHARK_FILTER="tcp.port == ${ZENOH_SESSION_PORT} || udp.port == ${ZENOH_SESSION_PORT} || udp.port == ${ZENOH_SCOUTING_PORT}"
    [ "$OPT_WITH_REST" = "true" ] && ZENOH_TSHARK_FILTER="${ZENOH_TSHARK_FILTER} || tcp.port == ${ZENOH_REST_PORT}"
    local DISPLAY_FILTER
    case "$OPT_MODE" in
        dds)   DISPLAY_FILTER="$DDS_TSHARK_FILTER" ;;
        zenoh) DISPLAY_FILTER="$ZENOH_TSHARK_FILTER" ;;
        all|*) DISPLAY_FILTER="${DDS_TSHARK_FILTER} || ${ZENOH_TSHARK_FILTER}" ;;
    esac

    echo -e "${BOLD}DDS + Zenoh Detail Analysis: $(basename "$pcap_file")${RESET}"
    echo -e "  Mode: ${CYAN}${OPT_MODE}${RESET}"

    # tshark may return non-zero on some operations; don't let set -e kill us
    set +e

    # 1) I/O statistics - auto-scaled to ~10 rows
    local io_duration
    io_duration=$(tshark -r "$pcap_file" -T fields -e frame.time_epoch 2>/dev/null \
        | awk 'NR==1{first=$1} {last=$1} END{if(NR>0) printf "%d", last-first+1; else print 1}')
    local io_interval=$(( io_duration / 10 ))
    [ "$io_interval" -lt 1 ] && io_interval=1
    echo ""
    echo -e "${CYAN}-- I/O Statistics (${io_interval}s intervals) --------${RESET}"
    tshark -r "$pcap_file" -q -z "io,stat,${io_interval},$DISPLAY_FILTER" 2>/dev/null

    # 2) Zenoh protocol dissection
    echo ""
    echo -e "${CYAN}-- Zenoh Protocol Traffic ----------------${RESET}"
    local zenoh_count
    zenoh_count=$(tshark -r "$pcap_file" -Y zenoh -T fields -e frame.number 2>/dev/null | wc -l)
    if [ "$zenoh_count" -gt 0 ]; then
        echo "  Zenoh dissected packets: $zenoh_count"
        echo ""
        echo -e "  ${BOLD}Zenoh message types:${RESET}"
        tshark -r "$pcap_file" -Y zenoh -T fields -e zenoh.msgtype 2>/dev/null \
            | tr ',' '\n' | sort | uniq -c | sort -rn | head -20 \
            | awk '{ printf "    %6d  %s\n", $1, $2 }'
        echo ""
        echo -e "  ${BOLD}Zenoh key expressions (top 10):${RESET}"
        tshark -r "$pcap_file" -Y zenoh -T fields -e zenoh.keyexpr 2>/dev/null \
            | sort | uniq -c | sort -rn | head -10 \
            | awk '{ printf "    %6d  %s\n", $1, $2 }'
    else
        echo "  No Zenoh dissected packets. (tshark may lack Zenoh dissector plugin)"
        echo "  Showing raw Zenoh port traffic instead:"
        echo ""
        tshark -r "$pcap_file" -Y "$ZENOH_TSHARK_FILTER" -c 10 2>/dev/null | sed 's/^/    /'
    fi

    # 2b) DDS/RTPS protocol dissection
    echo ""
    echo -e "${CYAN}-- DDS/RTPS Protocol Traffic (Fast-DDS) ---------${RESET}"
    local rtps_count
    rtps_count=$(tshark -r "$pcap_file" -Y rtps -T fields -e frame.number 2>/dev/null | wc -l)
    if [ "$rtps_count" -gt 0 ]; then
        echo "  RTPS dissected packets: $rtps_count"
        echo ""
        echo -e "  ${BOLD}RTPS submessage types (top 20):${RESET}"
        tshark -r "$pcap_file" -Y rtps \
            -T fields -e rtps.sm.id 2>/dev/null \
            | sort | uniq -c | sort -rn | head -20 \
            | awk '{ printf "    %6d  submessage_id=0x%s\n", $1, $2 }'
        echo ""
        echo -e "  ${BOLD}RTPS GUID prefixes / participants (top 10):${RESET}"
        tshark -r "$pcap_file" -Y rtps \
            -T fields -e rtps.guidPrefix 2>/dev/null \
            | sort | uniq -c | sort -rn | head -10 \
            | awk '{ printf "    %6d  %s\n", $1, $2 }'
        echo ""
        echo -e "  ${BOLD}uXRCE-DDS agent traffic (UDP port ${UXRCE_PORT}, DRONE_ID=${DRONE_ID}):${RESET}"
        local uxrce_count
        uxrce_count=$(tshark -r "$pcap_file" -Y "udp.port == ${UXRCE_PORT}" \
            -T fields -e frame.number 2>/dev/null | wc -l)
        echo "    $uxrce_count packets on port ${UXRCE_PORT} (PX4 <-> MicroXRCEAgent)"
    else
        echo "  No RTPS dissected packets. (RTPS dissector is built into Wireshark >= 2.x)"
        echo "  Showing raw DDS port traffic:"
        echo ""
        tshark -r "$pcap_file" -Y "$DDS_TSHARK_FILTER" -c 10 2>/dev/null | sed 's/^/    /'
    fi

    # 3) Scouting traffic analysis
    echo ""
    echo -e "${CYAN}-- Zenoh Scouting Traffic (UDP ${ZENOH_SCOUTING_PORT}) -----------${RESET}"
    local scout_count
    scout_count=$(tshark -r "$pcap_file" \
        -Y "udp.port == ${ZENOH_SCOUTING_PORT}" \
        -T fields -e frame.number 2>/dev/null | wc -l)
    echo "  Scouting packets: $scout_count"
    if [ "$scout_count" -gt 0 ]; then
        echo ""
        echo -e "  ${BOLD}Scouting sources:${RESET}"
        tshark -r "$pcap_file" -Y "udp.port == ${ZENOH_SCOUTING_PORT}" \
            -T fields -e ip.src 2>/dev/null \
            | sort | uniq -c | sort -rn | head -10 \
            | awk '{ printf "    %6d packets from %s\n", $1, $2 }'
    fi

    # 4) Endpoint statistics - which IPs send/receive most
    echo ""
    echo -e "${CYAN}-- Endpoint Statistics (IP) ---------------${RESET}"
    tshark -r "$pcap_file" -q -z endpoints,ip 2>/dev/null

    # 5) Conversation statistics
    echo ""
    echo -e "${CYAN}-- Conversations (IP) --------------------${RESET}"
    tshark -r "$pcap_file" -q -z conv,ip 2>/dev/null

    # 6) Multicast traffic
    echo ""
    echo -e "${CYAN}-- Multicast Traffic ---------------------${RESET}"
    local mcast_count
    mcast_count=$(tshark -r "$pcap_file" \
        -Y "ip.dst >= 224.0.0.0 && ip.dst <= 239.255.255.255" \
        -T fields -e frame.number 2>/dev/null | wc -l)
    echo "  Multicast packets: $mcast_count"
    if [ "$mcast_count" -gt 0 ]; then
        echo ""
        echo -e "  ${BOLD}Multicast destinations (top 10):${RESET}"
        tshark -r "$pcap_file" \
            -Y "ip.dst >= 224.0.0.0 && ip.dst <= 239.255.255.255" \
            -T fields -e ip.dst -e udp.dstport 2>/dev/null \
            | sort | uniq -c | sort -rn | head -10 \
            | awk '{ printf "    %6d packets -> %s:%s\n", $1, $2, $3 }'
        echo ""
        echo -e "  ${BOLD}Zenoh scouting multicast (${ZENOH_MCAST_GROUP}:${ZENOH_SCOUTING_PORT}):${RESET}"
        local zenoh_mcast
        zenoh_mcast=$(tshark -r "$pcap_file" \
            -Y "ip.dst == ${ZENOH_MCAST_GROUP} && udp.port == ${ZENOH_SCOUTING_PORT}" \
            -T fields -e frame.number 2>/dev/null | wc -l)
        echo "    $zenoh_mcast packets"
        echo ""
        echo -e "  ${BOLD}Fast-DDS discovery multicast (${DDS_MCAST_GROUP}:${DDS_META_MCAST_PORT}):${RESET}"
        local dds_mcast
        dds_mcast=$(tshark -r "$pcap_file" \
            -Y "ip.dst == ${DDS_MCAST_GROUP} && udp.port == ${DDS_META_MCAST_PORT}" \
            -T fields -e frame.number 2>/dev/null | wc -l)
        echo "    $dds_mcast packets"
    fi

    # 7) Port conversations - TCP and UDP separately
    echo ""
    echo -e "${CYAN}-- TCP Conversations -----------------------${RESET}"
    local tcp_conv_filter="tcp.port == ${ZENOH_SESSION_PORT}"
    [ "$OPT_WITH_REST" = "true" ] && tcp_conv_filter="${tcp_conv_filter} || tcp.port == ${ZENOH_REST_PORT}"
    tshark -r "$pcap_file" -q -z "conv,tcp,${tcp_conv_filter}" 2>/dev/null
    echo ""
    echo -e "${CYAN}-- UDP Conversations -----------------------${RESET}"
    local udp_conv_filter="udp.port == ${ZENOH_SCOUTING_PORT} || udp.port == ${ZENOH_SESSION_PORT} || udp.port == ${DDS_META_MCAST_PORT} || udp.port == ${DDS_META_UCAST_PORT} || udp.port == ${DDS_USER_MCAST_PORT} || udp.port == ${DDS_USER_UCAST_PORT} || udp.port == ${UXRCE_PORT}"
    tshark -r "$pcap_file" -q -z "conv,udp,${udp_conv_filter}" 2>/dev/null

    # 8) Packet size distribution
    echo ""
    echo -e "${CYAN}-- Packet Size Distribution --------------${RESET}"
    tshark -r "$pcap_file" -Y "$DISPLAY_FILTER" \
        -T fields -e frame.len 2>/dev/null \
        | awk 'BEGIN { b[0]="0-99"; b[1]="100-299"; b[2]="300-499"; b[3]="500-999"; b[4]="1000+" }
          {
            if ($1 < 100) dist[0]++
            else if ($1 < 300) dist[1]++
            else if ($1 < 500) dist[2]++
            else if ($1 < 1000) dist[3]++
            else dist[4]++
            total++
          }
          END {
            if (total == 0) { print "  No packets found."; exit }
            for (i = 0; i <= 4; i++) {
                c = (i in dist) ? dist[i] : 0
                pct = (c * 100) / total
                bar = ""
                bar_len = int(pct / 2 + 0.5)
                for (j = 0; j < bar_len; j++) bar = bar "#"
                printf "  %-10s %6d (%5.1f%%) %s\n", b[i] " B", c, pct, bar
            }
          }'

    # 9) Packet rate analysis
    echo ""
    echo -e "${CYAN}-- Packet Rate Analysis ------------------${RESET}"
    tshark -r "$pcap_file" -Y "$DISPLAY_FILTER" \
        -T fields -e frame.time_epoch 2>/dev/null \
        | awk '{
            ts = int($1)
            pps[ts]++
            if (NR == 1) first = ts
            last = ts
          }
          END {
            if (NR == 0) { print "  No packets found."; exit }
            duration = last - first + 1
            total = NR

            # basic stats
            min_pps = -1; max_pps = 0; max_ts = first
            sum_sq = 0
            avg = total / duration
            for (t = first; t <= last; t++) {
                v = (t in pps) ? pps[t] : 0
                if (min_pps < 0 || v < min_pps) min_pps = v
                if (v > max_pps) { max_pps = v; max_ts = t }
                sum_sq += (v - avg) * (v - avg)
            }
            stddev = sqrt(sum_sq / duration)

            printf "  Duration:        %d seconds\n", duration
            printf "  Total packets:   %d\n", total
            printf "  Avg rate:        %.1f packets/sec\n", avg
            printf "  Min rate:        %d packets/sec\n", min_pps
            printf "  Max rate:        %d packets/sec\n", max_pps

            # burst detection (> 2x average)
            threshold = avg * 2
            burst_count = 0
            for (t = first; t <= last; t++) {
                v = (t in pps) ? pps[t] : 0
                if (v > threshold) burst_count++
            }
            printf "\n  Burst threshold: >%.0f packets/sec (2x avg)\n", threshold
            printf "  Burst seconds:   %d / %d (%.1f%%)\n", burst_count, duration, (burst_count * 100) / duration

            # time-window packet distribution (auto-scaled intervals)
            if (duration <= 30) interval = 1
            else interval = int(duration / 30)
            if (interval < 1) interval = 1
            printf "\n  Time-window distribution (%ds intervals):\n", interval
            max_bucket = 0
            for (t = first; t <= last; t++) {
                v = (t in pps) ? pps[t] : 0
                b = int((t - first) / interval)
                bucket[b] += v
                if (bucket[b] > max_bucket) max_bucket = bucket[b]
            }
            num_buckets = int((duration - 1) / interval) + 1
            width = 40
            for (b = 0; b < num_buckets; b++) {
                c = (b in bucket) ? bucket[b] : 0
                t_start = first + b * interval
                t_end = t_start + interval - 1
                if (t_end > last) t_end = last
                bar = ""
                bar_len = (max_bucket > 0) ? int(c * width / max_bucket + 0.5) : 0
                for (j = 0; j < bar_len; j++) bar = bar "#"
                printf "  %s - %s  %6d pkts  |%-*s|\n", strftime("%H:%M:%S", t_start), strftime("%H:%M:%S", t_end), c, width, bar
            }
          }'

    set -e
}

# ── Command: status ──────────────────────────────────────────────────────────
cmd_status() {
    echo -e "${BOLD}DDS + Zenoh Network Capture Status${RESET}"
    echo ""

    # background capture status
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        echo -e "Background capture: ${GREEN}running${RESET} (PID: $(cat "$PID_FILE"))"
    else
        echo -e "Background capture: ${YELLOW}stopped${RESET}"
    fi

    # tool installation status
    echo ""
    echo -e "${BOLD}Installed tools:${RESET}"
    for tool in bmon tcpdump tshark wireshark; do
        if command -v "$tool" &>/dev/null; then
            echo -e "  ${GREEN}+${RESET} $tool  ($(command -v "$tool"))"
        else
            echo -e "  ${RED}x${RESET} $tool  (not installed)"
        fi
    done

    # Protocol dissector availability
    echo ""
    echo -e "${BOLD}Wireshark/tshark protocol dissectors:${RESET}"
    if command -v tshark &>/dev/null; then
        if tshark -G protocols 2>/dev/null | grep -q '^zenoh'; then
            echo -e "  ${GREEN}+${RESET} zenoh dissector available (Zenoh key-expression decoding enabled)"
        else
            echo -e "  ${YELLOW}!${RESET} zenoh dissector not found (install for Zenoh key-expression analysis)"
        fi
        if tshark -G protocols 2>/dev/null | grep -qi '^rtps'; then
            echo -e "  ${GREEN}+${RESET} RTPS dissector available (Fast-DDS/DDS protocol decoding enabled)"
        else
            echo -e "  ${YELLOW}!${RESET} RTPS dissector not found (built into Wireshark >= 2.x; check tshark version)"
        fi
    else
        echo -e "  ${RED}x${RESET} tshark not installed — no protocol dissection possible"
    fi

    # detected interfaces
    echo ""
    echo -e "${BOLD}Network interfaces:${RESET}"
    for iface in /sys/class/net/*; do
        local name state wireless
        name=$(basename "$iface")
        state=$(cat "$iface/operstate" 2>/dev/null || echo "unknown")
        wireless=$([ -d "$iface/wireless" ] && echo " [WiFi]" || echo "")
        echo -e "  ${name}${CYAN}${wireless}${RESET}  (${state})"
    done

    # DDS / ROS2 environment
    echo ""
    echo -e "${BOLD}DDS / ROS2 environment:${RESET}"
    echo -e "  RMW_IMPLEMENTATION:  ${CYAN}${RMW_IMPLEMENTATION}${RESET}"
    echo -e "  ROS_DOMAIN_ID:       ${CYAN}${ROS_DOMAIN_ID}${RESET}"
    echo -e "  DRONE_ID:            ${CYAN}${DRONE_ID}${RESET}  (from ${_ENV_FILE})"
    echo -e "  uXRCE-DDS port:      ${CYAN}${UXRCE_PORT}${RESET}  (= 8888 + DRONE_ID)"
    echo ""
    echo -e "${BOLD}Computed port assignments (ROS_DOMAIN_ID=${ROS_DOMAIN_ID}):${RESET}"
    echo -e "  Fast-DDS metatraffic multicast: UDP ${DDS_META_MCAST_PORT}  (${DDS_MCAST_GROUP}:${DDS_META_MCAST_PORT})"
    echo -e "  Fast-DDS metatraffic unicast:   UDP ${DDS_META_UCAST_PORT}"
    echo -e "  Fast-DDS user-data multicast:   UDP ${DDS_USER_MCAST_PORT}"
    echo -e "  Fast-DDS user-data unicast:     UDP ${DDS_USER_UCAST_PORT}"
    echo -e "  MicroXRCEAgent (uXRCE-DDS):     UDP ${UXRCE_PORT}"
    echo -e "  Zenoh scouting:                 UDP ${ZENOH_SCOUTING_PORT}  (${ZENOH_MCAST_GROUP}:${ZENOH_SCOUTING_PORT})"
    echo -e "  Zenoh session:                  TCP/UDP ${ZENOH_SESSION_PORT}"

    # Zenoh router config
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

    if command -v docker &>/dev/null; then
        echo ""
        echo -e "${BOLD}Containers:${RESET}"
        for c in ros2 px4; do
            local cstate
            cstate=$(docker ps --filter "name=^${c}$" --format '{{.Status}}' 2>/dev/null)
            if [ -n "$cstate" ]; then
                echo -e "  ${GREEN}+${RESET} ${c}: ${cstate}"
            else
                echo -e "  ${RED}x${RESET} ${c}: not running"
            fi
        done
    fi
}

# ── Usage ────────────────────────────────────────────────────────────────────
usage() {
    echo -e "${BOLD}network_capture.sh${RESET} - DDS + Zenoh Dual-Protocol Network Analysis Tool

${BOLD}Usage:${RESET}
  $0 <command> [options]

${BOLD}Commands:${RESET}
  ${CYAN}monitor${RESET}              Real-time bandwidth monitoring (bmon)
  ${CYAN}capture${RESET}              Start packet capture (tcpdump, Ctrl+C to stop)
  ${CYAN}capture --bg${RESET}         Start capture in background
  ${CYAN}stop${RESET}                 Stop background capture
  ${CYAN}list${RESET}                 List saved capture files
  ${CYAN}summary <file.pcap>${RESET}  Text summary of capture file
  ${CYAN}detail <file.pcap>${RESET}   Deep DDS + Zenoh protocol analysis with tshark
  ${CYAN}status${RESET}               Show capture status, environment, and tool availability

${BOLD}Options:${RESET}
  -i <interface>           Interface to monitor (overrides --scope)
  --scope <name>           Capture scope: external|internal|all (default: ${DEFAULT_SCOPE})
  --mode <mode>            Protocol filter mode: dds|zenoh|all (default: ${DEFAULT_MODE})
                             dds:   Fast-DDS/RTPS ports + uXRCE-DDS only
                             zenoh: Zenoh scouting + session only
                             all:   Both DDS and Zenoh (recommended)
  --with-rest              Include Zenoh REST API port ${ZENOH_REST_PORT} in filter
                           (only meaningful with --mode zenoh or all)
  --config <path>          Zenoh router config path (default: \$ZENOH_ROUTER_CONFIG_URI
                           or ./zenoh_config/router_config.json5)
  --filter <BPF>           Custom tcpdump BPF filter (overrides --mode)
  --duration <seconds>     Capture time limit (default: unlimited)
  --dir <directory>        Capture file output directory (default: ./captures/)
  --bg                     Run capture in background

${BOLD}Scopes:${RESET}
  ${CYAN}external${RESET}  Inter-drone link (wlP1p1s0/eno1, parsed from router_config.json5).
            Zenoh access_control blocks ${BOLD}fmu/**${RESET}, ${BOLD}rosout/**${RESET}, ${BOLD}tf/**${RESET} here — only ${BOLD}swarm/**${RESET} visible.
  ${CYAN}internal${RESET}  Loopback (lo). Includes DDS unicast sessions, ${BOLD}fmu/**${RESET}, uXRCE-DDS agent,
            and Zenoh client<->router sessions inside the host.
  ${CYAN}all${RESET}       ${BOLD}-i any${RESET}: captures every interface including lo. Packets on
            multiple ifaces may appear duplicated.

${BOLD}Examples:${RESET}
  $0 status                                        # show env, ports, containers, external ifaces
  $0 monitor                                       # external scope, auto interface
  $0 capture                                       # default: mode=all, scope=external
  $0 capture --mode dds                            # DDS + uXRCE only
  $0 capture --mode zenoh                          # Zenoh only
  $0 capture --mode all --scope internal           # everything on loopback
  $0 capture --scope internal --duration 30        # loopback: DDS unicast, fmu/**, sessions
  $0 capture --scope all --duration 30             # every interface
  $0 capture -i wlP1p1s0 --duration 60             # explicit iface (overrides scope)
  $0 capture -i eno1 --bg
  $0 stop
  $0 list
  $0 summary captures/capture_all_external_wlP1p1s0_20260304_120000.pcap
  $0 detail  captures/capture_dds_internal_lo_20260304_120000.pcap --mode dds

${BOLD}Port reference (DRONE_ID=${DRONE_ID}, ROS_DOMAIN_ID=${ROS_DOMAIN_ID}):${RESET}
  Fast-DDS RTPS:
    ${DDS_META_MCAST_PORT}   UDP metatraffic multicast   (${DDS_MCAST_GROUP}:${DDS_META_MCAST_PORT})
    ${DDS_META_UCAST_PORT}   UDP metatraffic unicast
    ${DDS_USER_MCAST_PORT}   UDP user-data multicast
    ${DDS_USER_UCAST_PORT}   UDP user-data unicast
  uXRCE-DDS (MicroXRCEAgent):
    ${UXRCE_PORT}   UDP agent port  (= 8888 + DRONE_ID)
  Zenoh router:
    ${ZENOH_SCOUTING_PORT}   UDP scouting/discovery      (multicast ${ZENOH_MCAST_GROUP})
    ${ZENOH_SESSION_PORT}   TCP/UDP session traffic
    ${ZENOH_REST_PORT}   TCP REST API                (optional, --with-rest)

${BOLD}Topic architecture:${RESET}
  PX4 -> uXRCE-DDS agent (UDP ${UXRCE_PORT}) -> ROS2 Fast-DDS:
    /px4_${DRONE_ID}/fmu/out/vehicle_local_position_v1   (RTPS, internal only)
    /px4_${DRONE_ID}/fmu/out/vehicle_status_v1           (RTPS, internal only)
  swarm_bridge publishes to Zenoh (external-visible):
    /swarm/drone_${DRONE_ID}/pose     10 Hz  (NED->ENU converted)
    /swarm/drone_${DRONE_ID}/status   1 Hz   (JSON: arm/nav/failsafe state)

${BOLD}Wireshark display filter examples:${RESET}
  Zenoh:
    zenoh                                           Zenoh protocol (requires dissector plugin)
    tcp.port == ${ZENOH_SESSION_PORT} || udp.port == ${ZENOH_SESSION_PORT}        Zenoh session traffic
    udp.port == ${ZENOH_SCOUTING_PORT}                               Zenoh scouting
    ip.dst == ${ZENOH_MCAST_GROUP}                           Zenoh scouting multicast
    zenoh.keyexpr contains \"swarm/drone_\"             Swarm bridge topics (needs dissector)
  DDS/RTPS (Fast-DDS):
    rtps                                            All RTPS traffic (built-in dissector)
    ip.dst == ${DDS_MCAST_GROUP}                         Fast-DDS discovery multicast
    udp.port == ${DDS_META_MCAST_PORT}                              DDS metatraffic discovery
    udp.port == ${UXRCE_PORT}                                 uXRCE-DDS agent (PX4 <-> ROS2)
    rtps && ip.src == <PX4-IP>                      PX4 RTPS traffic only
"
}

# ── Argument parsing ─────────────────────────────────────────────────────────
OPT_IFACE=""
OPT_FILTER=""
OPT_DURATION=""
OPT_BG="false"
OPT_SCOPE="$DEFAULT_SCOPE"
OPT_MODE="$DEFAULT_MODE"
OPT_WITH_REST="false"
COMMAND=""
POSITIONAL=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        monitor|capture|stop|list|summary|detail|status)
            COMMAND="$1"; shift ;;
        -i|--interface)
            OPT_IFACE="$2"; shift 2 ;;
        --filter)
            OPT_FILTER="$2"; shift 2 ;;
        --duration)
            OPT_DURATION="$2"; shift 2 ;;
        --dir)
            CAPTURE_DIR="$2"; shift 2 ;;
        --bg)
            OPT_BG="true"; shift ;;
        --scope)
            OPT_SCOPE="$2"; shift 2 ;;
        --mode)
            OPT_MODE="$2"
            case "$OPT_MODE" in
                dds|zenoh|all) ;;
                *) die "Invalid --mode: '$OPT_MODE'. Expected: dds|zenoh|all" ;;
            esac
            shift 2 ;;
        --with-rest)
            OPT_WITH_REST="true"; shift ;;
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
    monitor)  cmd_monitor ;;
    capture)  cmd_capture ;;
    stop)     cmd_stop ;;
    list)     cmd_list ;;
    summary)  cmd_summary "${POSITIONAL[0]:-}" ;;
    detail)   cmd_detail "${POSITIONAL[0]:-}" ;;
    status)   cmd_status ;;
    *)        die "Unknown command: $COMMAND"; usage ;;
esac
