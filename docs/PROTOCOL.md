# El canal teléfono ↔ Mac

Fase **4.0**: lo que hay que decidir antes de escribir una línea del servidor.

Este documento existe porque el atajo tentador es reenviar a lo bruto lo que ya
hay —los providers de Riverpod— y acabar con métodos sin criterio y con agujeros.
El contrato se escribe primero. Casi nada de esto es código.

> **Estado**: decidido el 19 ago 2026. Lo que sigue no son propuestas: son las
> decisiones con las que se va a escribir el servidor. Cuando alguna cambie, se
> cambia **aquí** y luego en el código.

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

Pasar a edición **se confirma en el escritorio** y **caduca a los 30 minutos**.

La caducidad se cuenta desde la confirmación y **no se renueva con la actividad**.
Si se renovara, un teléfono en uso mantendría el permiso abierto indefinidamente
— que es exactamente el escenario del teléfono perdido que esto viene a evitar.

Nexus llega con esto medio resuelto: el permiso ya es un eje explícito de la
interfaz y el modo se fija al lanzar cada encargo, así que la caducidad es un
temporizador y no una reingeniería.

El riesgo de fondo, para no perderlo de vista: el interruptor **puede editar**
mapea a `acceptEdits`, que escribe sin preguntar. Abrir eso por red es lo que
justifica todo este documento.

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

### Se queda en el Mac

| | Por qué |
|---|---|
| **Emparejar carpetas** | Es un selector de archivos local. Por red sería elegir a ciegas cualquier ruta del disco |
| **Crear skills** | Escribe en disco, y se administra desde el escritorio |
| **Subir el permiso a «puede editar»** | Por la 2.4: se confirma en el escritorio |

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
