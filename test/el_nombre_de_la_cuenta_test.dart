import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/workspace/data/datasources/claude_profiles_data_source.dart';
import 'package:nexus/features/workspace/domain/usecases/el_nombre_de_la_cuenta.dart';

/// **Cómo se llama una cuenta de Claude para quien la mira.**
///
/// 🔴 Pedido en tres reglas, después de descubrir que el correo estaba a la
/// vista en el `.claude.json` de cada cuenta: «si la cuenta dice en la
/// organización Global66 - Tech, que aparezca Global66; si tiene otra, algo
/// parecido a lo que aparece como organización; y si es algo diferente, algo
/// como Mi Perfil».
///
/// Los valores de aquí son **los de verdad**, leídos de las tres cuentas de
/// este Mac — incluida la sorpresa: dos de los tres directorios resultaron ser
/// la misma cuenta.
const _general = 'General';
const _mia = 'Mi perfil';

ClaudeProfile _cuenta({
  String path = '/Users/alguien/.claude-work',
  String name = 'work',
  String? correo,
  String? organizacion,
}) => ClaudeProfile(
  path: path,
  name: name,
  signedIn: true,
  correo: correo,
  organizacion: organizacion,
);

String nombre(ClaudeProfile cuenta) =>
    ElNombreDeLaCuenta.de(cuenta, general: _general, mia: _mia);

void main() {
  group('el nombre de la empresa', () {
    // El caso que lo pidió, con el valor literal de este Mac.
    test('«Global66 - Tech» se enseña como «Global66»', () {
      expect(
        nombre(
          _cuenta(
            correo: 'diego.hoyos@global66.com',
            organizacion: 'Global66 - Tech',
          ),
        ),
        'Global66',
      );
    });

    test('una organización sin departamento se queda como está', () {
      expect(nombre(_cuenta(organizacion: 'Global66')), 'Global66');
    });

    // Un guion **sin** espacios puede ser parte del nombre, y cortar ahí
    // dejaría media empresa.
    test('un guion pegado no se corta', () {
      expect(nombre(_cuenta(organizacion: 'Mercado-Libre')), 'Mercado-Libre');
    });

    test('y el guion largo también separa, que también se usa', () {
      expect(nombre(_cuenta(organizacion: 'Acme — Data')), 'Acme');
    });
  });

  group('una organización personal no es una organización', () {
    // El literal que escribe Claude Code para una cuenta de pago individual,
    // copiado de la de este Mac.
    test('«correo\'s Organization» es lo mío, no una empresa', () {
      expect(
        nombre(
          _cuenta(
            path: '/Users/alguien/.claude-private',
            name: 'private',
            correo: 'dfchaakon0813@gmail.com',
            organizacion: "dfchaakon0813@gmail.com's Organization",
          ),
        ),
        _mia,
      );
    });

    test('con el apóstrofo tipográfico, igual', () {
      expect(
        nombre(_cuenta(organizacion: '’s Organization'.padLeft(20, 'x'))),
        _mia,
      );
    });

    // La segunda señal: la organización lleva el correo dentro, aunque la
    // redacción cambie.
    test('si la organización lleva tu correo dentro, es tuya', () {
      expect(
        nombre(
          _cuenta(
            correo: 'alguien@gmail.com',
            organizacion: 'Cuenta de alguien@gmail.com',
          ),
        ),
        _mia,
      );
    });
  });

  group('cuando no se sabe', () {
    test('sin organización, se queda el nombre de su directorio', () {
      expect(nombre(_cuenta(organizacion: null)), 'work');
    });

    test('y la de siempre sin datos es la General', () {
      expect(
        nombre(_cuenta(path: '/Users/alguien/.claude', name: '')),
        _general,
      );
    });
  });

  // 🔴 **La sorpresa que obligó a esto:** en este Mac `.claude` y
  // `.claude-work` tienen el **mismo correo y la misma organización**, así que
  // las dos pestañas se llamarían «Global66» y no habría forma de saber cuál se
  // está tocando — y lo que se toca ahí instala servidores y skills.
  group('dos perfiles que son la misma cuenta', () {
    test('se distinguen por su directorio', () {
      final nombres = ElNombreDeLaCuenta.paraTodas(
        [
          _cuenta(
            path: '/Users/alguien/.claude',
            name: '',
            correo: 'diego.hoyos@global66.com',
            organizacion: 'Global66 - Tech',
          ),
          _cuenta(
            correo: 'diego.hoyos@global66.com',
            organizacion: 'Global66 - Tech',
          ),
          _cuenta(
            path: '/Users/alguien/.claude-private',
            name: 'private',
            correo: 'dfchaakon0813@gmail.com',
            organizacion: "dfchaakon0813@gmail.com's Organization",
          ),
        ],
        general: _general,
        mia: _mia,
      );

      expect(nombres, [
        'Global66 (General)',
        'Global66 (work)',
        // Esta no coincide con nadie, así que se queda limpia.
        _mia,
      ]);
    });

    test('y si no coinciden, nadie lleva paréntesis', () {
      final nombres = ElNombreDeLaCuenta.paraTodas(
        [
          _cuenta(organizacion: 'Global66 - Tech'),
          _cuenta(
            path: '/Users/alguien/.claude-otra',
            name: 'otra',
            organizacion: 'Acme',
          ),
        ],
        general: _general,
        mia: _mia,
      );

      expect(nombres, ['Global66', 'Acme']);
    });
  });
}
