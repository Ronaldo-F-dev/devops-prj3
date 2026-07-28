#!/usr/bin/env sh
set -eu

echo "Hostname: $(hostname)"
echo
echo "Disk usage:"
df -h
echo
echo "Memory usage:"
free -m