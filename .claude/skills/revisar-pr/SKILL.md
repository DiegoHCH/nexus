---
name: revisar-pr
description: Revisa un PR de GitHub en UN solo agente y con pocas vueltas de herramienta — la alternativa ligera a /code-review, que se abre en ocho subagentes y se come una sesión entera. Úsala cuando te pidan revisar un PR, mirar un diff antes de mezclar, o comentar lo que no pasa. Acepta un número de PR, una rama o nada (revisa el PR de la rama actual). Con `--comentar` publica en GitHub; sin eso, solo informa.
---

# Revisar un PR — ligero

Revisión de un PR con **un solo agente** y un presupuesto explícito de vueltas.

## Por qué existe

`/code-review` reparte el trabajo en ocho subagentes (Angle A, Angle B, Angle C,
reuse, simplification, efficiency, altitude, conventions). Es exhaustivo y es caro:
cuatro corridas sobre un PR de 670 líneas vaciaron una sesión de 5 horas en menos
de media hora.

El gasto **no está en escribir** —doce subagentes produjeron 3.500 tokens de texto—
ni en repartir. Está en que **cada llamada a una herramienta vuelve a leer todo el
contexto acumulado**. Un turno con veinte herramientas paga el contexto veinte veces.

De ahí la única regla de diseño de esta skill: **menos vueltas, no menos lectura**.
Leer el diff entero de una vez es barato. Hacer quince `grep` sobre él no lo es.

## Presupuesto

Estos son topes, no sugerencias. Si te quedas corto, **dilo en el informe** en vez de
gastar más:

| | Tope |
|---|---|
| Subagentes | **0** — nunca uses la herramienta Agent, ni aunque el PR sea grande |
| Vueltas de herramienta | **10** en total, incluida la que trae el diff |
| Archivos abiertos aparte del diff | **3**, y solo si el diff no basta para decidir |
| Hallazgos reportados | los **7** más graves, ordenados por gravedad |

Si el diff pasa de ~2.000 líneas, no lo revises entero: dilo, revisa los archivos con
más cambios dentro del presupuesto y marca el informe como **parcial**.

## Cómo se hace

### 1 · Traer el diff — UNA vuelta

Todo en un solo comando. No encadenes `gh pr view`, luego `gh pr diff`, luego
`git log`: son tres vueltas pagando el contexto tres veces.

Todo va en la misma llamada, **incluidas las revisiones anteriores y los commits**. Un
PR revisado ya suele traer una ronda de arreglos, y repetir lo que ya se corrigió es
peor que no revisar: hace perder el tiempo al autor y le quita credibilidad al informe.

```bash
PR=<número, o vacío para la rama actual>
gh pr view $PR --json number,title,author,headRefName,baseRefName,additions,deletions,changedFiles,body,reviews,comments \
  && echo "───── COMMITS ─────" && gh pr view $PR --json commits \
       -q '.commits[] | "\(.oid[0:7]) \(.messageHeadline)"' \
  && echo "───── DIFF ─────" && gh pr diff $PR
```

Si no hay número y la rama actual no tiene PR, `gh pr view` falla: dilo y para. No te
pongas a buscar por otros medios.

**Lee las revisiones y los mensajes de commit ANTES del diff.** Un commit tipo
`fix: address review findings` te dice que ya hubo una ronda; lo que arregló no se
vuelve a reportar. Si un hallazgo tuyo coincide con algo ya señalado, comprueba en el
diff si de verdad sigue ahí — y si sigue, dilo **marcándolo como no resuelto todavía**,
que es información distinta de un hallazgo nuevo.

### 2 · Leer y decidir — CERO vueltas

Aquí no se llama a nada. El diff ya está en contexto: se lee entero y se piensa.

Busca, en este orden de prioridad:

1. **Correctitud** — lo que se rompe con una entrada concreta. Off-by-one, `null` sin
   guardar, `await` que falta, condición invertida, error tragado, recurso sin cerrar.
2. **Comportamiento que desaparece** — algo que antes pasaba y ya no. Cuidado: no son
   solo las líneas borradas. Una línea **añadida** puede quitar comportamiento en toda
   la app (`splashFactory: NoSplash`, un `overflow: hidden`, un guard nuevo), y si el PR
   no lo menciona, es un cambio silencioso. Es lo que más se escapa y lo que más duele.
3. **Incoherencia con la intención declarada** — el propio diff dice una regla y el
   código de al lado la rompe. Un doc comment que dice «las tarjetas usan 2px» junto a un
   tema que les pone 3px. Una constante nombrada que existe y no se usa donde toca. El
   caso de fallo aquí es *«el archivo dice X y el código hace Y»*: la fuente de verdad
   está dentro del mismo diff, así que no hace falta salir a comprobar nada.
4. **Estado que falta** — se cubre un conjunto de estados y falta uno, así que ese cae a
   un default que contradice al resto. Se tematizan `border`, `enabledBorder` y
   `focusedBorder` pero no `errorBorder`; se manejan carga y éxito pero no el error; se
   definen unos roles de color a mano y otros quedan derivados. **Busca el hueco en la
   serie**: es un defecto real y de los más fáciles de ver leyendo solo el diff.
5. **Contrato roto** — firma, tipo de retorno, forma del JSON o clave de config que
   cambia y deja desactualizado a quien llama.
6. **Seguridad** — secreto en el diff, entrada sin validar que llega a una consulta o a
   un comando, permiso que se ensancha.
7. **Limpieza** — repetición, cosas que ya existen en el repo, trabajo desperdiciado.
   Solo si sobra presupuesto: nunca desplaza a lo de arriba.

### La barra: un caso de fallo concreto

Cada hallazgo necesita **un caso de fallo que puedas escribir en una frase**. Si no
sabes escribirlo, no es un hallazgo — es una impresión, y no va al informe.

Pero «concreto» **no significa siempre «una entrada que lo rompe»**. Eso solo aplica a
código imperativo. Mucho de lo que se revisa es declarativo —temas, tokens, config,
schemas, estilos— y **no tiene entradas**: si exiges un input que produzca un crash,
apruebas PRs llenos de defectos reales. Según el tipo de código, el caso de fallo es:

| Tipo de código | El caso de fallo es |
|---|---|
| Lógica, funciones | qué entrada o estado produce qué resultado malo |
| Tema, tokens, estilos | **qué se ve mal y en qué widget o pantalla** |
| Config, schema, manifest | qué deja de arrancar, de resolverse o de validar |
| Declarativo con doc al lado | **qué dice el doc y qué hace el código** |

Un defecto visual o de coherencia no es «limpieza» por no poder crashear: si el usuario
lo ve o contradice la intención escrita, es un hallazgo de pleno derecho.

### 3 · Comprobar solo lo dudoso — hasta 3 vueltas

Abre un archivo **únicamente** cuando el diff solo no permita decidir si algo es un
fallo de verdad. Casos típicos: la función que se llama no está en el diff, o hay que
ver si el que llamaba se actualizó.

Cuando abras, hazlo con puntería: `Read` con `offset`/`limit` sobre la zona, o un
`grep -rn` con la firma exacta. Nada de `Read` de un archivo de 2.000 líneas entero.

Si con 3 archivos no te alcanza para confirmar un hallazgo, **repórtalo como dudoso**
y di qué haría falta mirar. Un dudoso bien etiquetado vale; un dudoso disfrazado de
certeza, no.

### 4 · Informe

Empieza por el veredicto en una línea: **pasa** o **no pasa**, y por qué.

```
## PR #<n> — <título>
**No pasa** · 2 fallos de correctitud, 1 estado que falta
Ronda anterior: <commit de arreglos> — no repito lo que ya cerró

### 🔴 <archivo>:<línea> — <el fallo en una frase>
Falla cuando: <caso concreto según la tabla de arriba> → <resultado malo>
Arreglo: <lo mínimo que lo corrige>

### 🟡 <archivo>:<línea> — <dudoso>
<qué haría falta mirar para confirmarlo>
```

Si algo ya se señaló en una revisión anterior y **sigue sin arreglar**, va marcado como
`↩︎ ya señalado, sigue abierto`. Y si el autor lo arregló a propósito de una forma que
te chirría, eso **no es un hallazgo**: es una discrepancia de criterio. Dilo en una
frase al final y no la cuentes en el veredicto.

Sin hallazgos, el informe es una línea: **pasa**, y qué revisaste. No rellenes con
elogios ni con un resumen del PR — el autor ya sabe lo que escribió.

Cierra siempre diciendo **qué NO miraste** y por qué: archivos fuera de presupuesto,
tests que no corriste, hallazgos que quedaron en dudoso. Una revisión que calla sus
huecos se lee como si lo hubiera cubierto todo.

## Publicar en GitHub

**Por defecto no se publica nada.** El informe se entrega en la conversación y ya.
Comentar en un PR se ve, le llega al autor y no se deshace limpiamente.

Con `--comentar`, y **solo si el veredicto es «no pasa»**, publica un comentario único
con el informe:

```bash
gh pr comment $PR --body-file <archivo>
```

Un comentario con todo, no uno por hallazgo: cinco notificaciones para el autor por una
sola revisión es ruido.

Si el veredicto es «pasa», `--comentar` no publica nada — decirlo en el chat basta.

**Nunca por tu cuenta:** aprobar, mezclar, cerrar, dar por resueltos comentarios de
otros, ni empujar commits al PR. Si te lo piden explícitamente en el mismo mensaje, se
hace; si no, se ofrece en una frase y decide quien te lo encargó.

### Firma

Todo comentario publicado termina con:

```
By: Robin - Revisor PRs
```

Si el repo tiene un jolly roger en `.github/` (`robin-jolly-roger.png` o similar),
añádelo encima de la firma como `![](<ruta relativa>)`. Si no existe, la firma va sola:
no vayas a buscar la imagen ni la generes.

## Errores que cuestan caro

- **Explorar el repo «para tener contexto»** antes de leer el diff. El diff ES el
  contexto. Cada vuelta previa se paga en todas las vueltas siguientes.
- **Revisar dos veces el mismo PR** porque el informe pareció corto. Si no encontraste
  nada, el informe corto es el resultado correcto. Volver a correr la revisión completa
  cuesta lo mismo que la primera.
- **Un `grep` por hallazgo** para «confirmar». Agrupa: un solo `grep -rn` con varios
  patrones alternados (`-e`) es una vuelta, no cinco.
- **Correr los tests sin que te lo pidan.** Es caro en tiempo y en contexto, y no es lo
  que se pidió. Si crees que hacen falta, dilo en el informe.
