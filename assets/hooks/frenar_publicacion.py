#!/usr/bin/env python3
"""PreToolUse — no se abre un PR sobre un gate que no lo cubre.

Hasta aquí el gate era información: la barra decía verde o rojo y no pasaba nada. Esto es
lo que lo convierte en una puerta. **Y solo en el PR**, que es la diferencia que importa:
un push queda en una rama y no le cuesta nada a nadie; un PR entra en la cola de revisión
de otra persona, que va a leerlo dando por hecho que las pruebas pasaron. Frenar el push
también sería fricción sin destinatario — y la primera que alguien desactiva.

**Solo actúa donde el repo declara gate.** Sin un `.nexus-pruebas` en el árbol, este hook
no hace nada. El mecanismo vive en la cuenta —es de quien lo instala— y lo enciende el
repositorio, igual que las reglas por capa y que el plan.

Lee lo que Nexus guarda al correr el gate, en
`<CLAUDE_CONFIG_DIR>/nexus-pruebas/<carpeta>.json`:

    {"carpeta": "/ruta", "ramas": {"feat/algo": {
        "resultado": "verde", "huella": "<commit>", "cuando": 1756…,
        "aunque": {"motivo": "…", "huella": "<commit>"}}}}

Y decide así:

- **Sin correr** → se deniega, y no hay excusa que valga. No hay nada que justificar:
  hay algo que hacer, y son dos minutos menos que discutirlo.
- **Rojo** → se deniega. Un rojo no es una caducidad, es una respuesta.
- **Verde que cubre el árbol de ahora** → pasa, sin decir nada.
- **Verde que ya no cubre** → se deniega, salvo que en Nexus se haya escrito un motivo
  para publicar igual. Es la única puerta con llave, y la llave deja constancia.

Lo que este hook **no** puede hacer, y conviene saberlo: meter ese motivo en el cuerpo del
PR. Un `PreToolUse` deniega o deja pasar, no reescribe el comando. Así que el motivo se le
pone delante al modelo como contexto y se le pide que lo incluya — que es advisorio, y es
la única pieza de todo esto que lo es. Si un día importa de verdad, el sitio para
arreglarlo es que Nexus abra el PR él mismo.
"""

from __future__ import annotations

import hashlib
import json
import os
import shlex
import subprocess
import sys

EVENTO = "PreToolUse"
DECLARACION = ".nexus-pruebas"
SIN_RAMA = ":sin-rama"

# Hasta dónde se sube buscando la declaración. El mismo tope que usa Nexus para las
# reglas: más arriba ya no es el proyecto de nadie.
MAX_NIVELES = 6


def _publica(comando: str) -> bool:
    """Si este comando abre un PR.

    Se parten las cadenas —`cd x && gh pr create …`— porque el modelo las escribe así y
    mirar solo el principio dejaría pasar la mitad. Y se compara por tokens y no con un
    `in`: un `echo "gh pr create"` no abre nada, y un mensaje de commit que mencione el
    comando no puede frenar el trabajo.
    """
    for trozo in comando.replace("\n", ";").replace("|", ";").split(";"):
        for pieza in trozo.split("&&"):
            try:
                tokens = shlex.split(pieza)
            except ValueError:
                continue
            if not tokens:
                continue
            programa = os.path.basename(tokens[0])
            # `gh pr create`, con las banderas que sea entre medias.
            if programa == "gh" and "pr" in tokens[1:] and "create" in tokens[1:]:
                return True
    return False


def _carpeta_declarada(desde: str) -> str | None:
    """La carpeta del árbol que declara gate, subiendo desde donde se está.

    Subiendo y no en el sitio exacto porque el encargo puede arrancar en un
    subdirectorio, y el `.nexus-pruebas` vive en la raíz del repo.
    """
    actual = os.path.realpath(desde)
    for _ in range(MAX_NIVELES):
        if os.path.isfile(os.path.join(actual, DECLARACION)):
            return actual
        padre = os.path.dirname(actual)
        if padre == actual:
            return None
        actual = padre
    return None


def _rama(raiz: str) -> str:
    """En qué rama está esa carpeta.

    **La misma regla que la app y que el hook del plan**, copiada a propósito y no
    compartida: cada gancho se instala como un archivo suelto, y un módulo común sería una
    pieza más que puede faltar en una máquina y romper el gancho entero. El precio es que
    tres implementaciones se pueden separar, y por eso hay una prueba que las corre sobre
    el mismo repositorio y exige que digan lo mismo.
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
    return git("rev-parse", "--short", "HEAD") or SIN_RAMA


def _huella(raiz: str) -> str | None:
    """El árbol de ahora mismo, **calculado igual que lo calcula Nexus**.

    Tres cosas deterministas: el commit de `HEAD`, el diff contra él —con `--binary`, para
    que un cambio en un asset también cuente— y el hash del contenido de cada archivo que
    git todavía no sigue, que no sale en ningún diff y es justo lo que escribe un
    asistente.

    Nada de `git stash create`: fabrica un commit y el hash de un commit lleva la hora
    dentro, así que con el árbol sucio da un valor distinto cada vez. Como huella para
    comparar después, eso haría caducar el verde solo.

    La construcción está fijada al byte porque el otro lado está en Dart y no comparten
    código. Si se separan, esto deniega para siempre y el motivo es invisible; hay una
    prueba que corre los dos.
    """

    def git(*args: str, entrada: str | None = None) -> str:
        try:
            hecho = subprocess.run(
                ["git", "-C", raiz, *args],
                capture_output=True,
                text=True,
                input=entrada,
                timeout=20,
            )
        except (OSError, subprocess.SubprocessError):
            return ""
        return hecho.stdout.strip() if hecho.returncode == 0 else ""

    if not git("rev-parse", "--show-toplevel"):
        return None

    material = git("rev-parse", "HEAD") + "\n"
    material += git("diff", "HEAD", "--binary", "--no-color", "--no-ext-diff")

    sin_seguir = [
        linea
        for linea in git("ls-files", "--others", "--exclude-standard").split("\n")
        if linea
    ]
    if sin_seguir:
        hashes = git(
            "hash-object", "--stdin-paths", entrada="\n".join(sin_seguir) + "\n"
        ).split("\n")
        for i, ruta in enumerate(sin_seguir):
            material += f"\n{ruta}:{hashes[i] if i < len(hashes) else ''}"

    return hashlib.sha1(material.encode("utf-8")).hexdigest()


def _corrida(carpeta: str, rama: str) -> dict | None:
    """Lo que Nexus guardó de la última corrida en esa carpeta y esa rama."""
    base = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.nexus")
    d = os.path.join(base, "nexus-pruebas")
    if not os.path.isdir(d):
        return None

    buscada = os.path.realpath(carpeta)
    for nombre in os.listdir(d):
        if not nombre.endswith(".json"):
            continue
        try:
            with open(os.path.join(d, nombre), encoding="utf-8") as f:
                guardado = json.load(f)
        except (OSError, json.JSONDecodeError, ValueError):
            continue
        if not isinstance(guardado, dict):
            continue
        suya = guardado.get("carpeta")
        if not isinstance(suya, str) or os.path.realpath(suya) != buscada:
            continue
        ramas = guardado.get("ramas")
        if not isinstance(ramas, dict):
            return None
        de_la_rama = ramas.get(rama)
        return de_la_rama if isinstance(de_la_rama, dict) else None
    return None


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


def _pasar_con_contexto(texto: str) -> None:
    print(
        json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": EVENTO,
                    "additionalContext": texto,
                }
            },
            ensure_ascii=False,
        )
    )


def main() -> None:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        # Un hook roto no puede dejar la app sin poder trabajar: se sale, y el trabajo
        # sigue sin la garantía. Mal menor y recuperable; lo contrario es invisible.
        return

    entrada = payload.get("tool_input")
    comando = entrada.get("command") if isinstance(entrada, dict) else None
    if not isinstance(comando, str) or not _publica(comando):
        return

    raiz = payload.get("cwd") or os.getcwd()
    carpeta = _carpeta_declarada(raiz)
    if carpeta is None:
        return

    rama = _rama(carpeta)
    donde = "esta carpeta" if rama == SIN_RAMA else f"la rama «{rama}»"
    corrida = _corrida(carpeta, rama)

    if not corrida or corrida.get("resultado") not in ("verde", "rojo"):
        _denegar(
            f"El gate de {donde} no se ha corrido, y un PR entra en la cola de "
            "revisión de otra persona. Córrelo desde Nexus, en el chip de las "
            "pruebas del compositor. No hay forma de saltarse esto escribiendo algo: "
            "no hay nada que justificar, hay algo que hacer."
        )
        return

    if corrida.get("resultado") == "rojo":
        _denegar(
            f"El gate de {donde} está en rojo. Un rojo no es una caducidad que se "
            "pueda justificar: es una respuesta. Arregla lo que falla y vuelve a "
            "correrlo desde Nexus."
        )
        return

    huella = _huella(carpeta)
    if huella and corrida.get("huella") == huella:
        return

    # Verde que ya no cubre lo que hay. Es lo único que se puede saltar, y solo con un
    # motivo escrito en Nexus — que además caduca con el árbol, como el verde.
    aunque = corrida.get("aunque")
    if isinstance(aunque, dict) and huella and aunque.get("huella") == huella:
        motivo = str(aunque.get("motivo") or "").strip()
        if motivo:
            _pasar_con_contexto(
                "Este PR sale con una verificación parcial: el gate pasó, pero sobre un "
                f"árbol anterior. El motivo escrito por una persona es: «{motivo}». "
                "Inclúyelo en el cuerpo del PR bajo un apartado «Verificación parcial» — "
                "quien lo revise tiene que saber que el gate no cubre parte de lo que "
                "está leyendo."
            )
            return

    _denegar(
        f"El gate de {donde} pasó, pero sobre un árbol anterior: hay cambios que no ha "
        "visto nadie. Vuelve a correrlo desde Nexus, o escribe ahí el motivo para "
        "publicar igual — ese motivo viaja al cuerpo del PR, porque quien revise tiene "
        "que saber qué parte no está cubierta."
    )


if __name__ == "__main__":
    main()
