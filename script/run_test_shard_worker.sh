#!/usr/bin/env bash

set -euo pipefail

workspace="${GITHUB_WORKSPACE:-$(pwd)}"
plan_path="${TEST_SHARD_WORKER_PLAN:-$workspace/tmp/test-shard-worker-plan.tsv}"
evidence_dir="$workspace/tmp"
lane_root="$workspace/tmp/test-shard-lanes"
student_work_root="$workspace/tmp/test-shard-student-work"
log_root="$workspace/tmp/test-shard-logs"
database_dump="$workspace/tmp/ci-seeded-database.sql.gz"
student_work_archive="$workspace/tmp/ci-seeded-student-work.tar.gz"
api_image="${TEST_SHARD_API_IMAGE:-doubtfire-api-ci:local}"
texlive_image="${TEST_SHARD_TEXLIVE_IMAGE:-doubtfire-texlive-development:local}"
jplag_image="${TEST_SHARD_JPLAG_IMAGE:-doubtfire-jplag-development:local}"

required_variables=(
  CI_SERVICE_NETWORK
  DF_TEST_DB_ADAPTER
  DF_TEST_DB_HOST
  DF_TEST_DB_USERNAME
  DF_TEST_DB_PASSWORD
  TEST_SHARD_COUNT
)
for variable_name in "${required_variables[@]}"; do
  if [[ -z "${!variable_name:-}" ]]; then
    echo "Missing required environment variable: $variable_name" >&2
    exit 1
  fi
done

if [[ ! -s "$plan_path" ]]; then
  echo "Test shard worker plan is missing: $plan_path" >&2
  exit 1
fi
gzip -t "$database_dump"
tar -tzf "$student_work_archive" >/dev/null

database_container_id="$(
  docker ps --filter "network=$CI_SERVICE_NETWORK" --filter ancestor=mariadb --format '{{.ID}}' |
    head -n 1
)"
redis_container_id="$(
  docker ps --filter "network=$CI_SERVICE_NETWORK" --filter ancestor=redis:7.0 --format '{{.ID}}' |
    head -n 1
)"
if [[ -z "$database_container_id" || -z "$redis_container_id" ]]; then
  echo 'Unable to locate the MariaDB and Redis service containers.' >&2
  exit 1
fi

mkdir -p "$lane_root" "$student_work_root" "$log_root"
declare -a logical_shards=()
declare -a redis_databases=()
declare -a database_names=()
declare -a lane_workspaces=()
declare -a student_workspaces=()
declare -a latex_names=()
declare -a texlive_requirements=()
declare -a jplag_requirements=()
declare -a api_container_names=()
declare -a helper_container_names=()
declare -a cleanup_container_names=()
jplag_lane_count=0

cleanup() {
  for container_name in "${cleanup_container_names[@]:-}"; do
    [[ -n "$container_name" ]] || continue
    docker rm --force "$container_name" >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT INT TERM

cd "$workspace"
while IFS=$'\t' read -r logical_shard redis_database needs_texlive needs_jplag; do
  if [[ ! "$logical_shard" =~ ^[0-9]+$ || ! "$redis_database" =~ ^[0-3]$ ]]; then
    echo "Invalid logical shard plan row: $logical_shard $redis_database" >&2
    exit 1
  fi
  if [[ "$needs_texlive" != 'true' && "$needs_texlive" != 'false' ]] ||
     [[ "$needs_jplag" != 'true' && "$needs_jplag" != 'false' ]]; then
    echo "Invalid helper flags for logical shard $logical_shard" >&2
    exit 1
  fi

  database_name="doubtfire_test_shard_${logical_shard}"
  lane_workspace="$lane_root/shard-$logical_shard"
  student_workspace="$student_work_root/shard-$logical_shard"
  latex_name="${LATEX_CONTAINER_NAME:-doubtfire-texlive}-shard-$logical_shard"
  api_container_name="doubtfire-api-test-shard-$logical_shard"

  if [[ -e "$lane_workspace" || -e "$student_workspace" ]]; then
    echo "Refusing to reuse an existing logical-shard workspace: $logical_shard" >&2
    exit 1
  fi

  logical_shards+=("$logical_shard")
  redis_databases+=("$redis_database")
  database_names+=("$database_name")
  lane_workspaces+=("$lane_workspace")
  student_workspaces+=("$student_workspace")
  latex_names+=("$latex_name")
  texlive_requirements+=("$needs_texlive")
  jplag_requirements+=("$needs_jplag")
  api_container_names+=("$api_container_name")
  if [[ "$needs_texlive" == 'true' ]]; then
    helper_container_names+=("$latex_name")
  fi
  if [[ "$needs_jplag" == 'true' ]]; then
    helper_container_names+=(jplag)
    jplag_lane_count=$((jplag_lane_count + 1))
  fi
done < "$plan_path"

if [[ "${#logical_shards[@]}" -ne 4 ]]; then
  echo "Expected four logical shards in $plan_path, found ${#logical_shards[@]}." >&2
  exit 1
fi
if [[ "$(printf '%s\n' "${logical_shards[@]}" | sort -u | wc -l)" -ne 4 ]]; then
  echo 'The worker plan contains duplicate logical shards.' >&2
  exit 1
fi
if [[ "$(printf '%s\n' "${redis_databases[@]}" | sort -u | wc -l)" -ne 4 ]]; then
  echo 'The worker plan must use each isolated Redis database exactly once.' >&2
  exit 1
fi
if [[ "$jplag_lane_count" -gt 1 ]]; then
  echo 'A physical worker cannot run more than one JPlag logical shard.' >&2
  exit 1
fi
for container_name in "${api_container_names[@]}" "${helper_container_names[@]:-}"; do
  [[ -n "$container_name" ]] || continue
  if docker container inspect "$container_name" >/dev/null 2>&1; then
    echo "Planned test container name is already in use: $container_name" >&2
    exit 1
  fi
done
cleanup_container_names=("${api_container_names[@]}" "${helper_container_names[@]:-}")

for index in "${!logical_shards[@]}"; do
  database_name="${database_names[$index]}"
  redis_database="${redis_databases[$index]}"
  docker exec "$database_container_id" mariadb --user=root --execute \
    "DROP DATABASE IF EXISTS \`$database_name\`; CREATE DATABASE \`$database_name\`; GRANT ALL ON \`$database_name\`.* TO '$DF_TEST_DB_USERNAME'@'%';"
  docker exec "$redis_container_id" redis-cli -n "$redis_database" FLUSHDB >/dev/null
done

setup_logical_shard() {
  local index="$1"
  local logical_shard="${logical_shards[$index]}"
  local database_name="${database_names[$index]}"
  local lane_workspace="${lane_workspaces[$index]}"
  local student_workspace="${student_workspaces[$index]}"
  local latex_name="${latex_names[$index]}"

  mkdir -p "$lane_workspace" "$student_workspace"
  git ls-files -z |
    tar --null --files-from=- --create |
    tar --extract --directory="$lane_workspace"
  mkdir -p "$lane_workspace/tmp/jplag" "$lane_workspace/log"
  tar -xzf "$student_work_archive" -C "$student_workspace"
  gzip -dc "$database_dump" |
    docker exec --interactive "$database_container_id" mariadb --user=root "$database_name"

  if [[ "${texlive_requirements[$index]}" == 'true' ]]; then
    docker run --detach \
      --name "$latex_name" \
      --network "$CI_SERVICE_NETWORK" \
      --volume "$student_workspace:/student-work" \
      --volume "$lane_workspace/public/assets/images:/doubtfire/public/assets/images" \
      --volume "$lane_workspace/test_files:/doubtfire/test_files" \
      --volume "$lane_workspace/tmp/rails-latex:/workdir/texlive-latex" \
      "$texlive_image" \
      sleep infinity >/dev/null
    docker exec "$latex_name" lualatex -v >/dev/null
  fi

  if [[ "${jplag_requirements[$index]}" == 'true' ]]; then
    docker run --detach \
      --name jplag \
      --network "$CI_SERVICE_NETWORK" \
      --volume "$student_workspace:/student-work" \
      --volume "$lane_workspace/tmp/jplag:/tmp/jplag" \
      --volume "$lane_workspace/test_files/submissions/jplag:/test_files" \
      "$jplag_image" \
      sleep infinity >/dev/null
    docker exec --env TERM=xterm jplag \
      java -jar /jplag/jplag-jar-with-dependencies.jar /test_files \
      -l java --similarity-threshold=0.30 -M RUN -r test.jplag >/dev/null
  fi

  echo "Prepared logical shard $logical_shard."
}

setup_started_at=$SECONDS
declare -a setup_processes=()
for index in "${!logical_shards[@]}"; do
  setup_log_path="$log_root/shard-${logical_shards[$index]}-setup.log"
  setup_logical_shard "$index" >"$setup_log_path" 2>&1 &
  setup_processes+=("$!")
done

setup_failed=0
for index in "${!logical_shards[@]}"; do
  logical_shard="${logical_shards[$index]}"
  if wait "${setup_processes[$index]}"; then
    outcome='passed'
  else
    outcome='failed'
    setup_failed=1
  fi
  echo "::group::Set up logical shard $logical_shard/$TEST_SHARD_COUNT ($outcome)"
  cat "$log_root/shard-$logical_shard-setup.log"
  echo '::endgroup::'
done
echo "Prepared four logical-shard lanes in $((SECONDS - setup_started_at))s."
if [[ "$setup_failed" -ne 0 ]]; then
  exit 1
fi

run_logical_shard() {
  local index="$1"
  local logical_shard="${logical_shards[$index]}"
  local redis_database="${redis_databases[$index]}"
  local database_name="${database_names[$index]}"
  local lane_workspace="${lane_workspaces[$index]}"
  local student_workspace="${student_workspaces[$index]}"
  local latex_name="${latex_names[$index]}"
  local api_container_name="${api_container_names[$index]}"

  docker run --rm \
    --name "$api_container_name" \
    --network "$CI_SERVICE_NETWORK" \
    --volume "$lane_workspace:/doubtfire" \
    --volume "$student_workspace:/student-work" \
    --volume "$evidence_dir:/evidence" \
    --volume /var/run/docker.sock:/var/run/docker.sock \
    --volume "$lane_workspace/tmp/jplag:/tmp/jplag" \
    --env TERM=xterm \
    --env RAILS_ENV \
    --env DF_INSTITUTION_HOST \
    --env DF_INSTITUTION_PRODUCT_NAME \
    --env DF_SECRET_KEY_BASE \
    --env DF_SECRET_KEY_ATTR \
    --env DF_SECRET_KEY_DEVISE \
    --env DF_TEST_DB_ADAPTER \
    --env DF_TEST_DB_HOST \
    --env "DF_TEST_DB_DATABASE=$database_name" \
    --env DF_TEST_DB_USERNAME \
    --env DF_TEST_DB_PASSWORD \
    --env OVERSEER_ENABLED \
    --env DF_ENCRYPTION_PRIMARY_KEY \
    --env DF_ENCRYPTION_DETERMINISTIC_KEY \
    --env DF_ENCRYPTION_KEY_DERIVATION_SALT \
    --env "DF_REDIS_SIDEKIQ_URL=redis://redis:6379/$redis_database" \
    --env "DF_STUDENT_WORK_DIR=/student-work" \
    --env "LATEX_CONTAINER_NAME=$latex_name" \
    --env LATEX_BUILD_PATH \
    --env LTI_SHARED_API_SECRET \
    --env LTI_ENABLED \
    --env TEST_SHARD_COUNT \
    --env "TEST_SHARD_NUMBER=$logical_shard" \
    --env "TEST_SHARD_MANIFEST=/evidence/test-shard-manifests/shard-$logical_shard.txt" \
    --env "TEST_SHARD_RUN_COUNT=/evidence/test-shard-run-counts/shard-$logical_shard.txt" \
    --env "TEST_SHARD_EXECUTED_RUNNABLES=/evidence/test-shard-executed-runnables/shard-$logical_shard.txt" \
    --env "TEST_RUNNABLE_INVENTORY=/evidence/test-runnable-inventory.txt" \
    "$api_image" \
    bundle exec ruby script/test_shard.rb
}

declare -a shard_processes=()
tests_started_at=$SECONDS
for index in "${!logical_shards[@]}"; do
  log_path="$log_root/shard-${logical_shards[$index]}.log"
  run_logical_shard "$index" >"$log_path" 2>&1 &
  shard_processes+=("$!")
done

worker_failed=0
for index in "${!logical_shards[@]}"; do
  logical_shard="${logical_shards[$index]}"
  if wait "${shard_processes[$index]}"; then
    outcome='passed'
  else
    outcome='failed'
    worker_failed=1
  fi
  echo "::group::Logical shard $logical_shard/$TEST_SHARD_COUNT ($outcome)"
  cat "$log_root/shard-$logical_shard.log"
  echo '::endgroup::'
done
echo "Ran four logical test shards in $((SECONDS - tests_started_at))s."

exit "$worker_failed"
