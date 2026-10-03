#!/bin/bash
# Installed by Steamify CachyOS: start the newest release of its app.
set -o pipefail
if [[ "${1:-}" != --in-terminal ]] && ! python3 -c 'import PySide6.QtQml' 2>/dev/null; then
    exec konsole -e "$0" --in-terminal
fi
if ! curl -fsSL --max-time 30 "@URL@" | bash; then
    msg="Couldn't download or start Steamify. Are you connected to the internet?"
    if [[ "${1:-}" == --in-terminal ]]; then echo; echo "$msg"; read -rp "Press Enter to close this window... " _
    else kdialog --title Steamify --sorry "$msg" 2>/dev/null; fi
    exit 1
fi
