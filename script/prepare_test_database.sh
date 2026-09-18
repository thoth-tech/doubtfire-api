#!/usr/bin/env bash

set -euo pipefail

if [[ "${SEEDED_DATABASE_CACHE_HIT:-}" == "true" ]]; then
  gzip -t tmp/ci-seeded-database.sql.gz
  tar -tzf tmp/ci-seeded-student-work.tar.gz >/dev/null
  echo "Validated the populated test database cache; logical lanes import it directly."
  exit 0
fi

echo "Populating a fresh test database."
bundle exec rake db:populate
bundle exec rails runner "abort 'db:populate created no units' unless Unit.exists?"
