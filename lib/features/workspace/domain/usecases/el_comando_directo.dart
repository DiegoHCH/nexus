/// Reconoce cuándo lo que se escribió no es un encargo, sino un comando que se
/// corre aquí mismo.
///
/// Existe porque pedirle a Claude «haz `git status`» es pagar un encargo entero
/// —un proceso, contexto, tokens y unos segundos— para algo que son treinta
/// milisegundos de proceso local. Y porque la respuesta que uno quiere de
/// `git status` es la salida de git, literal, no un resumen de la salida de git.
///
/// ## Por qué `!` y no una lista de frases
///
/// Es la decisión contraria a la del parte, y por el mismo motivo que `/imagen`:
/// «status» es una palabra que aparece en encargos de verdad, así que reconocer
/// por lo que parezca la frase acabaría desviando un encargo legítimo a un
/// comando. Un prefijo que nadie escribe por accidente no tiene ese problema.
///
/// `!` y no `/` porque `/` ya es de los atajos que **sí** hablan con algo de
/// fuera —`/imagen` va a Gemini— y esto es lo contrario: no sale de la máquina.
/// Es además el prefijo que ya significa esto en la terminal de Claude Code, así
/// que no hay una convención nueva que aprender.
abstract final class ElComandoDirecto {
  static const prefijo = '!';

  /// Lo único que se corre por ahora.
  ///
  /// Uno y no una lista abierta: git es el que se pide veinte veces al día, su
  /// binario ya está resuelto y **no hace falta decidir qué NO puede correr**.
  /// Con cualquier binario del PATH esa pregunta pasa a ser una frontera de
  /// seguridad de verdad, y esa se diseña antes de abrirla, no después.
  static const soloEste = 'git';

  /// El comando de un bloque de código que **se puede correr desde aquí**, ya
  /// con su `!` delante, o `null` si ese bloque no es uno de esos.
  ///
  /// 🔴 **Existe porque un comando que se imprime hay que poder correrlo.** El
  /// asistente contesta con el comando en un bloque y lo siguiente que hace
  /// cualquiera es intentar ejecutarlo; hoy toca retranscribirlo, y ahí se
  /// pierde justo la parte que importa. Medido dos días seguidos sobre el mismo
  /// repo: se dijo `git push -u origin <rama>` y se tecleó `git push` a secas,
  /// con dos errores 128 distintos —una rama sin upstream y otra con el upstream
  /// en `main`— por la misma causa.
  ///
  /// **Una sola línea.** Un bloque de tres es un guion, y correr un guion línea
  /// a línea es otra cosa, que se diseña aparte.
  ///
  /// **Y solo lo que ya se sabe correr** —ver [soloEste]—: ofrecer el botón
  /// sobre un `aws sso login` sería ofrecer el «solo puedo git», que es la misma
  /// regla por la que un emulador apagado no aparece en el selector.
  ///
  /// Se acepta el bloque escrito de las dos formas, con `!` y sin él: en la
  /// terminal se escribe sin y aquí se escribe con.
  static String? deUnBloque(String texto) {
    final limpio = texto.trim();
    if (limpio.isEmpty || limpio.contains('\n')) return null;

    final frase = limpio.startsWith(prefijo) ? limpio : '$prefijo$limpio';
    final pedido = deLaFrase(frase);
    if (pedido == null || pedido.comando != soloEste) return null;

    return frase;
  }

  /// Qué se pidió con `!`, o `null` si la frase no llevaba `!` delante.
  ///
  /// Devuelve el comando aparte de sus argumentos **aunque no sea git**: quien
  /// lo recibe necesita poder decir qué se intentó. Tragarse un `!make test` en
  /// silencio se lee como que la app se comió el mensaje, y lo siguiente que
  /// hace uno es escribirlo otra vez.
  static ({String comando, List<String> argumentos})? deLaFrase(String frase) {
    final limpia = frase.trim();
    if (!limpia.startsWith(prefijo)) return null;

    final piezas = enPiezas(limpia.substring(prefijo.length));
    if (piezas.isEmpty) return null;

    return (comando: piezas.first, argumentos: piezas.skip(1).toList());
  }

  /// La salida de git, envuelta para que se lea **como en un editor**.
  ///
  /// La conversación pinta markdown, y su hoja de estilo ya tiene el bloque de
  /// código con monoespaciado, fondo y borde. Sin el cercado, la salida se
  /// pinta como prosa: `git log --oneline` es una tabla —hashes a la izquierda,
  /// mensajes a la derecha— y con salto suave y tipografía proporcional pierde
  /// exactamente lo que la hace legible.
  ///
  /// 🔴 **El cercado se mide, no se asume.** Un mensaje de commit puede llevar
  /// comillas invertidas dentro —y en un repo donde se habla de código, las
  /// lleva— así que un cercado de tres se rompería con el primer `git log` que
  /// las tuviera: el bloque se cerraría a media salida y el resto se pintaría
  /// como prosa suelta. Se cuenta la racha más larga y se pone una más.
  /// El parte de una corrida: qué se enseña, en qué orden, y qué se calla.
  ///
  /// 🔴 **Vivía dentro del controlador y decide más de lo que parece.** Lo de
  /// git va en un bloque monoespaciado porque es lo que se vino a ver —`git log
  /// --oneline` es una tabla y se lee alineada o no se lee— y lo de Nexus va en
  /// prosa alrededor, porque no es salida de nada.
  ///
  /// Las dos reglas que se rompen sin avisar:
  ///
  /// - **Un código distinto de cero con la salida en blanco es un fallo mudo**,
  ///   y eso se lee como que la app no hizo nada. Por eso el aviso del código
  ///   va aunque no haya nada más que enseñar.
  /// - **Y un cero con la salida en blanco no es un fallo**: es que no había
  ///   nada que decir, y decirlo es mejor que dejar la cabecera sola.
  ///
  /// La cabecera va siempre, y ese «siempre» costó un incidente: la primera vez
  /// que esto se usó de verdad contestó sobre un repo que no era el esperado, y
  /// lo único que lo delató fue que el nombre de una rama sonaba a otro
  /// proyecto. Con `!git log` no habría habido ni esa pista.
  static String comoSeCuenta(
    ({int codigo, String salida, bool tardoDemasiado}) hecho, {
    required String cabecera,
    required String tardoDemasiado,
    required String Function(int codigo) fallo,
    required String sinNadaQueDecir,
  }) => [
    '**$cabecera**',
    if (hecho.tardoDemasiado)
      tardoDemasiado
    else ...[
      if (hecho.codigo != 0) fallo(hecho.codigo),
      if (hecho.salida.trim().isEmpty)
        if (hecho.codigo == 0) sinNadaQueDecir else ''
      else
        enBloque(hecho.salida),
    ],
  ].where((linea) => linea.isNotEmpty).join('\n\n');

  static String enBloque(String salida) {
    final cercado = '`' * _laRachaMasLarga(salida);
    // El salto antes del cierre es obligatorio: sin él, una salida sin salto
    // final deja el cercado pegado a la última línea y deja de ser un cercado.
    return '$cercado\n${salida.trimRight()}\n$cercado';
  }

  /// Cuántas comillas invertidas necesita el cercado: una más que la racha más
  /// larga que haya dentro, y nunca menos de tres.
  static int _laRachaMasLarga(String texto) {
    var mayor = 0;
    var actual = 0;
    for (final letra in texto.split('')) {
      if (letra == '`') {
        actual++;
        if (actual > mayor) mayor = actual;
      } else {
        actual = 0;
      }
    }
    return mayor < 3 ? 3 : mayor + 1;
  }

  /// Parte la línea en argumentos, respetando las comillas.
  ///
  /// 🔴 **Las comillas no son un lujo: sin ellas no se puede commitear.** Un
  /// `git commit -m "fix: algo"` partido por espacios le llega a git como seis
  /// argumentos, y git contesta con su ayuda. El primer comando que uno quiere
  /// lanzar desde aquí es justo el que las necesita.
  ///
  /// Se cierran solas al final de la línea: una comilla sin pareja es alguien a
  /// medio escribir, y devolver lo que hay se parece más a lo que quería que
  /// negarse.
  static List<String> enPiezas(String linea) {
    final piezas = <String>[];
    final actual = StringBuffer();
    // Se lleva aparte de `actual.isNotEmpty` porque una pieza puede estar
    // legítimamente vacía: `-m ""` es un mensaje vacío, no la ausencia de un
    // argumento, y git tiene que recibir los dos.
    var empezada = false;
    String? comilla;

    for (final letra in linea.split('')) {
      if (comilla != null) {
        if (letra == comilla) {
          comilla = null;
        } else {
          actual.write(letra);
        }
        continue;
      }
      if (letra == '"' || letra == "'") {
        comilla = letra;
        empezada = true;
        continue;
      }
      if (letra.trim().isEmpty) {
        if (empezada) {
          piezas.add(actual.toString());
          actual.clear();
          empezada = false;
        }
        continue;
      }
      actual.write(letra);
      empezada = true;
    }
    if (empezada) piezas.add(actual.toString());

    return piezas;
  }
}
