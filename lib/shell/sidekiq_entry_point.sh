#!/bin/bash

set -euo pipefail

# Start the run once job.
echo "Sidekiq docker container has been started"

# Setup new aliases
newaliases

# Setup msmptrc
if [ -f "/shared-files/msmtprc" ]; then
  echo "Copying msmtprc file from shared-files"
  install -o root -g root -m 0600 /shared-files/msmtprc /etc/msmtprc
else
  echo "msmtprc file not found in shared-files, using default configuration"
fi

# Ensure existing mail settings are accessible only by root.
if [ -f /etc/msmtprc ]; then
  chown root:root /etc/msmtprc
  chmod 0600 /etc/msmtprc
fi

# Make Sidekiq PID 1 so Docker stop signals reach it directly.
exec bundle exec sidekiq
