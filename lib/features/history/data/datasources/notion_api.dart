import 'dart:convert';
import 'dart:io';

/// Lo justo de la API de Notion para archivar conversaciones.
///
/// Escrito contra `dart:io` en vez de traer un cliente HTTP: son cuatro
/// llamadas, y una dependencia más para eso no se paga sola.
class NotionApi {
  const NotionApi();

  static const _host = 'api.notion.com';

  /// La versión va en cada petición y **no es opcional**: sin ella la API
  /// responde 400. Fijarla aquí es lo que evita que un cambio del servicio
  /// rompa la app sin avisar.
  static const _version = '2022-06-28';

  /// El identificador que Notion mete al final de la URL de una página: 32
  /// caracteres hexadecimales, con o sin guiones.
  ///
  /// Se acepta la URL entera porque es lo que se puede copiar desde Notion —
  /// pedirle a alguien que extraiga el id a mano es pedirle que se equivoque.
  static String? pageIdFrom(String pageUrlOrId) {
    final match = RegExp(
      r'([0-9a-fA-F]{32})|([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})',
    ).allMatches(pageUrlOrId.trim()).lastOrNull;
    return match?.group(0);
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path,
    String token, {
    Map<String, dynamic>? body,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(method, Uri.https(_host, path));
      request.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
        ..set('Notion-Version', _version)
        ..set(HttpHeaders.contentTypeHeader, 'application/json');
      if (body != null) request.write(jsonEncode(body));

      final response = await request.close();
      final raw = await response.transform(utf8.decoder).join();
      final decoded = raw.isEmpty ? const <String, dynamic>{} : jsonDecode(raw);
      final map = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{};

      if (response.statusCode >= 300) {
        // El mensaje de Notion viaja hacia arriba tal cual: «page not found»
        // y «unauthorized» se arreglan de formas muy distintas, y traducirlos
        // a «no se pudo guardar» le quitaría al usuario justo el dato útil.
        throw NotionException(
          response.statusCode,
          map['message'] as String? ?? raw,
        );
      }
      return map;
    } finally {
      client.close();
    }
  }

  /// La página hija con ese título, si ya existe. Es lo que evita crear una
  /// página nueva del mismo proyecto cada vez que se guarda.
  Future<String?> findChildPage({
    required String token,
    required String parentId,
    required String title,
  }) async {
    final response = await _send(
      'GET',
      '/v1/blocks/$parentId/children?page_size=100',
      token,
    );
    for (final block in response['results'] as List<dynamic>? ?? const []) {
      if (block is! Map<String, dynamic>) continue;
      if (block['type'] != 'child_page') continue;
      final child = block['child_page'] as Map<String, dynamic>?;
      if (child?['title'] == title) return block['id'] as String?;
    }
    return null;
  }

  Future<String> createPage({
    required String token,
    required String parentId,
    required String title,
  }) async {
    final response = await _send(
      'POST',
      '/v1/pages',
      token,
      body: {
        'parent': {'page_id': parentId},
        'properties': {
          'title': [
            {
              'text': {'content': title},
            },
          ],
        },
      },
    );
    final id = response['id'] as String?;
    if (id == null) {
      throw const NotionException(0, 'Notion no devolvió la página creada');
    }
    return id;
  }

  /// Añade bloques al final de una página.
  ///
  /// Se añade en vez de reescribir a propósito: una conversación crece turno a
  /// turno, y reescribirla entera cada vez costaría borrar y recrear todos los
  /// bloques en cada respuesta.
  Future<void> append({
    required String token,
    required String pageId,
    required List<Map<String, dynamic>> blocks,
  }) async {
    if (blocks.isEmpty) return;
    // Notion acepta 100 bloques por petición; con más, corta.
    for (var i = 0; i < blocks.length; i += 100) {
      final slice = blocks.sublist(i, (i + 100).clamp(0, blocks.length));
      await _send(
        'PATCH',
        '/v1/blocks/$pageId/children',
        token,
        body: {'children': slice},
      );
    }
  }

  /// Comprueba que el token sirve y que la página existe, para poder decirlo
  /// en Ajustes en vez de fallar en silencio al primer turno.
  Future<void> check({required String token, required String pageId}) =>
      _send('GET', '/v1/pages/$pageId', token);
}

class NotionException implements Exception {
  const NotionException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'Notion respondió $statusCode: $message';
}
