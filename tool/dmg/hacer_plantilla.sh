#!/usr/bin/env bash
#
# Genera la plantilla de disposición de la ventana del instalador.
#
# **Esto se corre a mano y casi nunca**, no en cada release. Lo que produce es un
# `.DS_Store` que se versiona, y que `tool/dmg.sh` copia dentro del DMG.
#
# Va aparte por un motivo concreto: colocar iconos y poner un fondo **solo lo sabe
# hacer el Finder**, por AppleScript. Y en un runner de GitHub no hay Finder ni
# sesión gráfica, así que un release que dependiera de esto fallaría o —peor—
# saldría sin disposición sin decir nada. Con la plantilla versionada, el release
# solo copia un archivo.
#
#   tool/dmg/hacer_plantilla.sh <ruta a Nexus.app>
#
# Requiere permiso de automatización para controlar el Finder: la primera vez
# macOS lo pregunta. Si se deniega, esto falla y hay que darlo en Ajustes del
# sistema › Privacidad › Automatización.
set -euo pipefail

APP="${1:?falta la ruta del .app}"
AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# El nombre del volumen es **fijo y sin versión**, y de eso depende todo esto: el
# fondo se guarda en el `.DS_Store` como una referencia a
# `/Volumes/<nombre>/.background/…`, así que con «Nexus 0.0.6» la plantilla solo
# valdría para la 0.0.6. Con «Nexus» vale siempre. (La Oficina titula su volumen
# «La Oficina» por lo mismo.)
VOLUMEN="Nexus"
ALTO=420
ANCHO=660

MONTAJE="$(mktemp -d)"
TMPDMG="$(mktemp -u).dmg"
trap 'hdiutil detach "/Volumes/$VOLUMEN" >/dev/null 2>&1 || true; rm -rf "$MONTAJE" "$TMPDMG"' EXIT

echo "▸ armando un DMG de escritura para colocar las cosas"
ditto "$APP" "$MONTAJE/$(basename "$APP")"
ln -s /Applications "$MONTAJE/Aplicaciones"
mkdir -p "$MONTAJE/.background"
cp "$AQUI/fondo.tiff" "$MONTAJE/.background/fondo.tiff"

hdiutil detach "/Volumes/$VOLUMEN" >/dev/null 2>&1 || true
hdiutil create -volname "$VOLUMEN" -srcfolder "$MONTAJE" -ov \
  -format UDRW -fs HFS+ "$TMPDMG" >/dev/null
hdiutil attach "$TMPDMG" -nobrowse >/dev/null

echo "▸ pidiéndole al Finder que las coloque"
osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOLUMEN"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    -- El alto lleva 23 px de más: \`bounds\` incluye la barra de título, así que sin
    -- eso el fondo saldría recortado por abajo justo donde va la flecha.
    set the bounds of container window to {200, 120, 200 + $ANCHO, 120 + $ALTO + 23}
    set opciones to the icon view options of container window
    set arrangement of opciones to not arranged
    set icon size of opciones to 96
    set text size of opciones to 12
    set background picture of opciones to file ".background:fondo.tiff"
    set position of item "$(basename "$APP")" of container window to {165, 190}
    set position of item "Aplicaciones" of container window to {495, 190}
    close
    open
    update without registering applications
    delay 2
  end tell
end tell
APPLESCRIPT

# `sync` y una espera: el Finder escribe el .DS_Store cuando le parece, y sin esto
# se copia el de antes de colocar nada.
sync
sleep 2

cp "/Volumes/$VOLUMEN/.DS_Store" "$AQUI/DS_Store"
hdiutil detach "/Volumes/$VOLUMEN" >/dev/null

echo "✓ plantilla guardada en tool/dmg/DS_Store ($(stat -f%z "$AQUI/DS_Store") bytes)"
echo "  Commitéala: es lo que hace que el instalador se vea igual en cada release."
