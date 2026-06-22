#!/bin/bash
set -euo pipefail

usage() {
  echo "Usage: $0 [--edgerouter|--arch|--auto]"
  echo "  --edgerouter  Clear DNS cache on an EdgeRouter/EdgeOS device"
  echo "  --arch        Clear DNS cache on an Arch Linux host"
  echo "  --auto        Auto-detect the system (default)"
}

is_edgerouter() {
  [[ -d /opt/vyatta ]] || [[ -f /opt/vyatta/etc/version ]]
}

is_arch() {
  [[ -f /etc/arch-release ]]
}

clear_edgerouter() {
  echo "Clearing EdgeRouter DNS cache..."

  if command -v vbash >/dev/null 2>&1; then
    echo "Running: clear dns forwarding cache"
    vbash -c "clear dns forwarding cache" || true
  fi

  # Also restart dnsmasq to ensure the cache is flushed, regardless of CLI result.
  if [[ -x /etc/init.d/dnsmasq ]]; then
    echo "Restarting dnsmasq..."
    sudo /etc/init.d/dnsmasq restart
  elif command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet dnsmasq 2>/dev/null; then
    echo "Restarting dnsmasq via systemd..."
    sudo systemctl restart dnsmasq
  elif pgrep -x dnsmasq >/dev/null 2>&1; then
    echo "Sending HUP to dnsmasq..."
    sudo killall -HUP dnsmasq
  fi

  echo "EdgeRouter DNS cache cleared."
}

clear_arch() {
  echo "Clearing Arch Linux DNS cache..."

  if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
    echo "Flushing systemd-resolved cache..."
    resolvectl flush-caches
  fi

  if systemctl is-active --quiet dnsmasq 2>/dev/null; then
    echo "Restarting dnsmasq..."
    sudo systemctl restart dnsmasq
  fi

  if systemctl is-active --quiet unbound 2>/dev/null; then
    echo "Flushing unbound cache..."
    sudo unbound-control flush || true
  fi

  if systemctl is-active --quiet NetworkManager 2>/dev/null; then
    echo "Restarting NetworkManager (dnsmasq plugin)..."
    sudo systemctl restart NetworkManager
  fi

  echo "Arch Linux DNS cache cleared."
}

MODE="${1:---auto}"

case "$MODE" in
  --edgerouter|-e)
    clear_edgerouter
    ;;
  --arch|-a)
    clear_arch
    ;;
  --auto)
    if is_edgerouter; then
      clear_edgerouter
    elif is_arch; then
      clear_arch
    else
      echo "Could not auto-detect system. Use --edgerouter or --arch."
      usage
      exit 1
    fi
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage
    exit 1
    ;;
esac
