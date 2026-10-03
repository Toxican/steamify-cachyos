#!/bin/bash
# Installed by Steamify CachyOS: run its newest release.
# pipefail: a failed download must count as a failure, not an empty script.
set -o pipefail
if ! curl -fsSL --max-time 30 "@URL@" | bash; then
    echo
    echo "Couldn't download or run the wizard. Are you connected to the internet?"
    echo
    read -rp "Press Enter to close this window... " _
    exit 1
fi
# Done: close the window after a countdown (Enter closes it right away).
echo
for (( i = 10; i > 0; i-- )); do
    printf '\rClosing this window in %2d seconds (Enter to close now)... ' "$i"
    read -rs -t 1 _ && break
done
echo
