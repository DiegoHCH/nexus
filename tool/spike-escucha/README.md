# Spike: escuchar un nombre

Código de las medidas de [`docs/SPIKE-ESCUCHA.md`](../../docs/SPIKE-ESCUCHA.md).
**No forma parte de la app** y no se compila con ella: son tres programas sueltos
de Swift para contestar si la escucha continua era viable.

| | |
|---|---|
| `disponibilidad.swift` | qué idiomas reconocen en local. **No necesita micrófono** |
| `escucha.swift` | escucha continua: cortes de sesión y qué transcribe |
| `nombres.swift` | compara varios candidatos a palabra de activación |
| `medida-*.txt` | los registros de las corridas reales, del 1-9-2026 |

Los registros son `.txt` y no `.log` **porque `.gitignore` se come los `.log`** —
se quedaron fuera del primer commit sin que nada avisara, y el mensaje de ese
commit decía que se guardaban a propósito. Un archivo que dice ser la prueba y no
está es peor que no tenerlo.

Los registros se guardan a propósito: **son la medida**, y sin ellos el documento
sería una opinión. Ahí está el `«Nexos nexos nexos»` reescribiendo el pasado y el
`«bestia»` de tres de tres.

## Correrlos

`disponibilidad` va directo. Los otros dos necesitan micrófono y reconocimiento de
voz, y **un binario suelto no puede pedirlos**: muere con SIGABRT y el informe de
fallo dice que falta `NSSpeechRecognitionUsageDescription`. Hace falta un bundle:

```sh
swiftc -o escucha escucha.swift
mkdir -p Spike.app/Contents/MacOS && cp escucha Spike.app/Contents/MacOS/
# Info.plist con CFBundleExecutable, NSMicrophoneUsageDescription y
# NSSpeechRecognitionUsageDescription — ver el documento
codesign --force --sign - Spike.app
open Spike.app --args es-MX hestia 90
```

Y con `open` no hay salida estándar que leer: `escucha.swift` escribe a un archivo
por eso.
