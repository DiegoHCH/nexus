#!/usr/bin/env bash
#
# Notariza una release **ya publicada** y sustituye su archivo.
#
# Existe porque notarizar no obliga a sacar una versión nueva: el sello va sobre
# el mismo binario. La 0.0.1 se publicó sin notarizar —no había credenciales— y
# esto la arregla sin inventar una 0.0.2 que no traería ningún cambio.
#
#   tool/notarizar.sh 0.0.1
#
# Pide un perfil de credenciales que **crea el dueño de la cuenta**, no este
# guion, y en su propia terminal —la contraseña no debe acabar en un registro:
#
#   xcrun notarytool store-credentials "nexus-notarizacion" \
#     --apple-id TU_CORREO --team-id Y9H7TRB5L7 --password CONTRASEÑA_DE_APP
#
set -euo pipefail

PERFIL="nexus-notarizacion"
VERSION="${1:-}"
[[ -n "$VERSION" ]] || { echo "uso: tool/notarizar.sh <versión>" >&2; exit 1; }

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$RAIZ"

if ! xcrun notarytool history --keychain-profile "$PERFIL" >/dev/null 2>&1; then
  echo "✗ no hay perfil «${PERFIL}». Créalo en tu terminal (ver cabecera)." >&2
  exit 1
fi

TRABAJO="$(mktemp -d)"
trap 'rm -rf "$TRABAJO"' EXIT

# Se baja el archivo **publicado** en vez de reconstruir.
#
# Reconstruir daría un binario distinto —fechas, rutas— y entonces se estaría
# notarizando algo que no es lo que la gente tiene descargado. Lo que se quiere
# sellar es exactamente eso.
echo "▸ bajando lo que está publicado en v$VERSION"
gh release download "v$VERSION" --pattern "Nexus-$VERSION.zip" --dir "$TRABAJO"
ZIP="$TRABAJO/Nexus-$VERSION.zip"

echo "▸ desempaquetando"
ditto -x -k "$ZIP" "$TRABAJO/salida"
APP="$TRABAJO/salida/Nexus.app"
[[ -d "$APP" ]] || { echo "✗ no venía un Nexus.app dentro" >&2; exit 1; }

echo "▸ comprobando la firma antes de enviarlo"
codesign --verify --deep --strict "$APP"
codesign -dvvv "$APP" 2>&1 | grep -q 'flags=0x10000(runtime)' || {
  echo "✗ el paquete publicado no lleva hardened runtime: Apple lo rechazará" >&2
  exit 1
}

echo "▸ notarizando (Apple tarda entre uno y unos minutos)"
xcrun notarytool submit "$ZIP" --keychain-profile "$PERFIL" --wait

echo "▸ sellando el ticket en la app"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "▸ reempaquetando con el ticket dentro"
NUEVO="$TRABAJO/Nexus-$VERSION.zip"
rm -f "$NUEVO"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$NUEVO"

echo "▸ comprobando lo que verá quien la baje"
spctl -a -vv -t install "$APP"

echo "▸ sustituyendo el archivo de la release"
gh release upload "v$VERSION" "$NUEVO" --clobber

echo "✓ v$VERSION notarizada y con el archivo sustituido"
echo "  Ya se abre con doble clic: no hace falta el clic derecho de la primera vez."
