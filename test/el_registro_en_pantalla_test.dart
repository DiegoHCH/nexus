import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/emulators/data/datasources/registros_data_source.dart';
import 'package:nexus/features/emulators/domain/entities/emulador.dart';
import 'package:nexus/features/emulators/domain/entities/linea_de_registro.dart';
import 'package:nexus/features/emulators/presentation/providers/registro_del_sistema_providers.dart';

/// El registro del sistema, ya en el estado de la pantalla.
///
/// Lo que se prueba aquí es el ciclo —encender, recibir, apagar— y las dos
/// reglas que se notan cuando fallan: que **lo escuchado se conserva** al
/// apagar, porque si algo se cayó ahí está el motivo; y que un aparato no ve lo
/// del otro.
class _Fuente extends RegistrosDataSource {
  _Fuente(this.controlador);

  /// Por dispositivo: es lo que permite comprobar que no se mezclan.
  final Map<String, StreamController<LineaDeRegistro>> controlador;

  var cancelaciones = 0;

  @override
  Stream<LineaDeRegistro> escuchar({
    required PlataformaEmulador plataforma,
    required String deviceId,
    bool desdeAhora = true,
  }) {
    final c = controlador.putIfAbsent(
      deviceId,
      () => StreamController<LineaDeRegistro>(),
    );
    c.onCancel = () => cancelaciones++;
    return c.stream;
  }
}

LineaDeRegistro linea(
  String texto, {
  NivelDeRegistro nivel = NivelDeRegistro.info,
  String etiqueta = 'Tag',
}) => LineaDeRegistro(nivel: nivel, etiqueta: etiqueta, texto: texto);

void main() {
  late _Fuente fuente;
  late ProviderContainer container;

  setUp(() {
    fuente = _Fuente({});
    container = ProviderContainer(
      overrides: [registrosDataSourceProvider.overrideWithValue(fuente)],
    );
    addTearDown(container.dispose);
  });

  ElRegistroDelSistema registro() =>
      container.read(registroDelSistemaProvider.notifier);

  Future<void> asienta() => Future<void>.delayed(Duration.zero);

  test('al encender la lista existe, aunque esté vacía', () async {
    registro().escucha('a', PlataformaEmulador.android);

    expect(
      container.read(registroDelSistemaProvider)['a'],
      isEmpty,
      reason:
          '«escuchando, todavía nada» y «no se ha pulsado» no son lo mismo en '
          'pantalla',
    );
    expect(registro().escuchando('a'), isTrue);
  });

  test('lo que llega se anota', () async {
    registro().escucha('a', PlataformaEmulador.android);
    fuente.controlador['a']!.add(linea('arrancó'));
    await asienta();

    expect(
      container.read(registroDelSistemaProvider)['a']!.single.texto,
      'arrancó',
    );
  });

  test('un aparato no ve lo del otro', () async {
    registro().escucha('a', PlataformaEmulador.android);
    registro().escucha('b', PlataformaEmulador.ios);
    fuente.controlador['a']!.add(linea('de a'));
    fuente.controlador['b']!.add(linea('de b'));
    await asienta();

    final todo = container.read(registroDelSistemaProvider);
    expect(todo['a']!.single.texto, 'de a');
    expect(todo['b']!.single.texto, 'de b');
  });

  test('encender dos veces no abre dos escuchas', () async {
    registro()
      ..escucha('a', PlataformaEmulador.android)
      ..escucha('a', PlataformaEmulador.android);
    await registro().deja('a');

    expect(fuente.cancelaciones, 1);
  });

  // 🔴 Si algo se cayó, el motivo está ahí: borrarlo al apagar es tirar justo lo
  // que se vino a ver.
  test('apagar corta la escucha y conserva lo escuchado', () async {
    registro().escucha('a', PlataformaEmulador.android);
    fuente.controlador['a']!.add(linea('Fatal signal 11'));
    await asienta();
    await registro().deja('a');

    expect(registro().escuchando('a'), isFalse);
    expect(fuente.cancelaciones, 1);
    expect(
      container.read(registroDelSistemaProvider)['a']!.single.texto,
      'Fatal signal 11',
    );
  });

  test('el interruptor enciende y apaga', () async {
    registro().alterna('a', PlataformaEmulador.android);
    expect(registro().escuchando('a'), isTrue);

    registro().alterna('a', PlataformaEmulador.android);
    await asienta();
    expect(registro().escuchando('a'), isFalse);
  });

  // Que la herramienta no esté se lee **en el mismo sitio donde se estaba
  // mirando**, y no en un aviso que tapa la pantalla.
  test('un fallo de la fuente entra como una línea de error', () async {
    registro().escucha('a', PlataformaEmulador.ios);
    fuente.controlador['a']!.addError(
      Exception('No se encontró idevicesyslog'),
    );
    await asienta();

    final ultima = container.read(registroDelSistemaProvider)['a']!.single;
    expect(ultima.nivel, NivelDeRegistro.error);
    expect(ultima.texto, contains('idevicesyslog'));
    expect(
      registro().escuchando('a'),
      isFalse,
      reason: 'sin herramienta no hay nada que seguir escuchando',
    );
  });

  test('no crece sin límite', () async {
    registro().escucha('a', PlataformaEmulador.android);
    for (var i = 0; i < ElRegistroDelSistema.tope + 40; i++) {
      fuente.controlador['a']!.add(linea('línea $i'));
    }
    await asienta();

    final guardadas = container.read(registroDelSistemaProvider)['a']!;
    expect(guardadas, hasLength(ElRegistroDelSistema.tope));
    expect(
      guardadas.last.texto,
      'línea ${ElRegistroDelSistema.tope + 39}',
      reason: 'lo que se tira es lo viejo, no lo último',
    );
  });

  group('el filtro', () {
    test('el nivel es un suelo, y lo que no pasa no se ve', () async {
      registro().escucha('a', PlataformaEmulador.android);
      fuente.controlador['a']!
        ..add(linea('normal'))
        ..add(linea('roto', nivel: NivelDeRegistro.error));
      await asienta();

      container.read(filtroDelRegistroProvider.notifier).siguienteNivel();
      container.read(filtroDelRegistroProvider.notifier).siguienteNivel();

      expect(
        container.read(loQueSeVeDelRegistroProvider('a')).map((l) => l.texto),
        ['roto'],
      );
    });

    // Cuatro y no seis: verboso y depuración son miles de líneas por minuto y
    // nadie las lee a mano.
    test('el botón da la vuelta por los cuatro que se ofrecen', () {
      final filtro = container.read(filtroDelRegistroProvider.notifier);
      final vistos = <NivelDeRegistro>[];

      for (var i = 0; i < 5; i++) {
        vistos.add(container.read(filtroDelRegistroProvider).minimo);
        filtro.siguienteNivel();
      }

      expect(vistos, [
        NivelDeRegistro.info,
        NivelDeRegistro.aviso,
        NivelDeRegistro.error,
        NivelDeRegistro.fatal,
        NivelDeRegistro.info,
      ]);
    });

    test('el texto busca también en la etiqueta', () async {
      registro().escucha('a', PlataformaEmulador.android);
      fuente.controlador['a']!
        ..add(linea('x', etiqueta: 'AndroidRuntime'))
        ..add(linea('y', etiqueta: 'Otra'));
      await asienta();

      container.read(filtroDelRegistroProvider.notifier).buscar('runtime');

      expect(
        container.read(loQueSeVeDelRegistroProvider('a')).map((l) => l.texto),
        ['x'],
      );
    });
  });
}
