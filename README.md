# Time Tracker - Oh My Zsh Plugin

A lightweight and efficient oh-my-zsh plugin that automatically tracks time spent on git branches across multiple repositories. Perfect for developers who want to understand their time allocation across different projects and branches.

## Features

- 🕐 **Automatic Time Tracking**: Passively tracks time spent on each git branch
- 🔄 **Multi-Repository Support**: Handles multiple terminal sessions across different repositories simultaneously
- 💤 **Idle Detection**: Smart idle time detection (30-minute threshold by default) to avoid inflating time when terminals are inactive
- ⚡ **Efficient**: Checks every 10 minutes to minimize overhead
- 📊 **Detailed Statistics**: View time spent per branch and repository
- 💾 **Persistent Data**: Stores tracking data in `~/.time-tracker-data/` (gitignored)
- 🛡️ **Safe**: Handles system sleep/suspend gracefully

## Installation

### Using Oh My Zsh

1. Clone this repository into your Oh My Zsh custom plugins directory:

```bash
git clone https://github.com/mike-fam/time-tracker-plugin.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/time-tracker
```

2. Add `time-tracker` to your plugins array in `~/.zshrc`:

```zsh
plugins=(... time-tracker)
```

3. Restart your terminal or reload zsh:

```bash
source ~/.zshrc
```

### Manual Installation

1. Clone the repository:

```bash
git clone https://github.com/mike-fam/time-tracker-plugin.git ~/time-tracker
```

2. Source the plugin in your `~/.zshrc`:

```zsh
source ~/time-tracker/time-tracker.plugin.zsh
```

3. Reload your shell:

```bash
source ~/.zshrc
```

## Usage

The plugin works automatically once installed. Simply work in your git repositories as usual, and the plugin will track time in the background.

### Commands

#### `time-tracker-stats`

Display time tracking statistics for the current repository.

```bash
# Show stats for current repository and branch
time-tracker-stats

# Show stats for current repository, all branches
time-tracker-stats

# Show stats for a specific branch
time-tracker-stats -b feature/new-feature

# Show stats for all repositories
time-tracker-stats --all
```

**Options:**
- `-a, --all`: Show statistics for all tracked repositories
- `-b, --branch BRANCH`: Filter statistics for a specific branch

#### `time-tracker-clear`

Clear tracking data.

```bash
# Clear data for current repository (with confirmation)
time-tracker-clear

# Clear data for current repository (skip confirmation)
time-tracker-clear -y

# Clear all tracking data
time-tracker-clear --all

# Clear all tracking data (skip confirmation)
time-tracker-clear --all -y
```

**Options:**
- `-a, --all`: Clear data for all repositories
- `-y, --yes`: Skip confirmation prompt

#### `time-tracker-export`

Export tracking data to JSON format.

```bash
# Export to default file (time-tracker-export.json)
time-tracker-export

# Export to custom file
time-tracker-export my-stats.json
```

## Configuration

You can customize the plugin behavior by setting these environment variables in your `~/.zshrc` **before** the plugin is loaded:

```zsh
# Directory for storing tracking data (default: ~/.time-tracker-data)
export TIME_TRACKER_DATA_DIR="$HOME/.time-tracker-data"

# Check interval in seconds (default: 600 = 10 minutes)
export TIME_TRACKER_CHECK_INTERVAL=600

# Idle threshold in seconds (default: 1800 = 30 minutes)
export TIME_TRACKER_IDLE_THRESHOLD=1800

# Duration merge threshold in seconds (default: 1800 = 30 minutes)
# Activities within this window will be merged into continuous durations
export TIME_TRACKER_DURATION_MERGE_THRESHOLD=1800
```

### Example Configuration

```zsh
# In ~/.zshrc, before the plugins=(...) line

# Check every 5 minutes instead of 10
export TIME_TRACKER_CHECK_INTERVAL=300

# Consider idle after 15 minutes instead of 30
export TIME_TRACKER_IDLE_THRESHOLD=900

# Merge durations within 15 minutes instead of 30
export TIME_TRACKER_DURATION_MERGE_THRESHOLD=900

plugins=(... time-tracker)
```

## How It Works

1. **Initialization**: When you open a terminal in a git repository, the plugin initializes tracking
2. **Periodic Checks**: Every 10 minutes (configurable), the plugin checks if you're still active
3. **Idle Detection**: If no commands have been run for 30 minutes (configurable), time is not recorded
4. **Duration Merging**: If a new activity occurs within 30 minutes of the last duration end, they are merged into one continuous duration
5. **Data Storage**: Time durations are stored as JSON objects in repository-specific data files in `~/.time-tracker-data/`
6. **Multiple Sessions**: Each terminal session tracks independently; durations are merged when they overlap

### Data Format

Data is stored in JSON format with duration-based tracking:

```json
{
  "repository": "/path/to/repo",
  "durations": [
    {
      "branch": "main",
      "start": "2025-12-01T10:00:00Z",
      "end": "2025-12-01T11:30:00Z"
    },
    {
      "branch": "feature/new",
      "start": "2025-12-01T14:00:00Z",
      "end": "2025-12-01T15:20:00Z"
    }
  ]
}
```

Each duration represents a continuous work session on a branch. If you return to work within 30 minutes, the duration is extended rather than creating a new entry.

## Example Output

```bash
$ time-tracker-stats
Repository: /Users/john/projects/my-app

Time spent per branch:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
main                                        15h 40m
feature/user-authentication                  8h 20m
feature/dark-mode                           3h 10m
bugfix/login-issue                          1h 30m
```

### Sample Export JSON

```json
{
  "exported": "2025-12-01T14:30:00Z",
  "repositories": {
    "/Users/john/projects/my-app": {
      "durations": [
        {
          "branch": "main",
          "start": "2025-12-01T09:00:00Z",
          "end": "2025-12-01T12:30:00Z"
        },
        {
          "branch": "feature/user-authentication",
          "start": "2025-12-01T13:00:00Z",
          "end": "2025-12-01T16:45:00Z"
        }
      ]
    }
  }
}
```

## Privacy & Data

- All tracking data is stored locally in `~/.time-tracker-data/`
- Data files are automatically gitignored
- No data is sent to external services
- You can clear data at any time using `time-tracker-clear`

## Performance

The plugin is designed to be lightweight:
- Minimal overhead: only checks every 10 minutes
- Efficient file I/O: appends to files instead of rewriting
- No background processes: uses zsh hooks for event-driven updates
- Smart idle detection: prevents recording when inactive

## Troubleshooting

### Plugin not tracking time

1. Ensure you're in a git repository: `git status`
2. Check that the plugin is loaded: `type time-tracker-stats`
3. Verify data directory exists: `ls ~/.time-tracker-data/`

### Stats show no data

1. Ensure enough time has passed (at least 10 minutes of active work)
2. Check if you're idle: run a command to mark activity
3. Verify data file exists for your repository

### Clear all data and start fresh

```bash
time-tracker-clear --all -y
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - see LICENSE file for details

## Author

Created for developers who want to track their time passively and efficiently.
