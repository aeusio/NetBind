#!/usr/bin/env bash
set -e

# ==========================================================
#  Interface Proxy - Setup & Launcher (Linux / macOS)
#
#  Handles everything:
#    1. Checks for Python 3.10+, installs if missing
#    2. Creates a virtual environment
#    3. Installs pip and dependencies
#    4. Verifies the installation
#    5. Launches the proxy (detached, logs to file)
# ==========================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

VENV_DIR="$SCRIPT_DIR/venv"
PID_FILE="$SCRIPT_DIR/proxy.pid"
LOG_FILE="$SCRIPT_DIR/proxy.log"
PYTHON_CMD=""

echo ""
echo "  ========================================================"
echo "    Interface-Bound Proxy - Setup and Launcher"
echo "  ========================================================"
echo ""
echo "  Working directory: $SCRIPT_DIR"
echo ""

# ------------------------------------------------------------------
#  Helper: test if a python binary is real and >= 3.10
# ------------------------------------------------------------------
test_python() {
    local cmd="$1"
    local ver
    ver=$("$cmd" -c "import sys; print(sys.version.split()[0])" 2>/dev/null) || return 1
    # Check it looks like a version
    echo "$ver" | grep -qE '^[0-9]+\.' || return 1
    local major minor
    major=$(echo "$ver" | cut -d. -f1)
    minor=$(echo "$ver" | cut -d. -f2)
    if [ "$major" -ge 4 ] 2>/dev/null || { [ "$major" -eq 3 ] && [ "$minor" -ge 10 ]; } 2>/dev/null; then
        PYTHON_CMD="$cmd"
        PY_VER="$ver"
        return 0
    fi
    return 1
}

# ------------------------------------------------------------------
#  STEP 1: Find Python
# ------------------------------------------------------------------
echo "  [1/5] Checking for Python..."

# Priority 1: venv from previous run
if [ -x "$VENV_DIR/bin/python" ]; then
    if test_python "$VENV_DIR/bin/python"; then
        echo "        Found in virtual environment."
    fi
fi

# Priority 2: python3 on PATH
if [ -z "$PYTHON_CMD" ]; then
    if command -v python3 &>/dev/null; then
        if test_python python3; then
            echo "        Found python3 on PATH."
        fi
    fi
fi

# Priority 3: python on PATH
if [ -z "$PYTHON_CMD" ]; then
    if command -v python &>/dev/null; then
        if test_python python; then
            echo "        Found python on PATH."
        fi
    fi
fi

# Not found - try to install
if [ -z "$PYTHON_CMD" ]; then
    echo "        No working Python 3.10+ found."
    echo ""
    echo "  [2/5] Installing Python..."

    if command -v apt-get &>/dev/null; then
        echo "        Detected Debian/Ubuntu. Using apt..."
        sudo apt-get update -qq
        sudo apt-get install -y python3 python3-pip python3-venv
    elif command -v dnf &>/dev/null; then
        echo "        Detected Fedora/RHEL. Using dnf..."
        sudo dnf install -y python3 python3-pip python3-venv 2>/dev/null || \
        sudo dnf install -y python3 python3-pip
    elif command -v yum &>/dev/null; then
        echo "        Detected CentOS/RHEL. Using yum..."
        sudo yum install -y python3 python3-pip
    elif command -v pacman &>/dev/null; then
        echo "        Detected Arch Linux. Using pacman..."
        sudo pacman -Sy --noconfirm python python-pip
    elif command -v zypper &>/dev/null; then
        echo "        Detected openSUSE. Using zypper..."
        sudo zypper install -y python3 python3-pip python3-venv
    elif command -v apk &>/dev/null; then
        echo "        Detected Alpine. Using apk..."
        sudo apk add python3 py3-pip
    elif command -v brew &>/dev/null; then
        echo "        Detected macOS with Homebrew. Using brew..."
        brew install python@3.12
    else
        echo ""
        echo "  !! ERROR: Could not detect package manager."
        echo "  Please install Python 3.10+ manually and run this script again."
        echo ""
        exit 1
    fi

    # Re-check after install
    if command -v python3 &>/dev/null && test_python python3; then
        echo "        Python installed successfully."
    elif command -v python &>/dev/null && test_python python; then
        echo "        Python installed successfully."
    else
        echo ""
        echo "  !! ERROR: Python installation failed or version is too old."
        echo "  Please install Python 3.10+ manually."
        echo ""
        exit 1
    fi
fi

echo "        Using: $PYTHON_CMD"
echo "        Version: $PY_VER"
echo ""

# ------------------------------------------------------------------
#  STEP 3: Create virtual environment
# ------------------------------------------------------------------
echo "  [3/5] Setting up virtual environment..."

if [ -x "$VENV_DIR/bin/python" ]; then
    echo "        Virtual environment already exists."
else
    "$PYTHON_CMD" -m venv "$VENV_DIR" 2>/dev/null || {
        echo "        venv module not available. Installing..."
        if command -v apt-get &>/dev/null; then
            sudo apt-get install -y python3-venv
        fi
        "$PYTHON_CMD" -m venv "$VENV_DIR"
    }
    echo "        Created: $VENV_DIR"
fi

PYTHON_CMD="$VENV_DIR/bin/python"
echo "        Activated virtual environment."
echo ""

# ------------------------------------------------------------------
#  STEP 4: Upgrade pip and install dependencies
# ------------------------------------------------------------------
echo "  [4/5] Installing dependencies..."

"$PYTHON_CMD" -m pip install --upgrade pip --quiet 2>/dev/null
"$PYTHON_CMD" -m pip install -r "$SCRIPT_DIR/requirements.txt" --quiet

echo "        Dependencies installed."
echo ""

# ------------------------------------------------------------------
#  STEP 5: Verify
# ------------------------------------------------------------------
echo "  [5/5] Verifying installation..."

"$PYTHON_CMD" -c "import psutil; import asyncio; import socket; print('        All modules loaded OK.')"

echo ""
echo "  ========================================================"
echo "    Setup complete! Select interface to start proxy..."
echo "  ========================================================"
echo ""

# ------------------------------------------------------------------
#  Show interfaces and let user pick
# ------------------------------------------------------------------
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
#  Check if already running
# ------------------------------------------------------------------
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if kill -0 "$OLD_PID" 2>/dev/null; then
        echo "  Proxy already running (PID: $OLD_PID). Use kill.sh to stop first."
        exit 0
    fi
    rm -f "$PID_FILE"
fi

# ------------------------------------------------------------------
#  Launch detached
# ------------------------------------------------------------------
echo ""
echo "  Starting proxy on interface $BIND_IP (detached)..."

nohup "$PYTHON_CMD" "$SCRIPT_DIR/interface_proxy.py" \
    --bind "$BIND_IP" \
    --logfile "$LOG_FILE" \
    --pidfile "$PID_FILE" \
    </dev/null &>/dev/null &

sleep 2

if [ -f "$PID_FILE" ]; then
    NEW_PID=$(cat "$PID_FILE")
    echo ""
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
