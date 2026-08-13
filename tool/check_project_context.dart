// Enseña qué contexto se le va a poner a Claude para una carpeta dada, sin
// abrir la app ni gastar un encargo:
//
//   fvm dart run tool/check_project_context.dart ~/personal/nexus
//
// Sirve para lo que este mecanismo tiene de traicionero: cuando no encuentra el
// `ai-context` —porque la carpeta se llama de otra forma, o le falta el mapa—
// **falla en silencio**. El agente arranca sin el contexto de su repo y no hay
// ningún aviso de que le falta. Esto lo hace visible.
import 'package:flutter/foundation.dart';
import 'package:nexus/features/assistant/data/datasources/project_context_data_source.dart';
import 'package:nexus/features/assistant/data/repositories/project_context_prompt.dart';

void main(List<String> args) async {
  if (args.isEmpty) {
    if (kDebugMode) {
      print('Falta la carpeta: dart run tool/check_project_context.dart <ruta>');
    }
    return;
  }

  final leido = await const ProjectContextDataSource().read(args.first);

  if (kDebugMode) {
    print(
    'reglas encontradas (${leido.rules.length}), de la más lejana a la más cercana:',
  );
  }
  for (final file in leido.rules) {
    if (kDebugMode) {
      print('  · ${file.path}  (${file.content.length} caracteres)');
    }
  }
  if (kDebugMode) {
    print('contexto compartido: ${leido.sharedContext?.path ?? 'ninguno'}');
  }

  final texto = ProjectContextPrompt.compose(
    rules: leido.rules,
    sharedContext: leido.sharedContext,
  );
  if (kDebugMode) {
    print('prompt total: ${texto?.length ?? 0} caracteres');
  }
}
