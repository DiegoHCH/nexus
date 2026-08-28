import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/presentation/state/chat_message.dart';
import 'package:nexus/features/history/data/datasources/local_conversation_store.dart';
import 'package:nexus/features/history/domain/entities/conversation_record.dart';
import 'package:nexus/features/remote/domain/dispatcher.dart';
import 'package:nexus/features/remote/domain/remote_surface.dart';
import 'package:nexus/features/remote/presentation/assistant_surface.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// El banco que faltaba.
///
/// `AssistantSurface` es lo que el teléfono ve del Mac: dieciséis métodos, cada
/// uno leyendo media app a través de proveedores. **Ninguna prueba la construía**
/// —montarla parecía pedir demasiado— así que todo lo que hace se probaba con una
/// superficie *falsa* en `el_despacho_test`, que comprueba cómo se traducen las
/// respuestas pero no si la app produce esas respuestas.
///
/// El agujero se notó cerrando SEC-03: el tope de tamaño de documento se quedó con
/// una comprobación sobre el código —«que se llame a `length()` antes de leer»— en
/// vez de una prueba de verdad. Esto es esa prueba, y de paso el sitio donde
/// escribir las siguientes.
///
/// Resulta que montarla no pedía tanto: la carpeta de documentos sale de las
/// preferencias y la lista se lee del disco, así que con un directorio temporal y
/// unas preferencias falsas la superficie funciona entera.
void main() {
  // Sin binding, `SharedPreferences` no tiene con quién hablar y la carga falla en
  // silencio — y como esa carga se traga sus errores a propósito, el síntoma sería
  // idéntico al del fallo que se está midiendo.
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory documentos;
  late Directory soporte;

  setUp(() {
    documentos = Directory.systemTemp.createTempSync('superficie-documentos');
    // El almacén propio de la app pregunta al sistema dónde vive, y en una prueba
    // no hay sistema: sin esto la lectura no falla, se **cuelga**.
    soporte = Directory.systemTemp.createTempSync('superficie-soporte');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => soporte.path,
        );
    SharedPreferences.setMockInitialValues({
      'flutter.artifacts.folder': documentos.path,
    });
  });

  tearDown(() {
    documentos.deleteSync(recursive: true);
    soporte.deleteSync(recursive: true);
  });

  /// La superficie de verdad, con la app detrás.
  ///
  /// Se pide por su proveedor y no se construye a mano: así se prueba también el
  /// cableado, que es donde se cuelan las cosas.
  AssistantSurface montar() {
    final container = ProviderContainer(
      overrides: [
        // Lo único que se sustituye: leer los perfiles del Mac toca el disco de
        // quien corre la prueba, y aquí no aporta nada.
        claudeProfilesProvider.overrideWith((ref) async => const []),
      ],
    );
    addTearDown(container.dispose);
    return container.read(remoteSurfaceProvider) as AssistantSurface;
  }

  String escribe(String nombre, int bytes) {
    final archivo = File('${documentos.path}/$nombre')
      ..writeAsStringSync('x' * bytes);
    return archivo.path;
  }

  group('pedir un documento', () {
    test('uno normal llega entero', () async {
      final ruta = escribe('informe.md', 100);

      expect(await montar().artifact(ruta), 'x' * 100);
    });

    // SEC-03, y esta es la prueba que faltaba. Antes solo se comprobaba que el
    // código llamara a `length()`; ahora se comprueba lo que pasa.
    test('uno que no cabe se rechaza, y con su tamaño', () async {
      final ruta = escribe('enorme.md', Dispatcher.maxBytesDeDocumento + 1);

      await expectLater(
        montar().artifact(ruta),
        throwsA(
          isA<ArtifactTooLarge>().having(
            (e) => e.bytes,
            'bytes',
            Dispatcher.maxBytesDeDocumento + 1,
          ),
        ),
      );
    });

    // El borde por el lado que importa: rechazar de más deja fuera documentos que
    // sí caben, y el mensaje manda a abrirlos en el Mac sin motivo.
    test('justo en el tope todavía cabe', () async {
      final ruta = escribe('justo.md', Dispatcher.maxBytesDeDocumento);

      expect(
        (await montar().artifact(ruta)).length,
        Dispatcher.maxBytesDeDocumento,
      );
    });

    test('uno que no es texto se dice, no se intenta leer', () async {
      final ruta = escribe('logo.png', 10);

      await expectLater(
        montar().artifact(ruta),
        throwsA(isA<BinaryArtifact>()),
      );
    });

    // Sin esto, el identificador sería una ruta libre y el método se convertiría
    // en «leer cualquier archivo del Mac».
    test('uno que no está en la lista no se lee', () async {
      escribe('informe.md', 10);

      await expectLater(
        montar().artifact('/etc/passwd'),
        throwsA(isA<UnknownConversation>()),
      );
    });

    // El fallo que hizo nacer `cargada`: el teléfono pregunta una vez y se queda
    // con la respuesta, así que leer antes de que la carpeta esté resuelta le
    // daba «no hay documentos» habiendo treinta y seis.
    test('se espera a saber dónde está la carpeta antes de mirar', () async {
      escribe('informe.md', 10);

      // Sin ninguna vuelta de más: es la única forma de reproducirlo.
      final lista = await montar().artifacts();

      expect(lista.map((a) => a.name), contains('informe.md'));
    });
  });

  // Lo que el teléfono enseña como «archivo». Aquí cambió comportamiento al
  // cerrar ESC-03 —el título y los turnos salen ahora de la ficha y no de
  // recorrer los mensajes— y hasta ahora eso solo lo miraba una comprobación
  // sobre el código.
  group('el archivo', () {
    Future<void> guarda(String id, String texto, {int turnos = 1}) =>
        const LocalConversationStore().save(
          ConversationRecord(
            id: id,
            folderPath: '/Users/alguien/proyecto',
            startedAt: DateTime(2026, 8, 20, 10, id.length),
            messages: [
              ChatMessage(author: ChatAuthor.user, text: texto),
              for (var i = 1; i < turnos; i++)
                ChatMessage(author: ChatAuthor.nexus, text: 'lo que sea $i'),
            ],
          ),
        );

    test('el título y los turnos salen de la ficha, sin abrir nada', () async {
      await guarda('c1', 'mira el historial de git', turnos: 4);

      final pagina = await montar().archive();

      expect(pagina.items, hasLength(1));
      expect(pagina.items.single.title, 'mira el historial de git');
      expect(
        pagina.items.single.turns,
        4,
        reason:
            'antes se contaban recorriendo los mensajes, que obligaba a traerlos '
            'todos para pintar una lista',
      );
    });

    test('pagina, y dice desde dónde seguir', () async {
      for (var i = 0; i < 5; i++) {
        await guarda('c$i', 'la numero $i');
      }

      final primera = await montar().archive(limit: 2);

      expect(primera.items, hasLength(2));
      expect(primera.nextCursor, 2);
    });

    test('y la última página no ofrece continuación', () async {
      await guarda('c1', 'la unica');

      expect((await montar().archive()).nextCursor, isNull);
    });

    // La ficha estaba en la lista y detrás no hay nada: para el teléfono es lo
    // mismo que pedir una que no existe.
    test('retomar algo que ya no está se dice, no se calla', () async {
      await expectLater(
        montar().resumeConversation('no-existe'),
        throwsA(isA<UnknownConversation>()),
      );
    });
  });
}
