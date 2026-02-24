#!/bin/bash

# Build progress visualization
# Provides real-time progress tracking and visual status updates

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Progress bar file location
PROGRESS_FILE="/tmp/build_progress.json"

# Initialize progress tracking
init_progress_tracking() {
    local total_archs=$1
    local version=$2
    local package_name=$3
    
    # Initialize progress file
    cat > "$PROGRESS_FILE" << EOF
{
    "total_archs": $total_archs,
    "completed": 0,
    "failed": 0,
    "running": 0,
    "pending": $total_archs,
    "start_time": $(date +%s),
    "package": "$package_name",
    "version": "$version",
    "architectures": {}
}
EOF
}

# Update architecture status
# Usage: update_arch_status <arch> <status> [details]
# status: running, completed, failed, pending
update_arch_status() {
    local arch=$1
    local status=$2
    local details="${3:-}"
    local timestamp=$(date +%s)
    
    if [ ! -f "$PROGRESS_FILE" ]; then
        return 1
    fi
    
    # Read current progress
    local current=$(cat "$PROGRESS_FILE")
    
    # Update architecture status
    echo "$current" | jq --arg arch "$arch" --arg status "$status" --arg ts "$timestamp" --arg details "$details" '
        .architectures[$arch] = {
            "status": $status,
            "updated_at": ($ts | tonumber),
            "details": $details
        }
    ' > "${PROGRESS_FILE}.tmp" && mv "${PROGRESS_FILE}.tmp" "$PROGRESS_FILE"
    
    # Update counters
    update_progress_counters
}

# Update progress counters
update_progress_counters() {
    if [ ! -f "$PROGRESS_FILE" ]; then
        return 1
    fi
    
    local completed=$(jq '[.architectures[] | select(.status == "completed")] | length' "$PROGRESS_FILE")
    local failed=$(jq '[.architectures[] | select(.status == "failed")] | length' "$PROGRESS_FILE")
    local running=$(jq '[.architectures[] | select(.status == "running")] | length' "$PROGRESS_FILE")
    local pending=$(jq '[.architectures[] | select(.status == "pending" or .status == null)] | length' "$PROGRESS_FILE")
    local total=$(jq '.total_archs' "$PROGRESS_FILE")
    
    jq --argjson c "$completed" --argjson f "$failed" --argjson r "$running" --argjson p "$pending" '
        .completed = $c |
        .failed = $f |
        .running = $r |
        .pending = $p
    ' "$PROGRESS_FILE" > "${PROGRESS_FILE}.tmp" && mv "${PROGRESS_FILE}.tmp" "$PROGRESS_FILE"
}

# Draw progress bar
# Usage: draw_progress_bar <current> <total> <width>
draw_progress_bar() {
    local current=$1
    local total=$2
    local width=${3:-30}
    
    if [ $total -eq 0 ]; then
        printf "[%${width}s]" ""
        return
    fi
    
    local filled=$((current * width / total))
    local empty=$((width - filled))
    
    printf "${GREEN}["
    printf '%*s' "$filled" | tr ' ' '█'
    printf "${NC}"
    printf '%*s' "$empty" | tr ' ' '░'
    printf "]"
}

# Draw architecture status line
# Usage: draw_arch_line <arch> <status> [time]
draw_arch_line() {
    local arch=$1
    local status=$2
    local time="${3:-}"
    
    local icon=""
    local color=""
    
    case "$status" in
        "running")
            icon="🔄"
            color="$CYAN"
            ;;
        "completed")
            icon="✅"
            color="$GREEN"
            ;;
        "failed")
            icon="❌"
            color="$RED"
            ;;
        "pending")
            icon="⏳"
            color="$YELLOW"
            ;;
        *)
            icon="❓"
            color="$NC"
            ;;
    esac
    
    printf "  ${color}%s %-10s %-12s${NC}" "$icon" "$arch" "$status"
    if [ -n "$time" ]; then
        printf " (%s)" "$time"
    fi
    printf "\n"
}

# Display full progress dashboard
# Usage: display_progress_dashboard
display_progress_dashboard() {
    if [ ! -f "$PROGRESS_FILE" ]; then
        return 1
    fi
    
    local progress=$(cat "$PROGRESS_FILE")
    local total=$(echo "$progress" | jq '.total_archs')
    local completed=$(echo "$progress" | jq '.completed')
    local failed=$(echo "$progress" | jq '.failed')
    local running=$(echo "$progress" | jq '.running')
    local pending=$(echo "$progress" | jq '.pending')
    local start_time=$(echo "$progress" | jq '.start_time')
    local package=$(echo "$progress" | jq -r '.package')
    local version=$(echo "$progress" | jq -r '.version')
    
    # Calculate elapsed time
    local now=$(date +%s)
    local elapsed=$((now - start_time))
    local elapsed_min=$((elapsed / 60))
    local elapsed_sec=$((elapsed % 60))
    
    # Clear screen and move cursor to top
    echo -e "\033[H\033[J"
    
    # Header
    echo "=========================================="
    echo "  Building $package $version"
    echo "=========================================="
    echo ""
    
    # Overall progress
    printf "  Overall: "
    draw_progress_bar $((completed + failed)) "$total" 25
    printf " %d/%d\n" $((completed + failed)) "$total"
    echo ""
    
    # Status summary
    echo -e "  ${GREEN}✅ Completed:${NC} $completed"
    echo -e "  ${CYAN}🔄 Running:${NC} $running"
    echo -e "  ${RED}❌ Failed:${NC} $failed"
    echo -e "  ${YELLOW}⏳ Pending:${NC} $pending"
    echo ""
    
    # Elapsed time
    printf "  ⏱️  Elapsed: %dm %ds\n" $elapsed_min $elapsed_sec
    echo ""
    
    # Architecture details
    echo "  Architecture Status:"
    echo "  ────────────────────────────────────────"
    
    # Show each architecture status
    echo "$progress" | jq -r '.architectures | to_entries[] | "\(.key) \(.value.status)"' 2>/dev/null | while read -r arch status; do
        if [ -n "$arch" ] && [ -n "$status" ]; then
            draw_arch_line "$arch" "$status"
        fi
    done
    
    echo ""
    echo "=========================================="
    echo "  Press Ctrl+C to cancel build"
    echo "=========================================="
}

# Display simplified progress (for CI logs)
# Usage: display_simple_progress <completed> <total> <status>
display_simple_progress() {
    local completed=$1
    local total=$2
    local status=$3
    
    local percent=$((completed * 100 / total))
    local bar_width=30
    local filled=$((percent * bar_width / 100))
    
    printf "\r  ["
    printf '%*s' "$filled" | tr ' ' '█'
    printf '%*s' $((bar_width - filled)) | tr ' ' '░'
    printf "] %3d%% (%d/%d) %s" "$percent" "$completed" "$total" "$status"
}

# Format duration in human-readable format
format_duration() {
    local seconds=$1
    local minutes=$((seconds / 60))
    local remaining_seconds=$((seconds % 60))
    
    if [ $minutes -gt 0 ]; then
        printf "%dm%ds" $minutes $remaining_seconds
    else
        printf "%ds" $remaining_seconds
    fi
}

# Calculate ETA
# Usage: calculate_eta <completed> <total> <elapsed_seconds>
calculate_eta() {
    local completed=$1
    local total=$2
    local elapsed=$3
    
    if [ $completed -eq 0 ]; then
        echo "calculating..."
        return
    fi
    
    local avg_time=$((elapsed / completed))
    local remaining=$((total - completed))
    local eta_seconds=$((avg_time * remaining))
    
    format_duration $eta_seconds
}

# Cleanup progress tracking
cleanup_progress_tracking() {
    rm -f "$PROGRESS_FILE" "${PROGRESS_FILE}.tmp" 2>/dev/null
}

# Export functions
export -f init_progress_tracking
export -f update_arch_status
export -f update_progress_counters
export -f draw_progress_bar
export -f draw_arch_line
export -f display_progress_dashboard
export -f display_simple_progress
export -f format_duration
export -f calculate_eta
export -f cleanup_progress_tracking
