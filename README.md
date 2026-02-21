# Interface-Bound Proxy

<p align="center">
  <img src="logo.png" width="300">
</p>

Force your browser (or any app) to use a **specific network interface / internet line** by running a local proxy server that binds all outgoing connections to the chosen interface's IP.

Works on **Windows** and **Linux/macOS**.

## How it works

```
Browser --> 127.0.0.1:8118 (local proxy) --> binds to 2nd interface IP --> Internet
```

The proxy accepts HTTP and HTTPS (via CONNECT tunnelling) requests, then opens the outgoing connection **bound to the IP address of your chosen network adapter**. The OS routes that traffic through the corresponding interface.

## Quick start

### Windows

| Action | Script |
|--------|--------|
| First-time setup + launch | Double-click **`setup.bat`** |
| Quick launch (after setup) | Double-click **`run_proxy.bat`** |
| Stop the proxy | Double-click **`kill.bat`** |

`setup.bat` handles everything automatically, even on a fresh machine with no Python:
1. Downloads and sets up a portable Python (no installer, no admin, no PATH changes)
2. Installs pip and all dependencies
3. Lets you pick a network interface
4. Launches the proxy in the background (no terminal window stays open)
5. Writes logs to `proxy.log`

### Linux / macOS

```bash
# First-time setup + launch
chmod +x setup.sh run_proxy.sh kill.sh
./setup.sh

# Quick launch (after setup)
./run_proxy.sh

# Stop the proxy
./kill.sh
```

`setup.sh` detects your package manager and installs Python if needed:
- **Debian/Ubuntu**: `apt-get install python3 python3-pip python3-venv`
- **Fedora/RHEL**: `dnf install python3 python3-pip`
- **Arch**: `pacman -S python python-pip`
- **Alpine**: `apk add python3 py3-pip`
- **macOS (Homebrew)**: `brew install python@3.12`

### How to pick scripts

The scripts auto-detect the OS:
- On **Windows**, use the `.bat` files
- On **Linux/macOS**, use the `.sh` files

The Python proxy code (`interface_proxy.py`) is the same on both platforms.

## Configure your browser

After the proxy starts, set your browser's proxy to `127.0.0.1:8118`.

### Chrome / Edge / Brave (Windows)

- **Windows Settings** > Network & Internet > Proxy > Manual proxy setup:
  - Address: `127.0.0.1`, Port: `8118`
- Or launch Chrome with a flag:
  ```
  chrome.exe --proxy-server="http://127.0.0.1:8118"
  ```

### Chrome / Chromium (Linux)

```bash
google-chrome --proxy-server="http://127.0.0.1:8118"
# or
chromium --proxy-server="http://127.0.0.1:8118"
```

Or set the environment variable:
```bash
export http_proxy=http://127.0.0.1:8118
export https_proxy=http://127.0.0.1:8118
```

### Firefox (all platforms)

1. Settings > General > scroll to **Network Settings** > click **Settings...**
2. Select **Manual proxy configuration**
3. HTTP Proxy: `127.0.0.1`  Port: `8118`
4. Check **"Also use this proxy for HTTPS"**
5. Click OK

## Command-line options

```
python interface_proxy.py [options]
```

| Flag | Description | Default |
|------|-------------|---------|
| `--bind` / `-b` | IP of the interface to route through | *(interactive)* |
| `--port` / `-p` | Local proxy port | `8118` |
| `--listen` / `-l` | Address to listen on | `127.0.0.1` |
| `--logfile` | Write logs to file instead of console | *(console)* |
| `--pidfile` | Write process ID to file | *(none)* |
| `--list-interfaces` | Print interfaces and exit | |
| `--verbose` / `-v` | Debug logging | off |

## Finding your interface IPs

### Windows
```
ipconfig
```

### Linux
```bash
ip addr
# or
ifconfig
```

Look for your adapters (e.g., eth0, wlan0, enp3s0). Each has an **inet** address.

## Example

```
$ ./run_proxy.sh

  ============================================
   Interface-Bound Proxy Server
  ============================================

  Detecting network interfaces...

    [1]    192.168.1.10   (eth0)
    [2]      10.0.0.55   (wlan0)

  Select interface number: 2

  ========================================
   Proxy is running!
  ========================================

   PID:       12345
   Proxy:     127.0.0.1:8118
   Interface: 10.0.0.55
   Logs:      /home/user/proxy/proxy.log

   Set your browser proxy to 127.0.0.1:8118
   Run ./kill.sh to stop the proxy.
```

## Files

| File | Platform | Description |
|------|----------|-------------|
| `interface_proxy.py` | Both | The proxy server (Python) |
| `requirements.txt` | Both | Python dependencies |
| `setup.bat` | Windows | Full setup + launch |
| `run_proxy.bat` | Windows | Quick launch |
| `kill.bat` | Windows | Stop the proxy |
| `setup.sh` | Linux/macOS | Full setup + launch |
| `run_proxy.sh` | Linux/macOS | Quick launch |
| `kill.sh` | Linux/macOS | Stop the proxy |
| `proxy.log` | Both | Log file (created at runtime) |
| `proxy.pid` | Both | PID file (created at runtime) |

## Troubleshooting

- **"Connection refused"** -- Make sure the proxy is running. Check `proxy.log`.
- **Slow or no connection** -- Verify the interface IP is correct and has internet.
  - Windows: `ping 8.8.8.8 -S <interface_ip>`
  - Linux: `ping -I <interface_ip> 8.8.8.8`
- **Some sites don't work** -- The proxy handles HTTP/HTTPS. Protocols like QUIC (UDP) won't go through an HTTP proxy. In Firefox, set `network.http.http3.enable` to `false` in `about:config`.
- **Permission denied (Linux)** -- Run `chmod +x setup.sh run_proxy.sh kill.sh`.
