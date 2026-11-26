#!/bin/bash
# Buduje SumSnap.app w katalogu dist/.
# Użycie: ./build.sh            — tylko build
#         ./build.sh --install  — build + instalacja w /Applications i uruchomienie
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="SumSnap"
BUILD_DIR="dist"
APP="$BUILD_DIR/$APP_NAME.app"

echo "==> Kompilacja (release)"
swift build -c release --product "$APP_NAME"
BIN="$(swift build -c release --product "$APP_NAME" --show-bin-path)/$APP_NAME"

echo "==> Składanie pakietu $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Podpis ad-hoc zmienia się przy każdej przebudowie, przez co macOS unieważnia
# zgodę na Nagrywanie ekranu. Stała tożsamość rozwiązuje to raz na zawsze.
IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
  | grep -oE '"Apple Development: [^"]+"' | head -1 | tr -d '"')"

if [[ -n "$IDENTITY" ]]; then
  echo "==> Podpisywanie: $IDENTITY"
  codesign --force --sign "$IDENTITY" --timestamp=none "$APP"
else
  echo "==> Podpisywanie (ad-hoc — zgoda na Nagrywanie ekranu wygaśnie przy kolejnej przebudowie)"
  codesign --force --sign - --timestamp=none "$APP"
fi

if [[ "${1:-}" == "--install" ]]; then
  echo "==> Instalacja w /Applications"
  pkill -x "$APP_NAME" 2>/dev/null || true
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP" "/Applications/$APP_NAME.app"
  open "/Applications/$APP_NAME.app"
  echo "Gotowe — ikona ∑ jest w pasku menu."
else
  echo "Gotowe: $APP"
  echo "Instalacja: ./build.sh --install"
fi
