#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Anchor"
BUNDLE_ID="dev.ryuuieun.Anchor"
MIN_SYSTEM_VERSION="13.0"
CONFIGURATION="${CONFIGURATION:-debug}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
INSTALL_DIR="${ANCHOR_INSTALL_DIR:-/Applications}"
INSTALLED_APP_BUNDLE="$INSTALL_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
SIGNING_DIR="${ANCHOR_SIGNING_DIR:-$HOME/Library/Application Support/$APP_NAME/signing}"
SIGNING_KEYCHAIN="$SIGNING_DIR/$APP_NAME.keychain-db"
SIGNING_KEYCHAIN_PASSWORD_FILE="$SIGNING_DIR/keychain.password"
SIGNING_CERT_NAME="${ANCHOR_SIGNING_CERT_NAME:-$APP_NAME Local Code Signing}"
SIGNING_KEY="$SIGNING_DIR/codesign.key"
SIGNING_CERT="$SIGNING_DIR/codesign.crt"
SIGNING_P12="$SIGNING_DIR/codesign.p12"
SIGNING_IDENTITY=""

MODE="${1:-run}"

cd "$ROOT_DIR"

usage() {
  cat <<USAGE
Usage: ./script/build_and_run.sh [run|--build-only|--install|--verify|--logs|--telemetry|--init-signing]

Modes:
  run             Build, sign, and open dist/$APP_NAME.app
  --build-only    Build and sign dist/$APP_NAME.app without launching
  --install       Build, sign, copy to /Applications, and open installed app
  --verify        Build, sign, open dist/$APP_NAME.app, and verify the process is running
  --logs          Build, sign, open dist/$APP_NAME.app, then stream logs
  --telemetry     Build, sign, open dist/$APP_NAME.app, then stream Anchor subsystem telemetry
  --init-signing  Explicitly create the local signing identity if missing

Environment:
  ANCHOR_SIGNING_DIR        Override signing directory
  ANCHOR_SIGNING_CERT_NAME  Override local signing certificate name
  ANCHOR_INSTALL_DIR        Override install directory, default /Applications
USAGE
}

read_keychain_password() {
  if [[ -f "$SIGNING_KEYCHAIN_PASSWORD_FILE" ]]; then
    cat "$SIGNING_KEYCHAIN_PASSWORD_FILE"
  fi
}

ensure_keychain_password() {
  if [[ -f "$SIGNING_KEYCHAIN_PASSWORD_FILE" ]]; then
    return
  fi

  openssl rand -base64 32 > "$SIGNING_KEYCHAIN_PASSWORD_FILE"
  chmod 600 "$SIGNING_KEYCHAIN_PASSWORD_FILE"
}

unlock_signing_keychain() {
  local password
  password="$(read_keychain_password)"
  if security unlock-keychain -p "$password" "$SIGNING_KEYCHAIN" >/dev/null; then
    return 0
  fi

  # Older local setups used an empty keychain password. Keep that path working.
  if [[ -n "$password" ]] && security unlock-keychain -p "" "$SIGNING_KEYCHAIN" >/dev/null; then
    return 0
  fi

  return 1
}

find_signing_identity() {
  SIGNING_IDENTITY=""
  if [[ ! -f "$SIGNING_KEYCHAIN" ]]; then
    return 1
  fi

  unlock_signing_keychain

  SIGNING_IDENTITY="$(security find-identity -p codesigning -v "$SIGNING_KEYCHAIN" | awk -v name="$SIGNING_CERT_NAME" '$0 ~ name { print $2; exit }')"
  [[ -n "$SIGNING_IDENTITY" ]]
}

init_signing_identity() {
  mkdir -p "$SIGNING_DIR"
  chmod 700 "$SIGNING_DIR"

  if [[ ! -f "$SIGNING_KEYCHAIN" ]]; then
    ensure_keychain_password
    security create-keychain -p "$(read_keychain_password)" "$SIGNING_KEYCHAIN" >/dev/null
  fi
  unlock_signing_keychain

  if find_signing_identity; then
    echo "Signing identity already exists: $SIGNING_CERT_NAME"
    echo "Signing directory: $SIGNING_DIR"
    return
  fi

  rm -f "$SIGNING_KEY" "$SIGNING_P12"
  trap 'rm -f "$SIGNING_KEY" "$SIGNING_P12"' EXIT

  openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -subj "/CN=$SIGNING_CERT_NAME/" \
    -addext "keyUsage=digitalSignature" \
    -addext "extendedKeyUsage=codeSigning" \
    -keyout "$SIGNING_KEY" \
    -out "$SIGNING_CERT" >/dev/null 2>&1

  local p12_password
  p12_password="$(openssl rand -base64 32)"

  openssl pkcs12 -export \
    -legacy \
    -inkey "$SIGNING_KEY" \
    -in "$SIGNING_CERT" \
    -out "$SIGNING_P12" \
    -passout "pass:$p12_password" >/dev/null 2>&1

  security import "$SIGNING_P12" \
    -k "$SIGNING_KEYCHAIN" \
    -P "$p12_password" \
    -T /usr/bin/codesign >/dev/null
  security add-trusted-cert \
    -r trustRoot \
    -k "$SIGNING_KEYCHAIN" \
    "$SIGNING_CERT" >/dev/null 2>&1 || true
  security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s \
    -k "$(read_keychain_password)" \
    "$SIGNING_KEYCHAIN" >/dev/null 2>&1 || true
  rm -f "$SIGNING_KEY" "$SIGNING_P12"
  trap - EXIT

  SIGNING_IDENTITY="$(security find-identity -p codesigning -v "$SIGNING_KEYCHAIN" | awk -v name="$SIGNING_CERT_NAME" '$0 ~ name { print $2; exit }')"
  if [[ -z "$SIGNING_IDENTITY" ]]; then
    echo "Could not create local code signing identity" >&2
    exit 1
  fi

  echo "Initialized signing identity: $SIGNING_CERT_NAME"
  echo "Signing directory: $SIGNING_DIR"
}

require_signing_identity() {
  if find_signing_identity; then
    return
  fi

  cat >&2 <<ERROR
Missing Anchor signing identity.
Run this once before building:
  ./script/build_and_run.sh --init-signing

Expected signing directory:
  $SIGNING_DIR
ERROR
  exit 1
}

if [[ "$MODE" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "$MODE" == "--init-signing" ]]; then
  init_signing_identity
  exit 0
fi

stop_app_process() {
  local process_name="$1"
  if pgrep -x "$process_name" >/dev/null 2>&1; then
    pkill -x "$process_name" || true
  fi
}

case "$MODE" in
  run|--verify|--logs|--telemetry|--install)
    stop_app_process "$APP_NAME"
    ;;
  --build-only)
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

require_signing_identity

swift build -c "$CONFIGURATION"
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
EXECUTABLE="$BIN_DIR/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$EXECUTABLE" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"
cp "$ROOT_DIR/Resources/App_Icon.icns" "$RESOURCES_DIR/App_Icon.icns"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key>
  <string>App_Icon</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

/usr/bin/codesign \
  --force \
  --keychain "$SIGNING_KEYCHAIN" \
  --sign "$SIGNING_IDENTITY" \
  --identifier "$BUNDLE_ID" \
  "$APP_BUNDLE" >/dev/null

/usr/bin/codesign --verify --strict --verbose=2 "$APP_BUNDLE" >/dev/null

if [[ "$MODE" == "--build-only" ]]; then
  echo "Built $APP_BUNDLE"
  exit 0
fi

if [[ "$MODE" == "--install" ]]; then
  rm -rf "$INSTALLED_APP_BUNDLE"
  /usr/bin/ditto "$APP_BUNDLE" "$INSTALLED_APP_BUNDLE"
  /usr/bin/codesign --verify --strict --verbose=2 "$INSTALLED_APP_BUNDLE" >/dev/null
  echo "Installed $INSTALLED_APP_BUNDLE"
  /usr/bin/open -n "$INSTALLED_APP_BUNDLE"
  exit 0
fi

/usr/bin/open -n "$APP_BUNDLE"

if [[ "$MODE" == "--verify" ]]; then
  sleep 2
  pgrep -x "$APP_NAME" >/dev/null
  echo "$APP_NAME is running"
elif [[ "$MODE" == "--logs" ]]; then
  /usr/bin/log stream --info --style compact --predicate "process == '$APP_NAME'"
elif [[ "$MODE" == "--telemetry" ]]; then
  /usr/bin/log stream --debug --info --style compact --predicate "subsystem == '$BUNDLE_ID'"
fi
