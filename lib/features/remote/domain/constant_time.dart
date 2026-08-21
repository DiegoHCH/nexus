/// Comparar secretos sin que el **tiempo** diga cuánto acertaste.
///
/// Con `==`, Dart corta en el primer byte distinto: un secreto que empieza bien
/// tarda más en fallar que uno que empieza mal, y con suficientes intentos eso se
/// mide y se adivina byte a byte.
///
/// Vive aparte desde que hay **dos** secretos que comparar —el token del canal y
/// la frase de escritura—. Estaba dentro del portero, y dejarlo ahí habría acabado
/// en una segunda copia: la primera con esta disciplina y la segunda con un `==`
/// escrito de memoria.
///
/// La longitud sí se filtra, y es aceptable: la del token la fija esta app y la de
/// la frase la elige quien la escribe, pero ninguna de las dos es el secreto. Lo
/// que no puede filtrarse es el contenido.
bool igualesSinDelatar(String a, String b) {
  final ua = a.codeUnits;
  final ub = b.codeUnits;
  var diferencia = ua.length ^ ub.length;
  final hasta = ua.length > ub.length ? ua.length : ub.length;
  for (var i = 0; i < hasta; i++) {
    diferencia |= (i < ua.length ? ua[i] : 0) ^ (i < ub.length ? ub[i] : 0);
  }
  return diferencia == 0;
}
