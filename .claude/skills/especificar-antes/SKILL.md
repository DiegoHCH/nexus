---
name: especificar-antes
description: Escribir la especificación de algo antes de refinarlo o construirlo — qué problema resuelve, para quién, qué queda fuera, y las preguntas cuya respuesta cambia el trabajo. Fija también los principios del proyecto si no los hay. Úsala cuando llegue una petición vaga, cuando dos personas entiendan cosas distintas de lo mismo, o antes de estimar. NO decide cómo se implementa: eso es de `refinar-tecnico`.
---

# Especificar antes

El error más caro de un proyecto no es estimar mal: es **refinar muy bien algo que estaba
mal especificado**. Ese trabajo se hace entero, se revisa, se mezcla, y se descubre en la
demo — cuando ya se pagó todo.

Esta skill se pone delante de eso. No decide cómo se hace nada: decide **qué es**, para
quién, qué queda fuera, y qué preguntas hay que contestar antes de que valga la pena
pensar en el cómo.

## La regla que la ordena entera

**Si una pregunta puede cambiar el trabajo, no se contesta por cuenta propia.** Se escribe,
se le pone dueño, y se dice qué pasa si no se responde.

Es tentador rellenar los huecos —normalmente uno tiene una opinión razonable— y es
exactamente ahí donde se pierden las semanas: la opinión razonable se convierte en
requisito sin que nadie la haya aprobado, y para cuando alguien la discute ya está
construida.

## Presupuesto

| | Tope |
|---|---|
| Vueltas de herramienta | **3** — esto se escribe pensando, no investigando |
| Decisiones de implementación | **0** — no es de esta fase |
| Huecos rellenados por cuenta propia | **0** |

Si te encuentras leyendo código, te has pasado de fase: eso es `refinar-tecnico`. Aquí solo
se lee código para responder «¿esto ya existe?», y con eso basta.

---

## Fase 1 · Los principios, si no están escritos

Se hace **una vez por proyecto**, no por historia. Si ya existen —en un `CLAUDE.md`, en un
documento de decisiones— se leen y se salta esta fase.

Son las cosas que el proyecto decidió y que no se vuelven a discutir en cada tarea:
arquitectura, qué se prohíbe, qué se prefiere, y **por qué**. Cuatro o cinco, no veinte:
una lista de veinte principios es una lista que nadie consulta.

Lo que hace que sirvan es el **por qué**. «Usamos arquitectura limpia» no evita ninguna
discusión; «la regla de dependencia va hacia dentro, porque el dominio tiene que poder
probarse sin base de datos» sí la evita, y además se puede contradecir con un argumento.

## Fase 2 · La especificación

Seis preguntas, en este orden. Cortas: si una no cabe en dos frases, es que hay dos cosas
dentro.

1. **Qué problema resuelve.** El problema, no la solución. «Falta un botón de exportar» es
   una solución; «no puedo llevarme mis datos» es el problema, y admite otras salidas.
2. **Para quién**, y **cuántos son**. Cambia todo: lo que sirve a una persona experta no
   sirve a mil que entran por primera vez.
3. **Cómo se ve que funcionó.** Concreto y comprobable. Si no se puede decir cómo se
   verificará, no se puede saber cuándo está terminado.
4. **Qué queda fuera.** Es la más valiosa y la que más se salta. Sin ella, el alcance crece
   solo, y crece durante la implementación — que es cuando más cuesta.
5. **Qué pasa si no se hace.** Si la respuesta es «nada», ya tienes la decisión.
6. **Qué existe ya** que resuelva esto en parte. Media solución construida cambia la
   petición entera.

## Fase 3 · Las preguntas abiertas, con dueño

Cada una lleva tres cosas, y sin las tres no es una pregunta útil:

| | |
|---|---|
| **La pregunta** | En una frase, contestable con un dato o una decisión |
| **El dueño** | Una persona o un rol, no «el equipo» |
| **El impacto de no responderla** | Qué se hace mientras: se asume algo, se para, o se hace la mitad |

Y se **clasifican**, porque no todas paran el trabajo:

- **Bloqueantes** — sin esto no se puede empezar. Van arriba.
- **De alcance** — cambian cuánto trabajo es, no si se puede hacer. Se asume lo más
  pequeño y se marca.
- **De detalle** — se pueden decidir mientras se construye. Se anotan y se sigue.

Meterlas todas en el mismo saco hace que las tres bloqueen, y entonces la lista se ignora
entera.

## Fase 4 · El corte

Antes de pasar a refinar, una decisión explícita entre estas tres:

- **Va** — está claro, con las preguntas de detalle abiertas si hace falta.
- **Va recortado** — parte de lo pedido está claro y esa parte se especifica. Se dice qué
  se recortó y por qué.
- **No va todavía** — hay una pregunta bloqueante sin dueño, o el problema no está claro.
  **Esto es un resultado legítimo**, no un fracaso: es más barato que refinar a ciegas.

---

## El entregable

**Un HTML autocontenido**, fuera del repo de código. Corto — una especificación que no cabe
en una pantalla y media es un proyecto, no una historia, y hay que partirla.

Con esta estructura:

1. **Las preguntas abiertas, arriba.** Con su dueño y su impacto.
2. Las seis respuestas de la fase 2.
3. Lo que queda fuera, en su propia sección y no en una nota al pie.
4. El corte de la fase 4, dicho en una línea.
5. Los principios del proyecto, enlazados o incrustados si son nuevos.

Y lo mismo que en las demás: **este archivo es público, los proyectos no.** Nada de claves
de tickets, nombres de clientes ni sistemas internos dentro de la skill; eso va en el
entregable, que vive fuera.

## Cómo encaja con las otras

```
especificar-antes  →  refinar-tecnico  →  maquetar-con-criterio  →  construir  →  revisar-y-subir
   qué y para qué       cómo y cuánto        cómo se ve            el trabajo     antes de mezclar
```

**No se salta hacia atrás.** Si al refinar aparece una pregunta que cambia el qué, se
vuelve aquí y se actualiza la especificación — no se decide en el refinamiento. Un
refinamiento que redefine el alcance en silencio es la forma más común de que dos personas
crean cosas distintas del mismo trabajo.

## Errores que cuestan caro

- **Escribir la solución en el hueco del problema.** Es el error de arriba y se cuela solo:
  «necesitamos un botón» pasa por especificación y ya trae la respuesta dentro.
- **Dejar «qué queda fuera» vacío.** Garantiza que el alcance crezca durante la
  implementación, que es cuando más cuesta.
- **Preguntas sin dueño.** Una lista de preguntas que no son de nadie no se contesta: se
  arrastra de reunión en reunión.
- **Especificar de más.** Si la especificación decide colores, nombres de clases o
  estructura de carpetas, ha invadido las dos fases siguientes y las va a estorbar.
- **Tratar «no va todavía» como un fallo.** Es la salida más barata que tiene esta fase, y
  la que más veces debería usarse.
