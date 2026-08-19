import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nexus/features/updates/domain/repositories/release_feed.dart';

/// La última release publicada en GitHub.
///
/// Sin autenticar a propósito: el repo es público y el endpoint de releases no
/// pide llave. Autenticarlo obligaría a guardar un token para leer algo que
/// cualquiera puede leer, y el límite sin llave —60 peticiones por hora— queda
/// muy por encima de la política de esta app, que mira como mucho una vez cada
/// quince minutos.
class GitHubReleaseFeed implements ReleaseFeed {
  const GitHubReleaseFeed({this.repo = 'DiegoHCH/nexus'});

  final String repo;

  @override
  Future<({String tag, String url})?> latest() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(
        Uri.https('api.github.com', '/repos/$repo/releases/latest'),
      );
      // GitHub pide identificarse de alguna forma; sin esto contesta 403.
      request.headers.set(HttpHeaders.userAgentHeader, 'Nexus');
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');

      final response = await request.close();
      // Un 404 es lo normal **la primera vez**: repo sin ninguna release. No es
      // un error, es «no hay nada con lo que comparar todavía».
      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(await response.transform(utf8.decoder).join());
      if (decoded is! Map<String, dynamic>) return null;
      final tag = decoded['tag_name'] as String?;
      final url = decoded['html_url'] as String?;
      if (tag == null || url == null) return null;
      return (tag: tag, url: url);
    } on Exception catch (error) {
      // Sin red no se sabe, y no saber **no es** estar al día. Se dice arriba
      // devolviendo `null`, y quien lo lea distingue las dos cosas.
      debugPrint('actualizaciones · no se pudo preguntar: $error');
      return null;
    } finally {
      client.close();
    }
  }
}
