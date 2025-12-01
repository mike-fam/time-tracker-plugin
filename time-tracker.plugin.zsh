#!/usr/bin/env zsh
# time-tracker.plugin.zsh
# Tracks time spent on git branches across multiple repositories

# Configuration
TIME_TRACKER_DATA_DIR="${TIME_TRACKER_DATA_DIR:-${HOME}/.time-tracker-data}"
TIME_TRACKER_CHECK_INTERVAL="${TIME_TRACKER_CHECK_INTERVAL:-600}" # 10 minutes in seconds
TIME_TRACKER_IDLE_THRESHOLD="${TIME_TRACKER_IDLE_THRESHOLD:-1800}" # 30 minutes in seconds

# Internal state
typeset -g TIME_TRACKER_LAST_CHECK=0
typeset -g TIME_TRACKER_LAST_ACTIVITY=0
typeset -g TIME_TRACKER_SESSION_ID=""

# Initialize plugin
function __time_tracker_init() {
    # Check for jq dependency
    if ! command -v jq &>/dev/null; then
        echo "Error: time-tracker plugin requires 'jq' but it's not installed." >&2
        echo "Install it with: brew install jq (macOS) or apt-get install jq (Linux)" >&2
        return 1
    fi
    
    # Create data directory if it doesn't exist
    [[ ! -d "$TIME_TRACKER_DATA_DIR" ]] && mkdir -p "$TIME_TRACKER_DATA_DIR"
    
    # Generate session ID
    TIME_TRACKER_SESSION_ID="$$-$(date +%s)"
    
    # Initialize timestamps
    TIME_TRACKER_LAST_CHECK=$(date +%s)
    TIME_TRACKER_LAST_ACTIVITY=$(date +%s)
    
    # Initial track
    __time_tracker_record
}

# Get repository identifier
function __time_tracker_get_repo_id() {
    if git rev-parse --git-dir &>/dev/null; then
        local repo_path=$(git rev-parse --show-toplevel 2>/dev/null)
        if [[ -n "$repo_path" ]]; then
            echo "$repo_path"
            return 0
        fi
    fi
    return 1
}

# Get current branch name
function __time_tracker_get_branch() {
    git rev-parse --abbrev-ref HEAD 2>/dev/null
}

# Get data file path for current repository
function __time_tracker_get_data_file() {
    local repo_id="$1"
    if [[ -z "$repo_id" ]]; then
        return 1
    fi
    
    # Create a safe filename from repo path
    local safe_name=$(echo "$repo_id" | sed 's/[^a-zA-Z0-9]/_/g')
    echo "${TIME_TRACKER_DATA_DIR}/${safe_name}.dat"
}

# Check if terminal is idle
function __time_tracker_is_idle() {
    local current_time=$(date +%s)
    local idle_time=$((current_time - TIME_TRACKER_LAST_ACTIVITY))
    
    if [[ $idle_time -gt $TIME_TRACKER_IDLE_THRESHOLD ]]; then
        return 0  # Is idle
    else
        return 1  # Not idle
    fi
}

# Record time spent
function __time_tracker_record() {
    local repo_id=$(__time_tracker_get_repo_id)
    [[ -z "$repo_id" ]] && return
    
    local branch=$(__time_tracker_get_branch)
    [[ -z "$branch" ]] && return
    
    local data_file=$(__time_tracker_get_data_file "$repo_id")
    [[ -z "$data_file" ]] && return
    
    local current_time=$(date +%s)
    
    # Check if we should skip due to idle time
    if __time_tracker_is_idle; then
        # Reset activity timestamp but don't record time
        TIME_TRACKER_LAST_ACTIVITY=$current_time
        TIME_TRACKER_LAST_CHECK=$current_time
        return
    fi
    
    # Calculate time delta since last check
    local time_delta=$((current_time - TIME_TRACKER_LAST_CHECK))
    
    # Only record if time delta is reasonable (not from system sleep/suspend)
    if [[ $time_delta -lt 3600 ]]; then  # Less than 1 hour
        local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        
        # Append to data file: timestamp|repo|branch|seconds
        echo "${timestamp}|${repo_id}|${branch}|${time_delta}" >> "$data_file"
    fi
    
    TIME_TRACKER_LAST_CHECK=$current_time
}

# Periodic check (called from precmd)
function __time_tracker_periodic_check() {
    local current_time=$(date +%s)
    local time_since_check=$((current_time - TIME_TRACKER_LAST_CHECK))
    
    # Only check if interval has passed
    if [[ $time_since_check -ge $TIME_TRACKER_CHECK_INTERVAL ]]; then
        __time_tracker_record
    fi
}

# Update activity timestamp on command execution
function __time_tracker_on_command() {
    TIME_TRACKER_LAST_ACTIVITY=$(date +%s)
}

# Show time statistics
function time-tracker-stats() {
    local target_repo=""
    local target_branch=""
    local show_all=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -a|--all)
                show_all=true
                shift
                ;;
            -b|--branch)
                target_branch="$2"
                shift 2
                ;;
            *)
                echo "Unknown option: $1"
                echo "Usage: time-tracker-stats [-a|--all] [-b|--branch BRANCH]"
                return 1
                ;;
        esac
    done
    
    # Get current repository
    if ! $show_all; then
        target_repo=$(__time_tracker_get_repo_id)
        if [[ -z "$target_repo" ]]; then
            echo "Not in a git repository. Use --all to see stats from all repositories."
            return 1
        fi
        
        # Default to current branch if not specified
        if [[ -z "$target_branch" ]]; then
            target_branch=$(__time_tracker_get_branch)
        fi
    fi
    
    # Process data files
    if $show_all; then
        # Show stats for all repositories
        __time_tracker_process_all_stats
    else
        # Show stats for current repository
        local data_file=$(__time_tracker_get_data_file "$target_repo")
        if [[ ! -f "$data_file" ]]; then
            echo "No tracking data available for this repository."
            return 0
        fi
        
        __time_tracker_process_repo_stats "$data_file" "$target_repo" "$target_branch"
    fi
}

# Process stats for a specific repository
function __time_tracker_process_repo_stats() {
    local data_file="$1"
    local repo_path="$2"
    local filter_branch="$3"
    
    echo "Repository: $repo_path"
    echo ""
    
    # Use associative array to track time per branch
    typeset -A branch_times
    
    while IFS='|' read -r timestamp repo branch seconds; do
        if [[ -n "$filter_branch" && "$branch" != "$filter_branch" ]]; then
            continue
        fi
        
        if [[ -n "${branch_times[$branch]}" ]]; then
            branch_times[$branch]=$((branch_times[$branch] + seconds))
        else
            branch_times[$branch]=$seconds
        fi
    done < "$data_file"
    
    # Display results
    if [[ ${#branch_times[@]} -eq 0 ]]; then
        echo "No data available."
        return
    fi
    
    echo "Time spent per branch:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Sort by time (descending)
    for branch in ${(k)branch_times}; do
        local total_seconds=${branch_times[$branch]}
        local hours=$((total_seconds / 3600))
        local minutes=$(((total_seconds % 3600) / 60))
        printf "%-40s %3dh %2dm\n" "$branch" "$hours" "$minutes"
    done | sort -k2 -k3 -rn
}

# Process stats for all repositories
function __time_tracker_process_all_stats() {
    echo "Time tracking statistics (all repositories)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    local found_data=false
    
    for data_file in "$TIME_TRACKER_DATA_DIR"/*.dat(N); do
        if [[ ! -f "$data_file" ]]; then
            continue
        fi
        
        found_data=true
        
        # Extract repo path from data
        local repo_path=$(head -n 1 "$data_file" | cut -d'|' -f2)
        
        __time_tracker_process_repo_stats "$data_file" "$repo_path" ""
        echo ""
    done
    
    if ! $found_data; then
        echo "No tracking data available."
    fi
}

# Clear tracking data
function time-tracker-clear() {
    local confirm=""
    local clear_all=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -a|--all)
                clear_all=true
                shift
                ;;
            -y|--yes)
                confirm="y"
                shift
                ;;
            *)
                echo "Unknown option: $1"
                echo "Usage: time-tracker-clear [-a|--all] [-y|--yes]"
                return 1
                ;;
        esac
    done
    
    if $clear_all; then
        if [[ "$confirm" != "y" ]]; then
            echo -n "Clear all tracking data? [y/N] "
            read confirm
        fi
        
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
            rm -f "$TIME_TRACKER_DATA_DIR"/*.dat
            echo "All tracking data cleared."
        else
            echo "Cancelled."
        fi
    else
        local repo_id=$(__time_tracker_get_repo_id)
        if [[ -z "$repo_id" ]]; then
            echo "Not in a git repository."
            return 1
        fi
        
        local data_file=$(__time_tracker_get_data_file "$repo_id")
        
        if [[ "$confirm" != "y" ]]; then
            echo -n "Clear tracking data for this repository? [y/N] "
            read confirm
        fi
        
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
            rm -f "$data_file"
            echo "Tracking data cleared for this repository."
        else
            echo "Cancelled."
        fi
    fi
}

# Export data to JSON format
function time-tracker-export() {
    local output_file="${1:-time-tracker-export.json}"
    
    # Check for jq
    if ! command -v jq &>/dev/null; then
        echo "Error: jq is required for exporting. Install with: brew install jq" >&2
        return 1
    fi
    
    # Build JSON object using jq
    local exported_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local temp_data=$(mktemp)
    
    # Start with empty repositories object
    echo '{}' > "$temp_data"
    
    for data_file in "$TIME_TRACKER_DATA_DIR"/*.dat(N); do
        if [[ ! -f "$data_file" ]]; then
            continue
        fi
        
        # Get repo path from first line
        local repo_path=$(head -n 1 "$data_file" | cut -d'|' -f2)
        
        # Build entries array for this repository
        local entries_json=$(awk -F'|' '{
            printf "{\"timestamp\":\"%s\",\"branch\":\"%s\",\"seconds\":%s}\n", $1, $3, $4
        }' "$data_file" | jq -s '.')
        
        # Add repository to the object
        echo "$(cat "$temp_data")" | jq --arg repo "$repo_path" --argjson entries "$entries_json" \
            '.[$repo] = {"entries": $entries}' > "${temp_data}.tmp"
        mv "${temp_data}.tmp" "$temp_data"
    done
    
    # Create final JSON with exported timestamp and repositories
    jq -n --arg exported "$exported_time" --argjson repos "$(cat "$temp_data")" \
        '{"exported": $exported, "repositories": $repos}' > "$output_file"
    
    rm -f "$temp_data"
    
    echo "Data exported to: $output_file"
}' >> "$output_file"
    echo '  "repositories": {' >> "$output_file"
    
    local first_repo=true
    
    for data_file in "$TIME_TRACKER_DATA_DIR"/*.dat(N); do
        if [[ ! -f "$data_file" ]]; then
            continue
        fi
        
        if ! $first_repo; then
            echo "    }," >> "$output_file"
        fi
        first_repo=false
        
        # Get repo path from first line
        local repo_path=$(head -n 1 "$data_file" | cut -d'|' -f2)
        
        echo "    \"$repo_path\": {" >> "$output_file"
        echo '      "entries": [' >> "$output_file"
        
        local first_entry=true
        while IFS='|' read -r timestamp repo branch seconds; do
            if ! $first_entry; then
                echo "," >> "$output_file"
            fi
            first_entry=false
            
            echo -n "        {\"timestamp\": \"$timestamp\", \"branch\": \"$branch\", \"seconds\": $seconds}" >> "$output_file"
        done < "$data_file"
        
        echo "" >> "$output_file"
        echo "      ]" >> "$output_file"
    done
    
    if ! $first_repo; then
        echo "    }" >> "$output_file"
    fi
    
    echo "  }" >> "$output_file"
    echo "}" >> "$output_file"
    
    echo "Data exported to: $output_file"
}

# Add hooks
autoload -U add-zsh-hook
add-zsh-hook precmd __time_tracker_periodic_check
add-zsh-hook preexec __time_tracker_on_command

# Initialize on plugin load
__time_tracker_init
