#!/usr/bin/env bash
#
# Firmar las piezas que Sparkle trae dentro, de dentro hacia fuera.
#
# Sparkle no es solo una biblioteca: dentro del framework viaja un ejecutable
# (`Autoupdate`), una app (`Updater.app`) y dos servicios XPC. Xcode firma el
# framework pero **no lo que hay dentro de él**, así que esas cuatro piezas
# llegaban ad-hoc:
#
#     Autoupdate    flags=0x10002(adhoc,runtime)   TeamIdentifier=not set
#
# Y eso Apple lo rechaza al notarizar —«the binary is not signed with a valid
# Developer ID certificate»—. Medido aquí, antes de gastar un ciclo de release
# en descubrirlo.
#
# El orden es de dentro hacia fuera y no es negociable: firmar algo anidado
# invalida la firma de lo que lo contiene, así que si se firmara el framework
# primero, el primer XPC lo tiraría abajo.
#
# Va como fase de compilación y no en el guion de publicar a propósito: así
# **cualquier** build en Release sale notarizable, incluido uno hecho a mano
# desde Xcode. Metido en el guion de publicar, un build local parecería bueno y
# no lo sería.
set -euo pipefail

# En el CI de pruebas se compila con CODE_SIGNING_ALLOWED=NO, y ahí no hay nada
# que firmar.
[[ "${CODE_SIGNING_ALLOWED:-YES}" == "NO" ]] && exit 0

IDENTIDAD="${EXPANDED_CODE_SIGN_IDENTITY:-}"

# Ad-hoc («-») o sin identidad es el caso del día a día: `flutter run` firma así
# y funciona perfectamente en la máquina de quien desarrolla. Aquí no se toca
# nada, entre otras cosas porque `--timestamp` sobre una firma ad-hoc falla.
[[ -z "$IDENTIDAD" || "$IDENTIDAD" == "-" ]] && exit 0

MARCO="${CODESIGNING_FOLDER_PATH:?falta CODESIGNING_FOLDER_PATH}/Contents/Frameworks/Sparkle.framework"
[[ -d "$MARCO" ]] || exit 0

V="$MARCO/Versions/B"

firmar() {
  echo "  firmando $(basename "$1")"
  codesign --force --sign "$IDENTIDAD" --timestamp --options runtime "$1"
}

for servicio in "$V"/XPCServices/*.xpc; do
  [[ -e "$servicio" ]] && firmar "$servicio"
done
[[ -d "$V/Updater.app" ]] && firmar "$V/Updater.app"
[[ -f "$V/Autoupdate" ]] && firmar "$V/Autoupdate"
firmar "$MARCO"
