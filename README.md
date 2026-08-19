# Nexus

Un asistente de voz de escritorio para macOS que **ejecuta trabajo real en tu Mac**.
Le hablas, y hace: lee tus repos, escribe archivos, corre comandos.

No es un chat con voz. La voz la pone [Gemini Live](https://ai.google.dev/gemini-api/docs/live)
—audio a audio, con interrupción y detección de habla— y **las manos las pone
Claude Code** (`claude -p`, sin interfaz), que es quien toca de verdad tus
archivos. La cara es un orbe de malla sobre el vacío: un HUD, no una ventana de
mensajería.

## Instalar

Baja el `.dmg` de la [última versión](https://github.com/DiegoHCH/nexus/releases/latest),
ábrelo y **arrastra Nexus a Aplicaciones**.

Ese arrastre no es una formalidad. Una app en cuarentena que se abre **sin
moverla** —doble clic en Descargas— la ejecuta macOS desde una copia de solo
lectura con ruta aleatoria, y desde ahí **no puede actualizarse a sí misma**. En
Aplicaciones sí.

Está firmada con Developer ID y notarizada por Apple, así que se abre con doble
clic: sin clic derecho y sin avisos.

## Qué necesita para funcionar

La propia app lo comprueba al arrancar y te dice qué falta:

| | Para qué | Sin ello |
|---|---|---|
| **Claude Code** instalado y con sesión | es quien hace el trabajo | te contesta pero no puede hacer nada |
| Una **llave de Gemini** | la voz | funciona igual escribiendo |
| El **micrófono** | hablarle | funciona igual escribiendo |

Dentro hay un tour la primera vez y una guía completa en **Ajustes › Ayuda**.

## Cómo se usa

- **⌥Espacio** abre la sesión de voz sin traer la ventana al frente.
- Se **emparejan carpetas**: cada una con su modalidad —voz o solo texto— y su
  permiso de escritura. Sostiene hasta tres conversaciones a la vez, una por
  carpeta, y la voz va con la que tenga el foco.
- El icono de la **barra de menús** dice en qué anda sin que tengas que ir a
  buscar la ventana, y avisa cuando un encargo termina.
- Lo que Claude escribe queda en **Documentos**, con su lista y su visor.

### Lo que sale de tu Mac y lo que no

Una carpeta en modo **solo texto** no abre sesión de voz: nada de esa carpeta
viaja a Gemini, ni siquiera el audio. Es una negativa, no una preferencia — si
intentas hablar con una carpeta así, la sesión se rechaza.

## Se actualiza sola

El motor es [Sparkle](https://sparkle-project.org/); la interfaz es de Nexus. Al
haber una versión nueva sale una tarjeta arriba a la derecha —no una modal en
medio: una versión nueva es una noticia, no una pregunta— y desde ahí se descarga
e instala. **Lo que nunca hace es reiniciarse por su cuenta**: eso mataría un
`claude -p` a media escritura, así que el último paso lo confirmas tú.

Si lo dejas para luego, queda un punto rojo en el icono de la barra y en el menú
del compositor. «Ahora no» no es «nunca».

## Desarrollo

Flutter **3.47.0** y macOS **12** como mínimo.

```bash
flutter pub get
flutter run -d macos

flutter analyze
flutter test                       # las pruebas de Dart

# y las nativas, que son de verdad y no un adorno:
xcodebuild test -workspace macos/Runner.xcworkspace -scheme Runner \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

### Cómo está organizado

Clean Architecture **feature-first**: cada `lib/features/<lo que sea>/` con su
`domain`, `data` y `presentation`. Las capas de fuera dependen de las de dentro y
nunca al revés. El estado lo lleva Riverpod.

Lo que macOS no presta a Flutter vive en `macos/Runner/` como canales propios, uno
por asunto: el motor de audio —uno solo para escuchar y hablar, que es lo que
permite cancelar el eco—, los archivos, las miniaturas, el visor de documentos, la
energía, la apariencia, la barra de estado, los avisos y el actualizador.

Los comentarios del código explican **por qué** algo está así, no qué hace. Muchos
llevan la medición que llevó a esa decisión.

### Sacar una versión

Gitflow: `develop` integra, `master` es producción.

```
develop → release/x.y.z (subir el pubspec) → PR a master
```

**Y ahí se acaba el trabajo a mano.** Mezclar en `master` dispara el workflow, que
lee la versión del `pubspec`, se etiqueta, compila, firma, notariza, publica el
`.dmg` + el `.zip` + el `appcast.xml`, y devuelve `master` a `develop`.

El número de build importa tanto como la versión: `sparkle:version` es el
`CFBundleVersion`, y un build que no crece es una actualización que las apps
instaladas se niegan a ver.
