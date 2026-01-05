# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This repository contains bash scripts designed to extend the functionality of Arr applications (Lidarr, Radarr, Sonarr, Readarr) and SABnzbd when running in Linuxserver.io Docker containers. The scripts automate media downloading, processing, and management tasks.

**WARNING**: DO NOT USE PORTAINER - it is known to break functionality. These scripts are NOT supported by the official Arr communities.

## Repository Structure

The repository is organized by application type:
- `lidarr/` - Music management automation scripts
- `radarr/` - Movie management automation scripts
- `sonarr/` - TV series management automation scripts
- `readarr/` - Book management automation scripts
- `sabnzbd/` - Download client post-processing scripts
- `ra-rom-downloader/` - RetroArch ROM downloader scripts
- `universal/` - Shared functions and services used across all apps

Each application directory contains:
- `scripts_init.bash` - Entry point that downloads and runs `setup.bash` from the main branch
- `setup.bash` - Installation script that downloads dependencies, packages, and service scripts
- `extended.conf` - Configuration file with script settings and intervals
- Service scripts (`.bash` or `.service` files) - Background services that run at configured intervals
- Support files (config files, naming templates, etc.)

## Architecture

### Initialization Flow

1. User places `scripts_init.bash` in the container's `/custom-cont-init.d/` directory
2. On container start, `scripts_init.bash` downloads and executes the latest `setup.bash` from GitHub
3. `setup.bash` installs system packages (ffmpeg, python, jq, etc.) and downloads all service scripts to `/custom-services.d/`
4. Service scripts are executed by the container's init system and run continuously at configured intervals

### Shared Components

**universal/functions.bash**: Core utility functions used by all scripts:
- `log()` - Logging with timestamps to `/config/logs/`
- `logfileSetup()` - Creates log files and maintains log rotation (keeps last 2 files, deletes files older than 5 days)
- `getArrAppInfo()` - Extracts Arr app configuration from `/config/config.xml` (API key, port, URL base)
- `verifyApiAccess()` - Waits for Arr app API to be available, supports both v1 and v3 API versions
- `ConfValidationCheck()` - Validates `/config/extended.conf` exists and is readable

**universal/services/**: Shared service scripts:
- `QueueCleaner` - Removes failed/stalled downloads from Arr download queues
- `Recyclarr` - Configures custom formats and quality settings using recyclarr

### Configuration Pattern

All scripts follow this pattern:
1. Source `/config/extended.conf` for user settings
2. Source `/config/extended/functions` for shared functions
3. Call `logfileSetup()` to initialize logging
4. Call `getArrAppInfo()` and `verifyApiAccess()` to connect to the Arr app
5. Validate required configuration with `verifyConfig()`
6. Enter main loop that sleeps for configured interval

### API Interaction

Scripts interact with Arr apps using their REST APIs:
- API endpoint detection: Try v3 first, fall back to v1 if needed
- Authentication: API key extracted from `/config/config.xml` or passed via `arrApiKey` variable
- Common endpoints:
  - `/api/v3/system/status` - Health check
  - `/api/v3/queue` - Download queue management
  - `/api/v1/artist`, `/api/v1/album` (Lidarr)
  - `/api/v3/movie` (Radarr)
  - `/api/v3/series` (Sonarr)

### Download Workflow (Lidarr Example)

1. Audio.service.bash queries Lidarr API for missing/wanted albums
2. Searches for albums using configured client (Deezer/Tidal via freyr, deemix, tidal-dl)
3. Downloads to `/config/extended/downloads/`
4. Tags files using beets, adds artwork, lyrics, replaygain
5. Moves completed files to `/config/extended/import/`
6. Lidarr's "Usenet Blackhole" download client imports from the import directory

## Development Commands

Since this repository contains bash scripts without a build system, there are no traditional build/test/lint commands. Development workflow:

### Testing Scripts Locally

Scripts are designed to run inside Docker containers with specific dependencies. To test:

1. Use a Linuxserver.io container (e.g., `lscr.io/linuxserver/lidarr:latest`)
2. Mount volumes for `/custom-cont-init.d/` and `/custom-services.d/`
3. Place test script in appropriate directory
4. Restart container and monitor logs in `/config/logs/`

### Checking Syntax

```bash
# Check bash syntax for all scripts
find . -name "*.bash" -exec bash -n {} \;

# Check specific script
bash -n lidarr/Audio.service.bash
```

### Common Script Variables

When modifying scripts, be aware of these common variables:
- `scriptVersion` - Version number, increment when making changes
- `scriptName` - Used in logging
- `arrUrl` - Full URL to Arr app API (e.g., http://127.0.0.1:8686)
- `arrApiKey` - API key for authentication
- `arrName` - Instance name from config.xml

## Key Design Patterns

### Service Script Structure

All background services follow this pattern:
```bash
#!/usr/bin/with-contenv bash
scriptVersion="X.Y"
scriptName="ServiceName"

# Import configuration and functions
source /config/extended.conf
source /config/extended/functions

# Verify configuration
verifyConfig() {
    if [ "$enableServiceName" != "true" ]; then
        log "Script disabled"
        sleep infinity
    fi
}

# Main loop
while true; do
    # Do work
    # ...

    # Sleep for configured interval
    sleep $scriptInterval
done
```

### Error Handling

Scripts prefer to continue running rather than exit:
- Failed downloads are logged and retried later
- Missing dependencies trigger warnings but don't stop execution
- Invalid configuration causes script to sleep infinitely (not exit)

### File Permissions

Scripts frequently use:
- `chmod 777` for downloaded files/directories (required for container user access)
- `chgrp users` for shared access

## Configuration Files

### extended.conf

Each app has an `extended.conf` with sections:
- **Script Enablement**: Boolean flags to enable/disable features
- **Script Intervals**: How often each service runs (format: `15m`, `1h`, `2d`)
- **Paths**: Download/import/output directories
- **Client Settings**: API tokens, credentials for external services
- **Quality Settings**: Audio/video quality preferences

### Dependency Configs

- `beets-config.yaml` - Beets music tagger configuration (Lidarr)
- `sma.ini` - Sickbeard MP4 Automator settings (transcoding)
- `recyclarr.yaml` - Custom format and quality definitions
- `naming.json` - File/folder naming templates (Radarr/Sonarr)
- `naming-overrides.json` - User-provided naming overrides (Radarr/Sonarr)

### Naming Configuration (Radarr/Sonarr)

The AutoConfig.service scripts for both Radarr and Sonarr support flexible naming configuration through two complementary methods:

#### Profile Selection

Users can select which naming profile variant to use via `extended.conf`:
- **Sonarr**: Configure profiles for standard/daily/anime episodes, series folders, and season folders
- **Radarr**: Configure profiles for movie files and movie folders

Variables (in extended.conf):
```bash
# Sonarr
namingProfileStandardEpisode="default:4"  # Options: "default:3", "default:4", "original"
namingProfileDailyEpisode="default:4"
namingProfileAnimeEpisode="default:4"
namingProfileSeries="default"             # Options: "default", "plex", "emby", "jellyfin"
namingProfileSeason="default"

# Radarr
namingProfileMovieFile="default"          # Options: "default", "emby", "jellyfin", "anime", etc.
namingProfileMovieFolder="default"        # Options: "default", "plex", "emby", "jellyfin"
```

#### Override Files

Users can create `/config/extended/naming-overrides.json` to define custom naming patterns:
- Uses `jq` to perform a deep merge where user overrides take precedence
- Only need to include fields that should be changed
- Works in combination with profile selection

#### Processing Order

1. **Load Base**: From `/config/extended/naming.json` or Trash Guides
2. **Merge Overrides**: Apply naming-overrides.json if present
3. **Select Profile**: Extract the configured profile variant (e.g., `.episodes.standard["default:4"]`)
4. **Apply to Arr**: Send the final naming pattern to the Arr app via API

This allows users to:
- Quickly switch between built-in variants (e.g., plex, emby, jellyfin)
- Define completely custom patterns via overrides
- Combine both methods for maximum flexibility

Example Sonarr override (see `sonarr/naming-overrides.example.json`):
```json
{
    "episodes": {
        "standard": {
            "default:4": "{Series TitleYear} - S{season:00}E{episode:00} - Custom Pattern"
        }
    }
}
```

Example Radarr override (see `radarr/naming-overrides.example.json`):
```json
{
    "file": {
        "default": "{Movie CleanTitle} ({Release Year}) [{Custom Formats}]"
    }
}
```

## Update Process

The scripts auto-update by design:
1. User restarts container
2. `scripts_init.bash` downloads latest `setup.bash` from GitHub main branch
3. `setup.bash` downloads latest service scripts
4. A second restart is required for new scripts to take effect (container uses cached versions on first restart)

## External Dependencies

Scripts rely on these external tools (installed by setup.bash):
- **Media Tools**: ffmpeg, imagemagick, mkvtoolnix
- **Audio Tools**: flac, opus-tools, beets, r128gain
- **Download Clients**: yt-dlp, freyr, deemix, tidal-dl
- **Utilities**: jq, xq, curl, parallel
- **Python Tools**: beautifulsoup4, mutagen, requests, apprise
- **Recyclarr**: .NET-based quality profile manager

## Important Conventions

1. **All scripts use `#!/usr/bin/with-contenv bash`** - This is specific to the s6-overlay init system used by Linuxserver.io containers
2. **Logs go to `/config/logs/`** - Never log to stdout after initialization
3. **Configuration lives in `/config/`** - Persisted across container restarts
4. **Scripts download to `/custom-services.d/` or `/custom-cont-init.d/`** - These directories are scanned by the container init system
5. **URLs in scripts point to GitHub main branch** - Scripts always pull latest versions
6. **Script versioning** - Each setup.bash checks `/config/setup_version.txt` to avoid redundant setup

## Testing Considerations

- Scripts expect to run in Alpine Linux containers
- Dependencies use `apk` package manager
- Python packages installed system-wide with `--break-system-packages`
- Scripts assume network access to GitHub, various music/video services
- Most functionality requires valid API keys/tokens in extended.conf
