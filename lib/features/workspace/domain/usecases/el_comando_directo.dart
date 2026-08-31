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
