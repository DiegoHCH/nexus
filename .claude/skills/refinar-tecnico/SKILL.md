---
name: refinar-tecnico
description: Refinamiento técnico de una historia y sus tareas, sin tocar nada de fuera — no escribe en el gestor de tickets, no crea ramas, no commitea, no abre PR y no deja archivos dentro del repo. Trabaja por etapas acumulativas: primero la historia sola (mapa del código, alternativas, dependencias, preguntas abiertas) y después sus tareas con estimación, reusando el análisis ya hecho. El entregable es un HTML autocontenido. Úsala para preparar una reunión de refinamiento o para saber qué cuesta algo antes de comprometerlo.
---

# Refinar técnico

Un refinamiento sirve para **saber lo que cuesta algo antes de prometerlo**, y la mayoría
fallan por la misma razón: se hacen en la reunión, en voz alta, sobre un documento que
nadie leyó con el código delante. Lo que sale de ahí es una estimación de la sensación de
alguien, no del trabajo.

Esta skill hace el trabajo **antes** de la reunión y sin tocar nada: si el refinamiento
resulta malo se borra un HTML y no queda rastro en ningún tablero ni en git. Ese
aislamiento no es una precaución, es lo que la hace útil — **poder equivocarse sin coste
es lo que permite explorar de verdad.**

## Lo que esta skill nunca hace

Va primero porque es la garantía de la que dependen todas las demás:

- **No escribe en el gestor de tickets.** Lo lee, si le pasas una referencia. No comenta,
  no transiciona, no estima ahí, no crea nada.
- **No toca git.** Ni rama, ni `add`, ni commit, ni push, ni PR.
- **No deja un solo archivo dentro del repo de código.** Todo lo intermedio va a una
  carpeta de trabajo **fuera** del repo, y el entregable también. Después de correr esto,
  un `git status` del proyecto tiene que estar limpio — y eso se comprueba, no se supone.

Si en algún momento parece que hace falta romper una de estas, no se rompe: se anota en el
entregable como «esto habría que hacerlo aparte» y sigue.

## Presupuesto

| | Tope |
|---|---|
| Exploraciones del código por historia | **1** — la etapa 2 lee lo de la etapa 1 |
| Alternativas de diseño | **2 o 3** — con cuatro nadie compara |
| Preguntas que se contestan por cuenta propia | **0** |

El último es el que más se incumple y el que más caro sale. Si el documento no dice algo,
**no se inventa**: se escala como pregunta abierta con dueño. Un refinamiento que resuelve
las dudas por su cuenta produce una estimación de algo que nadie pidió.

---

## Las dos etapas

**Son acumulativas y reanudables.** Si pasan días entre una y otra no importa: la carpeta
de trabajo persiste y la etapa 2 no vuelve a explorar el código.

### Etapa 1 · La historia sola

Cuando llega la historia sin tareas todavía. Produce, en este orden:

1. **Lo funcional entendido**, reescrito en una frase. Si no cabe en una frase, la
   historia tiene dos historias dentro y eso es un hallazgo.
2. **El mapa del código**: dónde vive hoy lo que hay que tocar, qué existe ya y qué no.
   Con rutas de archivo, no con descripciones.
3. **Las alternativas**, con lo que cada una acepta a cambio. No «la mejor»: las dos o
   tres reales y qué se paga por cada una.
4. **Las dependencias de otros equipos**, con lo que falta de cada una. Un contrato que no
   existe no bloquea el refinamiento — se diseña contra un contrato **asumido**, se
   documenta como asumido, y la tarea que lo integra queda marcada como condicional.
5. **Las preguntas abiertas, con dueño y con el impacto de no responderlas.**
6. **El diseño de los cimientos**: lo que hay que montar antes de que cualquier tarea
   tenga sentido.
7. **Una descomposición propuesta en tareas, con estimación sugerida.**

**La etapa 1 vale por sí sola.** Ya contesta lo más caro —si esto es viable, dónde vive,
qué falta de fuera y qué hay que preguntar— así que sirve para ir a la reunión aunque la
etapa 2 no se corra nunca.

### Etapa 2 · Las tareas

Cuando ya hay lista de tareas. **No re-explora nada**: lee lo de la etapa 1 y añade:

1. **Un diseño por tarea**, dentro de los cimientos ya decididos.
2. **Una tabla de lo declarado contra lo estimado**, con la diferencia a la vista. Esa
   columna es el valor del refinamiento: es donde se ve que una tarea de «1» son tres.
3. **El orden de ejecución**, y qué se puede hacer en paralelo.

Si una tarea **contradice los cimientos** —implica otra arquitectura— no se rediseñan los
cimientos en silencio: se muestra el conflicto y se pregunta si se ajustan los cimientos
o si la tarea se diseña dentro de los actuales.

---

## La escala de esfuerzo

**Se pregunta una vez y se escribe en el entregable.** No se asume: cada equipo usa la
suya, y una estimación en una escala que el lector no comparte es peor que ninguna —
parece un dato y es un malentendido.

Lo que hay que fijar antes de estimar:

- A cuántas horas efectivas equivale **un punto**.
- Si la escala es lineal o Fibonacci. Números como `13` o `21` delatan lo segundo.

Y a partir de ahí, **cada estimación se expresa con su equivalencia al lado** —`3 pts ·
12 h · 1,5 d`— porque el punto es una convención y las horas no.

## Lo que se marca como no validado

Un refinamiento es honesto o no sirve, y lo que lo hace honesto es que **se vea lo que no
está confirmado**. Cada uno de estos lleva su marca visible en el entregable:

| | Qué significa |
|---|---|
| `contrato asumido` | Se diseñó contra una forma de datos que nadie confirmó |
| `pregunta abierta` | Falta una decisión de producto, con dueño y fecha |
| `sin explorar` | Una parte del código no se miró, y por qué |
| `decisión pendiente` | Hay dos caminos y no se eligió |
| `estimación condicional` | El número depende de algo de la lista de arriba |

Sin estas marcas, un refinamiento se lee como una promesa. Con ellas se lee como lo que
es: lo que se sabe hoy.

---

## El entregable

**Un HTML autocontenido** —CSS y JS dentro, sin CDN, diagramas en SVG inline— que se abre
en cualquier navegador y sobrevive sin conexión y sin cuenta.

Dos reglas sobre su contenido:

- **El entregable es el documento, no un resumen.** Los fragmentos de código van
  completos y aplicables. Nada de «ver el archivo tal»: quien lo lee no lo tiene.
- **Las preguntas abiertas van arriba.** Son lo más valioso de un refinamiento temprano y
  lo primero que hay que ver, no un apéndice.

Y sobre dónde vive: **fuera del repo de código, siempre.** El mismo archivo se enriquece
en cada etapa en vez de crear uno nuevo — así hay un solo documento por historia y no
tres versiones que se contradicen.

## ⚠️ Este archivo es público; los refinamientos no

Esta skill vive en un repositorio público. Lo que se refina, no.

- **No metas aquí** claves de tickets, nombres de repos internos, nombres de clientes,
  rutas de sistemas de la empresa ni convenciones de un equipo concreto. Si necesitas
  ajustar la skill a un contexto, ese ajuste va en el perfil o en el repo de ese trabajo,
  no en este archivo.
- **Los entregables van fuera del repo**, y por eso el punto anterior no es una
  incomodidad: la skill es genérica y el refinamiento es de quien lo corre.

---

## Bloqueantes, y qué hacer con cada uno

Ninguno de estos para el refinamiento. Lo que hacen es cambiar qué se entrega.

1. **Tareas sin haber hecho la etapa 1.** No se adivina el contexto de la historia: se
   ofrece correr la etapa 1 primero, o tratar todo como una sola corrida.
2. **Referencia de ticket inaccesible.** No bloquea: se degrada a tema libre y se avisa en
   el entregable.
3. **Varias historias en el mismo bloque.** Se pregunta cuál, o se corre una vez por
   historia. **Nunca dos historias en un entregable**: la estimación deja de poder leerse.
4. **Dependencia de otro equipo sin contrato.** Se diseña contra un contrato asumido, se
   marca, y la tarea de integración queda condicional.
5. **Una decisión de arquitectura sin resolver.** Se para y se pregunta. Si no se puede
   resolver ahora, se sigue con la alternativa marcada y se dice que está sin cerrar.

## Errores que cuestan caro

- **Estimar antes de mirar el código.** Es el error que esta skill existe para impedir.
- **Contestar las preguntas de producto por cuenta propia.** Produce un refinamiento
  precioso de algo que nadie pidió, y no se descubre hasta la demo.
- **Re-explorar el código en la etapa 2.** Es caro y, peor, produce un mapa distinto del
  mismo código — así que las dos etapas dejan de encajar.
- **Entregar un resumen en vez del documento.** Un refinamiento que remite a otros
  archivos obliga a repetir el trabajo a quien lo lee.
- **Quitar las marcas de lo no validado porque «quedan mal».** Es exactamente cuando más
  hacen falta.
