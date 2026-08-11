---
name: revisar-y-subir
description: >
  Revisión LOCAL de lo que llevas hecho —working tree y commits de la rama contra
  la rama base del repo— y, si pasa, subirlo. Un solo agente, sin GitHub de por medio para revisar
  y con una única confirmación antes de tocar el remoto. Barata por diseño: una llamada
  para recoger todo el contexto y tope de vueltas.
  Úsala cuando te pidan revisar los cambios, revisar la rama, ver qué llevas hecho,
  revisar antes de subir, o revisar y subir. NO es para revisar un PR ya abierto en
  GitHub: para eso está `revisar-pr`.
allowed-tools: Read, Glob, Grep, Bash
---

# Revisar lo local y subir

Revisión de la rama actual contra su **rama base**, **sin abrir nada en GitHub**, y con el
`git push` como único paso que toca el mundo exterior.

Dos ideas sostienen el flujo: **una sola parada** —en la primera fase; de ahí en adelante
todo informa y sigue, nunca bloquea— y **una confirmación única** antes de tocar el
remoto, en vez de una pregunta por paso.

## Presupuesto

Barata es un requisito, no un deseo. El gasto de una revisión **no está en leer el
diff** —eso es una lectura y es barato— sino en que **cada llamada a una herramienta
vuelve a leer todo el contexto acumulado**. Veinte llamadas pagan el contexto veinte
veces. De ahí los topes:

| | Tope |
|---|---|
| Subagentes | **0** — nunca uses la herramienta Agent |
| Vueltas de herramienta | **3** para revisar: 1 recoger + 1 comprobar + 1 de margen |
| Archivos abiertos aparte del diff | **0 por defecto** — ver Fase 3 antes de abrir nada |
| Hallazgos reportados | los **7** más graves |

Las de subir van aparte y son 1 (`git push`) más la confirmación. Si te acercas al tope
revisando, **cierra el informe con lo que tengas y marca los dudosos** — pasarse del
presupuesto no es un detalle: es justo lo que esta skill existe para evitar.

Si el diff pasa de ~2.000 líneas, dilo, revisa los archivos con más cambios dentro del
presupuesto y marca el informe como **parcial**. No lo compenses gastando más.

## Lo que NO hace

> Revisar es **solo lectura local**: nada de `gh`, nada de red, ni `git fetch`.
> Subir es **solo `git push`** de la rama actual, y solo tras confirmación explícita.
> Nunca: `push --force`, push a la rama base (`develop`/`main`/`master`), crear o mezclar un PR, tocar tags,
> `git reset`, ni commitear cosas que no le dijiste que commiteara.

---

## Fase 1 · Recoger todo — UNA vuelta

Un solo comando. No encadenes `git status`, luego `git log`, luego `git diff`: son tres
vueltas pagando el contexto tres veces.

La rama base la dice el `CONTEXT.md` del repo (`base_branch` en el registry). Si no la
tienes a mano, se deduce por lo que exista: `develop` → `main` → `master`.

```bash
BASE=$(git rev-parse --verify -q develop >/dev/null && echo develop \
    || (git rev-parse --verify -q main >/dev/null && echo main || echo master))
echo "───── BASE: $BASE ─────" \
&& echo "───── RAMA ─────"   && git branch --show-current \
&& echo "───── ESTADO ─────" && git status --short \
&& echo "───── COMMITS ─────" && git log --no-merges $BASE..HEAD --oneline \
&& echo "───── SIN SUBIR ─────" && { git log --oneline @{u}..HEAD 2>/dev/null || echo "(rama sin upstream)"; } \
&& echo "───── DIFF vs $BASE ─────" && git diff $BASE...HEAD \
&& echo "───── SIN COMMITEAR ─────" && git diff HEAD
```

**Revisa las dos cosas**: lo ya commiteado (`$BASE...HEAD`) y lo que sigue en el working
tree (`git diff HEAD`). Lo segundo es justo lo que se suele olvidar y lo que más veces
se sube a medias.

Las llaves alrededor del `git log @{u}..HEAD` no son decoración. Sin ellas, `A && B || C`
se agrupa como `(A && B) || C`, así que el `|| echo "(rama sin upstream)"` se dispara con
el fallo de **cualquier** comando anterior de la cadena: con una base que no existe como
ref local, el informe decía «rama sin upstream» —diagnóstico equivocado— y encima tapaba
la parada que sí correspondía.

**Única parada del flujo.** Detente y dilo si:

- `git branch --show-current` sale **vacía** → estás en **HEAD suelta** (checkout a un
  commit o a un tag): no hay rama que revisar ni que subir. Va primero porque las otras
  comprobaciones no la detectan, y sin ella la Fase 5 acabaría en
  `git push -u origin ""` → `fatal: invalid refspec ''`.
- Estás parado **sobre la propia base** (`$BASE`) → «estás sobre `{rama}`, ponte en una rama de trabajo».
- No hay commits adelante de `$BASE` **ni** cambios sin commitear → nada que revisar.
- No existe ninguna de las tres bases como ref local → dilo; esta skill no hace `fetch`.

Todo lo demás **informa y sigue**. Esta skill nunca bloquea: reporta y tú decides.

## Fase 2 · Leer y decidir — CERO vueltas

Aquí no se llama a nada: el diff ya está en contexto. Busca en este orden:

1. **Correctitud** — lo que se rompe con una entrada concreta. Off-by-one, `null` sin
   guardar, `await` que falta, condición invertida, error tragado, recurso sin cerrar.
2. **Comportamiento que desaparece** — algo que antes pasaba y ya no. No son solo las
   líneas borradas: una línea **añadida** puede apagar comportamiento en toda la app
   (`splashFactory: NoSplash`, `clipBehavior`, `physics: NeverScrollableScrollPhysics`,
   un guard nuevo). **Lista toda propiedad añadida que apague un default** y comprueba
   si algún commit la menciona; si no, es un cambio silencioso y va al informe.
3. **Incoherencia con la intención declarada** — el propio diff fija una regla y el
   código de al lado la rompe: un doc comment que dice «las tarjetas usan 2px» junto a
   un tema que les pone 3px. El caso de fallo es «el archivo dice X y el código hace Y»,
   y la fuente de verdad está dentro del diff: no hace falta salir a comprobar nada.
4. **Estado que falta** — se cubre un conjunto y falta uno, que cae a un default que
   contradice al resto: `border`/`enabledBorder`/`focusedBorder` sin `errorBorder`,
   carga y éxito sin error, unos roles de color a mano y otros derivados del seed.
   **Busca el hueco en la serie.**
5. **Contrato roto** — firma, tipo de retorno, forma del JSON o clave de config que
   cambia y deja desactualizado a quien llama.
6. **Seguridad** — secreto en el diff, entrada sin validar que llega a una consulta o a
   un comando, permiso que se ensancha.
7. **Limpieza** — repetición, cosas que ya existen en el repo. Solo si sobra
   presupuesto: nunca desplaza a lo de arriba.

### La barra: un caso de fallo concreto

Cada hallazgo necesita **un caso de fallo que quepa en una frase**. Si no sabes
escribirlo, no es un hallazgo: es una impresión, y no va al informe.

Pero «concreto» **no significa siempre «una entrada que lo rompe»**. Buena parte del
código que se revisa es declarativo —temas, tokens, widgets, estilos, config, schemas— y
**no tiene entradas**: si exiges un input que produzca un crash, apruebas cambios llenos de
defectos reales. Según el tipo de código:

| Tipo de código | El caso de fallo es |
|---|---|
| Lógica, funciones | qué entrada o estado produce qué resultado malo |
| Tema, tokens, estilos, widgets | **qué se ve mal y en qué pantalla** |
| Config, manifest, schema | qué deja de resolverse, de compilar o de cargar |
| Declarativo con doc al lado | **qué dice el doc y qué hace el código** |

Un defecto visual o de coherencia no es «limpieza» por no poder crashear: si el usuario
lo ve, o contradice la intención escrita, es un hallazgo de pleno derecho.

### Lo propio de cada repo

Esta skill es el **método**. Lo que cambia de un repo a otro —rama base, formato de
commit, qué comando comprueba el código, dónde vive el toolchain— está en el
**`CONTEXT.md` del repo**, que La Oficina te inyecta antes de empezar. Si lo tienes, eso
manda sobre cualquier valor por defecto de aquí.

Dos reglas que valen en todos:

- Un commit que no cumple el formato que pida el repo es un **hallazgo menor**, no un
  bloqueo.
- **No corras la comprobación del proyecto por tu cuenta** (`flutter analyze`, `npm test`,
  `make check`…). Son minutos y mucho contexto, y no es lo que se pidió. Si crees que
  hace falta, dilo en el informe y deja que se decida.

## Fase 3 · Comprobar solo lo dudoso — UNA vuelta

Casi nunca hace falta esta fase. Antes de abrir nada, dos comprobaciones:

**1 · ¿El archivo es nuevo en el diff?** Si aparece como `new file mode` o con `A` en
`--name-status`, **su contenido completo ya está en contexto**: el diff de un archivo
añadido son todas sus líneas. Volver a abrirlo es pagar dos veces por lo mismo, y en una
rama de arranque —donde casi todo es nuevo— eso es casi todo el gasto evitable.

**2 · ¿La respuesta está en otra parte del mismo diff?** Vuelve a leer antes de salir a
buscar. El diff suele traer ya el doc comment, la constante o el llamador que necesitas.

Solo si las dos fallan, abre — y **en una sola vuelta**, juntando todo lo que necesites
comprobar en un único comando. Dos ejemplos de cómo se agrupa:

```bash
# varias cosas en varios archivos, una sola llamada
grep -rn -e "NexusRadius.md" -e "errorBorder" -e "splashFactory" lib/

# regiones concretas de dos archivos, una sola llamada
sed -n '70,95p' lib/a.dart; echo ---; sed -n '10,25p' lib/b.dart
```

Un `grep` por hallazgo son cinco vueltas donde cabía una. Si con esa vuelta no confirmas
algo, **repórtalo como dudoso** y di qué falta mirar: es una respuesta legítima y barata.

## Fase 4 · Informe

Veredicto en la primera línea.

```
## <rama> → <base>
**No pasa** · 1 fallo de correctitud, 1 estado que falta
<n> commits · <n> archivos · <n> cambios sin commitear

### 🔴 <archivo>:<línea> — <el fallo en una frase>
Falla cuando: <caso concreto según la tabla> → <resultado malo>
Arreglo: <lo mínimo que lo corrige>

### 🟡 <archivo>:<línea> — <dudoso>
<qué haría falta mirar para confirmarlo>
```

Sin hallazgos, el informe es una línea: **pasa**, y qué revisaste. No rellenes con
elogios ni resumas el cambio: ya sabes lo que escribiste.

Cierra **siempre** con **qué NO miraste**: archivos fuera de presupuesto, análisis que
no corriste, dudosos sin cerrar. Una revisión que calla sus huecos se lee como si lo
hubiera cubierto todo.

---

## Fase 5 · Subir

**Solo si se pidió subir**, y **siempre con una confirmación**, que es única: se muestra
todo lo que se va a hacer y se ejecuta tras un OK. No una pregunta por paso.

Si el veredicto es **no pasa**, no propongas subir: di qué arreglar. Si aun así te lo
piden explícitamente, se sube — es su decisión, no la tuya.

Antes del OK, muestra exactamente esto:

```
Voy a subir:
  rama:     <rama> → origin/<rama>   (nueva | ya existe)
  commits:  <n> sin subir
  sin commitear: <n> archivos  ← NO se suben
```

Los cambios sin commitear **no se commitean solos**. Si hay, dilo en la confirmación:
se suben los commits y eso se queda fuera. Commitear se hace si te lo piden, con
Conventional Commits y con el alcance que te digan.

Tras el OK:

```bash
git push -u origin "$(git branch --show-current)"
```

`-u` porque la rama puede no tener upstream, y así el siguiente push es directo. Si el
push falla porque el remoto tiene commits que no tienes, **no fuerces y no rebasees por
tu cuenta**: reporta la salida de git tal cual y para.

Cuando termine, di la verdad de lo que quedó: rama subida, cuántos commits, qué se quedó
sin commitear, y —si aplica— que el PR sigue sin abrirse. Abrir el PR no es parte de
esto: si lo quieren, se ofrece en una frase.

## Errores que cuestan caro

- **Explorar el repo «para tener contexto»** antes de leer el diff. El diff ES el
  contexto, y cada vuelta previa se paga en todas las siguientes.
- **Volver a revisar** porque el informe pareció corto. Si no encontraste nada, el
  informe corto es el resultado correcto; repetir cuesta lo mismo que la primera vez.
- **Correr el análisis o los tests sin que te lo pidan.** Caro en tiempo y en contexto.
- **Subir sin mirar el working tree.** Es el error clásico: se suben 3 commits y se
  queda fuera el archivo que los hacía funcionar.
