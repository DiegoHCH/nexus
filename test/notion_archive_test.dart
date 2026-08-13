import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/presentation/state/chat_message.dart';
import 'package:nexus/features/history/data/datasources/notion_api.dart';
import 'package:nexus/features/history/data/repositories/notion_archive.dart';
import 'package:nexus/features/history/domain/entities/conversation_record.dart';

/// Notion, sin red: se apunta lo que se le habría pedido.
class _FakeApi implements NotionApi {
  final creadas = <String>[];
  final anexados = <Map<String, dynamic>>[];
  final existentes = <String, String>{};
  var _next = 0;

  @override
  Future<String?> findChildPage({
    required String token,
    required String parentId,
    required String title,
  }) async => existentes['$parentId/$title'];

  @override
  Future<String> createPage({
    required String token,
    required String parentId,
    required String title,
  }) async {
    creadas.add('$parentId/$title');
    final id = 'pagina-${_next++}';
    existentes['$parentId/$title'] = id;
    return id;
  }

  @override
  Future<void> append({
    required String token,
    required String pageId,
    required List<Map<String, dynamic>> blocks,
  }) async => anexados.addAll(blocks);

  @override
  Future<void> check({required String token, required String pageId}) async {}
}

ConversationRecord record({
  String id = 'c1',
  String folder = '/Users/alguien/workspace',
  List<ChatMessage>? messages,
}) => ConversationRecord(
  id: id,
  folderPath: folder,
  startedAt: DateTime(2026, 8, 12),
  messages:
      messages ??
      const [
        ChatMessage(author: ChatAuthor.user, text: 'mira el historial'),
        ChatMessage(author: ChatAuthor.nexus, text: 'tres commits sin subir'),
      ],
);

NotionArchive archiveWith(
  _FakeApi api, {
  Map<String, String>? pages,
  Map<String, int>? sent,
}) {
  final pageIds = pages ?? <String, String>{};
  final sentMessages = sent ?? <String, int>{};
  return NotionArchive(
    token: 'ntn_x',
    rootPageId: 'raiz',
    api: api,
    pageIds: pageIds,
    onPageCreated: (key, id) => pageIds[key] = id,
    sentMessages: sentMessages,
    onSent: (key, count) => sentMessages[key] = count,
  );
}

void main() {
  group('la URL que pega el usuario', () {
    // Se acepta la URL entera porque es lo que se puede copiar de Notion:
    // pedir el id a mano es pedir que se equivoque.
    test('el id sale de una URL normal', () {
      expect(
        NotionApi.pageIdFrom(
          'https://www.notion.so/Mis-notas-1f2e3d4c5b6a7988990a1b2c3d4e5f60',
        ),
        '1f2e3d4c5b6a7988990a1b2c3d4e5f60',
      );
    });

    test('también con guiones, y también pegando solo el id', () {
      expect(
        NotionApi.pageIdFrom('1f2e3d4c-5b6a-7988-990a-1b2c3d4e5f60'),
        '1f2e3d4c-5b6a-7988-990a-1b2c3d4e5f60',
      );
      expect(
        NotionApi.pageIdFrom('1f2e3d4c5b6a7988990a1b2c3d4e5f60'),
        '1f2e3d4c5b6a7988990a1b2c3d4e5f60',
      );
    });

    test('cualquier otra cosa no es una página', () {
      expect(NotionApi.pageIdFrom(''), isNull);
      expect(NotionApi.pageIdFrom('https://www.notion.so/mis-notas'), isNull);
    });
  });

  group('lo que se crea en Notion', () {
    // Lo mismo que se pidió para Obsidian, con la forma de Notion: cada
    // proyecto su sitio, y dentro sus conversaciones.
    test('una página por proyecto, y la conversación dentro', () async {
      final api = _FakeApi();

      await archiveWith(api).save(record());

      expect(api.creadas, ['raiz/workspace', 'pagina-0/mira el historial']);
    });

    test('dos proyectos no se mezclan', () async {
      final api = _FakeApi();
      final archive = archiveWith(api);

      await archive.save(record());
      await archive.save(
        record(
          id: 'c2',
          folder: '/Users/alguien/otro',
          messages: const [
            ChatMessage(author: ChatAuthor.user, text: 'algo del otro'),
          ],
        ),
      );

      expect(api.creadas, contains('raiz/workspace'));
      expect(api.creadas, contains('raiz/otro'));
    });

    test('si la página del proyecto ya existe, se reutiliza', () async {
      final api = _FakeApi()..existentes['raiz/workspace'] = 'ya-existia';

      await archiveWith(api).save(record());

      expect(api.creadas, isNot(contains('raiz/workspace')));
      expect(api.creadas.single, startsWith('ya-existia/'));
    });

    // Guardar ocurre al terminar cada turno: si se mandara la conversación
    // entera cada vez, la página acabaría con todo repetido cinco veces.
    test('el segundo turno solo sube lo nuevo', () async {
      final api = _FakeApi();
      final pages = <String, String>{};
      final sent = <String, int>{};

      await archiveWith(api, pages: pages, sent: sent).save(record());
      final trasElPrimero = api.anexados.length;

      await archiveWith(api, pages: pages, sent: sent).save(
        record(
          messages: const [
            ChatMessage(author: ChatAuthor.user, text: 'mira el historial'),
            ChatMessage(
              author: ChatAuthor.nexus,
              text: 'tres commits sin subir',
            ),
            ChatMessage(author: ChatAuthor.user, text: 'súbelos'),
          ],
        ),
      );

      // Un encabezado y un párrafo del mensaje nuevo, y nada más.
      expect(api.anexados.length, trasElPrimero + 2);
    });

    test(
      'una respuesta larguísima se parte en trozos que Notion acepte',
      () async {
        final api = _FakeApi();

        await archiveWith(api).save(
          record(
            messages: [
              const ChatMessage(
                author: ChatAuthor.user,
                text: 'resume el repo',
              ),
              ChatMessage(author: ChatAuthor.nexus, text: 'x' * 5000),
            ],
          ),
        );

        final parrafos = api.anexados.where((b) => b['type'] == 'paragraph');
        for (final bloque in parrafos) {
          final texto =
              ((bloque['paragraph'] as Map)['rich_text'] as List).first
                  as Map<String, dynamic>;
          expect(
            ((texto['text'] as Map)['content'] as String).length,
            lessThanOrEqualTo(2000),
          );
        }
      },
    );

    test('una conversación vacía no crea nada', () async {
      final api = _FakeApi();

      await archiveWith(api).save(record(messages: const []));

      expect(api.creadas, isEmpty);
      expect(api.anexados, isEmpty);
    });
  });
}
