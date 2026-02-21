#!/usr/bin/env bash

# ==========================================================
#  Interface Proxy - Stop (Linux / macOS)
# ==========================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

PID_FILE="$SCRIPT_DIR/proxy.pid"
LOG_FILE="$SCRIPT_DIR/proxy.log"

echo ""
echo "  ============================================"
echo "   Interface-Bound Proxy - Stop"
echo "  ============================================"
echo ""

KILLED=0

# Method 1: PID file
if [ -f "$PID_FILE" ]; then
    PROXY_PID=$(cat "$PID_FILE")
    echo "  Found PID file. PID: $PROXY_PID"

    if kill -0 "$PROXY_PID" 2>/dev/null; then
        echo "  Killing proxy process..."
        kill "$PROXY_PID" 2>/dev/null
        sleep 1
        # Force kill if still alive
        if kill -0 "$PROXY_PID" 2>/dev/null; then
            kill -9 "$PROXY_PID" 2>/dev/null
        fi
        echo "  Proxy stopped successfully."
        KILLED=1
    else
        echo "  Process $PROXY_PID is not running (already stopped)."
    fi

    rm -f "$PID_FILE"
else
    # Method 2: Search for the process
    echo "  No PID file found. Searching for running proxy processes..."
    echo ""

    PIDS=$(pgrep -f "interface_proxy.py" 2>/dev/null || true)

    if [ -n "$PIDS" ]; then
        for pid in $PIDS; do
            echo "  Found proxy process: PID $pid"
            echo "  Killing..."
            kill "$pid" 2>/dev/null || true
            KILLED=1
        done
        sleep 1
        # Force kill any survivors
        PIDS=$(pgrep -f "interface_proxy.py" 2>/dev/null || true)
        for pid in $PIDS; do
            kill -9 "$pid" 2>/dev/null || true
        done
        echo "  Stopped."
    else
        echo "  No running proxy process found."
        echo "  The proxy may already be stopped."
    fi
fi

rm -f "$PID_FILE"

echo ""
echo "  ----------------------------------------"
echo "   Proxy stopped."
[ -f "$LOG_FILE" ] && echo "   Logs: $LOG_FILE"
echo "  ----------------------------------------"
echo ""
