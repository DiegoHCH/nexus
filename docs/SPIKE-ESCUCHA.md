# Spike: escuchar un nombre y despertar

**Estado: spike cerrado, función no construida.** Aquí está lo medido, lo decidido
y lo que queda por decidir, para poder retomarlo sin repetir el trabajo.

Medido el 1 de septiembre de 2026, en un MacBook Pro con macOS 26.6.2 y Swift 6.3.3.
El código está en [`tool/spike-escucha/`](../tool/spike-escucha), con los registros
de las corridas reales en `medida-escucha.txt` y `medida-nombres.txt`.

## Qué se quería

Que Nexus escuche siempre y, al oír su nombre, **conteste sin abrir conversación
todavía** — porque desde ese primer llamado se le dice en qué carpeta trabajar, o
directamente una tarea. Es un enrutador por voz antes de que exista una carpeta,
que hoy es de donde cuelga todo: la cuenta, el modelo, los permisos y el prompt.

## Lo que se midió

### Reconocer en local es viable

`SFSpeechRecognizer` con `requiresOnDeviceRecognition` funciona **sin red**, que es
la condición que hacía esto aceptable: la app promete que en modo solo texto «nada
de esa carpeta viaja a Gemini, ni siquiera el audio», y un micrófono siempre abierto
hacia Google la volvería mentira.

| | |
|---|---|
| Cortes de sesión | **0** en tres corridas de 90 s, 60 s y 90 s |
| Latencia hasta detectar | **~100 ms**, en resultado **parcial** |
| Red | ninguna |

Los 100 ms en parcial son lo que permite reaccionar al instante, como el anillo de
un Echo, en vez de esperar a que termines la frase.

### 🔴 Solo 5 de 63 idiomas reconocen en local

Y es una dependencia del sistema operativo, no nuestra:

```
con modelo local (5):  en-ID  en-PH  en-SA  en-US  es-MX
sin él (58):           es-ES  es-CO  es-419  pt-BR  fr-FR  de-DE  …
```

Son modelos que macOS descarga por idioma. **El español de España y el de Colombia
no estaban instalados**; el único español con modelo local era `es-MX`. Para
detectar un nombre da igual el acento —no hay que entender frases— pero hay que
**comprobarlo en la máquina de cada persona** y tener una respuesta para quien no
tenga ninguno. La alternativa, mandar audio a Apple, es justo lo que no queremos.

### El nombre importa, y «Nexus» es malo en español

Se compararon cinco candidatos con `contextualStrings` sesgando hacia todos a la
vez —lo que reparte el sesgo y da una medida pesimista.

Lo que oyó cuando se dijo «Nexus»: `nexos`, `nachos`, `net`, `XOX`. Y en una frase
normal —«qué hay de nuevo»— oyó **`nexos`** al final, o sea un falso positivo en
potencia. Con «Nexus» no hay ajuste que gane las dos: exacto pierde llamadas, con
holgura despierta solo.

Los otros fallaban distinto y mejor: sus errores eran **la palabra a medio formar**
—`ori`→`orión`, `nev`→`nébula`— y no otra palabra española.

### `contextualStrings` vence a la palabra que compite

«Hestia» sin sesgar se oyó **«bestia» 3 de 3 veces** — la «h» española es muda, así
que suena `estia` y el reconocedor la completa con la palabra que conoce.

Con «hestia» dentro de `contextualStrings`: **6 aciertos y cero «bestia»**. El sesgo
resuelve la colisión, y eso permite usar un nombre elegido por gusto y no por
fonética.

| candidato | aciertos | forma de fallar |
|---|---|---|
| orión | 9 | `ori` → limpio |
| patricia | 8 | un `tía` suelto antes |
| hestia | 6 | se queda en `tía` |

La muestra es de 5-6 repeticiones por nombre: **sirve para ver el patrón de fallo,
no para ordenarlos**.

## Los cuatro problemas de diseño

Todos salieron de los registros y ninguno es un muro, pero ninguno es gratis.

1. **Dispararía 19 veces.** Los parciales se **acumulan**: la transcripción crece y
   un `contains` vuelve a acertar en cada actualización. Hace falta despertar una
   vez por vez que se dice, no una por parcial.

2. **El reconocedor reescribe el pasado.** Medido: `«Nexus nexus nexus nexus nexus
   ne»` pasó a `«Nexos nexos nexos nexos nexos ne»` en 200 ms. Una transcripción
   que acertó **puede dejar de acertar**, así que confirmar el despertar con lo que
   venga después es frágil.

3. **Falsos positivos contra falsos negativos.** Comparar exacto pierde las veces
   que oye una variante; comparar con holgura despierta con palabras normales. Con
   el sesgo puesto el problema se reduce mucho, pero no desaparece.

4. **El búfer crece sin parar.** Una petición acumula hasta que se le dice que
   terminó. Para escuchar todo el día hay que reiniciarla cada cierto tiempo, y hay
   que comprobar si al reiniciar quedan **huecos sordos**.

## 🔴 El nudo de verdad: quién es dueño del micrófono

Esto es lo que decide si la función se puede construir, y no es el reconocedor.

`NexusAudioEngine` instala **un tap** en `inputNode`, y AVFAudio solo admite uno por
bus. Un segundo **mata el proceso** con una NSException que no se puede atrapar —
está documentado en el propio motor, con un incidente real detrás.

Peor: el arranque del motor hace `removeTap` antes de instalar el suyo. Así que si
el escucha tuviera su tap y empezara una conversación, **el escucha se quedaría
sordo en silencio**. Y al revés.

Dos diseños posibles:

**A · Un tap, dos consumidores.** El motor duplex sigue siendo dueño y, dentro de
Swift, el mismo búfer alimenta también al reconocedor. Nunca hay dos taps, pero el
grafo pesado —cancelación de eco, nodo de reproducción, conversores— tiene que estar
montado todo el día para oír una palabra.

**B · Traspaso de propiedad.** El escucha es dueño cuando no hay conversación, con
un grafo mínimo; al despertar suelta el tap y el duplex toma el relevo; al colgar lo
recupera. **Es el recomendado**: el escucha no necesita eco ni reproducción, y no
hace falta detectar el nombre mientras ya estás hablando.

El riesgo de B es el traspaso, y hay que decirlo: el motor ya documenta un cierre de
la app por taps solapados durante los ciclos de abrir y cerrar el micrófono. La
mitigación es la que ellos ya usan para los cambios de configuración — **un solo
dueño a la vez y todo el traspaso en el hilo principal**.

## Lo que ninguno de los dos resuelve

**El motor no tiene modo «solo salida».** Hoy un aviso de agenda abre el micrófono
para decir una frase, porque `acquire()` monta el grafo completo. Con el escucha en
medio eso se vuelve visible: el aviso pediría un micrófono que el escucha ya tiene.

Eso apunta a una pieza previa y más pequeña: que el motor sepa **para qué se le
pide** —escuchar el nombre, conversar, o solo hablar—. Separar ese «solo salida»
desatasca los dos diseños y se puede hacer sin tocar nada de la escucha.

## Lo que queda por decidir, si se retoma

- ¿Se acepta el **indicador naranja de micrófono encendido de forma permanente**?
  Aunque no salga nada de la máquina, macOS lo va a mostrar todo el día.
- ¿Qué hace si **no entiende la carpeta**? Preguntar, listar las que hay, o callar.
- ¿El nombre para despertar es **el configurable** (Ajustes › Nombres) o uno fijo?
  Con `contextualStrings` el configurable sale casi gratis, así que fijarlo solo
  paga si algún día se entrena un modelo propio de una palabra, al estilo Alexa —
  que es el único camino para que la escucha sea barata en batería.
- El **enrutador por voz** —«en qué carpeta» y «qué tarea»— se puede construir y
  probar **con `⌥Espacio` y sin escucha continua**. Es el 80 % del valor sin pagar
  el nudo del micrófono, y el día que la escucha exista, ya la espera.

## Cómo repetir las medidas

Los binarios sueltos **no sirven**: mueren con SIGABRT y el informe lo dice —
«must contain an NSSpeechRecognitionUsageDescription key». Hace falta un bundle
mínimo con `NSMicrophoneUsageDescription` y `NSSpeechRecognitionUsageDescription`,
firmado ad-hoc, y lanzado con `open` para que macOS pueda pedir los permisos.

```sh
cd tool/spike-escucha
swiftc -o disponibilidad disponibilidad.swift && ./disponibilidad   # sin micrófono
# para las otras dos: ver el bundle descrito arriba
```
