import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/e2e/domain/usecases/los_tags_de_un_flow.dart';

/// La cabecera de un flow real de `global66/automated-test`, copiada tal cual.
const _flowReal = '''
appId: \${APP_ID}
name: Login To Home Flow
tags:
  - acct-pe
# Clasificación: STATE-DEPENDENT.
# FIXTURES REQUERIDOS:
#   - \${EMAIL} / \${PASSWORD} de una cuenta ya onboardeada.
---
# Setup reutilizable.
- runFlow: commons/setup-authed.yaml
- inputText: "tags: - acct-co"
- assertVisible:
    id: icon.question
''';

void main() {
  group('los tags de un flow', () {
    test('los lee de la cabecera de un flow real', () {
      expect(LosTagsDeUnFlow.leer(_flowReal), {'acct-pe'});
    });

    test('no mira más allá del separador de documentos', () {
      // El flow tiene `tags: - acct-co` DENTRO de un inputText. Si se leyera el
      // archivo entero, esa cuenta saldría de dentro de un tap.
      expect(LosTagsDeUnFlow.leer(_flowReal), isNot(contains('acct-co')));
    });

    test('entiende la forma en línea', () {
      expect(
        LosTagsDeUnFlow.leer('tags: [acct-co, smoke]\n---\n- launchApp'),
        {'acct-co', 'smoke'},
      );
    });

    test('cierra el bloque cuando llega otra clave', () {
      const flow = 'tags:\n  - acct-pe\nname: Otra cosa\n---\n- launchApp';
      expect(LosTagsDeUnFlow.leer(flow), {'acct-pe'});
    });

    test('un flow sin tags no declara ninguno', () {
      expect(LosTagsDeUnFlow.leer('appId: x\n---\n- launchApp'), isEmpty);
    });

    test('ignora un comentario pegado a la etiqueta', () {
      expect(
        LosTagsDeUnFlow.leer('tags:\n  - acct-pe # la peruana\n---\n'),
        {'acct-pe'},
      );
    });

    test('quita las comillas', () {
      expect(LosTagsDeUnFlow.leer('tags:\n  - "acct-pe"\n---\n'), {'acct-pe'});
    });

    test('saca la clave de cuenta del prefijo', () {
      expect(LosTagsDeUnFlow.cuentasQuePide(_flowReal), {'pe'});
    });

    test('una etiqueta que no es de cuenta no cuenta como tal', () {
      const flow = 'tags:\n  - smoke\n  - acct-co\n---\n';
      expect(LosTagsDeUnFlow.cuentasQuePide(flow), {'co'});
    });

    test('un acct- pelado no es una clave', () {
      expect(LosTagsDeUnFlow.cuentasQuePide('tags:\n  - acct-\n---\n'), isEmpty);
    });
  });
}
