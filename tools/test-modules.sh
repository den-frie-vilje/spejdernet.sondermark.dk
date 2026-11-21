#!/bin/sh
# Proves that the HumHub image built from this repository still carries the
# community's marketplace modules: brings deploy/compose.test.yml up on an
# empty database, installs and enables every module in deploy/modules.txt,
# then signs in as the test administrator and renders the pages the modules
# take part in. Runs on a pull request (.github/workflows/test-modules.yml)
# and anywhere with Docker: tools/test-modules.sh. Exit 0 is a pass; the
# stack is removed either way, and a failure prints the container log first.
set -eu
cd "$(dirname "$0")/.."

compose() { docker compose -f deploy/compose.test.yml "$@"; }
# The console runs as the web user so the files it writes stay writable for
# the web application.
yii() { compose exec -T -u nginx -w /var/www/localhost/htdocs/protected humhub php yii "$@"; }

URL=http://127.0.0.1:18080
JAR=$(mktemp)
BODY=$(mktemp)
finish() {
  status=$?
  if [ "$status" -ne 0 ]; then
    echo "--- humhub container log, last 100 lines"
    compose logs --no-color --tail 100 humhub || true
  fi
  compose down -v --remove-orphans > /dev/null 2>&1 || true
  rm -f "$JAR" "$BODY"
  exit "$status"
}
trap finish EXIT
fail() { echo "FAIL: $*"; exit 1; }

echo "1/4 building the images and installing HumHub on an empty database"
compose up -d --build --wait --wait-timeout 900

echo "2/4 installing and enabling the modules in deploy/modules.txt"
MODULES=$(grep -vE '^[[:space:]]*(#|$)' deploy/modules.txt)
# Each console process caches the module list; the next module's dependency
# check (ModuleDependencyService::getUnmetDependencies) must see this one
# enabled, so the cache is flushed in between.
for m in $MODULES; do
  yii module/install "$m"
  yii module/enable "$m"
  yii cache/flush-all > /dev/null
done
LIST=$(yii module/list)
echo "$LIST"
for m in $MODULES; do
  echo "$LIST" | grep -qE "^  $m +enabled " || fail "$m is not enabled"
done
# The marketplace serves releases per core version; every module must be at
# the release it serves for this core, and the integrity check must pass.
yii module/update-all
yii integrity/run

echo "3/4 signing in as the test administrator and rendering the pages"
# Prints the status code; the body lands in $BODY.
page() { curl -sS -o "$BODY" --max-time 60 -b "$JAR" -c "$JAR" -w '%{http_code}' "$@"; }
page "$URL/user/auth/login" > /dev/null
TOKEN=$(grep -oE 'name="csrf-token" content="[^"]+"' "$BODY" | cut -d'"' -f4)
PARAM=$(grep -oE 'name="csrf-param" content="[^"]+"' "$BODY" | cut -d'"' -f4)
[ -n "$TOKEN" ] && [ -n "$PARAM" ] || fail "no CSRF token on the sign-in page"
code=$(page "$URL/user/auth/login" --data-urlencode "$PARAM=$TOKEN" \
  --data-urlencode 'Login[username]=admin' --data-urlencode 'Login[password]=test-modules')
[ "$code" = 302 ] || fail "sign-in answered $code"

# A page passes with 200 and no error page in the body. A module without a
# page of its own answers 404 to every candidate path; that is reported, not
# failed, since the module's widgets are rendered by the pages below.
render() {
  code=$(page "$URL$1")
  case "$code" in
    200) grep -q 'An internal server error occurred' "$BODY" && fail "$1 rendered the error page"; echo "  200 $1"; return 0 ;;
    404) return 1 ;;
    *) fail "$1 answered $code" ;;
  esac
}
for p in /dashboard /directory/members /admin/module; do
  render "$p" || fail "$p answered 404"
done
# /admin/module is the module manager; it names every installed module.
page "$URL/admin/module" > /dev/null
for m in $MODULES; do
  grep -q "moduleId=$m\b" "$BODY" || fail "the module manager does not list $m"
done
for m in $MODULES; do
  for p in /$m/admin /$m/config /$m/global /$m/index; do
    render "$p" && break
  done || echo "  none $m has no page of its own"
done

echo "4/4 reading the application log"
ERRORS=$(compose exec -T humhub sh -c 'cat protected/runtime/logs/app.log 2>/dev/null' | grep -E '\[error\]' || true)
[ -z "$ERRORS" ] || { echo "$ERRORS"; fail "errors in protected/runtime/logs/app.log"; }

echo "PASS: $(echo "$MODULES" | wc -w | tr -d ' ') modules installed, enabled and rendering"
