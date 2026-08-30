#!/bin/bash

set -euo pipefail

# Cron starts jobs with a deliberately small environment. Persist only the
# application and Ruby runtime settings that those jobs can need, rather than
# copying every variable inherited by the container. Values are shell-escaped
# because this file is sourced through BASH_ENV by .ci-setup/crontab.
is_cron_environment_variable() {
  case "$1" in
    BUNDLE_* | DATABASE_URL | DF_* | D2L_* | DISK_SPACE_ENDPOINT_ENABLED | \
      DOCKER_CERT_PATH | DOCKER_HOST | DOCKER_PROXY_URL | DOCKER_REGISTRY_URL | \
      DOCKER_TLS_VERIFY | DOCKER_TOKEN | DOCKER_USER | DOUBTFIRE_* | GEM_HOME | \
      GEM_PATH | GOTENBERG_* | HTTP_PROXY | HTTPS_PROXY | LANG | LATEX_* | \
      LC_* | LTI_* | MODERATION_SCORE_FACTOR | NO_PROXY | OVERSEER_* | \
      RABBITMQ_* | RACK_ENV | RAILS_* | RUBYLIB | RUBYOPT | SENTRY_* | \
      SSL_CERT_DIR | SSL_CERT_FILE | TCA_* | TII_* | TMPDIR | TZ | \
      http_proxy | https_proxy | no_proxy)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

destination="${1:-/container.env}"
temporary_file=''

cleanup() {
  if [[ -n "${temporary_file}" ]]; then
    rm -f -- "${temporary_file}"
  fi
}

trap cleanup EXIT
trap 'exit 1' HUP INT TERM

umask 077
temporary_file="$(mktemp "${destination}.tmp.XXXXXX")"

while IFS= read -r variable_name; do
  if is_cron_environment_variable "${variable_name}"; then
    printf 'export %s=%q\n' \
      "${variable_name}" "${!variable_name}" >> "${temporary_file}"
  fi
done < <(compgen -e | LC_ALL=C sort)

chmod 0600 "${temporary_file}"
mv -f -- "${temporary_file}" "${destination}"
temporary_file=''
trap - EXIT HUP INT TERM
