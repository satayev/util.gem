#!/bin/bash
#
# Commands to execute in interactive terminals
#
# Executed last
# Not included in non-interactive terminals, like cron
#

if command -v screens > /dev/null; then
  screens=$(screens)
  if [[ -n "$screens" ]]; then
    echo "Open screen sessions: $(echo "$screens" | wc -w)"
    echo "  $(echo "$screens" | tr '\n' ' ')"
  fi
  unset screens
fi
