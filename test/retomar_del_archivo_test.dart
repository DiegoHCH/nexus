import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/domain/entities/conversation.dart';
import 'package:nexus/features/assistant/presentation/providers/assistant_controller.dart';
import 'package:nexus/features/assistant/presentation/providers/claude_bridge_providers.dart';
import 'package:nexus/features/assistant/presentation/providers/conversations_providers.dart';
import 'package:nexus/features/assistant/domain/repositories/conversation_memory.dart';
import 'package:nexus/features/assistant/presentation/state/chat_message.dart';
import 'package:nexus/features/history/domain/entities/conversation_record.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';
import 'package:nexus/features/workspace/domain/entities/workspace.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Retomar una del archivo teniendo otra delante.
///
/// Lo que pasaba: la conversación elegida se abría **en la que ya tenías** y la
/// modificaba. Una conversación viva se guarda en el archivo desde su primer turno, así
/// que la de la lista puede ser exactamente la que estás mirando — y abrirla otra vez
/// creaba una segunda pestaña escribiendo en el mismo registro.

const _carpeta = '/Users/alguien/General';
const _otra = '/Users/alguien/personal/nexus';

class _SinMemoria implements ConversationMemory {
  const _SinMemoria();
  @override
  Future<FolderMemory> read(String folderPath, {String? claudeProfile}) async =>
      const FolderMemory();
  @override
  Future<void> rememberSession(
    String folderPath,
    String sessionId, {
    String? claudeProfile,
  }) async {}
  @override
  Future<void> rememberPrompt(String folderPath, String prompt) async {}
  @override
  Future<void> forget(String folderPath) async {}
}

class _Espacio extends WorkspaceController {
  @override
  Workspace build() => Workspace(
    folders: [
      PairedFolder(path: _carpeta, modality: FolderModality.voice),
      PairedFolder(path: _otra, modality: FolderModality.voice),
    ],
    activePath: _otra,
  );
}

ConversationRecord _registro(String id) => ConversationRecord(
  id: id,
  folderPath: _carpeta,
  startedAt: DateTime(2026, 8, 24, 8),
  messages: const [
    ChatMessage(author: ChatAuthor.user, text: 'ordena la casa'),
  ],
);

ProviderContainer _contenedor() {
  final c = ProviderContainer(
    overrides: [
      conversationMemoryProvider.overrideWithValue(const _SinMemoria()),
      workspaceControllerProvider.overrideWith(_Espacio.new),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('la que ya está abierta se enfoca, no se duplica', () async {
    final c = _contenedor();
    final abierta = await c.read(conversationsProvider.notifier).open(_carpeta);
    // Esa pestaña adopta el registro, que es lo que hace al guardarse.
    c
        .read(assistantControllerProvider(abierta!).notifier)
        .resume(_registro('r1'));
    final otra = await c.read(conversationsProvider.notifier).open(_carpeta);

    // Con el foco en la otra, se retoma la del archivo que ya estaba abierta.
    c.read(conversationsProvider.notifier).focus(otra!);
    final resultado = await c.read(retomarDelArchivoProvider)(_registro('r1'));

    expect(resultado, RetomarResultado.yaEstaba);
    expect(c.read(conversationsProvider).items, hasLength(2));
    expect(
      c.read(conversationsProvider).focusedId,
      abierta,
      reason: 'se va a la suya en vez de escribir en la que estabas mirando',
    );
  });

  test('una que no está abierta se abre en pestaña nueva', () async {
    final c = _contenedor();
    final primera = await c.read(conversationsProvider.notifier).open(_carpeta);
    c
        .read(assistantControllerProvider(primera!).notifier)
        .resume(_registro('r1'));

    final resultado = await c.read(retomarDelArchivoProvider)(_registro('r2'));

    expect(resultado, RetomarResultado.enPestanaNueva);
    expect(c.read(conversationsProvider).items, hasLength(2));
    // Y la que ya tenías **no se toca**: era el fallo original.
    expect(
      c.read(assistantControllerProvider(primera).notifier).isShowing('r1'),
      isTrue,
    );
  });

  test(
    'el caso reportado: abierta en una carpeta, se retoma una de otra',
    () async {
      // Tal cual lo describio: una sola conversacion abierta sobre `nexus`, se abre el
      // historial y se elige una de `General`. Tiene que salir en **pestaña nueva** y
      // sobre su propia carpeta — no cambiar la que estaba delante.
      final c = _contenedor();
      final abierta = await c.read(conversationsProvider.notifier).open(_otra);
      c
          .read(assistantControllerProvider(abierta!).notifier)
          .resume(
            ConversationRecord(
              id: 'la-de-nexus',
              folderPath: _otra,
              startedAt: DateTime(2026, 8, 24, 7),
              messages: const [
                ChatMessage(
                  author: ChatAuthor.user,
                  text: 'de que trata el proyecto',
                ),
              ],
            ),
          );

      final resultado = await c.read(retomarDelArchivoProvider)(
        ConversationRecord(
          id: 'la-de-general',
          folderPath: _carpeta,
          startedAt: DateTime(2026, 8, 24, 8),
          messages: const [
            ChatMessage(
              author: ChatAuthor.user,
              text: 'que reuniones tengo hoy',
            ),
          ],
        ),
      );

      expect(resultado, RetomarResultado.enPestanaNueva);
      final items = c.read(conversationsProvider).items;
      expect(
        items,
        hasLength(2),
        reason: 'la de otra carpeta abre pestaña propia',
      );
      expect(
        items.map((i) => i.folderPath),
        containsAll([_otra, _carpeta]),
        reason: 'y sobre SU carpeta, no sobre la que estaba abierta',
      );
      // Y la que estaba delante **no se toca**: es el fallo reportado.
      expect(
        c
            .read(assistantControllerProvider(abierta).notifier)
            .isShowing('la-de-nexus'),
        isTrue,
      );
    },
  );

  test('con el muelle lleno se dice, no se calla', () async {
    final c = _contenedor();
    for (var i = 0; i < Conversations.max; i++) {
      expect(
        await c.read(conversationsProvider.notifier).open(_carpeta),
        isNotNull,
      );
    }

    final resultado = await c.read(retomarDelArchivoProvider)(
      _registro('nueva'),
    );

    expect(resultado, RetomarResultado.noCabe);
  });

  test('caben seis, en columnas de tres', () {
    // El tope estuvo en tres por atención, y el uso lo corrigió: se dejan corriendo y
    // se vuelve a ellas. Seis y no siete por la rejilla — un número que no sea
    // múltiplo deja una columna coja.
    expect(Conversations.max, 6);
    expect(Conversations.max % Conversations.porColumna, 0);
  });
  test('todos los sitios que abren el historial pasan por el proveedor', () {
    // **El fallo que costó tres rondas.** Hay dos sitios que abren la hoja del
    // historial —el menú de macOS y el atajo de la pantalla— y solo se arreglo uno. El
    // otro seguia llamando a `controller.resume`, que pinta el registro elegido dentro
    // de la conversacion que tienes delante: eliges una de otra carpeta y te cambia la
    // que estabas mirando, con las dos escribiendo en el mismo registro.
    //
    // Se comprueba leyendo los archivos porque lo que hay que atar es que **no quede
    // ninguno suelto**, y eso no lo ve una prueba de un camino concreto.
    final sitios = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where(
          (f) => f.readAsStringSync().contains('ConversationHistorySheet.open'),
        )
        .toList();

    expect(
      sitios,
      hasLength(2),
      reason: 'si aparece un tercero, tiene que decidir igual',
    );

    for (final sitio in sitios) {
      final fuente = sitio.readAsStringSync();
      final desde = fuente.indexOf('ConversationHistorySheet.open');
      final trozo = fuente.substring(desde, fuente.indexOf('onForget', desde));
      expect(
        trozo,
        contains('retomarDelArchivoProvider'),
        reason:
            '${sitio.path.split('/').last} elige sin pasar por el proveedor: '
            'volvera a escribir en la conversacion que este delante',
      );
      expect(trozo, isNot(contains('onPick: controller.resume')));
    }
  });
  test('el telefono retoma por el mismo camino que el escritorio', () {
    // **El tercer camino**, y el que faltaba: la superficie remota abria la carpeta y
    // nunca pintaba el registro, asi que el telefono retomaba una conversacion del
    // historial y la recibia vacia. Mismo patron que ya paso tres veces hoy — varios
    // sitios haciendo lo mismo y solo uno arreglado.
    final superficie = File(
      'lib/features/remote/presentation/assistant_surface.dart',
    ).readAsStringSync();
    final desde = superficie.indexOf('Future<String> resumeConversation');
    final cuerpo = superficie.substring(
      desde,
      superficie.indexOf('\n  }\n', desde),
    );

    expect(
      cuerpo,
      contains('retomarDelArchivoProvider'),
      reason: 'sin el proveedor, el telefono abre la carpeta y no pinta nada',
    );
    expect(
      cuerpo,
      isNot(contains('conversationsProvider.notifier)\n          .open(')),
      reason: 'abrir la carpeta a mano es lo que dejaba la conversacion vacia',
    );
  });
}
