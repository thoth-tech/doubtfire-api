#!/bin/bash

set -euo pipefail

# Start the run once job.
echo "Pdfgen docker container has been started"

# Setup new aliases
newaliases

# Save only the environment required when Rails jobs run under cron. The file
# contains secrets needed to boot the application, so its writer keeps it
# private and this entry point must never print it.
/doubtfire/lib/shell/write_cron_environment.sh /container.env

# Ensure log is present
touch /var/log/cron.log

# Setup crontab - clear then load with file
crontab -r 2>/dev/null || true
crontab /etc/cron.d/container_cronjob

echo "RESET CRONTAB" >> /var/log/cron.log

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

# Make cron PID 1 so Docker stop signals reach it directly. cron -f does not
# return while healthy, so the old trailing tail command was unreachable.
chmod 0644 /etc/cron.d/container_cronjob
exec cron -f
