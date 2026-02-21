#!/usr/bin/env bash
set -e

# ==========================================================
#  Interface Proxy - Quick Launcher (Linux / macOS)
#  Launches the proxy detached with logs to file.
# ==========================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

VENV_DIR="$SCRIPT_DIR/venv"
PID_FILE="$SCRIPT_DIR/proxy.pid"
LOG_FILE="$SCRIPT_DIR/proxy.log"

echo ""
echo "  ============================================"
echo "   Interface-Bound Proxy Server"
echo "  ============================================"
echo ""

# ------------------------------------------------------------------
#  Check if already running
# ------------------------------------------------------------------
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if kill -0 "$OLD_PID" 2>/dev/null; then
        echo "  Proxy is already running (PID: $OLD_PID)."
        echo "  Use ./kill.sh to stop it first."
        echo ""
        exit 0
    fi
    echo "  Stale PID file found. Cleaning up..."
    rm -f "$PID_FILE"
fi

# ------------------------------------------------------------------
#  Find Python
# ------------------------------------------------------------------
PYTHON_CMD=""

if [ -x "$VENV_DIR/bin/python" ]; then
    PYTHON_CMD="$VENV_DIR/bin/python"
elif command -v python3 &>/dev/null; then
    PYTHON_CMD="python3"
elif command -v python &>/dev/null; then
    PYTHON_CMD="python"
fi

if [ -z "$PYTHON_CMD" ]; then
    echo "  ERROR: No Python found. Please run ./setup.sh first."
    echo ""
    exit 1
fi

# Verify dependencies
if ! "$PYTHON_CMD" -c "import psutil" &>/dev/null; then
    echo "  Dependencies not installed. Please run ./setup.sh first."
    echo ""
    exit 1
fi

# ------------------------------------------------------------------
#  Show interfaces and let user pick
# ------------------------------------------------------------------
echo "  Detecting network interfaces..."
echo ""

IFACE_LIST=$("$PYTHON_CMD" "$SCRIPT_DIR/interface_proxy.py" --list-interfaces 2>/dev/null)

if [ -z "$IFACE_LIST" ]; then
    echo "  ERROR: No network interfaces found."
    exit 1
fi

i=0
declare -a IFACE_IPS
while IFS=$'\t' read -r ip name; do
    i=$((i + 1))
    IFACE_IPS[$i]="$ip"
    printf "    [%d]  %15s   (%s)\n" "$i" "$ip" "$name"
done <<< "$IFACE_LIST"

echo ""
read -rp "  Select interface number: " CHOICE

BIND_IP="${IFACE_IPS[$CHOICE]}"
if [ -z "$BIND_IP" ]; then
    echo "  Invalid choice."
    exit 1
fi

# ------------------------------------------------------------------
#  Launch detached
# ------------------------------------------------------------------
echo ""
echo "  Starting proxy on interface $BIND_IP ..."
echo "  Logs: $LOG_FILE"
echo ""

nohup "$PYTHON_CMD" "$SCRIPT_DIR/interface_proxy.py" \
    --bind "$BIND_IP" \
    --logfile "$LOG_FILE" \
    --pidfile "$PID_FILE" \
    </dev/null &>/dev/null &

sleep 2

if [ -f "$PID_FILE" ]; then
    NEW_PID=$(cat "$PID_FILE")
    echo "  ========================================"
    echo "   Proxy is running!"
    echo "  ========================================"
    echo ""
    echo "   PID:       $NEW_PID"
    echo "   Proxy:     127.0.0.1:8118"
    echo "   Interface: $BIND_IP"
    echo "   Logs:      $LOG_FILE"
    echo ""
    echo "   Set your browser proxy to 127.0.0.1:8118"
    echo "   Run ./kill.sh to stop the proxy."
    echo ""
else
    echo "  ERROR: Proxy failed to start. Check $LOG_FILE for details."
    exit 1
fi
