import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/artifacts/data/datasources/artifacts_data_source.dart';
import 'package:nexus/features/artifacts/domain/entities/artifact.dart';
import 'package:nexus/features/artifacts/presentation/providers/artifacts_providers.dart';
import 'package:nexus/features/assistant/presentation/providers/lo_que_dejo_el_encargo.dart';
import 'package:nexus/features/workspace/data/datasources/claude_profiles_data_source.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

/// **Qué dejó tocado un encargo**, ahora que vive fuera del controlador.
///
/// 🔴 Punto 2 del repaso: el controlador del asistente tenía **2.458 líneas y
/// seis trabajos dentro**, y era donde aterrizaban todos los incidentes. Esto es
/// uno de los seis, y sale entero porque tiene una costura estrecha: se le
/// pregunta y devuelve datos, sin tocar el estado ni pintar nada.
///
/// Y **por fin se puede probar**: dentro del controlador, comprobar la resta de
/// documentos pedía montar una conversación entera con su Claude de mentira.
class _Cajon extends ArtifactsDataSource {
  const _Cajon(this._rutas);

  /// Lo que hay en el cajón en cada llamada, en orden: la primera es la foto de
  /// «antes» y la segunda la de «después».
  final List<List<String>> _rutas;

  @override
  Future<List<Artifact>> list(
    String directory, {
    Set<String> cuentas = const {},
  }) async {
    final vuelta = _vueltas.length;
    _vueltas.add(cuentas);
    final rutas = vuelta < _rutas.length ? _rutas[vuelta] : _rutas.last;
    return [
      for (final ruta in rutas)
        Artifact(
          path: ruta,
          name: ruta.split('/').last,
          at: DateTime(2026, 9, 9),
        ),
    ];
  }

  static final _vueltas = <Set<String>>[];
}

void main() {
  late Directory cajon;

  setUp(() {
    _Cajon._vueltas.clear();
    cajon = Directory.systemTemp.createTempSync('cajon');
  });
  tearDown(() => cajon.deleteSync(recursive: true));

  ProviderContainer contenedor(List<List<String>> rutas) {
    final c = ProviderContainer(
      overrides: [
        artifactsDataSourceProvider.overrideWithValue(_Cajon(rutas)),
        artifactsFolderProvider.overrideWith(() => _Cajon6(cajon.path)),
        claudeProfilesProvider.overrideWith(
          (ref) async => const [
            ClaudeProfile(
              path: '/Users/alguien/.claude-work',
              name: 'work',
              signedIn: true,
            ),
          ],
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  LoQueDejoElEncargo deLaConversacion(ProviderContainer c) =>
      c.read(loQueDejoElEncargoProvider('c1'));

  test('el documento nuevo es el que no estaba antes', () async {
    final c = contenedor([
      ['/cajon/viejo.html'],
      ['/cajon/viejo.html', '/cajon/nuevo.html'],
    ]);
    final dejo = deLaConversacion(c);

    // Sin carpeta de repo: aquí se mide la mitad de los documentos.
    await dejo.tomaLaMarca(null);

    expect(await dejo.elDocumentoNuevo(), '/cajon/nuevo.html');
  });

  // 🔴 **La marca se consume.** Vale para un encargo: dejarla puesta haría que
  // un turno sin marca comparase contra la del anterior y colgase el documento
  // de aquél de una respuesta que no tiene nada que ver.
  test('y no se cuelga dos veces del turno siguiente', () async {
    final c = contenedor([
      ['/cajon/viejo.html'],
      ['/cajon/viejo.html', '/cajon/nuevo.html'],
    ]);
    final dejo = deLaConversacion(c);
    await dejo.tomaLaMarca(null);

    expect(await dejo.elDocumentoNuevo(), '/cajon/nuevo.html');
    expect(
      await dejo.elDocumentoNuevo(),
      isNull,
      reason: 'sin marca no hay nada que comparar, y eso es lo correcto',
    );
  });

  // 🔴 **`null` no es lo mismo que vacío.** Sin haber tomado la marca, restar
  // contra el vacío hace que **toda** la carpeta parezca recién salida.
  test('sin marca no cuelga nada, aunque el cajón esté lleno', () async {
    final c = contenedor([
      ['/cajon/uno.html', '/cajon/dos.html'],
    ]);

    expect(await deLaConversacion(c).elDocumentoNuevo(), isNull);
  });

  test('si no hay nada nuevo, no hay documento', () async {
    final c = contenedor([
      ['/cajon/viejo.html'],
      ['/cajon/viejo.html'],
    ]);
    final dejo = deLaConversacion(c);
    await dejo.tomaLaMarca(null);

    expect(await dejo.elDocumentoNuevo(), isNull);
  });

  // 🔴 **Las dos fotos, con las mismas reglas.** Aquí había un `.value` sobre un
  // proveedor asíncrono: la de «antes» podía tomarse sin cuentas y la de
  // «después» con ellas, y comparar dos listas sacadas con reglas distintas
  // convierte la diferencia en basura.
  test('las dos fotos se toman con las mismas cuentas', () async {
    final c = contenedor([
      ['/cajon/viejo.html'],
      ['/cajon/viejo.html'],
    ]);
    final dejo = deLaConversacion(c);

    await dejo.tomaLaMarca(null);
    await dejo.elDocumentoNuevo();

    expect(_Cajon._vueltas, hasLength(2));
    expect(_Cajon._vueltas.first, {'work'});
    expect(
      _Cajon._vueltas.last,
      _Cajon._vueltas.first,
      reason: 'dos listas con reglas distintas no se pueden restar',
    );
  });

  // Sin carpeta de documentos no hay nada que mirar, y eso no es un error: es
  // que no se ha elegido dónde guardarlos.
  test('sin cajón elegido, ningún documento', () async {
    final c = ProviderContainer(
      overrides: [
        artifactsDataSourceProvider.overrideWithValue(const _Cajon([[]])),
        artifactsFolderProvider.overrideWith(() => _Cajon6(null)),
        claudeProfilesProvider.overrideWith((ref) async => const []),
      ],
    );
    addTearDown(c.dispose);
    final dejo = c.read(loQueDejoElEncargoProvider('c1'));

    await dejo.tomaLaMarca(null);
    expect(await dejo.elDocumentoNuevo(), isNull);
  });

  // 🔴 **Se desmonta con la conversación**, y sin este guardia quince pruebas
  // se pusieron en rojo con «Cannot use the Ref … after it has been disposed»:
  // todo esto corre con `unawaited` al final de un encargo y lee proveedores
  // después de un `await`.
  test('con la conversación cerrada, no lanza: no hace nada', () async {
    final c = contenedor([
      ['/cajon/viejo.html'],
      ['/cajon/viejo.html', '/cajon/nuevo.html'],
    ]);
    final dejo = deLaConversacion(c);
    await dejo.tomaLaMarca(null);

    c.dispose();

    expect(await dejo.elDocumentoNuevo(), isNull);
  });
}

/// La carpeta de documentos, fijada. La de verdad la lee del disco.
class _Cajon6 extends ArtifactsFolder {
  _Cajon6(this._ruta);

  final String? _ruta;

  @override
  String? build() => _ruta;
}
