log () {
  m_time=`date "+%F %T"`
  echo $m_time" :: $scriptName :: $scriptVersion :: "$1
  echo $m_time" :: $scriptName :: $scriptVersion :: "$1 >> "/config/logs/$logFileName"
}

logfileSetup () {
  logFileName="$scriptName-$(date +"%Y_%m_%d_%I_%M_%p").txt"

  # Keep only the last 2 log files for 3 active log files at any given time...
  rm -f $(ls -1t /config/logs/$scriptName-* | tail -n +2)
  # delete log files older than 5 days
  find "/config/logs" -type f -iname "$scriptName-*.txt" -mtime +5 -delete
  
  if [ ! -f "/config/logs/$logFileName" ]; then
    echo "" > "/config/logs/$logFileName"
    chmod 666 "/config/logs/$logFileName"
  fi
}

getArrAppInfo () {
  # Get Arr App information
  if [ -z "$arrUrl" ] || [ -z "$arrApiKey" ]; then
    arrUrlBase="$(cat /config/config.xml | xq | jq -r .Config.UrlBase)"
    if [ "$arrUrlBase" == "null" ]; then
      arrUrlBase=""
    else
      arrUrlBase="/$(echo "$arrUrlBase" | sed "s/\///")"
    fi
    arrName="$(cat /config/config.xml | xq | jq -r .Config.InstanceName)"
    arrApiKey="$(cat /config/config.xml | xq | jq -r .Config.ApiKey)"
    arrPort="$(cat /config/config.xml | xq | jq -r .Config.Port)"
    arrUrl="http://127.0.0.1:${arrPort}${arrUrlBase}"
  fi
}

verifyApiAccess () {
  until false
  do
    arrApiTest=""
    arrApiVersion=""
    if [ -z "$arrApiTest" ]; then
      arrApiVersion="v3"
      arrApiTest="$(curl -s "$arrUrl/api/$arrApiVersion/system/status?apikey=$arrApiKey" | jq -r .instanceName)"
    fi
    if [ -z "$arrApiTest" ]; then
      arrApiVersion="v1"
      arrApiTest="$(curl -s "$arrUrl/api/$arrApiVersion/system/status?apikey=$arrApiKey" | jq -r .instanceName)"
    fi
    if [ ! -z "$arrApiTest" ]; then
      break
    else
      log "$arrName is not ready, sleeping until valid response..."
      sleep 1
    fi
  done
}

ConfValidationCheck () {
  if [ ! -f "/config/extended.conf" ]; then
    log "ERROR :: \"extended.conf\" file is missing..."
    log "ERROR :: Download the extended.conf config file and place it into \"/config\" folder..."
    log "ERROR :: Exiting..."
    exit
  fi
  if [ -z "$enableAutoConfig" ]; then
    log "ERROR :: \"extended.conf\" file is unreadable..."
    log "ERROR :: Likely caused by editing with a non unix/linux compatible editor, to fix, replace the file with a valid one or correct the line endings..."
    log "ERROR :: Exiting..."
    exit
  fi
}

loadNamingConfiguration () {
  # Load and merge naming configuration for Arr applications
  # Args:
  #   $1 - Application name (e.g., "Radarr" or "Sonarr")
  # Returns:
  #   Sets global variable 'namingJson' with the merged configuration
  #   Returns 0 on success, 1 on failure
  
  local appName="$1"
  local appNameLower=$(echo "$appName" | tr '[:upper:]' '[:lower:]')
  local baseNamingJson
  
  # Initialize global variable
  namingJson=""
  
  # Load base naming configuration
  if [ -f /config/extended/naming.json ]; then
    log "Loading base $appName Naming from /config/extended/naming.json..."
    baseNamingJson=$(cat /config/extended/naming.json)
  else
    log "Loading base $appName Naming from Trash Guides..."
    baseNamingJson=$(curl -s "https://raw.githubusercontent.com/TRaSH-/Guides/master/docs/json/$appNameLower/naming/$appNameLower-naming.json")
  fi
  
  # Verify base configuration was loaded
  if [ -z "$baseNamingJson" ]; then
    log "ERROR: Failed to load base naming configuration"
    return 1
  fi
  
  # Check for user overrides and merge if present
  if [ -f /config/extended/naming-overrides.json ]; then
    log "Found naming overrides at /config/extended/naming-overrides.json, merging with base..."
    if namingJson=$(echo "$baseNamingJson" | jq -e -s --argfile overrides /config/extended/naming-overrides.json '.[0] * $overrides'); then
      log "Naming configuration merged successfully"
    else
      log "Failed to merge naming overrides; invalid JSON or jq error detected. Falling back to base naming configuration."
      namingJson="$baseNamingJson"
    fi
  else
    log "No naming overrides found, using base configuration"
    namingJson="$baseNamingJson"
  fi
  
  return 0
}

logfileSetup
ConfValidationCheck
