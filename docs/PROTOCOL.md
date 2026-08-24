# El canal teléfono ↔ Mac

Fase **4.0**: lo que hay que decidir antes de escribir una línea del servidor.

Este documento existe porque el atajo tentador es reenviar a lo bruto lo que ya
hay —los providers de Riverpod— y acabar con métodos sin criterio y con agujeros.
El contrato se escribe primero. Casi nada de esto es código.

> **Estado**: decidido el 19 ago 2026, con la **2.4 corregida el 20 ago**. Lo que
> sigue no son propuestas: son las decisiones con las que se está escribiendo el
> servidor. Cuando alguna cambie, se cambia **aquí** y luego en el código — como
> pasó con la 2.4, que pedía algo imposible y lo dice en su propio apartado.

---

## 1 · El transporte: solo Tailscale

El servidor escucha **únicamente en la interfaz de Tailscale**. Nunca en
`0.0.0.0`, nunca en la interfaz de la red local.

WireGuard ya trae cifrado e identidad de dispositivo, así que el socket es
inalcanzable desde la red local y desde internet. Eso es lo que evita tener que
montar TLS encima.

**Se consideró permitir la red local y se descartó**, y el motivo es concreto: al
salir de WireGuard hay que asumir una red hostil, lo que obliga a `wss` con
certificado para una IP privada. Ninguna autoridad emite certificados para
`192.168.x.x`, así que sería autofirmado más *pinning* en la app, y rotación de
certificados en los dos lados para siempre. Todo eso a cambio de no instalar
Tailscale.

**El precio, dicho claro**: Tailscale en el Mac y en el teléfono. Es una
dependencia real, del mismo tipo que las que la app ya tiene —Claude Code, una
llave de Gemini— y la comprobación de arranque tendrá que decirlo cuando falte.

---

## 2 · Las seis que no son decisiones

La ficha `lo1` las llama decisiones porque en La Oficina nadie las había escrito.
No tienen alternativa razonable: son el mínimo.

### 2.1 · Token en cada conexión

No solo al emparejar. Rotable y revocable desde Ajustes, y rotarlo **invalida
todos los teléfonos de golpe**.

- Se genera en el Mac.
- En el teléfono vive en el Keystore, vía `flutter_secure_storage` — el mismo
  paquete que ya guarda la llave de Gemini.
- **Viaja en una cabecera, nunca en la URL.** Las URLs acaban en registros: del
  servidor, de los proxies, del historial. Una cabecera no.

### 2.2 · Comparación en tiempo constante, y límite de intentos por IP

Comparar el token con `==` filtra su contenido por el tiempo que tarda en fallar:
se adivina byte a byte. Y sin límite de intentos, adivinarlo es cuestión de
paciencia.

### 2.3 · Validar `Host` y `Origin` en el upgrade

**Esta es la que se salta todo el mundo, y la única que sigue siendo necesaria
aunque el transporte sea perfecto.**

Cualquier página web abierta **en tu propio Mac** puede hablarle a un servidor
local mediante *DNS rebinding*. El token no protege de eso: el navegador lo
enviaría igual, porque el ataque viene de dentro del límite de confianza.

Se cierra rechazando el upgrade del WebSocket cuando `Host` u `Origin` no son los
esperados.

### 2.4 · El móvil nace en solo lectura

Y **solo lectura no significa que no pueda mandar encargos**: sí puede, y así lo
dice la sección 3. Significa que su encargo corre con `canEdit: false` — Claude
lee el repositorio y contesta, pero no escribe.

Subir a edición pide **la frase de escritura** y **caduca a los 30 minutos**.

La caducidad se cuenta desde que se concede y **no se renueva con la actividad**.
Si se renovara, un teléfono en uso mantendría el permiso abierto
indefinidamente — que es exactamente el escenario del teléfono perdido que esto
viene a evitar.

El riesgo de fondo, para no perderlo de vista: el interruptor **puede editar**
mapea a `acceptEdits`, que escribe sin preguntar. Abrir eso por red es lo que
justifica todo este documento.

#### Esto decía «se confirma en el escritorio», y estaba mal

Corregido el 20 ago, y el motivo merece quedar escrito porque el error es fácil de
repetir.

**Si la confirmación exige el escritorio, editar en remoto es imposible por
definición**: justo cuando estás fuera, no hay nadie en el Mac para conceder nada.
La función se quedaba sin su caso principal.

El error de fondo fue confundir el requisito con una de sus formas. El requisito
real es:

> Subir a edición tiene que exigir **algo que quien robe el teléfono no tenga**.

La proximidad al Mac era una manera de conseguir eso, y resulta ser la única que
además te excluye a ti.

#### Y por qué no vale el Face ID del teléfono

Fue lo primero que se pensó, y **no sirve aquí**: el Mac no puede comprobar que
haya ocurrido. Si el teléfono dice «el usuario se autenticó», hay que creérselo — y
quien haya sacado el token del Keystore puede mandar esa misma frase sin ninguna
cara delante.

Face ID protege contra alguien que coge tu teléfono desbloqueado y abre la app. No
protege contra quien se llevó el token, que es el escenario que importa.

#### La frase de escritura

Un segundo secreto **que el Mac sí puede verificar**:

- Se define en el Mac y vive en su llavero, igual que el token.
- **No se guarda nunca en el teléfono.** Se teclea cuando se quiere escribir.
- Viaja dentro del WebSocket, que ya va cifrado por WireGuard, y **nunca a un
  registro**: es un objeto con `toString` redactado, como el token.
- Se compara **en tiempo constante** y con su propio límite de intentos, aparte del
  de la conexión: adivinarla por un canal ya autenticado no puede ser gratis.
- Concede **treinta minutos para todo el canal**, no por carpeta. Por carpeta sería
  más fino y en la práctica es la misma persona tecleando la misma frase varias
  veces: fricción sin ganancia.

**Sin frase definida, el móvil se queda en solo lectura para siempre.** Es el
estado por defecto y es el correcto: quien no la haya puesto no ha dicho en ningún
momento que quiera que el teléfono escriba.

Y como complemento —no como sustituto— el Mac puede **preautorizar** una ventana
antes de salir, para no teclearla cada media hora.

| | ¿puede escribir? |
|---|---|
| Tú, desde donde sea | **sí**, con la frase |
| Quien tenga tu teléfono | no: el token está ahí, la frase no |
| Quien saque el token del Keystore | no, por lo mismo |
| Quien entre en el Mac | sí — pero ahí ya está todo perdido, y este documento no lo cubre |

### 2.5 · Registro append-only

Qué pidió el móvil, con qué permiso y cuándo. Append-only: un registro que se
puede editar no sirve para lo que sirve un registro.

### 2.6 · Ver quién está conectado, y poder echarlo

Lista de clientes con su última actividad, y un botón para cortar. Hoy no existe
ninguna de las dos cosas.

---

## 3 · Qué se expone y qué no

La superficie de Nexus es mucho menor que la de La Oficina —allí el triaje costó
59 handlers— y precisamente por eso conviene fijarla **antes de que crezca**.

### Va al móvil

- Mandar un encargo, y detenerlo.
- El stream de actividad y de respuesta.
- Las conversaciones y su historial.
- El estado del medidor de contexto y el permiso vigente.
- **Subir el permiso** a escritura, y solo con la frase de escritura de la 2.4.
  Estuvo en el lado de «se queda en el Mac» mientras la confirmación era del
  escritorio; con la frase ya no tiene que serlo, y dejarlo ahí era lo que hacía
  imposible editar en remoto.
- **El archivo de conversaciones**, y **retomar una del archivo**. Salió de usar el
  teléfono: si en el
  Mac no hay ninguna conversación abierta, el móvil no podía hacer nada — y eso
  convierte «mira cómo va lo que dejaste» en «solo sirve si te acordaste de dejarlo
  abierto». Retomar es lo mismo que hace `⌘H` en el escritorio.
- Ese archivo es **la misma lista que enseña `⌘H`**, no la del almacén interno de la
  app: buena parte de las conversaciones vive en el vault que el usuario configuró, y
  leer solo el almacén hacía que el teléfono enseñara una donde el escritorio enseñaba
  treinta y una. Cada una lleva **de qué cuenta es** —`work`, `private`—, porque el
  escritorio las separa en pestañas y en el teléfono no hay sitio para pestañas.
- La lista **se pagina** con `cursor` y `nextCursor`. El teléfono sigue el cursor hasta
  que no venga: una sola página con un límite deja fuera conversaciones sin decirlo, y
  una lista que se corta en silencio se lee como una lista completa.
- Las **carpetas** llevan también su cuenta, y por un motivo distinto al del archivo:
  abrir una conversación **es elegir una cuenta sin verlo** —la carpeta lleva su perfil
  pegado en el Mac—, así que desde el teléfono se elegía a ciegas qué memoria y qué
  contexto iban a atender el encargo.
- Los **artifacts** llevan su cuenta y, además, **si son texto**. Lo segundo va en la
  lista y no se descubre al abrir: pedir un `.png` acababa en un error de codificación
  —leer un binario como cadena no da una imagen— y el teléfono se quedaba con un fallo
  genérico donde tenía que haber un «esto se abre en el Mac». Un documento que no es
  texto se enseña igual, apagado: esconderlo deja preguntándose si falta algo.
  Un `.html` **es** texto, así que viaja por el canal como una cadena y el teléfono lo
  pinta en un visor propio: no hizo falta inventar transporte binario ni servir
  ficheros por HTTP, y por tanto el canal no gana ninguna puerta nueva. Ese visor no
  navega: lo que se pinta es lo que llegó, y un enlace a la red lo convertiría en un
  navegador.
- **Los artifacts** y **el contenido de un artifact**: los documentos que produce
  Claude. Son de lectura y son el resultado del trabajo — poder mandar un encargo y no
  poder ver lo que produjo es medio canal.
- El **estado del orbe** viaja con cada conversación, y es el del Mac tal cual: el
  teléfono no lo deduce. Sólo recibía `streaming`, así que de los cuatro estados
  —reposo, escuchando, trabajando, hablando— podía dibujar dos: el micro abierto no
  es trabajo corriendo, y la voz saliendo tampoco. Reenviarlo hace que el orbe del
  teléfono **sea** el del Mac y no una imitación que se desincroniza en cuanto se
  añada un estado.
- Va en un evento propio, `orb`, y **no dentro de `turn`**: `streaming` y el orbe
  cambian en momentos distintos, y juntarlos haría que uno arrastrara al otro.
- Con cada conversación viaja también **su nombre**: el primer encargo, aplanado a una
  línea. Va en la vista y no solo en la lista porque una conversación **nace de un
  evento** —se abre desde el teléfono— y hasta la siguiente lista no tenía carpeta ni
  nombre: lo que se veía era su identificador, que no dice nada.
- Y el **acento** tiene su propio evento, sin `conversation`: es del Mac entero. Se
  leía solo en el saludo, así que cambiarlo con el teléfono conectado no llegaba hasta
  la siguiente reconexión — y lo prometido era heredarlo sin volver a emparejar, no
  reconectar. Va numerado como todo lo demás para que un teléfono que se reincorpora lo
  reciba en su resync, sin un camino aparte que mantener.
- **Y el teléfono lo apaga si no hay enlace.** El espejo se queda con lo último que
  supo, así que un Mac que estaba trabajando cuando se perdió la cobertura dejaría el
  orbe girando sobre una pantalla que dice «se perdió el enlace». Un orbe girando
  promete trabajo que está pasando; sin enlace no se sabe si el Mac terminó, falló o
  se durmió, y dormido es la única forma honesta de decir «no sé nada».
- **Abrir una conversación sobre una carpeta ya emparejada**, y también
  **las carpetas emparejadas**, para poder elegir. Esto es lo que parece chocar con «emparejar carpetas se queda en el Mac»
  y no choca: el motivo de esa línea es que por red se elegiría **a ciegas cualquier
  ruta del disco**, y aquí el Mac ofrece la lista y el teléfono escoge de ella. Nadie
  elige una ruta que el Mac no tuviera ya. Emparejar una carpeta nueva sigue fuera.
- **Ponerle nombre a una conversación** y **cerrar una conversación**. Las dos son
  estado de Nexus sobre sus propias fichas, no los archivos del usuario, así que **no
  piden la frase de escritura** — el mismo razonamiento que abrir una sobre una carpeta
  ya emparejada. Cerrar no borra nada: lo dicho sigue en el archivo y de ahí se retoma,
  que es lo que hace que no sea destructivo aunque lo parezca. Un nombre vacío quita el
  puesto y devuelve al derivado, que es lo que hace falta para poder deshacer.
- **Abrir el micrófono del teléfono** y **cerrar el micrófono del teléfono**. Son dos
  métodos y no un interruptor con parámetro: **cerrar tiene que poder llegar aunque se
  haya perdido el que abrió**, y con uno solo habría que llevar la cuenta de quién
  manda. Tampoco piden la frase, por lo mismo que abrir una conversación: hablar no
  escribe archivos. Lo que se diga sí pasa por el permiso, porque acaba en un encargo y
  el encargo ya lo comprueba.
- Y el audio va en un **marco propio, sin confirmación y sin reintento**. Es la decisión
  de fondo de la voz remota: un trozo que llega tarde es peor que un hueco, porque
  reenviarlo mete en la conversación medio segundo de hace un rato. Un `ack` por trozo
  serían tres mensajes por cada 20 ms de voz, y lo que protege el deduplicador —efectos
  que no se repiten— aquí no aplica: un trozo duplicado no borra un archivo, solo suena
  raro. Va en base64 porque el canal es de texto: cuesta un tercio más, unos 43 KB/s a
  16 kHz mono de 16 bits, que es nada por Tailscale y bastante menos que mantener un
  segundo transporte solo para esto.
- **El audio sube; la voz no baja.** Lo que Nexus responde en voz alta sale por los
  altavoces del Mac, que es lo que decidió `lo8` y lo que hace que el teléfono sea un
  mando a distancia y no un cliente autónomo. Sin Mac despierto y alcanzable no hay voz.

### Se queda en el Mac

| | Por qué |
|---|---|
| **Emparejar una carpeta nueva** | Es un selector de archivos local. Por red sería elegir a ciegas cualquier ruta del disco. **Elegir entre las ya emparejadas sí va**, porque ahí la lista la pone el Mac |
| **Crear skills** | Escribe en disco, y se administra desde el escritorio |
| **Definir o cambiar la frase de escritura** | Es la llave del permiso: pedirla por el mismo canal que la usa sería regalarla |

La regla, traída de La Oficina: **un canal remoto que pueda instalar o mutar
cosas amplía mucho la superficie a cambio de poca ganancia.**

---

## 4 · El contrato

Tres formas de mensaje, y no una sola tubería:

1. **Petición/respuesta** — el móvil pide, el servidor contesta.
2. **Eventos empujados** — el servidor cuenta lo que pasa.
3. **Snapshot** — el estado entero, para arrancar o para recuperarse.

### 4.1 · Los modelos se comparten, no se generan

En La Oficina esto disolvía una decisión pendiente entera —modelos a mano contra
generados desde un esquema—. Aquí ahorra menos, porque **los dos clientes son
Dart**: los modelos van en un paquete compartido y no hay esquema del que generar
nada.

Lo que **no** desaparece por eso es la versión del protocolo.

### 4.2 · La versión va en el handshake

El servidor anuncia `min` y `current`. Un cliente por debajo de `min` recibe
«actualiza» y no un fallo raro.

Hace falta porque escritorio y móvil **se actualizan por su cuenta**: desde la
0.0.2 el escritorio se actualiza solo, y el teléfono irá por la tienda. Las dos
versiones van a divergir siempre.

### 4.3 · Un encargo no puede correr dos veces

**La trampa cara.** Si el WebSocket cae después de que el escritorio recibió el
encargo pero antes de confirmarlo, el móvil lo reenvía y `claude -p` corre dos
veces — con `acceptEdits`, escribiendo dos veces en tus archivos.

Se cierra **en el protocolo y no en la app**:

- `clientMsgId` generado en el cliente.
- Confirmación explícita del servidor.
- Deduplicación con TTL en el servidor.

El outbox del móvil —que es lo que hace que puedas mandar un encargo sin
cobertura— **solo es seguro con esto**.

### 4.4 · Reconectar es «mándame desde `lastSeq`»

Los eventos van numerados con un `seq` monotónico, y el servidor guarda un búfer
circular. Reconectar pide desde el último visto, que es barato en 4G. El snapshot
completo queda como **camino de excepción**, no como el normal.

Con tres conversaciones a la vez esto no es un detalle: son tres flujos vivos.

### 4.5 · Los deltas se agrupan ~100 ms, y en el servidor

La app de escritorio pinta cada fragmento porque le sale gratis: es memoria
compartida. Por red no. En móvil con mala señal es inusable, y la batería lo nota.

Se agrupa **en el servidor** y no en el cliente: agrupar en el cliente ya pagó el
envío, que es lo que se quería evitar.

Lo mismo con el historial y la actividad, que hoy se sirven de golpe: **paginación**,
porque el teléfono no puede tragarse una sesión entera.

Y los eventos se hacen de **diferencias de estado, no de deltas acumulados**. El
escritorio ya tiene un flujo de deltas y era lo obvio de reenviar, pero un flujo
acumulado tiene una propiedad mala: si se pierde uno, el teléfono queda mal para
siempre y nada lo delata. Con diferencias, cada envío se calcula contra lo último que
salió de verdad, así que un hueco se cierra solo en el siguiente.

De ahí sale también la regla del texto: lo normal es mandar **solo lo que falta**,
pero cuando la respuesta no es continuación de la anterior —empezó otro turno— va con
`replace`. Sin esa distinción el teléfono pegaría la respuesta nueva al final de la
vieja, y eso pasa en cada segundo encargo.

La ventana es **por conversación y no global**: la cuenta empieza cuando cambió *esa*,
así que un cambio nunca espera al reloj de otra.

### 4.6 · El `ack` va antes de ejecutar, no con el resultado

Es el orden y no un detalle. Un encargo dura minutos: si la confirmación llegara
con el resultado, el móvil pasaría esos minutos sin saber si su petición llegó — y
un móvil que no lo sabe **reenvía**, que es exactamente lo que abre la 4.3.

Así que toda petición recibe dos marcos: el `ack` al instante, y después el `result`
o el `failure`. Un reenvío recibe `ack` con `duplicate` y **no se ejecuta**.

Para `sendErrand`, el `result` dice **que arrancó**, no que terminara: lo que pasa
dentro llega como eventos.

### 4.7 · Cuando algo no se puede atender, se contesta

Nunca se deja una petición sin respuesta. Un teléfono esperando para siempre se lee
como «el Mac no responde», y manda a buscar el problema al sitio equivocado.

Los códigos, que son lo que el móvil convierte en algo que enseñar:

| código | qué pasó | qué hace el móvil |
|---|---|---|
| `unknownMethod` | este Mac no conoce el método | actualizar el escritorio |
| `unknownConversation` | esa conversación ya no está abierta | quitarla y recargar la lista |
| `badParams` | falta algo o no se entiende | es un fallo del cliente |
| `noPhrase` | no hay frase de escritura definida en el Mac | «defínela en el Mac» |
| `wrongPhrase` | la frase no era | volver a pedirla |
| `tooManyAttempts` | se gastó el cupo de intentos | esperar |
| `unavailable` | el canal no atiende peticiones | reconectar |
| `internal` | algo se rompió por dentro | reintentar |

Dos reglas sobre lo que **no** viaja. El `internal` va **sin detalles**: lo que sabe
el Mac se queda en su registro. Y la frase de escritura no aparece nunca en un marco
de respuesta ni en el registro — el registro anota el método y jamás los parámetros,
porque `debugPrint` acaba en el registro del sistema.

---

## 5 · Los estados de la conexión, dichos en pantalla

**conectado · reconectando · resync · sin conexión**, más caché persistente para
leer lo último sin red.

En Nexus pesa más que en La Oficina por una razón concreta: un encargo puede
durar minutos y **el orbe ya usa el silencio como estado normal**. Sin una señal
explícita, «está pensando» y «no llego al Mac» se dibujan idénticos.

### El Mac dormido: no se le impide dormir

Si el Mac se duerme estando ocioso, el móvil no alcanza nada. Las dos salidas
eran mantenerlo despierto o decir la verdad.

**Se dice la verdad.** El servidor no toma una aserción de energía para estar
accesible.

Ya existe `NexusPower`, que impide dormir **mientras hay un encargo en marcha**:
un motivo acotado, con principio y fin. «Estar accesible» no tiene fin, y
convertiría «mi portátil se duerme al cerrarlo» en «mi portátil no duerme nunca» —
un coste grande e invisible en batería y en calor.

Así que el teléfono dirá **«el Mac está dormido»**, distinto de «no responde», que
es justo lo que pide la ficha `lo6`. Y quien quiera accesibilidad permanente tiene
el interruptor del propio sistema —«Despertar para acceso a la red»—, que es una
decisión del dueño del Mac y no de esta app.

---

## Lo que este documento no decide

- **La forma exacta de cada mensaje.** Eso es la 4.1, y sale de aquí.
- **Cómo se empareja la primera vez** —código en pantalla, QR— que es interfaz y
  no seguridad: el token y su transporte ya están decididos arriba.
- **Nada del cliente móvil.** Este documento es del canal.
