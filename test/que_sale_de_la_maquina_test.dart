import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/history/domain/repositories/conversation_archive.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';
import 'package:nexus/features/workspace/domain/usecases/que_sale_de_la_maquina.dart';

/// ADD-02. Una pantalla que se equivoque sobre esto es peor que no tenerla: se
/// lee como un permiso. Así que la regla se prueba entera.

PairedFolder _carpeta({
  FolderModality modalidad = FolderModality.voice,
  String? cuenta,
}) => PairedFolder(
  path: '/Users/alguien/proyecto',
  modality: modalidad,
  claudeProfile: cuenta,
);

List<PuertaDeSalida> _puertas({
  PairedFolder? carpeta,
  bool hayLlaveDeGemini = true,
  bool vozAbierta = false,
  ArchiveDestination destino = ArchiveDestination.none,
  bool destinoListo = false,
  bool canalEncendido = false,
  bool hayAlguienConectado = false,
  String? direccion,
}) => QueSaleDeLaMaquina.para(
  carpeta: carpeta,
  hayLlaveDeGemini: hayLlaveDeGemini,
  vozAbierta: vozAbierta,
  destinoDeArchivo: destino,
  destinoListo: destinoListo,
  canalEncendido: canalEncendido,
  hayAlguienConectado: hayAlguienConectado,
  direccionDelCanal: direccion,
);

ComoEsta _como(List<PuertaDeSalida> puertas, Salida cual) =>
    puertas.firstWhere((p) => p.cual == cual).como;

void main() {
  // Una lista que solo enseña lo abierto no responde «¿y Notion?», que es justo
  // la pregunta que trae a alguien a mirar esto.
  test('siempre están las cuatro, también las cerradas', () {
    expect(_puertas().map((p) => p.cual), [
      Salida.anthropic,
      Salida.gemini,
      Salida.notion,
      Salida.canal,
    ]);
  });

  group('Anthropic', () {
    // El informe que pidió esta pantalla listaba tres puertas y se dejó la que
    // está siempre abierta.
    test('con una carpeta emparejada, sale en cada encargo', () {
      expect(
        _como(_puertas(carpeta: _carpeta()), Salida.anthropic),
        ComoEsta.abierta,
      );
    });

    test('sin carpeta no hay nada que mandar', () {
      expect(_como(_puertas(), Salida.anthropic), ComoEsta.cerrada);
    });

    test('y dice con qué cuenta', () {
      final puertas = _puertas(carpeta: _carpeta(cuenta: 'work'));
      expect(
        puertas.firstWhere((p) => p.cual == Salida.anthropic).dato,
        'work',
      );
    });
  });

  group('Gemini', () {
    test('con carpeta de voz y llave, puede abrirse', () {
      expect(
        _como(_puertas(carpeta: _carpeta()), Salida.gemini),
        ComoEsta.disponible,
      );
    });

    test('y hablando, está abierta', () {
      expect(
        _como(_puertas(carpeta: _carpeta(), vozAbierta: true), Salida.gemini),
        ComoEsta.abierta,
      );
    });

    // No es solo el micrófono: en solo texto el servicio de voz no participa,
    // porque restringir solo la entrada dejaría la fuga abierta por el otro
    // lado — lo que Claude leyó viaja dentro de la respuesta narrada.
    test('en una carpeta de solo texto, cerrada aunque haya llave', () {
      expect(
        _como(
          _puertas(carpeta: _carpeta(modalidad: FolderModality.textOnly)),
          Salida.gemini,
        ),
        ComoEsta.cerrada,
      );
    });

    // Decir «disponible» sin llave sería prometer algo que al pulsar falla.
    test('sin llave, cerrada aunque la carpeta permita voz', () {
      expect(
        _como(
          _puertas(carpeta: _carpeta(), hayLlaveDeGemini: false),
          Salida.gemini,
        ),
        ComoEsta.cerrada,
      );
    });
  });

  group('Notion', () {
    // Archivar pasa al terminar cada turno: estando configurado esto no es
    // «podría», es que va a pasar en cuanto digas algo.
    test('configurado y listo, salen conversaciones enteras', () {
      expect(
        _como(
          _puertas(destino: ArchiveDestination.notion, destinoListo: true),
          Salida.notion,
        ),
        ComoEsta.abierta,
      );
    });

    test('a medio configurar, no sale nada', () {
      expect(
        _como(_puertas(destino: ArchiveDestination.notion), Salida.notion),
        ComoEsta.cerrada,
      );
    });

    // El vault y la carpeta son disco de este Mac: no son una salida.
    test('archivar en una carpeta o en Obsidian no es salir', () {
      for (final destino in [
        ArchiveDestination.folder,
        ArchiveDestination.obsidian,
      ]) {
        expect(
          _como(_puertas(destino: destino, destinoListo: true), Salida.notion),
          ComoEsta.cerrada,
          reason: destino.name,
        );
      }
    });
  });

  group('el canal', () {
    test('apagado, cerrada', () {
      expect(_como(_puertas(), Salida.canal), ComoEsta.cerrada);
    });

    test('encendido y sin nadie dentro, disponible', () {
      expect(
        _como(_puertas(canalEncendido: true), Salida.canal),
        ComoEsta.disponible,
      );
    });

    test('con alguien dentro, abierta y con su dirección', () {
      final puertas = _puertas(
        canalEncendido: true,
        hayAlguienConectado: true,
        direccion: '100.64.0.1:7845',
      );
      final canal = puertas.firstWhere((p) => p.cual == Salida.canal);

      expect(canal.como, ComoEsta.abierta);
      expect(canal.dato, '100.64.0.1:7845');
    });

    test(
      'apagado no enseña dirección, que sería enseñar una puerta que no está',
      () {
        final canal = _puertas(
          direccion: '100.64.0.1:7845',
        ).firstWhere((p) => p.cual == Salida.canal);

        expect(canal.dato, isNull);
      },
    );
  });
}
