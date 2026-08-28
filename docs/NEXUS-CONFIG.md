# `.nexus/config.json` — lo que un repositorio declara sobre sí mismo

Un archivo, versionado dentro del repositorio, que dice cómo se trabaja en él.
Se revisa en un PR como cualquier otro archivo del repo, y lo hereda quien clone.

Existe porque hasta ahora lo que un repositorio sabe de sí mismo —que
`build_runner` tarda cuatro minutos, que sus flows están en `flows/`, que su
contenido no puede salir hacia un tercero— vivía en las preferencias de **cada**
Mac. Cada persona lo aprendía una vez, a mano, y nadie podía revisarlo.

```json
{
  "soloTexto": true,
  "soloLectura": false,
  "comandosVetados": ["build_runner", "pod install"],
  "carpetaDePruebas": "flows",
  "modelo": "opus",
  "esfuerzo": "high"
}
```

Se busca en la carpeta donde Claude trabaja de verdad —el repo activo, si la
carpeta emparejada es una raíz con varios— y todos los campos son opcionales.

---

## 1 · La regla: esto solo puede apretar

Un archivo que viaja dentro de un repositorio lo escribe **quien haya escrito
ese repositorio**. Clonar no puede ser un permiso.

Así que ningún campo abre nada. Cada uno cae en uno de tres cajones:

| Cajón | Campos | Qué hace |
|---|---|---|
| **Aprieta** | `soloTexto`, `soloLectura`, `comandosVetados` | Solo restringe. Puede apagarte la voz; no puede encenderla. Añade comandos a tu lista de vetados; no quita ninguno. |
| **Manda** | `carpetaDePruebas` | Es un hecho del repositorio, no una opinión tuya, y no abre ninguna puerta: solo dice dónde mirar. Gana a tu ajuste. |
| **Sugiere** | `modelo`, `esfuerzo` | La propuesta del repo para quien no ha elegido. Tu elección explícita gana, porque el cupo que se gasta es el tuyo. |

Lo que **nunca** se lee de aquí: la cuenta de Claude (`claudeProfile`) y el repo
activo. Son rutas del disco de una persona; versionarlas le rompería el arranque
a todos los demás.

En el código, la regla es un solo método —`ConfigDelRepo.aplicarA`— y hay una
prueba de forma que falla si alguna de sus ramas llega a nombrar
`FolderModality.voice`, porque ese es exactamente el camino por el que clonar un
repositorio encendería un micrófono.

## 2 · Lo tuyo no se toca

Nexus mantiene dos vistas del mismo estado y las dos hacen falta:

- **lo efectivo** — ya apretado por el repositorio. Es lo que está en vigor y lo
  que se enseña.
- **lo tuyo** — lo que elegiste en Ajustes. Es lo único que se guarda en el
  disco, y es sobre lo que se edita.

Por eso quitar la regla del repositorio te devuelve **tu** ajuste, no el que te
dejó él. Y por eso cambiar de modelo en un repo que pide solo texto no te borra
la voz que tú habías dado.

En la pantalla de Permisos, lo que declara el repositorio aparece escrito, y los
controles que fija dejan de responder en vez de aceptar el gesto y volver atrás
—que se lee como un fallo y no como un permiso denegado—.

## 3 · Lo que trae mal se avisa, y no se aplica

Una llave que no existe, un tipo que no cuadra, un archivo que no es JSON: se
recoge como aviso y se enseña en Ajustes.

Las dos mitades importan. Aplicarlo sería adivinar; callarlo dejaría a quien
revisa el PR sin saber que su línea no hace nada. Un aviso **nunca** concede
nada: lo que no se entiende, no se aplica.

## 4 · Cuándo se relee

Al arrancar y después de cada cambio de ajustes, con caché por fecha y tamaño.

No lleva vigilancia como las reglas de `CLAUDE.md`. Aquella avisa porque un
cambio ahí puede pedirle a Claude algo nuevo; esto solo puede apretar, así que
releer tarde es quedarse con **más** restricción, nunca con menos.
