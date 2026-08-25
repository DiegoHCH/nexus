#!/usr/bin/env python3
"""PreToolUse — pone delante la regla de la capa del archivo que se va a editar.

Existe porque una regla que el modelo *puede* leer se lee la mitad de las veces. Está
medido en este proyecto por el otro lado: un `CLAUDE.md` que manda a buscar las reglas a
otro archivo se cumple una de cada dos, y por eso Nexus las carga en vez de remitir a
ellas. Esto es lo mismo un paso más adentro — la regla llega **en el momento exacto en que
se va a aplicar**, y sabiendo qué archivo se toca.

Es lo único que no se puede hacer desde el encargo: quien decide los archivos es Claude,
después de leerlo. Un hook los ve antes.

No instala nada ni depende de nada: el `python3` que ya trae macOS. Y **no hace nada** en
una carpeta sin `.nexus-reglas` — el mecanismo vive en la cuenta y lo activa el repo.

Formato de `.nexus-reglas`, en la raíz del proyecto:

    # Una ruta sola: se carga siempre, la lee Nexus antes del encargo.
    ~/contexto/proyecto/rules/INDEX.md

    # Con flecha: se inyecta solo cuando se toca algo que encaja.
    **/domain/**        -> ~/contexto/proyecto/rules/dominio.md
    **/presentation/**  -> ~/contexto/proyecto/rules/presentacion.md
"""

from __future__ import annotations

import fnmatch
import json
import os
import sys

EVENTO = "PreToolUse"
ARCHIVO = ".nexus-reglas"

# Tope por edición. La regla entera puede ser enorme y esto viaja **en cada** edición, no
# una vez por encargo: lo que no cabe se recorta y se dice, con la ruta al archivo completo
# para que el modelo lea el detalle si le hace falta.
TOPE = 4000

# Dónde queda constancia de lo inyectado. Sin esto es magia, y la magia no sirve cuando
# algo sale mal: la pregunta «¿por qué ignoró esa regla?» solo se puede contestar si se
# puede ver qué se le puso delante.
#
# **Fuera del repo, siempre.** La primera versión lo dejaba en la raíz del proyecto, y en
# un repo del trabajo eso es un archivo que aparece en `git status` y que alguien acaba
# commiteando. Va junto a la configuración de la cuenta, que es de quien corre esto.
def _registro() -> str:
    base = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.nexus")
    os.makedirs(base, exist_ok=True)
    return os.path.join(base, "nexus-inyecciones.log")


def _ruta_del_archivo(entrada: dict) -> str | None:
    """La ruta que la herramienta va a tocar.

    Se prueban varias claves a propósito: el nombre exacto lo fija el CLI y puede cambiar
    entre versiones. Fallar por un nombre distinto dejaría de inyectar **en silencio**, que
    es el peor final posible para esta pieza.
    """
    for clave in ("file_path", "filePath", "path", "notebook_path"):
        valor = entrada.get(clave)
        if isinstance(valor, str) and valor.strip():
            return valor
    return None


def _reglas(raiz: str) -> list[tuple[str, str]]:
    """Los pares `patrón, ruta` del archivo del proyecto. Sin él, lista vacía."""
    lista = os.path.join(raiz, ARCHIVO)
    if not os.path.isfile(lista):
        return []

    pares: list[tuple[str, str]] = []
    with open(lista, encoding="utf-8") as f:
        for linea in f:
            crudo = linea.strip()
            if not crudo or crudo.startswith("#"):
                continue
            # Sin flecha es una regla de las que Nexus carga siempre, antes del encargo:
            # aquí no se toca. Repetirla en cada edición sería mandarla dos veces.
            if "->" not in crudo:
                continue
            patron, _, destino = crudo.partition("->")
            patron, destino = patron.strip(), destino.strip()
            if patron and destino:
                pares.append((patron, destino))
    return pares


def _encaja(patron: str, ruta_relativa: str, ruta_absoluta: str) -> bool:
    """Se prueba contra la relativa **y** la absoluta.

    Un patrón como `**/domain/**` se escribe pensando en el repo, y quien lo escribe no
    sabe dónde está clonado. Probar las dos evita que el patrón dependa de la máquina.
    """
    return fnmatch.fnmatch(ruta_relativa, patron) or fnmatch.fnmatch(
        ruta_absoluta, patron
    )


def _resolver(destino: str, raiz: str) -> str:
    if destino.startswith("~"):
        return os.path.expanduser(destino)
    if destino.startswith("/"):
        return destino
    return os.path.join(raiz, destino)


def _contenido(ruta: str) -> str | None:
    try:
        with open(ruta, encoding="utf-8") as f:
            texto = f.read()
    except OSError:
        return None
    if not texto.strip():
        return None
    if len(texto) <= TOPE:
        return texto
    return (
        texto[:TOPE]
        + f"\n\n[…recortado. El archivo completo está en `{ruta}`]"
    )


def main() -> None:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        # Un hook que revienta no puede impedir editar: se sale en silencio y el trabajo
        # sigue sin la regla, que es peor que con ella y mucho mejor que un bloqueo.
        return

    raiz = payload.get("cwd") or os.getcwd()
    entrada = payload.get("tool_input") or payload.get("toolInput") or {}
    if not isinstance(entrada, dict):
        return

    ruta = _ruta_del_archivo(entrada)
    if ruta is None:
        return

    pares = _reglas(raiz)
    if not pares:
        return

    absoluta = ruta if ruta.startswith("/") else os.path.join(raiz, ruta)
    relativa = os.path.relpath(absoluta, raiz)

    trozos: list[str] = []
    usadas: list[str] = []
    for patron, destino in pares:
        if not _encaja(patron, relativa, absoluta):
            continue
        resuelta = _resolver(destino, raiz)
        texto = _contenido(resuelta)
        if texto is None:
            # Declarada y ausente: se dice. Un archivo movido o mal escrito produciría
            # trabajo que ignora una regla, y nadie sospecha de un archivo que creía
            # cargado.
            trozos.append(
                f"## Regla declarada que no se encontró\n\n"
                f"`{ARCHIVO}` apunta a `{resuelta}` para `{patron}`, y no está."
            )
            usadas.append(f"{destino} (ausente)")
            continue
        trozos.append(f"## Reglas para `{relativa}` — `{destino}`\n\n{texto}")
        usadas.append(destino)

    if not trozos:
        return

    # Queda constancia antes de emitir: si emitir fallara, lo que importa saber es qué se
    # intentó poner delante.
    try:
        with open(_registro(), "a", encoding="utf-8") as f:
            f.write(f"{raiz}\t{relativa}\t{', '.join(usadas)}\n")
    except OSError:
        pass

    print(
        json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": EVENTO,
                    "additionalContext": "\n\n---\n\n".join(trozos),
                }
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
