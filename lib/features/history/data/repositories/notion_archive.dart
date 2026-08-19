import 'package:nexus/features/assistant/presentation/state/chat_message.dart';
import 'package:nexus/features/history/data/datasources/notion_api.dart';
import 'package:nexus/features/history/domain/entities/conversation_record.dart';
import 'package:nexus/features/history/domain/repositories/conversation_archive.dart';

/// Guarda las conversaciones en Notion, una página por proyecto.
///
/// La forma es la misma que en disco, porque la petición era la misma: las
/// conversaciones se agrupan **por proyecto**. Aquí eso es una página hija por
/// carpeta —`workspace`, `otro-proyecto`— y dentro, una página por
/// conversación. El equivalente al grafo de Obsidian es esa jerarquía: se abre
/// el proyecto y están las suyas, no las de todos.
class NotionArchive implements ConversationArchive {
  NotionArchive({
    required this.token,
    required this.rootPageId,
    required this.pageIds,
    required this.onPageCreated,
    required this.sentMessages,
    required this.onSent,
    this.api = const NotionApi(),
  });

  final String token;

  /// La página donde cuelga todo, la que el usuario pegó.
  final String rootPageId;

  final NotionApi api;

  /// Páginas ya creadas: `proyecto` y `proyecto/conversación` → id de Notion.
  /// Se guarda fuera para que sobreviva a reiniciar la app; si no, cada
  /// arranque crearía páginas nuevas de lo mismo.
  final Map<String, String> pageIds;
  final void Function(String key, String pageId) onPageCreated;

  /// Cuántos mensajes de cada conversación se han mandado ya. Es lo que hace
  /// que guardar turno a turno **añada** lo nuevo en vez de repetir la
  /// conversación entera.
  final Map<String, int> sentMessages;
  final void Function(String key, int count) onSent;

  @override
  Future<void> save(ConversationRecord record) async {
    if (record.isEmpty) return;

    final projectKey = 'proyecto:${record.projectName}';
    final projectPage = await _resolve(
      key: projectKey,
      parentId: rootPageId,
      title: record.projectName,
    );

    final conversationKey = 'chat:${record.id}';
    final conversationPage = await _resolve(
      key: conversationKey,
      parentId: projectPage,
      title: record.title,
    );

    final already = sentMessages[conversationKey] ?? 0;
    final pending = record.messages.skip(already).toList();
    final blocks = pending
        .where((message) => message.text.trim().isNotEmpty)
        .expand(_blocksFor)
        .toList();

    await api.append(token: token, pageId: conversationPage, blocks: blocks);
    onSent(conversationKey, record.messages.length);
  }

  /// Devuelve la página, reutilizando la que haya. Se busca en Notion además de
  /// mirar lo guardado: la app puede haberse reinstalado, y el usuario podría
  /// haber borrado la página a mano.
  Future<String> _resolve({
    required String key,
    required String parentId,
    required String title,
  }) async {
    final known = pageIds[key];
    if (known != null) return known;

    final existing = await api.findChildPage(
      token: token,
      parentId: parentId,
      title: title,
    );
    final id =
        existing ??
        await api.createPage(token: token, parentId: parentId, title: title);
    onPageCreated(key, id);
    return id;
  }

  /// Un mensaje, en bloques de Notion.
  ///
  /// El texto se parte en trozos de 1.800 caracteres porque Notion rechaza
  /// cualquier fragmento de más de 2.000, y una respuesta larga de Claude los
  /// pasa sin despeinarse.
  List<Map<String, dynamic>> _blocksFor(ChatMessage message) {
    final quien = message.author == ChatAuthor.user ? 'Tú' : 'Nexus';
    final comoLoDijo = message.spoken ? ' · por voz' : '';
    return [
      _heading('$quien$comoLoDijo'),
      for (final trozo in _split(message.text.trim())) _paragraph(trozo),
    ];
  }

  static Iterable<String> _split(String text) sync* {
    const limit = 1800;
    for (var i = 0; i < text.length; i += limit) {
      yield text.substring(i, (i + limit).clamp(0, text.length));
    }
  }

  static Map<String, dynamic> _heading(String text) => {
    'object': 'block',
    'type': 'heading_3',
    'heading_3': {
      'rich_text': [
        {
          'type': 'text',
          'text': {'content': text},
        },
      ],
    },
  };

  static Map<String, dynamic> _paragraph(String text) => {
    'object': 'block',
    'type': 'paragraph',
    'paragraph': {
      'rich_text': [
        {
          'type': 'text',
          'text': {'content': text},
        },
      ],
    },
  };
}
