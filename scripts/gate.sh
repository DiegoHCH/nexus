#!/usr/bin/env bash
#
# El gate, **el mismo que el CI y en el mismo orden**.
#
# 🔴 **Existe porque el gate local no era el gate.** El CI corre seis pasos y en
# local se corrían dos de memoria —`flutter analyze` y `flutter test`—, así que:
#
# - un PR se puso rojo por `dart format`, cinco minutos después de empujar, por
#   un bloque escrito a mano que el formateador quería con otra sangría;
# - las **37 pruebas del paquete del protocolo** no las corría nadie en local, y
#   una de ellas compara el código con `docs/PROTOCOL.md`: si no se ejecuta, el
#   documento y el contrato se separan en silencio;
# - y el suelo de cobertura de `domain` solo se podía comprobar empujando.
#
# El orden **no es decorativo** y viene copiado del workflow con su motivo: las
# dependencias del paquete del protocolo se resuelven **antes** del análisis,
# porque `flutter analyze` desde la raíz analiza también `packages/` y sin
# resolver daba 98 errores de imports que no existen. Eso no se vio en local en
# su día justamente porque el estado local estaba contaminado.
#
# Se corre **todo** y se informa al final, en vez de parar en el primer fallo:
# lo que hace falta antes de empujar es saber cuántos frentes hay abiertos, no
# el primero por orden alfabético.
set -uo pipefail
cd "$(dirname "$0")/.."

paso() {
  local nombre="$1"; shift
  printf '\n\033[1m▶ %s\033[0m\n' "$nombre"
  if "$@"; then
    RESULTADOS+=("ok|$nombre")
    return 0
  fi
  RESULTADOS+=("falló|$nombre")
  return 1
}

RESULTADOS=()

paso "dependencias" flutter pub get
paso "dependencias del protocolo" bash -c 'cd packages/nexus_protocol && dart pub get'
paso "analyze (--fatal-infos)" flutter analyze --fatal-infos
paso "format" dart format --output=none --set-exit-if-changed lib test packages
paso "pruebas del protocolo" bash -c 'cd packages/nexus_protocol && dart test'
paso "pruebas con cobertura" flutter test --coverage
# Solo tiene sentido si hubo informe: sin `lcov.info` esto diría «falta el
# archivo» y sumaría un fallo que ya está contado arriba.
if [ -f coverage/lcov.info ]; then
  paso "suelo de cobertura" ./scripts/cobertura.sh
fi

printf '\n\033[1m═══ RESULTADO DEL GATE ═══\033[0m\n'
malos=0
for r in "${RESULTADOS[@]}"; do
  estado="${r%%|*}"; nombre="${r#*|}"
  if [ "$estado" = ok ]; then
    printf '  \033[32m✔\033[0m %s\n' "$nombre"
  else
    printf '  \033[31m✖\033[0m %s\n' "$nombre"
    malos=$((malos + 1))
  fi
done

if [ "$malos" -gt 0 ]; then
  printf '\n\033[31m%d paso(s) sin pasar. Esto mismo diría el CI.\033[0m\n' "$malos"
  exit 1
fi
printf '\n\033[32mTodo en verde. Es lo que va a decir el CI.\033[0m\n'
