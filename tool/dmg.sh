#!/usr/bin/env bash
#
# Arma el DMG de instalación: la app y un atajo a Aplicaciones al lado.
#
# No es cosmético. Un `.zip` invita a abrir la app **desde Descargas**, y una app
# en cuarentena que se abre sin moverla la ejecuta macOS desde una ruta aleatoria
# de solo lectura —traslocación de Gatekeeper—: ahí la app no sabe dónde vive y
# cualquier actualizador que reemplace el `.app` escribiría sobre una copia
# fantasma. El DMG con su atajo empuja a arrastrarla, y al moverla con el Finder
# eso deja de pasar.
#
#   tool/dmg.sh <ruta a Nexus.app> <salida.dmg> <versión>
#
# Con `hdiutil`, que viene en el sistema, y no con un paquete de terceros: es una
# dependencia menos en el camino que produce lo que la gente descarga.
set -euo pipefail

APP="${1:?falta la ruta del .app}"
SALIDA="${2:?falta la ruta del .dmg}"
VERSION="${3:?falta la versión}"

[[ -d "$APP" ]] || { echo "✗ no existe $APP" >&2; exit 1; }

MONTAJE="$(mktemp -d)"
trap 'rm -rf "$MONTAJE"' EXIT

# `ditto` para copiar la app: `cp -R` no conserva los enlaces de los frameworks y
# rompe la firma. Es la misma razón por la que el zip se hace con ditto.
ditto "$APP" "$MONTAJE/$(basename "$APP")"
ln -s /Applications "$MONTAJE/Aplicaciones"

rm -f "$SALIDA"
hdiutil create \
  -volname "Nexus $VERSION" \
  -srcfolder "$MONTAJE" \
  -ov -format UDZO \
  "$SALIDA" >/dev/null

echo "$SALIDA"
