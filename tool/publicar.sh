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
#   tool/publicar.sh 0.1.0 --sin-notarizar   (no recomendado, ver abajo)
#
# Notariza por defecto. El primer paso lo tienes que dar tú una vez, porque pide
# credenciales de tu cuenta de Apple y esas **no viven en el repo**:
#
#   xcrun notarytool store-credentials "nexus-notarizacion" \
#     --apple-id TU_CORREO --team-id Y9H7TRB5L7 --password CONTRASEÑA_DE_APP
#
# La contraseña es una «contraseña específica de aplicación», que se crea en
# appleid.apple.com; no es la de tu cuenta. Queda en el llavero del login, y este
# guion solo la nombra por el perfil.
#
set -euo pipefail

PERFIL="nexus-notarizacion"
NOTARIZAR=1
[[ "${2:-}" == "--sin-notarizar" ]] && NOTARIZAR=0

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

# Y lo que se publica tiene que estar **en master**.
#
# Gitflow: master es producción y de ahí salen las releases taggeadas; develop es
# integración. Este guion no lo comprobaba y estuvo a punto de publicar desde una
# rama de trabajo — la etiqueta habría apuntado a un commit que ni estaba en la
# rama principal, así que «la versión 0.0.1» no habría querido decir nada.
git fetch -q origin master
if ! git merge-base --is-ancestor HEAD origin/master; then
  cat >&2 <<GITFLOW
✗ este commit no está en master, y las releases salen de master.

  El camino es: rama release/<versión> desde develop → PR a master → mezclar,
  y entonces publicar desde master. Ahora mismo estás en:

    $(git rev-parse --abbrev-ref HEAD)  ($(git rev-parse --short HEAD))
GITFLOW
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

if [[ "$NOTARIZAR" == "1" ]]; then
  if ! xcrun notarytool history --keychain-profile "$PERFIL" >/dev/null 2>&1; then
    cat >&2 <<AVISO
✗ no hay perfil de notarización guardado con el nombre «${PERFIL}».

  Se crea una sola vez, y con tus credenciales —por eso no lo hace este guion:

    xcrun notarytool store-credentials "$PERFIL" \\
      --apple-id TU_CORREO --team-id Y9H7TRB5L7 --password CONTRASEÑA_DE_APP

  La contraseña es una «específica de aplicación» de appleid.apple.com, no la de
  tu cuenta. Si de verdad quieres publicar sin notarizar, pasa --sin-notarizar y
  quien la baje tendrá que abrirla con clic derecho la primera vez.
AVISO
    exit 1
  fi

  echo "▸ notarizando (Apple tarda entre uno y unos minutos)"
  xcrun notarytool submit "$SALIDA" --keychain-profile "$PERFIL" --wait

  # El sello va en la **app**, no en el zip: así el paquete lleva el ticket
  # dentro y macOS no necesita preguntar por red para abrirla.
  echo "▸ sellando el ticket en la app"
  xcrun stapler staple "$APP"

  # Y se vuelve a empaquetar, porque el zip de antes se hizo sin el sello.
  echo "▸ reempaquetando con el ticket dentro"
  rm -f "$SALIDA"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$SALIDA"

  echo "▸ comprobando lo que verá quien la baje"
  spctl -a -vv -t install "$APP"
fi

# El DMG, con la app ya sellada dentro. Ver `tool/dmg.sh` para el porqué del
# formato; aquí solo importa el orden: después de sellar, nunca antes.
DMG="build/Nexus-$VERSION.dmg"
echo "▸ armando el DMG de instalación"
tool/dmg.sh "$APP" "$DMG"

IDENTIDAD="$(security find-identity -v -p codesigning \
  | awk -F'"' '/Developer ID Application/{print $2; exit}')"
codesign --sign "$IDENTIDAD" --timestamp --force "$DMG"
codesign --verify --strict "$DMG"

if [[ "$NOTARIZAR" == "1" ]]; then
  echo "▸ notarizando el DMG (un DMG sin notarizar avisa al montarlo, aunque la app esté bien)"
  set +e
  ENVIO="$(xcrun notarytool submit "$DMG" --keychain-profile "$PERFIL" --wait 2>&1)"
  set -e
  echo "$ENVIO"
  case "$ENVIO" in
    *'status: Accepted'*) ;;
    *) echo "✗ Apple no aceptó el DMG" >&2; exit 1 ;;
  esac
  xcrun stapler staple "$DMG"
fi

# El feed que lee la app instalada. Sin esto el actualizador no encuentra nada
# nunca. Aquí la clave privada sale del **llavero** —`sign_update` la busca sola—
# y no de un secreto: en esta máquina ya está, y así no hay que pasarla por ningún
# sitio.
echo "▸ armando el appcast"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
# Su salida trae **la firma y el tamaño**: `sparkle:edSignature="…" length="…"`.
# Escribir además nuestro propio `length` redefinía el atributo y el appcast
# no parseaba. Comprobado con xmllint antes de publicar nada.
FIRMA="$(macos/Pods/Sparkle/bin/sign_update "$SALIDA")"
[[ "$FIRMA" == *edSignature* ]] || {
  echo "✗ sign_update no devolvió una firma." >&2
  echo "  ¿existe la clave? Se crea una vez con:  macos/Pods/Sparkle/bin/generate_keys" >&2
  exit 1
}

ANTERIOR="$(git describe --tags --abbrev=0 "v$VERSION^" 2>/dev/null || true)"
if [[ -n "$ANTERIOR" ]]; then
  NOTAS="$(git log --no-merges --pretty='- %s' "$ANTERIOR..HEAD")"
else
  NOTAS="- first published version"
fi

APPCAST="build/appcast.xml"
{
  echo '<?xml version="1.0" encoding="utf-8"?>'
  echo '<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">'
  echo '  <channel>'
  echo '    <title>Nexus</title>'
  echo '    <item>'
  echo "      <title>$VERSION</title>"
  echo "      <pubDate>$(date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>"
  echo '      <sparkle:minimumSystemVersion>12.0</sparkle:minimumSystemVersion>'
  echo '      <description><![CDATA['
  echo "$NOTAS"
  echo '      ]]></description>'
  echo "      <enclosure url=\"https://github.com/DiegoHCH/nexus/releases/download/v$VERSION/Nexus-$VERSION.zip\""
  echo "                 sparkle:version=\"$BUILD\""
  echo "                 sparkle:shortVersionString=\"$VERSION\""
  echo '                 type="application/octet-stream"'
  echo "                 $FIRMA />"
  echo '    </item>'
  echo '  </channel>'
  echo '</rss>'
} > "$APPCAST"
xmllint --noout "$APPCAST" || { echo "✗ el appcast no es XML válido" >&2; exit 1; }

echo "▸ publicando la release v$VERSION"
gh release create "v$VERSION" "$DMG" "$SALIDA" "$APPCAST" \
  --title "Nexus $VERSION" \
  --notes "$(cat <<NOTAS
**Instalación**: abre el \`.dmg\` y **arrastra Nexus a Aplicaciones**.

Ese arrastre importa más de lo que parece: una app abierta desde Descargas la
ejecuta macOS desde una copia de solo lectura, y desde ahí **no puede
actualizarse sola**. En Aplicaciones sí.

(El \`.zip\` está para las actualizaciones automáticas; para instalar, el DMG.)

$(if [[ "$NOTARIZAR" == "1" ]]; then
  echo "**Firmada y notarizada por Apple**, así que se abre con doble clic como cualquier otra app."
else
  echo "**Está firmada, no notarizada.** macOS dirá «no se pudo verificar»: la primera vez se abre con **clic derecho › Abrir**."
fi)

**Qué necesita para funcionar** — lo comprueba la propia app al arrancar y te lo
dice si falta:

- **Claude Code** instalado y con sesión: es quien hace el trabajo.
- Una **llave de Gemini** para la voz. Sin ella todo lo demás funciona escribiendo.
- El **micrófono**, solo para hablarle.

Dentro hay un tour la primera vez y una guía en **Ajustes › Ayuda**.
NOTAS
)"

echo "✓ publicada: $(gh release view "v$VERSION" --json url --jq .url)"
if [[ "$NOTARIZAR" == "0" ]]; then
  echo
  echo "Publicada SIN notarizar: quien la baje verá «no se pudo verificar» y"
  echo "tendrá que abrirla con clic derecho la primera vez."
fi
