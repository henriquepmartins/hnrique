#!/bin/bash
# Instala no iPhone o último build publicado (tag build-N), assinado com a conta
# gratuita da Apple, e reinstala antes que o perfil de 7 dias vença.
set -euo pipefail

UDID="${UDID:-00008110-000A5DC23C02401E}"
TEAM="${TEAM:-H2474S94U5}"
BUNDLE_ID="app.henrique.academia.$TEAM"
MIN_HOURS="${MIN_HOURS:-72}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE="$HOME/Library/Caches/henrique-ios"
LOCK="$CACHE/lock"
STATE="$CACHE/installed-$UDID"
PROFILES="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"

FORCE=0
case "${1:-}" in
  '') ;;
  --force) FORCE=1 ;;
  *) printf 'Uso: %s [--force]\n' "$0" >&2; exit 2 ;;
esac

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
fail() { log "Erro: $*"; exit 1; }
when() { date -r "$1" '+%Y-%m-%d %H:%M'; }

mkdir -p "$CACHE"
if ! mkdir "$LOCK" 2>/dev/null; then
  OWNER="$(cat "$LOCK/pid" 2>/dev/null || true)"
  if [[ -n "$OWNER" ]] && kill -0 "$OWNER" 2>/dev/null; then
    log "Outra execução (pid $OWNER) está em andamento."
    exit 0
  fi
  rm -rf "$LOCK"
  mkdir "$LOCK"
fi
echo $$ > "$LOCK/pid"
TMP="$(mktemp -d "$CACHE/.tmp.XXXXXX")"
trap 'rm -rf "$LOCK" "$TMP"' EXIT

device_reachable() {
  xcrun devicectl list devices --json-output "$TMP/devices.json" >/dev/null 2>&1 || return 1
  local tunnel
  tunnel="$(jq -r --arg udid "$UDID" '.result.devices[] | select(.hardwareProperties.udid == $udid) | .connectionProperties.tunnelState' "$TMP/devices.json")"
  [[ -n "$tunnel" && "$tunnel" != unavailable ]]
}

# Imprime o CFBundleVersion instalado, ou nada se o app não está no iPhone.
installed_version() {
  xcrun devicectl device info apps --device "$UDID" --bundle-id "$BUNDLE_ID" \
    --json-output "$TMP/apps.json" >/dev/null 2>&1 || return 1
  jq -r --arg id "$BUNDLE_ID" '.result.apps[] | select(.bundleIdentifier == $id) | .bundleVersion' "$TMP/apps.json"
}

latest_release() {
  local tags
  if tags="$(git -C "$ROOT" ls-remote --tags --refs origin 'refs/tags/build-*' 2>/dev/null)"; then
    tags="$(awk '{ sub("refs/tags/", "", $2); print $2 }' <<<"$tags")"
  else
    log 'Sem acesso ao origin, uso as tags locais.' >&2
    tags="$(git -C "$ROOT" tag -l 'build-*')"
  fi
  sed -n 's/^build-\([0-9][0-9]*\)$/\1/p' <<<"$tags" | sort -n | tail -1
}

profile_field() {
  security cms -D -i "$1/embedded.mobileprovision" 2>/dev/null | plutil -extract "$2" raw -o - -
}

# Imprime quando vence o perfil do app em cache, em segundos desde 1970, ou 0 se o app
# não existe, é de outro build ou não passa no codesign.
cached_expiry() {
  local app="$1" build="$2" expiration
  [[ -d "$app" ]] || { echo 0; return; }
  [[ "$(plutil -extract CFBundleVersion raw -o - "$app/Info.plist" 2>/dev/null)" == "$build" ]] || { echo 0; return; }
  codesign --verify --strict "$app" 2>/dev/null || { echo 0; return; }
  expiration="$(profile_field "$app" ExpirationDate)" || { echo 0; return; }
  date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$expiration" +%s
}

signature_state() {
  if (( $1 - $(date +%s) > MIN_HOURS * 3600 )); then echo valida; else echo vencendo; fi
}

build_signed() {
  local build="$1" dir="$2"
  if [[ ! -d "$dir/src" ]]; then
    git -C "$ROOT" rev-parse -q --verify "refs/tags/build-$build^{commit}" >/dev/null \
      || git -C "$ROOT" fetch --quiet origin tag "build-$build" \
      || fail "não consegui baixar a tag build-$build."
    mkdir -p "$TMP/src"
    git -C "$ROOT" archive "build-$build" | tar -x -C "$TMP/src"
    mv "$TMP/src" "$dir/src"
  fi
  # Desde a Live Activity o id do app vem de APP_BUNDLE_ID, e a extensão fica com
  # o mesmo id mais .live. PRODUCT_BUNDLE_IDENTIFIER na linha de comando daria o
  # id do app à extensão também. Tags anteriores não têm APP_BUNDLE_ID.
  local bundle_id="APP_BUNDLE_ID=$BUNDLE_ID"
  grep -q 'APP_BUNDLE_ID' "$dir/src/Henrique.xcodeproj/project.pbxproj" \
    || bundle_id="PRODUCT_BUNDLE_IDENTIFIER=$BUNDLE_ID"
  log "Compilando o build $build a partir da tag."
  if ! xcodebuild build \
    -project "$dir/src/Henrique.xcodeproj" \
    -scheme Henrique \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$dir/derived" \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM" \
    CODE_SIGN_STYLE=Automatic \
    "$bundle_id" \
    > "$dir/xcodebuild.log" 2>&1; then
    tail -30 "$dir/xcodebuild.log"
    fail "o xcodebuild falhou. Log completo em $dir/xcodebuild.log"
  fi
}

if ! device_reachable || ! INSTALLED="$(installed_version)"; then
  log "iPhone $UDID fora de alcance. Nada a fazer."
  exit 0
fi

N="$(latest_release)"
[[ -n "$N" ]] || fail 'nenhuma tag build-N encontrada.'

INSTALLED_EXPIRY=0
if [[ -f "$STATE" ]]; then
  read -r STATE_BUILD STATE_EXPIRY < "$STATE"
  [[ "$STATE_BUILD" == "$INSTALLED" ]] && INSTALLED_EXPIRY="$STATE_EXPIRY"
fi
VERSION=outra
[[ "$INSTALLED" == "$N" ]] && VERSION=atual

case "$FORCE:$VERSION:$(signature_state "$INSTALLED_EXPIRY")" in
  0:atual:valida)
    log "Build $N instalado, assinatura vale até $(when "$INSTALLED_EXPIRY"). Nada a fazer."
    exit 0 ;;
  0:atual:vencendo) log "Build $N instalado, mas a assinatura vence em menos de ${MIN_HOURS}h ou não tem registro." ;;
  0:outra:*)        log "iPhone com o build ${INSTALLED:-nenhum}, o último é $N." ;;
  1:*:*)            log "Reinstalação forçada do build $N." ;;
esac

DIR="$CACHE/build-$N"
APP="$DIR/derived/Build/Products/Release-iphoneos/Henrique.app"
mkdir -p "$DIR"
find "$CACHE" -maxdepth 1 -name 'build-*' ! -name "build-$N" -exec rm -rf {} +

EXPIRY="$(cached_expiry "$APP" "$N")"
if [[ "$(signature_state "$EXPIRY")" == vencendo ]]; then
  build_signed "$N" "$DIR"
  EXPIRY="$(cached_expiry "$APP" "$N")"
fi
# O Xcode reaproveita o perfil guardado enquanto ele vale. Apagar força um perfil novo.
if [[ "$(signature_state "$EXPIRY")" == vencendo && -d "$APP" ]]; then
  OLD_PROFILE="$(profile_field "$APP" UUID || true)"
  log "O perfil $OLD_PROFILE vence em $(when "$EXPIRY"). Peço um perfil novo ao Xcode."
  [[ -n "$OLD_PROFILE" ]] && rm -f "$PROFILES/$OLD_PROFILE.mobileprovision"
  rm -rf "$APP"
  build_signed "$N" "$DIR"
  EXPIRY="$(cached_expiry "$APP" "$N")"
fi
[[ "$(signature_state "$EXPIRY")" == valida ]] \
  || fail "o app assinado do build $N não tem perfil com mais de ${MIN_HOURS}h de validade."
log "App assinado do build $N pronto, perfil vale até $(when "$EXPIRY")."

log "Instalando no iPhone."
xcrun devicectl device install app --device "$UDID" "$APP" > "$TMP/install.log" 2>&1 \
  || { tail -20 "$TMP/install.log"; fail 'a instalação falhou.'; }
INSTALLED="$(installed_version)" || fail 'o iPhone sumiu logo depois da instalação.'
[[ "$INSTALLED" == "$N" ]] || fail "o iPhone ficou com o build ${INSTALLED:-nenhum}, esperado $N."
echo "$N $EXPIRY" > "$STATE"
log "Build $N instalado. Assinatura vale até $(when "$EXPIRY")."
