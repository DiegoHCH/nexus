import 'package:nexus/features/run/domain/usecases/protocolo_del_vm_service.dart';

/// Cuándo se para la app sola.
///
/// Los tres modos del VM service, con los nombres que se le dicen por el cable.
/// **`sinDueño` es el que sirve** —una excepción que nadie atrapa es un fallo—;
/// `todas` para en las que el código ya maneja, que en una app de verdad son
/// cientos y paran en sitios que a nadie le interesan.
enum ModoDePausa {
  ninguna('None'),
  sinDueno('Unhandled'),
  todas('All');

  const ModoDePausa(this.comoSeDice);

  final String comoSeDice;
}

/// Qué paso se da al reanudar.
///
/// `Over` sigue en la misma función, `Into` entra en la que se llama y `Out`
/// vuelve a quien llamó. Sin ninguno, se sigue corriendo hasta el próximo
/// motivo para pararse.
enum PasoDelDepurador {
  siguiente('Over'),
  entrar('Into'),
  salir('Out');

  const PasoDelDepurador(this.comoSeDice);

  final String comoSeDice;
}

/// Dónde se paró la app y por qué.
class LaParadaDeLaApp {
  const LaParadaDeLaApp({
    required this.isolate,
    this.excepcion,
    this.funcion,
    this.archivo,
    this.scriptId,
    this.posicion,
    this.linea,
  });

  /// A quién hay que decirle que siga. **Viene en el evento y no se adivina**:
  /// una app de Flutter tiene varios isolates y reanudar el que no es deja la
  /// interfaz congelada sin ningún aviso.
  final String isolate;

  /// La excepción, ya legible: «Bad state: setState() called during build».
  final String? excepcion;

  /// En qué función estaba.
  final String? funcion;

  /// El archivo, tal como lo nombra la VM: `package:app/algo.dart`.
  final String? archivo;

  /// Con qué se le puede pedir el texto del archivo, para traducir [posicion] a
  /// una línea. Ver [ElFrenoDeLaApp.pedirElScript].
  final String? scriptId;

  /// La posición **en caracteres**, que es lo único que da el evento.
  ///
  /// 🔴 **No es una línea, y confundirlas es enseñar un número que no existe.**
  /// El VM service habla de `tokenPos`, un índice en la tabla de posiciones del
  /// script; para saber en qué línea cae hay que pedir el script y buscarla. Ver
  /// [ElFrenoDeLaApp.laLineaDeLaPosicion].
  final int? posicion;

  /// La línea, cuando ya se tradujo.
  final int? linea;

  LaParadaDeLaApp conLaLinea(int? cual) => LaParadaDeLaApp(
    isolate: isolate,
    excepcion: excepcion,
    funcion: funcion,
    archivo: archivo,
    scriptId: scriptId,
    posicion: posicion,
    linea: cual,
  );

  /// Dónde pasó, en una línea: `algo.dart:78 · Algo.build`.
  ///
  /// El archivo **por su nombre y no por su paquete**: en la fila caben unos
  /// treinta caracteres y `package:front_mobile_b2c/features/…/gate.dart` se
  /// corta justo por donde importa.
  String? get donde {
    final nombre = archivo?.split('/').last;
    if (nombre == null) return funcion;
    final conLinea = linea == null ? nombre : '$nombre:$linea';
    return funcion == null ? conLinea : '$conLinea · $funcion';
  }
}

/// El idioma del depurador: pararse, saber dónde se paró y seguir.
///
/// 🔴 **La otra mitad del punto 13 del plan del 4 de septiembre.** Nació
/// opcional, y dejó de serlo a medias el 8: resultó que por el VM service viajan
/// los errores del framework —ver [ElErrorQuePintaLaApp]— y sin él no llegaban.
/// Esa mitad se publicó en la 1.10.0 y **dejó el cable puesto**; esta es la que
/// aprovecha que ya está: el socket, el idioma JSON-RPC y el ciclo de vida
/// estaban escritos y probados.
///
/// Aquí vive solo el idioma —entra texto, sale lo que dice— por lo mismo que en
/// el daemon y en los errores: es la parte con reglas, la que se rompe al añadir
/// algo, y **la única que se puede probar sin una app corriendo**. Un método mal
/// escrito no falla: el VM service contesta un error que nadie mira y la app se
/// queda parada para siempre.
abstract final class ElFrenoDeLaApp {
  /// El canal donde el depurador cuenta las paradas.
  static const canal = 'Debug';

  /// Quiénes hay corriendo dentro de la app. Hace falta porque **el modo de
  /// pausa se pone por isolate**, no por app.
  static String pedirLosIsolates(int id) =>
      ProtocoloDelVmService.peticion(id, 'getVM');

  /// Apuntarse al canal del depurador. Sin esto no llega ninguna parada: igual
  /// que con los errores, hay que pedirlo.
  static String escucharLasParadas(int id) =>
      ProtocoloDelVmService.escuchar(id, canal);

  /// Poner o quitar el freno.
  ///
  /// 🔴 **`setIsolatePauseMode` y no `setExceptionPauseMode`.** El segundo es el
  /// nombre viejo: sigue funcionando y está marcado como obsoleto desde la
  /// versión 3.53 del protocolo, y es el que salía en la ficha del repaso. Se
  /// usa el nuevo, que además admite el resto de modos en la misma llamada.
  static String frenar(
    int id, {
    required String isolate,
    required ModoDePausa cuando,
  }) => ProtocoloDelVmService.peticion(id, 'setIsolatePauseMode', {
    'isolateId': isolate,
    'exceptionPauseMode': cuando.comoSeDice,
  });

  /// Que siga. Sin [paso], hasta el próximo motivo para pararse.
  static String seguir(
    int id, {
    required String isolate,
    PasoDelDepurador? paso,
  }) => ProtocoloDelVmService.peticion(id, 'resume', {
    'isolateId': isolate,
    if (paso != null) 'step': paso.comoSeDice,
  });

  /// El script, para poder traducir la posición a una línea.
  static String pedirElScript(
    int id, {
    required String isolate,
    required String script,
  }) => ProtocoloDelVmService.peticion(id, 'getObject', {
    'isolateId': isolate,
    'objectId': script,
  });

  /// Los isolates que trae la respuesta de [pedirLosIsolates].
  static List<String> losIsolates(Object? respuesta) {
    final resultado = ProtocoloDelVmService.elResultado(respuesta);
    final isolates = resultado?['isolates'];
    if (isolates is! List) return const [];
    return [
      for (final isolate in isolates)
        if (isolate is Map)
          if (isolate['id'] case final String id) id,
    ];
  }

  /// La parada que cuenta esta línea, o `null` si la línea es otra cosa.
  ///
  /// Se leen **las dos** clases de parada que puede pedir alguien desde aquí:
  /// `PauseException` —el freno de las excepciones— y `PauseBreakpoint`, que es
  /// donde acaba un paso. `PauseStart` y `PauseExit` no cuentan: son el arranque
  /// y el final del isolate, y enseñarlos como una parada diría que la app se
  /// detuvo cuando lo que hizo fue nacer.
  static LaParadaDeLaApp? laParada(String linea) {
    final evento = ProtocoloDelVmService.elEvento(linea);
    if (evento == null) return null;
    final clase = evento['kind'];
    if (clase != 'PauseException' &&
        clase != 'PauseBreakpoint' &&
        clase != 'PauseInterrupted' &&
        clase != 'PausePostRequest') {
      return null;
    }

    final isolate = (evento['isolate'] as Map?)?['id'];
    if (isolate is! String) return null;

    final marco = evento['topFrame'];
    final sitio = marco is Map ? marco['location'] : null;
    final script = sitio is Map ? sitio['script'] : null;

    return LaParadaDeLaApp(
      isolate: isolate,
      excepcion: _laExcepcion(evento['exception']),
      funcion: marco is Map
          ? ((marco['function'] as Map?)?['name'] as String?)
          : null,
      archivo: script is Map ? script['uri'] as String? : null,
      scriptId: script is Map ? script['id'] as String? : null,
      posicion: sitio is Map ? sitio['tokenPos'] as int? : null,
    );
  }

  /// El isolate que acaba de seguir, si esta línea lo dice.
  ///
  /// Hace falta para **borrar la parada**: sin esto, la fila seguiría diciendo
  /// «parada en gate.dart:78» con la app corriendo, que es peor que no decir
  /// nada.
  static String? siguio(String linea) {
    final evento = ProtocoloDelVmService.elEvento(linea);
    if (evento == null || evento['kind'] != 'Resume') return null;
    final isolate = (evento['isolate'] as Map?)?['id'];
    return isolate is String ? isolate : null;
  }

  /// En qué línea cae [posicion], según la tabla del script.
  ///
  /// 🔴 **La tabla no es una lista de líneas: es una lista de listas.** Cada
  /// entrada empieza por el número de línea y sigue con pares
  /// `posición, columna`. Lo que hay que buscar es la entrada que contiene esa
  /// posición, y si no está exacta —pasa, porque no toda posición es un token—
  /// vale la mayor que no la pase. Leerlo como un índice daría un número
  /// plausible y equivocado, que es la peor clase de número.
  static int? laLineaDeLaPosicion(Object? respuesta, int? posicion) {
    if (posicion == null) return null;
    final resultado = ProtocoloDelVmService.elResultado(respuesta);
    final tabla = resultado?['tokenPosTable'];
    if (tabla is! List) return null;

    int? mejorLinea;
    var mejorPosicion = -1;
    for (final fila in tabla) {
      if (fila is! List || fila.length < 3) continue;
      final linea = fila.first;
      if (linea is! int) continue;
      // De dos en dos: posición y columna.
      for (var i = 1; i + 1 < fila.length; i += 2) {
        final donde = fila[i];
        if (donde is! int || donde > posicion) continue;
        if (donde > mejorPosicion) {
          mejorPosicion = donde;
          mejorLinea = linea;
        }
      }
    }
    return mejorLinea;
  }

  static String? _laExcepcion(Object? excepcion) {
    if (excepcion is! Map) return null;
    // 🔴 **El texto tal cual, sin pegarle la clase delante.** La primera versión
    // la pegaba —«de qué tipo fue»— y la prueba lo cazó al primer evento de
    // verdad: `valueAsString` de un `StateError` ya es «Bad state: setState()
    // called during build», así que salía «StateError: Bad state: …». Los
    // errores del núcleo de Dart se nombran solos en su texto, y una terminal
    // enseña justo eso.
    //
    // La clase se usa cuando **no** hay texto, que pasa: una instancia
    // cualquiera solo trae `valueAsString` si es un primitivo. «RangeError» es
    // poco, pero es más que nada.
    final texto = excepcion['valueAsString'];
    if (texto is String && texto.trim().isNotEmpty) return texto.trim();
    final clase = (excepcion['class'] as Map?)?['name'];
    return clase is String ? clase : null;
  }
}
