import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/domain/entities/el_acento.dart';

/// El acento con el que se pide que hable la voz.
///
/// 🔴 **Existe porque las voces de Gemini no traen acento.** La doc las
/// describe solo por cualidad vocal y sobre el idioma dice que «explicitly
/// setting a language code is not supported for native audio output models».
/// Lo que sí soporta: «you can control style, tone, **accent**, and pace using
/// natural language prompts». Así que el acento se pide con palabras y acaba en
/// la instrucción del sistema, no en un campo del protocolo — donde no existe.
void main() {
  group('cómo se compone con el idioma', () {
    test('sin elegir, el idioma a secas', () {
      expect(const ElAcento.sinElegir().conElIdioma('español'), 'español');
    });

    test('con variante, el idioma la lleva detrás', () {
      expect(
        const ElAcento('latinoamericano').conElIdioma('español'),
        'español latinoamericano',
      );
      expect(
        const ElAcento('de Colombia').conElIdioma('español'),
        'español de Colombia',
      );
    });

    // La app en inglés compone igual: la variante se escribe una vez y sirve
    // para el idioma que sea.
    test('y funciona con cualquier idioma', () {
      expect(
        const ElAcento('latinoamericano').conElIdioma('English'),
        'English latinoamericano',
      );
    });
  });

  group('qué se guarda', () {
    /// Vacío no es «pide el neutro»: es que no se ha dicho. Pedirlo es una
    /// instrucción y callarse no, así que se guarda `null` y quien lo lee tiene
    /// que poder separarlos.
    test('sin elegir no se guarda nada', () {
      expect(const ElAcento.sinElegir().guardado, isNull);
    });

    test('lo guardado se recupera igual', () {
      const puesto = ElAcento('de México');
      expect(ElAcento.porNombre(puesto.guardado), puesto);
    });

    test('nada guardado vuelve a sin elegir', () {
      expect(ElAcento.porNombre(null), const ElAcento.sinElegir());
      expect(ElAcento.porNombre(''), const ElAcento.sinElegir());
    });

    /// Una variante que ya no está en la lista **se respeta**. La eligió
    /// alguien y sigue siendo una frase válida para el modelo: caer al neutro
    /// le cambiaría el ajuste por la espalda al recortar la lista.
    test('una variante que ya no se ofrece no se pierde', () {
      final rara = ElAcento.porNombre('de Uruguay');

      expect(rara.variante, 'de Uruguay');
      expect(rara.conElIdioma('español'), 'español de Uruguay');
    });
  });

  group('las opciones que se ofrecen', () {
    test('la primera es no elegir, que es lo que hay por defecto', () {
      expect(ElAcento.opciones.first, const ElAcento.sinElegir());
    });

    test('no hay repetidas', () {
      final vistas = ElAcento.opciones.map((a) => a.variante).toSet();

      expect(vistas, hasLength(ElAcento.opciones.length));
    });

    /// Nombrar el sitio antes que la etiqueta: «de México» se lee como un
    /// lugar y «mexicano» como una categoría de persona. La única sin «de» es
    /// la panregional, que no es un país.
    test('las de país se nombran por el sitio', () {
      final paises = ElAcento.opciones
          .where((a) => a.variante != null && a.variante != 'latinoamericano')
          .map((a) => a.variante!);

      expect(paises, isNotEmpty);
      for (final nombre in paises) {
        expect(nombre, startsWith('de '), reason: nombre);
      }
    });
  });
}
