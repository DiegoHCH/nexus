#!/usr/bin/env bash
#
# Arma el DMG de instalación: la app, un atajo a Aplicaciones, y la ventana ya
# puesta —fondo, tamaño y posiciones— con el icono del volumen.
#
# El formato no es cosmético. Un `.zip` invita a abrir la app **desde Descargas**,
# y una app en cuarentena que se abre sin moverla la ejecuta macOS desde una ruta
# aleatoria de solo lectura —traslocación de Gatekeeper—: ahí la app no sabe dónde
# vive y **no puede actualizarse a sí misma**. El DMG con su atajo empuja a
# arrastrarla, y al moverla con el Finder eso deja de pasar.
#
#   tool/dmg.sh <ruta a Nexus.app> <salida.dmg>
#
# La ventana **no la coloca este guion**: copia el `.DS_Store` que hay versionado
# en `tool/dmg/`. Colocar iconos y poner un fondo solo lo sabe hacer el Finder por
# AppleScript, y en un runner de GitHub no hay Finder ni sesión gráfica; un release
# que dependiera de eso fallaría, o —peor— saldría sin disposición sin avisar. La
# plantilla se rehace a mano con `tool/dmg/hacer_plantilla.sh` cuando cambie el
# diseño, y ese es el único paso que necesita una pantalla.
set -euo pipefail

APP="${1:?falta la ruta del .app}"
SALIDA="${2:?falta la ruta del .dmg}"
AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/dmg"

[[ -d "$APP" ]] || { echo "✗ no existe $APP" >&2; exit 1; }
for pieza in fondo.tiff DS_Store; do
  [[ -f "$AQUI/$pieza" ]] || { echo "✗ falta tool/dmg/$pieza" >&2; exit 1; }
done

# El nombre del volumen es **fijo y sin versión**, y de eso depende la plantilla:
# el fondo se guarda en el `.DS_Store` como una referencia a
# `/Volumes/<nombre>/.background/…`, así que con «Nexus 0.0.6» solo valdría para esa
# versión. Con «Nexus» vale siempre. La Oficina titula el suyo «La Oficina» por lo
# mismo, y por eso su ventana se ve igual en cada release.
VOLUMEN="Nexus"

MONTAJE="$(mktemp -d)"
RW="$(mktemp -u).dmg"

# Desmontar con reintentos, y no de un tiro.
#
# Falla con «Resource busy» más a menudo de lo que parece: el Finder mantiene la
# ventana abierta, y Spotlight indexa el volumen recién montado justo después de
# escribir en él. La primera versión de esto se cayó ahí —con todo el contenido ya
# puesto— y se quedó sin convertir, así que **no había DMG y tampoco un error
# claro**. El `-force` va al final y no al principio: forzar sin esperar deja el
# volumen a medio escribir.
desmontar() {
  local intento
  for intento in 1 2 3 4 5; do
    hdiutil detach "/Volumes/$VOLUMEN" >/dev/null 2>&1 && return 0
    sleep 2
  done
  hdiutil detach "/Volumes/$VOLUMEN" -force >/dev/null 2>&1 || true
}

trap 'desmontar; rm -rf "$MONTAJE" "$RW"' EXIT

# `ditto` para copiar la app: `cp -R` no conserva los enlaces de los frameworks y
# rompe la firma. Es la misma razón por la que el zip se hace con ditto.
ditto "$APP" "$MONTAJE/$(basename "$APP")"
ln -s /Applications "$MONTAJE/Aplicaciones"
mkdir -p "$MONTAJE/.background"
cp "$AQUI/fondo.tiff" "$MONTAJE/.background/fondo.tiff"
# El icono del volumen se construye aquí desde el `appiconset` de la app en vez de
# guardarse hecho: así no hay dos iconos que puedan separarse, y el día que el de
# la app cambie este cambia con él. `iconutil` viene con las herramientas de
# Xcode, que en el camino de release ya hacen falta para compilar.
ICONSET="$MONTAJE/../Nexus.iconset"
mkdir -p "$ICONSET"
A="$(cd "$AQUI/../.." && pwd)/macos/Runner/Assets.xcassets/AppIcon.appiconset"
for par in 16:16x16 32:16x16@2x 32:32x32 64:32x32@2x 128:128x128 256:128x128@2x \
           256:256x256 512:256x256@2x 512:512x512 1024:512x512@2x; do
  origen="${par%%:*}"; destino="${par##*:}"
  [[ -f "$A/app_icon_$origen.png" ]] && cp "$A/app_icon_$origen.png" "$ICONSET/icon_$destino.png"
done
iconutil -c icns "$ICONSET" -o "$MONTAJE/.VolumeIcon.icns"
rm -rf "$ICONSET"

# De escritura primero y comprimido al final: la marca de «tengo icono propio» se
# pone sobre el volumen **montado**, y en un DMG de solo lectura no se puede
# escribir nada.
desmontar
hdiutil create -volname "$VOLUMEN" -srcfolder "$MONTAJE" -ov \
  -format UDRW -fs HFS+ "$RW" >/dev/null
hdiutil attach "$RW" -nobrowse >/dev/null

# La disposición, tal como se guardó. Va después de montar y no en la carpeta de
# origen porque `hdiutil` regenera el suyo al crear el volumen.
cp "$AQUI/DS_Store" "/Volumes/$VOLUMEN/.DS_Store"

# Y la marca que hace que el Finder use `.VolumeIcon.icns` en vez del icono
# genérico de imagen de disco. Sin esto el archivo está ahí y no se usa: es un
# atributo del volumen, no la presencia del icono.
SetFile -a C "/Volumes/$VOLUMEN"

sync
desmontar

rm -f "$SALIDA"
hdiutil convert "$RW" -format UDZO -ov -o "$SALIDA" >/dev/null

echo "$SALIDA"
