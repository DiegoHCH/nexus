import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/data/repositories/gemini_voice_gateway.dart';

/// Lo que el modelo de voz lee antes de decidir a quién llama.
///
/// 🔴 Esto existe por una frase que estuvo semanas en la descripción de
/// `pedir_a_claude`: «Todavía no hay carpeta emparejada, así que trabaja sobre
/// el directorio donde corre la app y no sobre un proyecto concreto».
/// Incondicional, y falsa desde que emparejar carpetas es el eje del producto:
/// de la carpeta cuelgan la cuenta, el modelo, los permisos y el prompt.
///
/// No la pilló nada porque **una descripción de herramienta es interfaz hacia
/// un modelo**: no tiene tipos que fallen, no hay pantalla donde se vea torcida
/// y no revienta ninguna prueba. Se rompe en silencio y se paga en cómo se
/// enruta cada encargo.
void main() {
  Map<String, dynamic> herramienta(String nombre) =>
      GeminiVoiceGateway.lasHerramientas.firstWhere(
        (h) => h['name'] == nombre,
        orElse: () => throw StateError('no se declara $nombre'),
      );

  String descripcion(String nombre) =>
      herramienta(nombre)['description'] as String;

  test('se declaran las cinco herramientas, con su nombre exacto', () {
    expect(
      GeminiVoiceGateway.lasHerramientas.map((h) => h['name']),
      containsAll(<String>[
        GeminiVoiceGateway.toolName,
        GeminiVoiceGateway.skillToolName,
        GeminiVoiceGateway.testToolName,
        GeminiVoiceGateway.parteToolName,
        GeminiVoiceGateway.agendaToolName,
      ]),
      reason:
          'el caso de uso reconoce las llamadas por estas constantes: un '
          'nombre que se aparte deja la herramienta declarada y sin atender',
    );
  });

  test('ninguna descripción le dice al modelo que no hay carpeta', () {
    // Se mira por el concepto y no por la frase exacta: lo que no puede volver
    // es la afirmación, se redacte como se redacte.
    final prohibidas = [
      'no hay carpeta',
      'no hay ninguna carpeta',
      'todavía no hay',
      'directorio donde corre la app',
      'sin carpeta emparejada',
    ];

    for (final h in GeminiVoiceGateway.lasHerramientas) {
      final texto = (h['description'] as String).toLowerCase();
      for (final prohibida in prohibidas) {
        expect(
          texto.contains(prohibida),
          isFalse,
          reason:
              '«${h['name']}» le dice al modelo «$prohibida». Las carpetas '
              'emparejadas son el eje del producto: de ellas salen la cuenta, '
              'el modelo, los permisos y el prompt.',
        );
      }
    }
  });

  test('pedir_a_claude dice dónde corre el encargo', () {
    final texto = descripcion(GeminiVoiceGateway.toolName).toLowerCase();

    expect(
      texto.contains('carpeta de esta conversación'),
      isTrue,
      reason:
          'sin esto el modelo no sabe que la ruta ya está decidida, y se pone '
          'a preguntarla o a inventarla',
    );
  });

  test('cada herramienta declara los parámetros que su caso de uso lee', () {
    // El nombre del parámetro es un contrato: el caso de uso lee `arguments`
    // por clave, y una clave renombrada aquí llega como un argumento vacío.
    const esperados = <String, List<String>>{
      'pedir_a_claude': ['instruccion'],
      'crear_skill': ['nombre', 'para_que'],
      'correr_prueba': ['prueba'],
      'pedir_el_parte': <String>[],
      'consultar_agenda': <String>[],
    };

    esperados.forEach((nombre, requeridos) {
      final parametros =
          herramienta(nombre)['parameters'] as Map<String, dynamic>;
      final propiedades = parametros['properties'] as Map<String, Object?>;

      expect(
        propiedades.keys,
        unorderedEquals(requeridos),
        reason: 'los argumentos de $nombre',
      );
      expect(
        (parametros['required'] as List<dynamic>? ?? const []).cast<String>(),
        unorderedEquals(requeridos),
        reason: 'lo que $nombre exige',
      );
    });
  });
}
