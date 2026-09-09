#!/usr/bin/env bash
#
# El suelo de cobertura, **medido donde importa**.
#
# 🔴 Vive en un archivo y no dentro del workflow porque lo miran dos: el CI y
# quien corre el gate en su máquina. Cuando estaba solo en el YAML, el número
# no se podía comprobar en local **de ninguna forma** — así que el suelo era
# una sorpresa que llegaba cinco minutos después de empujar.
#
# El umbral va sobre `domain` y no sobre el total, y eso está decidido con los
# números delante: el agregado engaña —69 % global, 93 % en `domain`, 52 % en
# `core`— y un umbral global se contenta con pruebas de widgets y baja solo con
# que alguien añada una pantalla grande, castigando lo que no toca. Sobre
# `domain` dice lo único que se quiere decir: **la capa donde se decide no
# retrocede**.
#
# 85 y no 93: el margen es para que un caso de uso nuevo y a medio cubrir no
# rompa el CI del PR que lo introduce, no para tolerar que se erosione.
set -uo pipefail

SUELO="${SUELO:-85}"
LCOV="${1:-coverage/lcov.info}"

if [ ! -f "$LCOV" ]; then
  echo "No hay $LCOV: hay que correr «flutter test --coverage» antes." >&2
  exit 1
fi

awk -F: -v suelo="$SUELO" '
  /^SF:/ { dominio = ($2 ~ /\/domain\//) }
  /^LF:/ { t += $2; if (dominio) dt += $2 }
  /^LH:/ { c += $2; if (dominio) dc += $2 }
  END {
    if (t == 0 || dt == 0) {
      print "El informe no trae líneas que contar."
      exit 1
    }
    printf "Cobertura de líneas: **%.1f %%** — %d de %d\n", 100*c/t, c, t
    printf "En `domain`: **%.1f %%** — %d de %d\n", 100*dc/dt, dc, dt
    if (100*dc/dt < suelo) {
      printf "\n**Por debajo del suelo de %d %% en `domain`.**\n", suelo
      exit 1
    }
  }
' "$LCOV"
