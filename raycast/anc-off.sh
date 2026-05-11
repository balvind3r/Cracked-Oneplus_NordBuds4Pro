#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title ANC Off
# @raycast.mode silent
# @raycast.packageName Nord Buds
# @raycast.icon 🎧

exec "$(dirname "$0")/../nordbuds-cli" off
