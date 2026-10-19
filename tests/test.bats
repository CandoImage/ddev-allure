#!/usr/bin/env bats

# Bats is a testing framework for Bash
# Documentation https://bats-core.readthedocs.io/en/stable/
# Bats libraries documentation https://github.com/ztombol/bats-docs

# For local tests, install bats-core, bats-assert, bats-file, bats-support
# And run this in the add-on root directory:
#   bats ./tests/test.bats
# To exclude release tests:
#   bats ./tests/test.bats --filter-tags '!release'
# For debugging:
#   bats ./tests/test.bats --show-output-of-passing-tests --verbose-run --print-output-on-failure
#
# Note: the add-on starts ONE shared server (ddev-allure); the teardown purges it.

setup() {
  set -eu -o pipefail

  export GITHUB_REPO=CandoImage/ddev-allure

  TEST_BREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
  export BATS_LIB_PATH="${BATS_LIB_PATH}:${TEST_BREW_PREFIX}/lib:/usr/lib/bats"
  bats_load_library bats-assert
  bats_load_library bats-file
  bats_load_library bats-support

  export DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." >/dev/null 2>&1 && pwd)"
  export PROJNAME="test-$(basename "${GITHUB_REPO}")"
  mkdir -p ~/tmp
  export TESTDIR=$(mktemp -d ~/tmp/${PROJNAME}.XXXXXX)
  export DDEV_NONINTERACTIVE=true
  export DDEV_NO_INSTRUMENTATION=true
  ddev delete -Oy "${PROJNAME}" >/dev/null 2>&1 || true
  cd "${TESTDIR}"
  # Optional for hosts where 80/443 are taken, e.g. TEST_ROUTER_HTTPS_PORT=8443.
  local router_ports=()
  [ -n "${TEST_ROUTER_HTTP_PORT:-}" ] && router_ports+=(--router-http-port="${TEST_ROUTER_HTTP_PORT}")
  [ -n "${TEST_ROUTER_HTTPS_PORT:-}" ] && router_ports+=(--router-https-port="${TEST_ROUTER_HTTPS_PORT}")
  run ddev config --project-name="${PROJNAME}" --project-tld=ddev.site --omit-containers=db "${router_ports[@]}"
  assert_success
  run ddev start -y
  assert_success
}

wait_for_api() {
  for _ in $(seq 1 60); do
    curl -sf http://localhost:5050/version >/dev/null && return 0
    sleep 2
  done
  return 1
}

health_checks() {
  run ddev allure start
  assert_success
  assert_output --partial "http://ddev-allure:5050"
  run wait_for_api
  assert_success

  # Own compose project: never part of the calling DDEV project.
  run docker inspect ddev-allure --format '{{index .Config.Labels "com.docker.compose.project"}}'
  assert_output "ddev-allure"

  # Host, router route and DDEV containers.
  run curl -sf http://localhost:5050/version
  assert_output --partial '"version"'
  run curl -sf -o /dev/null -w '%{http_code}' http://localhost:5252/
  assert_output "200"
  assert_file_exist ~/.ddev/traefik/custom-global-config/ddev-allure.yaml
  local https_port
  https_port=$(ddev describe -j | jq -r '.raw.router_https_port')
  run curl -skf -o /dev/null -w '%{http_code}' "https://allure-api.ddev.site:${https_port}/version"
  assert_output "200"
  run ddev exec curl -sf http://ddev-allure:5050/version
  assert_success

  # Push results and generate a report.
  run curl -sf -X POST "http://localhost:5050/send-results?project_id=ddev-allure-test&force_project_creation=true" \
    -F "files[]=@${DIR}/tests/testdata/allure-results/0c2b6a3e-6c0e-4d5a-9a43-6b1f3c2d7e11-result.json"
  assert_success
  run curl -sf "http://localhost:5050/generate-report?project_id=ddev-allure-test"
  assert_success
  run curl -sf http://localhost:5050/projects/ddev-allure-test/reports/latest/widgets/summary.json
  assert_output --partial '"passed":1'

  # Independent of the project: survives ddev stop, results survive stop/start.
  run ddev stop
  assert_success
  run curl -sf http://localhost:5050/version
  assert_success
  run ddev allure stop
  assert_success
  assert_file_not_exist ~/.ddev/traefik/custom-global-config/ddev-allure.yaml
  run ddev allure start
  assert_success
  run wait_for_api
  assert_success
  run curl -sf http://localhost:5050/projects
  assert_output --partial "ddev-allure-test"
}

teardown() {
  set -eu -o pipefail
  cd "${TESTDIR}" || ( printf "unable to cd to %s\n" "${TESTDIR}" && exit 1 )
  ddev allure purge >/dev/null 2>&1 || true
  ddev delete -Oy "${PROJNAME}" >/dev/null 2>&1
  [ "${TESTDIR}" != "" ] && rm -rf "${TESTDIR}"
}

@test "install from directory" {
  set -eu -o pipefail
  echo "# ddev add-on get ${DIR} with project ${PROJNAME} in $(pwd)" >&3
  run ddev add-on get "${DIR}"
  assert_success
  run ddev restart -y
  assert_success
  health_checks
}

# bats test_tags=release
@test "install from release" {
  set -eu -o pipefail
  echo "# ddev add-on get ${GITHUB_REPO} with project ${PROJNAME} in $(pwd)" >&3
  run ddev add-on get "${GITHUB_REPO}"
  assert_success
  run ddev restart -y
  assert_success
  health_checks
}
