#!/usr/bin/env zsh
# time-tracker.plugin.zsh
# Tracks time spent on git branches across multiple repositories

# Configuration
TIME_TRACKER_DATA_FILE="${TIME_TRACKER_DATA_FILE:-${HOME}/.time-tracker-data.json}"
TIME_TRACKER_CHECK_INTERVAL="${TIME_TRACKER_CHECK_INTERVAL:-600}" # 10 minutes in seconds
TIME_TRACKER_IDLE_THRESHOLD="${TIME_TRACKER_IDLE_THRESHOLD:-1800}" # 30 minutes in seconds
TIME_TRACKER_DURATION_MERGE_THRESHOLD="${TIME_TRACKER_DURATION_MERGE_THRESHOLD:-1800}" # 30 minutes in seconds

# Internal state
typeset -g TIME_TRACKER_LAST_CHECK=0
typeset -g TIME_TRACKER_LAST_ACTIVITY=0

# Initialize plugin
function __time_tracker_init() {
    # Check for jq dependency
    if ! command -v jq &>/dev/null; then
        return 1
    fi
    
    # Create data file if it doesn't exist
    if [[ ! -f "$TIME_TRACKER_DATA_FILE" ]]; then
        local data_dir=$(dirname "$TIME_TRACKER_DATA_FILE")
        [[ ! -d "$data_dir" ]] && mkdir -p "$data_dir"
        echo '{"repositories":{}}' | jq '.' > "$TIME_TRACKER_DATA_FILE"
    fi
    
    # Initialize timestamps
    TIME_TRACKER_LAST_CHECK=$(date +%s)
    TIME_TRACKER_LAST_ACTIVITY=$(date +%s)
    
    # Initial track
    __time_tracker_record
}

# Get repository identifier
function __time_tracker_get_repo_id() {
    git rev-parse --show-toplevel 2>/dev/null
}

# Get current branch name
function __time_tracker_get_branch() {
    git rev-parse --abbrev-ref HEAD 2>/dev/null
}

# Get the shared data file path
function __time_tracker_get_data_file() {
    echo "$TIME_TRACKER_DATA_FILE"
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
    
    local data_file=$(__time_tracker_get_data_file)
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
        
        # Use jq to add or merge duration in the single data file
        local temp_file=$(mktemp)
        jq --arg repo "$repo_id" \
           --arg branch "$branch" \
           --arg start "$timestamp" \
           --argjson seconds "$time_delta" \
           --argjson threshold "$TIME_TRACKER_DURATION_MERGE_THRESHOLD" \
           '
           # Parse ISO timestamps to Unix time
           def parse_time: sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601;
           def to_iso: strftime("%Y-%m-%dT%H:%M:%SZ");
           
           # Ensure repository exists
           if .repositories[$repo] == null then
               .repositories[$repo] = {"durations": []}
           end |
           
           # Find the last duration for this branch in this repo
           .repositories[$repo].durations as $durations |
           ($durations | map(select(.branch == $branch)) | last) as $last_duration |
           
           if $last_duration then
               # Check if we should merge with the last duration
               ($start | parse_time) as $new_start |
               ($last_duration.end | parse_time) as $last_end |
               ($new_start - $last_end) as $gap |
               
               if $gap <= $threshold then
                   # Merge: extend the last duration
                   .repositories[$repo].durations |= map(
                       if . == $last_duration then
                           .end = ($new_start + $seconds | to_iso)
                       else
                           .
                       end
                   )
               else
                   # Create new duration
                   .repositories[$repo].durations += [{
                       "branch": $branch,
                       "start": $start,
                       "end": (($start | parse_time) + $seconds | to_iso)
                   }]
               end
           else
               # No previous duration for this branch, create new
               .repositories[$repo].durations += [{
                   "branch": $branch,
                   "start": $start,
                   "end": (($start | parse_time) + $seconds | to_iso)
               }]
           end
           ' "$data_file" > "$temp_file" 2>/dev/null && mv "$temp_file" "$data_file" 2>/dev/null
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
    
    # Process data file
    local data_file=$(__time_tracker_get_data_file)
    if [[ ! -f "$data_file" ]]; then
        echo "No tracking data available."
        return 0
    fi
    
    if $show_all; then
        # Show stats for all repositories
        __time_tracker_process_all_stats "$data_file"
    else
        # Show stats for current repository
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
    
    # Use jq to aggregate durations by branch from single file
    local stats=$(jq -r --arg repo "$repo_path" --arg branch "$filter_branch" '
        def parse_time: sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601;
        
        .repositories[$repo] // {"durations": []} |
        .durations |
        (if $branch != "" then map(select(.branch == $branch)) else . end) |
        group_by(.branch) |
        map({
            branch: .[0].branch,
            total_seconds: map((.end | parse_time) - (.start | parse_time)) | add
        }) |
        sort_by(-.total_seconds) |
        .[] |
        "\(.branch)|\(.total_seconds)"
    ' "$data_file")
    
    if [[ -z "$stats" ]]; then
        echo "No data available."
        return
    fi
    
    echo "Time spent per branch:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    echo "$stats" | while IFS='|' read -r branch total_seconds; do
        local hours=$((total_seconds / 3600))
        local minutes=$(((total_seconds % 3600) / 60))
        printf "%-40s %3dh %2dm\n" "$branch" "$hours" "$minutes"
    done
}

# Process stats for all repositories
function __time_tracker_process_all_stats() {
    local data_file="$1"
    
    echo "Time tracking statistics (all repositories)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Get all repository paths from single file
    local repos=$(jq -r '.repositories | keys[]' "$data_file" 2>/dev/null)
    
    if [[ -z "$repos" ]]; then
        echo "No tracking data available."
        return
    fi
    
    echo "$repos" | while read -r repo_path; do
        __time_tracker_process_repo_stats "$data_file" "$repo_path" ""
        echo ""
    done
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
    
    local data_file=$(__time_tracker_get_data_file)
    
    if $clear_all; then
        if [[ "$confirm" != "y" ]]; then
            echo -n "Clear all tracking data? [y/N] "
            read confirm
        fi
        
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
            echo '{"repositories":{}}' | jq '.' > "$data_file"
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
        
        if [[ "$confirm" != "y" ]]; then
            echo -n "Clear tracking data for this repository? [y/N] "
            read confirm
        fi
        
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
            local temp_file=$(mktemp)
            jq --arg repo "$repo_id" 'del(.repositories[$repo])' "$data_file" > "$temp_file" && mv "$temp_file" "$data_file"
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
    
    local data_file=$(__time_tracker_get_data_file)
    if [[ ! -f "$data_file" ]]; then
        echo "No tracking data available to export."
        return 1
    fi
    
    local exported_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Add exported timestamp to data
    jq --arg exported "$exported_time" '{exported: $exported, repositories}' "$data_file" > "$output_file"
    
    echo "Data exported to: $output_file"
}

# Add hooks
autoload -U add-zsh-hook
add-zsh-hook precmd __time_tracker_periodic_check
add-zsh-hook preexec __time_tracker_on_command

# Initialize on plugin load
__time_tracker_init
