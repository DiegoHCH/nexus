import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/e2e/domain/usecases/el_arbol_de_un_flow.dart';
import 'package:nexus/features/e2e/domain/usecases/las_variables_del_proyecto.dart';

/// La cadena real de `global66/automated-test`, con las rutas tal cual.
final _repo = <String, String>{
  '/r/flows/04-account-detail-flow.yaml': '''
appId: \${APP_ID}
tags:
  - acct-pe
---
- runFlow: commons/setup-authed.yaml
- assertVisible:
    id: \${ACCOUNT_DETAIL_CURRENCY}
''',
  '/r/flows/commons/setup-authed.yaml': '''
appId: \${APP_ID}
---
# Fallback por si el dialog igual aparece
- runFlow:
    when:
      platform: iOS
    commands:
      - tapOn:
          text: "Allow"
- runFlow: ../auth/00-login.yaml
- runFlow: ../auth/01-pin.yaml
''',
  '/r/flows/auth/00-login.yaml': '''
---
- inputText: \${EMAIL}
- inputText: \${PASSWORD}
''',
  '/r/flows/auth/01-pin.yaml': '''
---
- inputText: \${PIN_1}\${PIN_2}\${PIN_3}\${PIN_4}
''',
};

String? _leer(String ruta) => _repo[ruta];

void main() {
  group('las referencias de un flow', () {
    test('coge la forma corriente', () {
      expect(
        ElArbolDeUnFlow.referencias('- runFlow: commons/setup-authed.yaml'),
        ['commons/setup-authed.yaml'],
      );
    });

    test('coge la forma con file y env', () {
      const flow =
          '- runFlow:\n    file: commons/open-deeplink.yaml\n    env:\n      DEEPLINK_PATH: /x';
      expect(ElArbolDeUnFlow.referencias(flow), ['commons/open-deeplink.yaml']);
    });

    test('coge la forma en línea con llaves', () {
      expect(
        ElArbolDeUnFlow.referencias('- runFlow: {file: a/b.yaml, env: {X: 1}}'),
        ['a/b.yaml'],
      );
    });

    test('un runFlow con commands embebidos NO es un archivo', () {
      const flow =
          '- runFlow:\n    when:\n      platform: iOS\n    commands:\n      - tapOn: Allow';
      expect(ElArbolDeUnFlow.referencias(flow), isEmpty);
    });

    test('una ruta con una variable dentro no se resuelve ahora', () {
      expect(
        ElArbolDeUnFlow.referencias(r'- runFlow: flows/${NOMBRE}.yaml'),
        isEmpty,
      );
    });

    test('un comentario no es una referencia', () {
      expect(ElArbolDeUnFlow.referencias('# - runFlow: x.yaml'), isEmpty);
    });
  });

  group('el árbol entero', () {
    test('junta el flow y todo lo que arrastra, dos niveles abajo', () {
      final texto = ElArbolDeUnFlow.texto(
        ruta: '/r/flows/04-account-detail-flow.yaml',
        leer: _leer,
      );
      // El `..` se colapsa: desde flows/commons/, ../auth/ es flows/auth/.
      expect(texto, contains('EMAIL'));
      expect(texto, contains('PASSWORD'));
      expect(texto, contains('PIN_4'));
      expect(texto, contains('ACCOUNT_DETAIL_CURRENCY'));
    });

    test('🔴 el fallo que esto arregla: sin el árbol solo llegaba APP_ID', () {
      const credenciales = {
        'APP_ID': 'com.global66.cards.ci',
        'EMAIL': 'a@b.c',
        'PASSWORD': 'secreta',
        'PIN_1': '1',
      };
      final soloElFlow = LasVariablesDelProyecto.paraElFlow(
        yaml: _repo['/r/flows/04-account-detail-flow.yaml']!,
        variables: credenciales,
      );
      expect(soloElFlow.keys, ['APP_ID'], reason: 'así estaba: el login moría');

      final conElArbol = LasVariablesDelProyecto.paraElFlow(
        yaml: ElArbolDeUnFlow.texto(
          ruta: '/r/flows/04-account-detail-flow.yaml',
          leer: _leer,
        ),
        variables: credenciales,
      );
      expect(
        conElArbol.keys,
        containsAll(['APP_ID', 'EMAIL', 'PASSWORD', 'PIN_1']),
      );
    });

    test('un archivo que falta se salta en silencio', () {
      final texto = ElArbolDeUnFlow.texto(
        ruta: '/r/flows/04-account-detail-flow.yaml',
        leer: (r) => r.endsWith('00-login.yaml') ? null : _repo[r],
      );
      expect(texto, contains('PIN_4'));
      expect(texto, isNot(contains('PASSWORD')));
    });

    test('un ciclo no cuelga', () {
      final ciclo = {
        '/a.yaml': '- runFlow: b.yaml',
        '/b.yaml': '- runFlow: a.yaml\n- inputText: \${TOKEN}',
      };
      final texto = ElArbolDeUnFlow.texto(
        ruta: '/a.yaml',
        leer: (r) => ciclo[r],
      );
      expect(texto, contains('TOKEN'));
    });

    test('la versión que no bloquea da lo mismo que la síncrona', () async {
      // Son dos caminos para el mismo resultado y la lista del repo usa el
      // asíncrono: si divergen, el aviso de «le faltan» diría una cosa y el
      // lanzamiento pasaría otra.
      const ruta = '/r/flows/04-account-detail-flow.yaml';
      expect(
        await ElArbolDeUnFlow.textoAsync(
          ruta: ruta,
          leer: (r) async => _repo[r],
        ),
        ElArbolDeUnFlow.texto(ruta: ruta, leer: _leer),
      );
    });

    test('async: un ciclo tampoco cuelga', () async {
      final ciclo = {
        '/a.yaml': '- runFlow: b.yaml',
        '/b.yaml': '- runFlow: a.yaml\n- inputText: \${TOKEN}',
      };
      final texto = await ElArbolDeUnFlow.textoAsync(
        ruta: '/a.yaml',
        leer: (r) async => ciclo[r],
      );
      expect(texto, contains('TOKEN'));
    });

    test('un flow sin subflows es él mismo', () {
      expect(
        ElArbolDeUnFlow.texto(ruta: '/r/flows/auth/01-pin.yaml', leer: _leer),
        contains('PIN_1'),
      );
    });
  });
}
