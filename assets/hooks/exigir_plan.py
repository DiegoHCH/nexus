#!/usr/bin/env python3
"""PreToolUse — no se escribe sin un plan firmado.

Un plan «firmado por una persona antes de escribir código» solo significa algo si algo
**se niega** mientras no lo esté. Sin eso es un texto en pantalla: se lee, se ignora, y a
la semana nadie lo escribe. Así que esto deniega la edición, con el motivo.

La fricción es deliberada y es el punto. Lo que compra: que nadie —ni el modelo ni quien
lo maneja— empiece a tocar archivos sin que alguien haya dicho en una frase qué se va a
hacer y por qué.

**Solo actúa donde se pide.** Una carpeta exige plan si existe su marca en la
configuración de la cuenta; en las demás, este hook no hace nada. El mecanismo vive en la
cuenta —es de quien lo instala, no se hereda— y lo enciende la carpeta.

La marca es un JSON en `<CLAUDE_CONFIG_DIR>/nexus-planes/<carpeta>.json`:

    {"carpeta": "/ruta/del/proyecto", "exige": true, "vale": 28800,
     "ramas": {"feat/algo": {"plan": "qué se va a hacer", "firmado": 1756…}}}

La carpeta va **dentro** y se compara resuelta: codificarla en el nombre del archivo hizo
que `/var` y `/private/var` fueran dos carpetas distintas, y el gate dejó pasar sin decir
nada.

**La exigencia es de la carpeta y la firma es de la rama**, y esa división no es un
detalle de implementación: son dos decisiones de plazos distintos. Que un proyecto pida
plan se decide una vez; qué se va a hacer se decide por tarea, y una tarea es una rama.
Con una sola firma por carpeta, cambiar de rama para atender una urgencia borraba el plan
de lo que estabas haciendo, y al volver había que firmar otra vez algo que seguía siendo
verdad.

- `exige: false` o sin archivo → no se pide nada.
- sin entrada para la rama actual, `plan` vacío o `firmado` caducado → se deniega.

Caduca a propósito, y con el mismo criterio que la frase de escritura de Nexus: un permiso
que no caduca deja de ser una decisión y pasa a ser un ajuste que alguien puso una vez. La
jornada y no la hora porque el plazo tiene que durar lo que dura una tarea: con una hora,
dos días de trabajo se firmaban dieciséis veces y la firma se convierte en un trámite.

Formato viejo —la firma suelta en la raíz del archivo, sin `ramas`— se lee como **sin
firmar**: `exige` se respeta y se pide firmar una vez más. Heredarla en todas las ramas
sería justo el fallo que esto viene a arreglar.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time

EVENTO = "PreToolUse"

# Cuánto vale una firma si la marca no dice otra cosa. Una jornada: lo que dura una tarea
# antes de que «lo que iba a hacer» ya no sea lo que se está haciendo. Al día siguiente se
# vuelve a firmar, que es cuando de verdad suele haber cambiado.
VALE_POR = 28800

# La clave donde va la firma de una carpeta que no está en un repositorio. Lleva dos
# puntos porque git los prohíbe en un nombre de rama: así no puede chocar nunca con una.
SIN_RAMA = ":sin-rama"


def _marca(raiz: str) -> dict | None:
    """La marca que manda aquí: la de esta carpeta o la de la más cercana por encima.

    **Cubre lo que hay dentro, y eso no es un extra.** Nexus arranca el encargo *dentro*
    del repo elegido, no en la carpeta emparejada: con una raíz de varios repos, encender
    el interruptor en la raíz y comparar rutas exactas dejaba escribir sin plan en cada
    repo de dentro, en silencio. Medido con el hook de verdad sobre
    `~/Workspace/front-mobile-b2c` el mismo día que se añadió el interruptor.

    Gana la **más cercana**, así que un `exige: false` en un subdirectorio es una excepción
    deliberada a la regla de arriba y no un descuido — si mandara la de más arriba, apagarlo
    en un sitio concreto sería imposible.

    La primera versión nombraba el archivo con un hash de la ruta, y falló en la primera
    prueba de verdad: macOS resuelve `/var` a `/private/var`, así que la marca se guardó
    con un hash y el CLI reportó el otro. El hook no la encontró y **dejó escribir sin
    plan, en silencio** — el peor final posible para esto, porque crees que estás
    protegido.

    Así que no se codifica la ruta en el nombre: la marca **la dice dentro**, y aquí se
    comparan rutas resueltas. Se leen todas las que haya, que son las carpetas que alguien
    encendió a mano: unas pocas, y son archivos de dos líneas.
    """
    base = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.nexus")
    d = os.path.join(base, "nexus-planes")
    if not os.path.isdir(d):
        return None

    porCarpeta: dict[str, dict] = {}
    for nombre in os.listdir(d):
        if not nombre.endswith(".json"):
            continue
        try:
            with open(os.path.join(d, nombre), encoding="utf-8") as f:
                marca = json.load(f)
        except (OSError, json.JSONDecodeError, ValueError):
            continue
        if not isinstance(marca, dict):
            continue
        suya = marca.get("carpeta")
        if isinstance(suya, str) and suya:
            porCarpeta[os.path.realpath(suya)] = marca

    # De la carpeta hacia arriba, y la primera que aparezca decide.
    actual = os.path.realpath(raiz)
    while True:
        if actual in porCarpeta:
            return porCarpeta[actual]
        padre = os.path.dirname(actual)
        if padre == actual:  # la raíz del sistema: se acabó por dónde subir
            return None
        actual = padre


def _rama(raiz: str) -> str:
    """En qué rama está esa carpeta, **con la misma regla que usa la app**.

    Este es el punto donde los dos lados se pueden desalinear sin que nada falle: si la
    app guarda la firma bajo un nombre y esto busca otro, el gate deniega para siempre y
    el motivo es invisible. Por eso la regla es la de `GitDataSource.read` copiada
    literalmente —`--abbrev-ref`, y el commit corto con `HEAD` suelta— y hay una prueba
    que ejecuta los dos lados sobre el mismo repo para que no se separen.

    Se pregunta a git y no se lee `.git/HEAD` a mano por lo de siempre: el caso raro —un
    worktree, un submódulo— lo resuelve git y no un parser nuestro.

    Y se llama **solo si la carpeta exige plan**. En las demás este hook tiene que costar
    lo más parecido a nada: corre en cada edición.
    """

    def git(*args: str) -> str:
        try:
            hecho = subprocess.run(
                ["git", "-C", raiz, *args],
                capture_output=True,
                text=True,
                timeout=5,
            )
        except (OSError, subprocess.SubprocessError):
            return ""
        return hecho.stdout.strip() if hecho.returncode == 0 else ""

    if not git("rev-parse", "--show-toplevel"):
        return SIN_RAMA
    rama = git("rev-parse", "--abbrev-ref", "HEAD")
    if rama and rama != "HEAD":
        return rama
    # `HEAD` suelta: git contesta literalmente «HEAD», que no distingue un commit de otro.
    return git("rev-parse", "--short", "HEAD") or SIN_RAMA


def _denegar(motivo: str) -> None:
    print(
        json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": EVENTO,
                    "permissionDecision": "deny",
                    "permissionDecisionReason": motivo,
                },
                "systemMessage": motivo,
            },
            ensure_ascii=False,
        )
    )


def main() -> None:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        # **Aquí no se deniega por un fallo propio.** Un hook roto que bloquea la edición
        # deja la app inservible y el motivo es invisible: nadie sospecha del hook. Se
        # sale, y el trabajo sigue sin la garantía — que es un mal menor y recuperable.
        return

    raiz = payload.get("cwd") or os.getcwd()
    marca = _marca(raiz)
    if marca is None or not marca.get("exige"):
        return

    rama = _rama(raiz)
    ramas = marca.get("ramas")
    firma = ramas.get(rama) if isinstance(ramas, dict) else None
    if not isinstance(firma, dict):
        firma = {}

    donde = "esta carpeta" if rama == SIN_RAMA else f"la rama «{rama}»"

    plan = str(firma.get("plan") or "").strip()
    if not plan:
        _denegar(
            f"No hay plan firmado para {donde}, y aquí no se escribe sin uno. "
            "La firma no se pone en el chat: se firma en Nexus, en el chip del "
            "compositor que dice PLAN SIN FIRMAR. Escribir «firmado» aquí no vale, "
            "y pedir permiso tampoco — hasta que esa firma exista, esto seguirá "
            "denegando."
        )
        return

    firmado = firma.get("firmado")
    vale = marca.get("vale") or VALE_POR
    if not isinstance(firmado, (int, float)):
        _denegar(
            f"El plan de {donde} no dice cuándo se firmó, así que no se puede "
            "saber si sigue valiendo. Vuelve a firmarlo."
        )
        return

    edad = time.time() - firmado
    if edad > vale:
        horas = int(edad // 3600)
        cuanto = f"{horas} horas" if horas else f"{int(edad // 60)} minutos"
        _denegar(
            f"El plan de {donde} se firmó hace {cuanto} y ya caducó. "
            "Un permiso que no caduca deja de ser una decisión: fírmalo otra vez, o "
            "cámbialo si lo que estás haciendo ya no es lo que decía."
        )
        return

    # Firmado y vigente: no se dice nada. `allow` explícito se saltaría las demás
    # comprobaciones de permisos del CLI, y esto solo tiene autoridad para negar.
    return


if __name__ == "__main__":
    main()
