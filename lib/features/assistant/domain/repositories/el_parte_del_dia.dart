/// Pedir el parte del día desde la conversación hablada.
///
/// **El mismo parte que el botón del menú**, y esa es toda la intención: quien
/// dice «dame el daily» tiene que acabar con lo mismo en pantalla que quien lo
/// pulsa —el resumen del último día con trabajo, del proyecto que va a ese
/// Slack, y debajo el botón para mandarlo—. Si hablando saliera otra cosa,
/// serían dos partes distintos con el mismo nombre.
///
/// Es un puerto y no una llamada directa por lo de siempre: el dominio de la
/// conversación no puede conocer el del historial. Recibe el material montado y
/// devuelve el parte escrito.
///
/// Se parte en dos porque el trabajo lo hace Claude y quien lo encarga es la
/// conversación: [instruccion] entrega qué hay que contar, y [yaEstaEscrito]
/// recoge lo que salió para dejarlo en el chat con su botón. Sin la segunda, el
/// parte se contaría en voz alta y se perdería: hablando, lo que Claude
/// devuelve alimenta la narración, no la conversación escrita.
abstract class ElParteDelDia {
  /// El encargo con el material del día, o `null` si no hay ningún día anterior
  /// que contar — que es distinto de fallar: se dice y no se inventa un parte
  /// de la nada.
  Future<String?> instruccion();

  /// Deja el parte ya redactado en la conversación, marcado como parte, que es
  /// lo que hace aparecer el botón de enviarlo a Slack.
  void yaEstaEscrito(String parte);
}
