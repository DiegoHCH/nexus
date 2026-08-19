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
# Por defecto se notariza **lo publicado**: reconstruir daría un binario
# distinto —fechas, rutas— y se estaría sellando algo que no es lo que la
# gente descargó.
#
# Pero a veces lo publicado **no se puede notarizar**, y entonces no hay
# elección. Pasó con la 0.0.1: se firmó sin sello de tiempo seguro, Apple la
# rechazó, y el arreglo está en cómo se firma — así que toca reconstruir y
# sustituir el archivo. `--reconstruir` hace eso, diciéndolo.
if [[ "${2:-}" == "--reconstruir" ]]; then
  echo "▸ reconstruyendo en Release (lo publicado no era notarizable)"
  flutter build macos --release >/dev/null
  ZIP="$TRABAJO/Nexus-$VERSION.zip"
  ditto -c -k --sequesterRsrc --keepParent \
    "build/macos/Build/Products/Release/Nexus.app" "$ZIP"
else
  echo "▸ bajando lo que está publicado en v$VERSION"
  gh release download "v$VERSION" --pattern "Nexus-$VERSION.zip" --dir "$TRABAJO"
  ZIP="$TRABAJO/Nexus-$VERSION.zip"
fi

echo "▸ desempaquetando"
ditto -x -k "$ZIP" "$TRABAJO/salida"
APP="$TRABAJO/salida/Nexus.app"
[[ -d "$APP" ]] || { echo "✗ no venía un Nexus.app dentro" >&2; exit 1; }

echo "▸ comprobando la firma antes de enviarlo"
codesign --verify --deep --strict "$APP"
# Se captura y **después** se busca, en vez de encadenar con una tubería.
#
# `codesign … | grep -q` con `pipefail` es un falso negativo garantizado: grep
# encuentra la línea y sale de inmediato, codesign recibe SIGPIPE y devuelve
# error, y pipefail hace fallar la tubería **aunque la coincidencia fuera
# correcta**. Pasó aquí: el paquete sí estaba endurecido y el guion dijo que no.
DATOS_FIRMA="$(codesign -dvvv "$APP" 2>&1 || true)"
case "$DATOS_FIRMA" in
  *'flags=0x10000(runtime)'*) ;;
  *)
    echo "✗ no lleva hardened runtime: Apple lo rechazará" >&2
    exit 1
    ;;
esac
# Y el sello de tiempo **seguro**, que no es `Signed Time`: ese es local y no
# cuenta. Es exactamente por lo que se rechazó el primer envío de la 0.0.1.
case "$DATOS_FIRMA" in
  *'Timestamp='*) ;;
  *)
    echo "✗ la firma no lleva sello de tiempo seguro (solo «Signed Time»)." >&2
    echo "  Se arregla firmando con --timestamp; ver OTHER_CODE_SIGN_FLAGS." >&2
    exit 1
    ;;
esac

echo "▸ notarizando (Apple tarda entre uno y unos minutos)"
# **Se mira el veredicto, no el código de salida.**
#
# `notarytool submit --wait` devuelve 0 cuando termina de esperar, aunque
# Apple haya dicho `Invalid`. Pasó: el envío se rechazó por falta de sello de
# tiempo y este guion siguió adelante a sellar un ticket que no existía, así
# que el error que se leyó fue «Record not found» del sellado — un síntoma
# tres pasos más allá de la causa.
ENVIO="$(xcrun notarytool submit "$ZIP" --keychain-profile "$PERFIL" --wait 2>&1)"
echo "$ENVIO"
ID_ENVIO="$(printf '%s' "$ENVIO" | awk '/^  id: /{print $2; exit}')"

case "$ENVIO" in
  *'status: Accepted'*) ;;
  *)
    echo "✗ Apple no la aceptó. Lo que dijo:" >&2
    xcrun notarytool log "$ID_ENVIO" --keychain-profile "$PERFIL" 2>&1 >&2 || true
    exit 1
    ;;
esac

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
