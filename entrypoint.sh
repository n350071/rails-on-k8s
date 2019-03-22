#!/bin/bash
# -e Exit immediately if a command exits without 0 (error).
# -u Exit immediately if undefeined val is used (error).
set -eu

# Remove a potentially pre-existing server.pid for Rails.
rm -f /myapp/tmp/pids/server.pid

# Then exec the container's main process (what's set as CMD in the Dockerfile).
# exec "$@" will replace the current running shell with the command that "$@" is pointing to.
exec "$@"
