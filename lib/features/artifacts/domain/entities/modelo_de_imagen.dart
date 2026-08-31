/// Con qué modelo se dibuja.
///
/// **Se elige y no se fija en una constante** porque el precio se paga del
/// saldo de quien lo pide y entre el más caro y el más barato hay el doble. Y
/// porque el bueno se satura: cuando nano banana 2 contesta «high demand»,
/// poder bajar a otro es la diferencia entre seguir trabajando y esperar.
enum ModeloDeImagen {
  /// La generación actual. La de los ejemplos de la API.
  nanoBanana2('gemini-3.1-flash-image', 'Nano Banana 2', r'$0,045–0,067'),

  /// La misma generación, más barata y menos concurrida.
  nanoBanana2Lite(
    'gemini-3.1-flash-lite-image',
    'Nano Banana 2 Lite',
    r'$0,034',
  ),

  /// La anterior. Sigue estando bien y su cola suele ser más corta.
  nanoBanana('gemini-2.5-flash-image', 'Nano Banana', r'$0,039');

  const ModeloDeImagen(this.id, this.nombre, this.precio);

  /// Lo que se manda a la API. Un id mal escrito es un 404 en la cara de quien
  /// lo pide, así que están los cuatro copiados de la documentación.
  final String id;

  final String nombre;

  /// Por imagen, en el nivel estándar. Se enseña **al elegir** y no en la
  /// factura: es cuando sirve de algo.
  final String precio;

  /// El de siempre si lo guardado no se reconoce —una versión anterior, un
  /// modelo retirado—. Volver al de por defecto es mejor que no dibujar.
  static ModeloDeImagen porId(String? id) =>
      values.firstWhere((modelo) => modelo.id == id, orElse: () => nanoBanana2);
}
