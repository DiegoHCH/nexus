#!/usr/bin/env bash
#
# Publica una versión de Nexus.
#
# Corre **en este Mac y no en CI**, y no es pereza: la app se firma con el
# Developer ID que solo existe en este llavero. Un runner de GitHub no lo tiene
# —lo comprobamos: el primer CI murió justo ahí— así que una release construida
# en CI saldría sin firmar, que es peor que sin notarizar.
#
#   tool/publicar.sh 0.1.0
#
set -euo pipefail

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "uso: tool/publicar.sh <versión>   (ej. 0.1.0)" >&2
  exit 1
fi

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$RAIZ"

# La versión del `pubspec` manda: si no coinciden, el actualizador compararía
# contra una etiqueta que no corresponde a lo que hay dentro del paquete.
EN_PUBSPEC="$(grep '^version:' pubspec.yaml | sed 's/version: *//; s/+.*//')"
if [[ "$EN_PUBSPEC" != "$VERSION" ]]; then
  echo "✗ pubspec.yaml dice $EN_PUBSPEC y estás publicando $VERSION" >&2
  echo "  cambia el pubspec primero: la versión de dentro es la que vale." >&2
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "✗ hay cambios sin commitear: una release tiene que ser reproducible" >&2
  exit 1
fi

echo "▸ compilando en Release"
flutter build macos --release

APP="build/macos/Build/Products/Release/Nexus.app"
[[ -d "$APP" ]] || { echo "✗ no se construyó $APP" >&2; exit 1; }

echo "▸ comprobando la firma"
codesign --verify --deep --strict "$APP"
FIRMA="$(codesign -dv "$APP" 2>&1 | grep -c 'TeamIdentifier=Y9H7TRB5L7' || true)"
[[ "$FIRMA" == "1" ]] || { echo "✗ no está firmada con el Developer ID esperado" >&2; exit 1; }

# `ditto` y no `zip`: preserva los enlaces simbólicos de los frameworks y los
# metadatos, y con `zip` a secas la firma se rompe al descomprimir.
SALIDA="build/Nexus-$VERSION.zip"
echo "▸ empaquetando en $SALIDA"
rm -f "$SALIDA"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$SALIDA"

echo "▸ publicando la release v$VERSION"
gh release create "v$VERSION" "$SALIDA" \
  --title "Nexus $VERSION" \
  --notes "$(cat <<'NOTAS'
Primera versión publicable.

**Está firmada, no notarizada.** macOS dirá «no se pudo verificar»: la primera
vez se abre con **clic derecho › Abrir**. Es lo que ya anticipaba la ficha `le9`,
y se arregla cuando se configure `notarytool`.

**Qué necesita para funcionar** — lo comprueba la propia app al arrancar y te lo
dice si falta:

- **Claude Code** instalado y con sesión: es quien hace el trabajo.
- Una **llave de Gemini** para la voz. Sin ella todo lo demás funciona escribiendo.
- El **micrófono**, solo para hablarle.

Dentro hay un tour la primera vez y una guía en **Ajustes › Ayuda**.
NOTAS
)"

echo "✓ publicada: $(gh release view "v$VERSION" --json url --jq .url)"
echo
echo "Sin notarizar, quien la baje verá «no se pudo verificar» y tendrá que"
echo "abrirla con clic derecho la primera vez. Para arreglarlo hace falta"
echo "correr notarytool con tu cuenta de Apple — no está automatizado aquí a"
echo "propósito: pide credenciales que no deben vivir en un script del repo."
