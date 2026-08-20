#!/bin/bash
# Los iconos de Android e iOS, sacados del mismo arte que el del Mac.
#
# Existe porque los tres sistemas quieren cosas distintas del mismo dibujo, y
# hacerlo a mano deja iconos que nadie sabe regenerar:
#
# · **iOS los quiere opacos.** El arte del Mac lleva alfa —esquinas transparentes,
#   que es su convención— y en iOS eso se pinta blanco o negro y queda un cuadrado
#   con muescas. Aquí se aplana sobre el vacío de la app.
# · **iOS los quiere a sangre**: la máscara la pone el sistema, así que el margen
#   propio del arte se suma al del sistema y deja el orbe pequeño. Al 110 % ese
#   margen se sale del lienzo. Se come 51 px de 1024 por lado y el margen del arte
#   son 72, así que no toca el orbe.
# · **Android 8+ recorta con la máscara del lanzador.** Sin capa adaptativa mete el
#   icono legado dentro de un círculo blanco: un sello pequeño sobre un fondo que no
#   es el nuestro. El frente va al 80 %, que es lo que llena la ventana visible
#   —el 66,7 % central— después del recorte.
#
# Y se compone con Core Graphics y no con `NSImage.draw`: en un proceso de línea de
# comandos sin app de AppKit detrás, ese dibujo **no pinta nada y no avisa**. La
# primera versión de esto generó diez iconos negros sin un solo error.
set -euo pipefail
cd "$(dirname "$0")/.."

ARTE=macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png
FONDO=04070D
BIN=$(mktemp -d)/componer
trap 'rm -rf "$(dirname "$BIN")"' EXIT
swiftc -O -o "$BIN" tool/componer_icono.swift

# ── iOS: cada tamaño que pida su catálogo ─────────────────────────────
python3 - "$BIN" "$ARTE" "$FONDO" <<'PY'
import json, os, subprocess, sys
binario, arte, fondo = sys.argv[1:4]
d = 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
for img in json.load(open(f'{d}/Contents.json'))['images']:
    if 'filename' not in img: continue
    px = round(float(img['size'].split('x')[0]) * int(img.get('scale', '1x')[0]))
    subprocess.run([binario, arte, os.path.join(d, img['filename']),
                    str(px), '1.10', fondo], check=True)
print('iOS: iconos regenerados')
PY

# ── Android: adaptativo (frente al 80 %) y legado a sangre ────────────
for t in "mdpi 108 48" "hdpi 162 72" "xhdpi 216 96" "xxhdpi 324 144" "xxxhdpi 432 192"; do
  read -r dpi frente legado <<< "$t"
  "$BIN" "$ARTE" "android/app/src/main/res/mipmap-$dpi/ic_launcher_foreground.png" "$frente" 0.80 "$FONDO"
  "$BIN" "$ARTE" "android/app/src/main/res/mipmap-$dpi/ic_launcher.png"            "$legado" 1.0  "$FONDO"
done
echo "Android: iconos regenerados"
