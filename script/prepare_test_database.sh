#!/usr/bin/env bash

set -euo pipefail

restore_seeded_database() {
  gzip -t tmp/ci-seeded-database.sql.gz || return 1
  tar -tzf tmp/ci-seeded-student-work.tar.gz >/dev/null || return 1

  local database_container_id
  database_container_id="$(docker ps --filter ancestor=mariadb --format '{{.ID}}' | head -n 1)"
  if [[ -z "$database_container_id" ]]; then
    echo "Unable to find the MariaDB service container."
    return 1
  fi

  gzip -dc tmp/ci-seeded-database.sql.gz |
    docker exec -i "$database_container_id" mariadb \
      --user="$DF_TEST_DB_USERNAME" \
      --password="$DF_TEST_DB_PASSWORD" \
      "$DF_TEST_DB_DATABASE" || return 1
  tar -xzf tmp/ci-seeded-student-work.tar.gz -C /student-work || return 1
}

if [[ "${SEEDED_DATABASE_CACHE_HIT:-}" == "true" ]] && restore_seeded_database; then
  echo "Restored the populated test database cache."
else
  echo "Populating a fresh test database."
  bundle exec rake db:populate
fi

bundle exec rails runner "abort 'db:populate created no units' unless Unit.exists?"
