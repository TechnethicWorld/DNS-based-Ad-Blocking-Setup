#!/bin/sh

# Disable debug output
set +x

# === CONFIGURATION ===
ADBLOCK_DIR="/etc/unbound/adblock"
HOSTS_FILE="$ADBLOCK_DIR/hostnames.txt"
ZONE_FILE="/etc/unbound/adblock.conf"
SOURCE_URL="https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
LOG_TAG="adblock_update"

# === FUNCTION: LOGGING ===
log() {
  if [ -t 1 ]; then
    echo "[*] $1"
  else
    logger -t "$LOG_TAG" "$1"
  fi
}

# === START ===
log "Starting adblock update..."

# Create directory if not exists
mkdir -p "$ADBLOCK_DIR" >/dev/null 2>&1 || {
  log "Failed to create directory $ADBLOCK_DIR"
  exit 1
}

# Download blocklist
log "Downloading blocklist from GitHub..."
echo "Please wait, downloading blocklist..."
wget -q -O "$HOSTS_FILE" "$SOURCE_URL" >/dev/null 2>&1
if [ $? -eq 0 ]; then
  log "Blocklist downloaded successfully."
else
  log "Download failed."
  exit 1
fi

# Convert to Unbound format, skip IP entries in second column
log "Converting blocklist to Unbound config..."
echo "Please wait, converting blocklist..."

awk '
  BEGIN {FS=" "}
  function is_ip(s) {
    return (s ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) || (s ~ /^::$/)
  }
  {
    if ($0 ~ /^#/ || NF < 2) next;
    if ($1 == "0.0.0.0" || $1 == "::") {
      domain = $2
      if (!is_ip(domain)) {
        if (!(domain in seen)) {
          print "local-zone: \"" domain "\" redirect"
          print "local-data: \"" domain " A 127.0.0.1\""
          seen[domain] = 1
        }
      }
    }
  }
' "$HOSTS_FILE" > "$ZONE_FILE" 2>/dev/null

if [ $? -ne 0 ]; then
  log "Conversion failed."
  exit 1
fi

# Ensure inclusion in unbound.conf
log "Ensuring blocklist inclusion in Unbound configuration..."
if ! grep -q "$ZONE_FILE" /etc/unbound/unbound.conf; then
  echo "include: \"$ZONE_FILE\"" >> /etc/unbound/unbound.conf
  log "Included $ZONE_FILE in unbound.conf"
fi

# Restart Unbound
log "Restarting Unbound service..."
echo "Please wait, restarting Unbound..."
/etc/init.d/unbound restart >/dev/null 2>&1
if [ $? -eq 0 ]; then
  log "Unbound restarted successfully."
else
  log "Failed to restart Unbound."
  exit 1
fi

# Clean up - Remove the downloaded blocklist file to save space
log "Cleaning up: Removing downloaded blocklist..."
rm -f "$HOSTS_FILE" 2>/dev/null
if [ $? -eq 0 ]; then
  log "Blocklist file removed successfully."
else
  log "Failed to remove blocklist file."
fi

log "Adblock update completed successfully."
exit 0


