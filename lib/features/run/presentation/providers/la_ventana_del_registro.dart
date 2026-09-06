import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/i18n/language_preference.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/core/platform/lo_que_pide_la_pagina.dart';
import 'package:nexus/core/platform/ventana_del_visor.dart';
import 'package:nexus/features/emulators/domain/entities/linea_de_registro.dart';
import 'package:nexus/features/emulators/presentation/providers/registro_del_sistema_providers.dart';
import 'package:nexus/features/run/domain/entities/corrida.dart';
import 'package:nexus/features/run/domain/usecases/el_registro_como_html.dart';
import 'package:nexus/features/run/presentation/providers/corridas_providers.dart';
import 'package:path_provider/path_provider.dart';

/// Quien escribe la página y abre su ventana.
///
/// Es un proveedor y no una llamada directa a [VentanaDelVisor] para que se
/// pueda probar lo de arriba —cuántas veces se pinta, con qué dentro, cuándo se
/// deja de pintar—, que es justo lo que aquí tiene reglas. La ventana de la
/// actividad no lo tiene y por eso no se puede probar; esto no repite esa.
typedef ElPintorDeVentanas =
    Future<void> Function(
      String nombre,
      String html, {
      required bool primeraVez,
    });

final elPintorDeVentanasProvider = Provider<ElPintorDeVentanas>(
  (ref) => _conElVisor,
);

Future<void> _conElVisor(
  String nombre,
  String html, {
  required bool primeraVez,
}) async {
  // **Fuera de la carpeta emparejada, y no por orden.** Escribir dentro del
  // repo dejaría archivos sin trackear en el árbol, y eso lo recoge el resumen
  // de «lo que tocó este encargo».
  final soporte = await getApplicationSupportDirectory();
  await VentanaDelVisor.pinta(
    raiz: soporte.path,
    nombre: nombre,
    html: html,
    primeraVez: primeraVez,
    // Ancha y no muy alta, al revés que la de la actividad: aquí lo que se lee
    // son líneas largas —una traza de Gradle, una excepción con su paquete— y
    // lo que estorba es que se partan.
    ancho: 820,
    alto: 520,
  );
}

/// Los registros, cada uno en su ventana.
///
/// 🔴 **Antes crecían hacia abajo dentro del panel.** Los dos botones eran
/// interruptores con estado del widget que insertaban el volcado en la misma
/// columna: el menú de correr se convertía en un cuadrado con una terminal
/// dentro, y al cerrarlo se perdía hasta el hecho de que estaba abierto. Ahora
/// abren una ventana del sistema, como los documentos y como la actividad de un
/// encargo: se mueve, se deja al lado y no tapa nada.
///
/// **El estado vive aquí y no en el widget** por lo mismo: si la ventana
/// sobrevive al panel, quién está abierta tiene que sobrevivir también, o el
/// botón miente en cuanto se cierra el menú.
class LasVentanasDelRegistro extends Notifier<Set<String>> {
  /// Cada cuánto se repinta como mucho.
  ///
  /// 🔴 **Un `logcat` de un teléfono de verdad son cientos de líneas por
  /// minuto**, y una compilación de Gradle escupe a ráfagas. Escribir el
  /// archivo por cada línea es machacar el disco y pedirle al visor una recarga
  /// por línea, que además deja la página parpadeando. Se junta lo que llegue
  /// en este rato y se escribe una vez.
  static const ritmo = Duration(milliseconds: 300);

  /// A qué se está atento por ventana. Se guardan para poder soltarlas: esto no
  /// es un widget y nadie las cancela por nosotros.
  final _siguiendo = <String, List<ProviderSubscription<Object?>>>{};
  final _pendiente = <String, Timer>{};

  /// De qué es cada ventana abierta, para poder repintarla sin que nadie lo
  /// pida —cuando cambia el filtro, por ejemplo—.
  final _deQue = <String, _DeQueVa>{};

  @override
  Set<String> build() {
    ref.onDispose(() {
      for (final quietas in _siguiendo.values) {
        for (final s in quietas) {
          s.close();
        }
      }
      for (final t in _pendiente.values) {
        t.cancel();
      }
    });
    return const {};
  }

  /// El nombre del archivo, que es la identidad de la ventana: el visor lleva
  /// las suyas por ruta, así que reescribir la misma actualiza la que ya está
  /// delante en vez de abrir otra.
  static String nombreDe(String deviceId, {required bool sistema}) =>
      '${sistema ? 'sistema' : 'registro'}-${_limpio(deviceId)}';

  /// Abrir si estaba cerrada, dejar de seguirla si estaba abierta.
  ///
  /// «Dejar de seguirla» y no «cerrarla»: la ventana es del sistema y **no se
  /// puede cerrar desde aquí** —el visor no expone eso—. Lo que se apaga es el
  /// repintado, que es lo que cuesta. Si de verdad se cerró, el visor lo dice y
  /// se apaga solo; ver [_atiendeLasPeticiones].
  void alterna(Corrida corrida, {required bool sistema}) {
    final nombre = nombreDe(corrida.deviceId, sistema: sistema);
    if (state.contains(nombre)) {
      _soltar(nombre);
      return;
    }
    unawaited(abre(corrida, sistema: sistema));
  }

  Future<void> abre(Corrida corrida, {required bool sistema}) async {
    _atiendeLasPeticiones();
    final nombre = nombreDe(corrida.deviceId, sistema: sistema);
    final yaEstaba = state.contains(nombre);
    _deQue[nombre] = _DeQueVa(corrida, sistema: sistema);
    state = {...state, nombre};

    // El registro del sistema **se escucha a petición**: un `logcat` abierto es
    // un proceso más, un cable ocupado y batería del teléfono. Abrir su ventana
    // es justo la petición, igual que abrir el cuadro lo era antes.
    if (sistema) {
      ref
          .read(registroDelSistemaProvider.notifier)
          .escucha(corrida.deviceId, corrida.plataforma);
    }

    await _pinta(nombre, primeraVez: !yaEstaba);
    if (yaEstaba) return;
    _sigue(nombre, corrida, sistema: sistema);
  }

  void _sigue(String nombre, Corrida corrida, {required bool sistema}) {
    // 🔴 **Se escucha por el contenedor, no con `watch`.** Esto no es un widget:
    // nadie lo reconstruye. `Ref.listen` está pensado para usarse mientras se
    // construye un proveedor, y esto pasa cuando alguien pulsa un botón.
    final quietas = <ProviderSubscription<Object?>>[];

    if (sistema) {
      quietas.add(
        ref.container.listen<List<LineaDeRegistro>>(
          loQueSeVeDelRegistroProvider(corrida.deviceId),
          (_, _) => _alRitmo(nombre),
        ),
      );
    } else {
      // Se mira solo la lista de este dispositivo: el proveedor es un mapa con
      // todas las corridas, y una línea de otra no tiene nada que repintar aquí.
      quietas.add(
        ref.container.listen<Map<String, List<String>>>(registrosProvider, (
          antes,
          ahora,
        ) {
          if (identical(antes?[corrida.deviceId], ahora[corrida.deviceId])) {
            return;
          }
          _alRitmo(nombre);
        }),
      );
    }

    // Y la corrida, para que el indicador se apague al pararla. **Aquí acaba el
    // seguimiento del registro de la corrida**: sin proceso no van a llegar más
    // líneas, y seguir escuchando sería un oyente vivo por cada app que se
    // corrió en la sesión. El del sistema no, que ese sigue hablando aunque la
    // app se haya ido — que es cuando más dice.
    quietas.add(
      ref.container.listen<Map<String, Corrida>>(corridasProvider, (_, ahora) {
        if (ahora.containsKey(corrida.deviceId)) return;
        unawaited(_pinta(nombre, primeraVez: false));
        if (!sistema) _soltar(nombre);
      }),
    );

    _siguiendo[nombre] = quietas;
  }

  /// Junta lo que llegue en [ritmo] y escribe una vez.
  void _alRitmo(String nombre) {
    if (_pendiente.containsKey(nombre)) return;
    _pendiente[nombre] = Timer(ritmo, () {
      _pendiente.remove(nombre);
      if (state.contains(nombre)) unawaited(_pinta(nombre, primeraVez: false));
    });
  }

  Future<void> _pinta(String nombre, {required bool primeraVez}) async {
    final deQue = _deQue[nombre];
    if (deQue == null) return;
    final s = ref.read(stringsProvider);
    final corrida = deQue.corrida;
    final viva = ref.read(corridasProvider).containsKey(corrida.deviceId);

    final html = deQue.sistema
        ? _elDelSistema(corrida, s: s, viva: viva)
        : _elDeLaCorrida(corrida, s: s, viva: viva);

    await ref.read(elPintorDeVentanasProvider)(
      nombre,
      html,
      primeraVez: primeraVez,
    );
  }

  String _elDeLaCorrida(
    Corrida corrida, {
    required NexusStrings s,
    required bool viva,
  }) {
    final lineas = ref.read(registrosProvider)[corrida.deviceId] ?? const [];
    return ElRegistroComoHtml.escribe(
      viva: viva,
      lineas: [for (final linea in lineas) LineaDeLaVentana(linea)],
      textos: TextosDelRegistro(
        titulo: s.runLogs,
        dispositivo: '${corrida.configuracion} · ${corrida.dispositivo}',
        vacio: s.runCompiling,
      ),
    );
  }

  String _elDelSistema(
    Corrida corrida, {
    required NexusStrings s,
    required bool viva,
  }) {
    final filtro = ref.read(filtroDelRegistroProvider);
    final escuchando = ref
        .read(registroDelSistemaProvider.notifier)
        .escuchando(corrida.deviceId);
    final lineas = ref.read(loQueSeVeDelRegistroProvider(corrida.deviceId));

    return ElRegistroComoHtml.escribe(
      viva: escuchando,
      escuchandoEn: corrida.deviceId,
      escuchando: escuchando,
      lineas: [
        for (final linea in lineas)
          LineaDeLaVentana(
            linea.texto,
            etiqueta: linea.etiqueta,
            tono: switch (linea.nivel) {
              NivelDeRegistro.fatal ||
              NivelDeRegistro.error => TonoDeLinea.error,
              NivelDeRegistro.aviso => TonoDeLinea.aviso,
              _ => TonoDeLinea.normal,
            },
          ),
      ],
      textos: TextosDelRegistro(
        titulo: s.runSystemLog,
        dispositivo: corrida.dispositivo,
        vacio: escuchando ? s.runSystemLogWaiting : s.runSystemLogOff,
        // El nivel, como un ciclo y no como una lista: son cuatro pasos y un
        // desplegable para cuatro cosas es más clics que leer.
        nivel: switch (filtro.minimo) {
          NivelDeRegistro.aviso => s.nivelDesdeAvisos,
          NivelDeRegistro.error => s.nivelSoloErrores,
          NivelDeRegistro.fatal => s.nivelSoloFatales,
          _ => s.nivelTodo,
        },
        escucha: s.runSystemLog,
      ),
    );
  }

  /// Lo que piden los enlaces de la página, y lo que dice el visor al cerrarse.
  ///
  /// La página es estática —ni una línea de JavaScript— y sus botones son
  /// enlaces `nexus://`, que el visor intercepta y reenvía. Es la misma tubería
  /// del botón de detener de la ventana de la actividad.
  void _atiendeLasPeticiones() {
    if (_atendiendo) return;
    _atendiendo = true;

    LoQuePideLaPagina.escuchar(ElRegistroComoHtml.que, (ruta) {
      final partes = ruta.split('/').where((p) => p.isNotEmpty).toList();
      switch (partes) {
        case ['nivel']:
          ref.read(filtroDelRegistroProvider.notifier).siguienteNivel();
          _repintaLosDelSistema();
        case ['escucha', final deviceId]:
          final deQue = _deQue[nombreDe(deviceId, sistema: true)];
          if (deQue == null) return;
          ref
              .read(registroDelSistemaProvider.notifier)
              .alterna(deviceId, deQue.corrida.plataforma);
          _repintaLosDelSistema();
      }
    });

    // 🔴 **Cerrar la ventana tiene que apagar el repintado.** Es la única forma
    // de saberlo: nada de esto se entera solo, y sin ello se seguiría
    // escribiendo un archivo cada trescientos milisegundos para una ventana que
    // ya no existe, con el botón del panel diciendo que sigue abierta.
    LoQuePideLaPagina.escuchar('cerrada', (ruta) {
      final archivo = ruta.split('/').last;
      _soltar(archivo.replaceAll('.html', ''));
    });
  }

  bool _atendiendo = false;

  /// Un cambio de filtro o de escucha no llega por ningún proveedor de líneas
  /// —el filtro las quita, no las trae—, así que se repinta a mano.
  void _repintaLosDelSistema() {
    for (final nombre in state) {
      if (_deQue[nombre]?.sistema ?? false) {
        unawaited(_pinta(nombre, primeraVez: false));
      }
    }
  }

  void _soltar(String nombre) {
    if (!state.contains(nombre)) return;
    for (final s
        in _siguiendo.remove(nombre) ??
            const <ProviderSubscription<Object?>>[]) {
      s.close();
    }
    _pendiente.remove(nombre)?.cancel();
    _deQue.remove(nombre);
    state = {...state}..remove(nombre);
  }

  /// El nombre va a una ruta de archivo, así que lo que no sea seguro se cae.
  static String _limpio(String crudo) =>
      crudo.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
}

/// De qué va una ventana abierta.
class _DeQueVa {
  const _DeQueVa(this.corrida, {required this.sistema});

  final Corrida corrida;
  final bool sistema;
}

final lasVentanasDelRegistroProvider =
    NotifierProvider<LasVentanasDelRegistro, Set<String>>(
      LasVentanasDelRegistro.new,
    );
