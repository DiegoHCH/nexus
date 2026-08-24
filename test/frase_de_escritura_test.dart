import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/remote/domain/write_phrase.dart';

// La frase que deja al teléfono escribir.
//
// Existe porque el token no puede ser el único secreto: quien se lleve el teléfono
// se lleva el token. Y existe **así** —verificada en el Mac, no guardada en el
// teléfono— porque la decisión 2.4 del contrato pedía confirmar en el escritorio, y
// eso volvía imposible el caso principal: estando fuera no hay nadie en el Mac.
//
// Lo que se vigila aquí es lo que falla en silencio: una frase vacía que todo el
// mundo acierta, un permiso que sobrevive a lo que no debería, y un cupo de
// intentos que se gasta con quien no podía acertar.
void main() {
  const frase = WritePhrase('la-frase-de-verdad');

  group('la frase', () {
    test('pide un mínimo, y no es decoración', () {
      // Con el límite de intentos, adivinar está acotado — pero tres caracteres se
      // adivinan **dentro** del límite en unos días.
      expect(const WritePhrase('corta').valida, isFalse);
      expect(const WritePhrase('12345678').valida, isTrue);
      expect(frase.valida, isTrue);
      // Y los espacios no cuentan como longitud.
      expect(const WritePhrase('   a    ').valida, isFalse);
    });

    test('no se escribe en los registros', () {
      // Importa más que con el token: esta viaja **dentro de un mensaje**, y el
      // servidor registra lo que llega.
      final impreso = '$frase';
      expect(impreso.contains('la-frase-de-verdad'), isFalse);
      expect(impreso, 'WritePhrase(definida)');
    });

    test('comparar dos frases no delata su contenido', () {
      expect(frase == const WritePhrase('la-frase-de-verdad'), isTrue);
      expect(frase == const WritePhrase('la-frase-de-verdax'), isFalse);
      // Y el hash es constante a propósito: derivarlo del valor filtraría
      // información a cualquier `Set` o `Map` de frases.
      expect(frase.hashCode, const WritePhrase('otra cosa').hashCode);
    });
  });

  group('abrir la escritura', () {
    test('con la frase correcta se concede', () {
      final unlock = WriteUnlock();
      expect(
        unlock.intentar(guardada: frase, recibida: 'la-frase-de-verdad'),
        isNull,
      );
      expect(unlock.puedeEscribir, isTrue);
    });

    test('con la equivocada, no', () {
      final unlock = WriteUnlock();
      expect(
        unlock.intentar(guardada: frase, recibida: 'otra'),
        WriteDenial.frase,
      );
      expect(unlock.puedeEscribir, isFalse);
    });

    test('sin frase definida se queda en solo lectura, y se dice', () {
      // Es el estado por defecto y es el correcto: quien no la ha puesto no ha
      // dicho en ningún momento que quiera que el teléfono escriba. Y el móvil
      // necesita saber **por qué** para poder decir «define una en el Mac».
      final unlock = WriteUnlock();
      expect(
        unlock.intentar(guardada: null, recibida: 'lo que sea'),
        WriteDenial.sinFrase,
      );
    });

    test('y sin frase no se gasta cupo', () {
      // Si contara, gastarle los intentos a quien no puede acertar nunca solo
      // consigue que el mensaje útil deje de llegar.
      final unlock = WriteUnlock();
      for (var i = 0; i < 20; i++) {
        unlock.intentar(guardada: null, recibida: 'x');
      }
      expect(unlock.fallos, 0);
      expect(
        unlock.intentar(guardada: frase, recibida: 'la-frase-de-verdad'),
        isNull,
        reason: 'quien define la frase después tiene que poder entrar',
      );
    });

    test('una frase vacía guardada no la acierta cualquiera', () {
      // El caso que el almacén evita devolviendo `null`, comprobado también aquí:
      // si una cadena vacía llegara como frase, un intento vacío la acertaría.
      final unlock = WriteUnlock();
      expect(
        unlock.intentar(guardada: const WritePhrase(''), recibida: ''),
        isNull,
        reason:
            'esto es lo que pasaría, y por eso el almacén no devuelve vacías',
      );
    });

    test('cinco fallos y se cierra', () {
      final unlock = WriteUnlock();
      for (var i = 0; i < 5; i++) {
        expect(
          unlock.intentar(guardada: frase, recibida: 'mal-$i'),
          WriteDenial.frase,
        );
      }
      expect(
        unlock.intentar(guardada: frase, recibida: 'la-frase-de-verdad'),
        WriteDenial.demasiadosIntentos,
        reason: 'ni con la buena: el cupo es del canal, no de la frase',
      );
    });

    test('pasada la ventana se puede volver a intentar', () {
      var ahora = DateTime(2026, 8, 20, 10);
      final unlock = WriteUnlock(reloj: () => ahora);
      for (var i = 0; i < 5; i++) {
        unlock.intentar(guardada: frase, recibida: 'mal');
      }
      ahora = ahora.add(const Duration(minutes: 11));
      expect(
        unlock.intentar(guardada: frase, recibida: 'la-frase-de-verdad'),
        isNull,
      );
    });

    test('acertar limpia los fallos', () {
      // Quien se equivoca al teclear y luego acierta no debería arrastrar el cupo.
      final unlock = WriteUnlock();
      unlock.intentar(guardada: frase, recibida: 'mal');
      unlock.intentar(guardada: frase, recibida: 'mal');
      expect(unlock.fallos, 2);
      unlock.intentar(guardada: frase, recibida: 'la-frase-de-verdad');
      expect(unlock.fallos, 0);
    });
  });

  group('el permiso concedido', () {
    test('caduca a la media hora', () {
      var ahora = DateTime(2026, 8, 20, 10);
      final unlock = WriteUnlock(reloj: () => ahora);
      unlock.intentar(guardada: frase, recibida: 'la-frase-de-verdad');
      expect(unlock.puedeEscribir, isTrue);

      ahora = ahora.add(const Duration(minutes: 29, seconds: 59));
      expect(unlock.puedeEscribir, isTrue);
      ahora = ahora.add(const Duration(seconds: 2));
      expect(unlock.puedeEscribir, isFalse);
    });

    test('y no se renueva con la actividad', () {
      // Si se renovara, un teléfono en uso lo mantendría abierto indefinidamente —
      // que es exactamente el escenario del teléfono perdido.
      var ahora = DateTime(2026, 8, 20, 10);
      final unlock = WriteUnlock(reloj: () => ahora);
      unlock.intentar(guardada: frase, recibida: 'la-frase-de-verdad');

      for (var i = 0; i < 20; i++) {
        ahora = ahora.add(const Duration(minutes: 2));
        // Consultar es la actividad: si esto renovara, nunca caducaría.
        unlock.puedeEscribir;
      }
      expect(
        unlock.puedeEscribir,
        isFalse,
        reason: 'han pasado cuarenta minutos',
      );
    });

    test('se puede revocar antes de que caduque', () {
      // Lo usa rotar el token: revocar el acceso y dejarle el permiso de escritura
      // sería revocar a medias.
      final unlock = WriteUnlock();
      unlock.intentar(guardada: frase, recibida: 'la-frase-de-verdad');
      unlock.revocar();
      expect(unlock.puedeEscribir, isFalse);
    });
  });
}
