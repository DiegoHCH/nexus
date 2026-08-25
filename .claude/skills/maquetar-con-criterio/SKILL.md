---
name: maquetar-con-criterio
description: Maquetar una pantalla o una app entera partiendo de una postura y no de una biblioteca de componentes. Úsala cuando haya que diseñar una interfaz nueva, rehacer una que se ve genérica, o preparar mockups antes de implementar. Produce mockups en HTML con el motivo de cada decisión al lado. NO es para retocar una pantalla ya decidida: para eso se toca el código directamente.
---

# Maquetar con criterio

Una interfaz se ve «como todas» por un motivo mecánico, no por falta de talento: **se
empezó eligiendo componentes.** En cuanto la primera decisión es «esto va en una tarjeta»,
el resto se deduce solo — la tarjeta pide sombra, la sombra pide radio, el radio pide el
resto del kit, y sale lo mismo que sale siempre porque **es** lo mismo.

Esta skill invierte el orden: primero se decide **qué dice cada forma**, y el componente
aparece al final como consecuencia. Es más lento en la primera pantalla y más rápido en
las diez siguientes, porque a partir de la segunda las decisiones ya están tomadas.

## Presupuesto

El gasto de maquetar no está en dibujar: está en **rehacer**. Un mockup cuesta minutos y
una pantalla implementada cuesta días, así que el presupuesto se mide en decisiones que se
toman **antes** de escribir código, no en tiempo de dibujo.

| | Tope |
|---|---|
| Componentes elegidos en la fase 1 | **0** — es la regla, no un consejo |
| Variantes de una misma pantalla | **3** — con cuatro ya nadie compara, se elige la primera |
| Decisiones sin motivo escrito | **0** |

Si te encuentras dibujando la cuarta variante, no estás explorando: estás evitando
decidir. Elige entre las tres y sigue.

---

## Fase 1 · La postura, antes del componente

Antes de cualquier forma, se contestan tres cosas por escrito. Cortas — una o dos frases
cada una.

1. **Qué es esto.** No qué hace: qué **es**. «Un asistente de voz» y «un panel de control
   con voz» piden interfaces opuestas.
2. **Qué tiene que sentir quien lo abre**, en una palabra. Calma, urgencia, precisión,
   confianza, juego. Una sola: dos palabras es no haber elegido.
3. **Qué NO es.** Esta es la que más trabaja. «No es un chat», «no es un dashboard», «no
   es una red social» descartan de golpe la mitad de los defaults.

### Y ahora lo importante: qué dice cada forma

Antes de usar una forma, se escribe **qué afirma**. No cómo se ve: qué le dice a quien la
mira. Ejemplo real, de un proyecto donde esto funcionó:

> Una burbuja dice «dos personas charlando». Un bloque con una línea de un píxel dice «un
> registro de lo que pasó». La app era lo segundo, así que las burbujas se fueron.

Ese párrafo es el método entero. Se repite por cada decisión estructural:

| Forma | Qué afirma | ¿Es lo que queremos? |
|---|---|---|
| Tarjeta con sombra | «esto es un objeto que se puede coger» | |
| Línea de 1px | «esto es un registro, un límite, un dato» | |
| Esquina redondeada grande | «amable, informal, táctil» | |
| Esquina recta | «preciso, técnico, serio» | |
| Relleno de color | «esto está pasando ahora» | |
| Solo contorno | «esto está disponible, no activo» | |

**Rellena esa tabla con las formas de tu pantalla antes de dibujar nada.** Las que
afirmen algo que no quieres decir, se caen — y con ellas se cae el kit que las
acompañaba.

## Fase 2 · La lista de lo que se rechaza

Aquí es donde una interfaz deja de parecerse a las demás, y es un paso explícito porque
si no se escribe, no pasa. **Enumera los defaults que descartas y por qué.** Uno por
línea:

```
· Barra de pestañas abajo → no, hay una sola cosa que hacer: navegar sugiere que hay cinco.
· Botón flotante → no, la acción principal ya vive en el campo de texto.
· Sombras → no, esto no es una pila de papeles; los planos se separan con líneas.
· Tipografía del sistema para los datos → no, los números en mono se leen en columna.
```

Dos reglas sobre esta lista:

- **Cada rechazo lleva su motivo.** «No me gusta» no es un motivo: no se puede discutir ni
  se puede heredar a la pantalla siguiente.
- **Si no puedes rechazar nada, no has decidido nada.** Una lista vacía significa que
  vas a producir el default, y entonces esta skill no está aportando.

## Fase 3 · Dibujar, en HTML y con el motivo al lado

Los mockups van en **un solo archivo HTML** autocontenido, no en una herramienta de
diseño. Tres razones, en orden de peso:

1. **Se puede leer con el código delante.** El mockup y la implementación se comparan sin
   traducir de un formato a otro.
2. **El motivo vive pegado a la forma.** Cada decisión lleva su párrafo al lado, y eso es
   lo que permite descubrir una contradicción — «este texto dice 2px y el de al lado pone
   3» es un fallo que se ve leyendo, no mirando.
3. Sobrevive sin cuenta, sin plugin y sin conexión.

Qué tiene que traer el archivo:

- **Las pantallas** en su tamaño real, no como diagramas.
- **Los estados que no son el feliz**: vacío, cargando, error, sin permiso, sin conexión.
  No son opcionales y no se resuelven con un indicador girando en el centro: cada uno dice
  **qué pasó y qué se puede hacer**, y ninguno se disculpa.
- **Tema claro y oscuro**, los dos dibujados. Un tema que nadie miró nunca es un tema
  roto: el contraste se rompe en el que no se abrió.
- **El léxico**: qué palabra se usa para cada cosa y qué palabra queda prohibida.

## Fase 4 · El mockup es una propuesta, no una ley

Esta fase existe porque su ausencia cuesta caro **en los dos sentidos**.

**Un mockup que no se abre se ignora.** Si hay mockups, se leen **antes** de implementar la
UI relacionada. Saltárselo es rehacer la pantalla, y pasa por creer que uno se acuerda de
lo que decía.

**Y un mockup puede estar equivocado.** Caso real: el mockup decía «mantén pulsado para
hablar», se construyó así con su motivo escrito —un micrófono olvidado abierto es lo peor
en un teléfono de bolsillo— y con la app en la mano resultó lo contrario: sostener obliga a
tener el dedo en el cristal justo cuando lo natural es dejar el teléfono en la mesa. El
gesto cambió a un interruptor y el riesgo se cubrió en otro sitio.

Así que al implementar:

- Si el código se aparta del mockup, **el mockup se actualiza y se dice por qué**. Dos
  fuentes de verdad que se contradicen son peor que una equivocada.
- Lo que se pierde por el cambio **se anota**. En el caso de arriba se perdió poder
  interrumpir hablando encima, y eso tenía que ser una elección y no un descuido.

---

## Reglas que no se discuten

- **La fase 1 va entera antes de la primera forma.** Es la única que no se puede recuperar
  después: una vez elegido el kit, se razona hacia atrás para justificarlo.
- **Tema claro y oscuro, siempre.** No se «añade luego».
- **Ningún estado sin acciones por descuido.** Si un estado no ofrece nada que hacer, que
  sea porque alguien lo decidió.
- **El motivo se escribe en el momento**, no después. Reconstruirlo más tarde produce la
  justificación de lo que ya hiciste, no la razón por la que lo hiciste.

## Errores que cuestan caro

- **Abrir la biblioteca de componentes en la fase 1.** Es el error que esta skill existe
  para impedir; todo lo demás son consecuencias suyas.
- **Dibujar solo el camino feliz.** Los estados raros son la mitad de la app y siempre se
  diseñan con prisa y mal.
- **Confundir «original» con «raro».** El objetivo no es que sorprenda: es que **diga lo
  que la app es**. Una interfaz sobria y precisa puede ser completamente propia; una llena
  de gestos inventados solo es incómoda.
- **Copiar el sistema de otro proyecto tuyo.** Funciona la primera vez y a la tercera has
  vuelto a tener un default, solo que es tuyo. La fase 1 se rehace en cada proyecto: es
  corta.
