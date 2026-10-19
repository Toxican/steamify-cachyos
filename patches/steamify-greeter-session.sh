#!/bin/bash
# Multi-user mode: the login screen preselects the session the PC would start
# in, as "Boot into" says (gamescope, or the desktop), instead of the one used
# last. plasma-login-manager keeps that per user in its greeter state; this
# sets it at every start of the login manager (a drop-in runs it before it).
USER_NAME="@USER@"
STATE=/var/lib/plasmalogin/.local/state/plasma-login-greeterstaterc

[[ -d "$(dirname "$STATE")" ]] || exit 0
session=gamescope-session.desktop
systemctl is-enabled -q steamify-boot-desktop.service 2>/dev/null && session=plasma.desktop

python3 - "$STATE" "$USER_NAME" "$session" << 'PY' || exit 0
import json
import os
import sys

path, user, session = sys.argv[1:4]
lines = open(path).read().split("\n") if os.path.exists(path) else []
KEY = "LastLoggedInSession="
sessions = {}
start = end = None
for i, line in enumerate(lines):
    if line.strip() == "[General]":
        start, end = i, len(lines)
    elif start is not None and line.startswith("[") and end == len(lines):
        end = i
if start is not None:
    for i in range(start + 1, end):
        if lines[i].startswith(KEY):
            try:
                sessions = json.loads(lines[i][len(KEY):])
            except ValueError:
                sessions = {}
            del lines[i]
            end -= 1
            break
sessions[user] = session
entry = KEY + json.dumps(sessions, separators=(",", ":"))
if start is None:
    lines = [ln for ln in lines if ln] + ["[General]", entry, ""]
else:
    lines.insert(start + 1, entry)
open(path, "w").write("\n".join(lines))
PY
chown plasmalogin:plasmalogin "$STATE" 2>/dev/null
exit 0
