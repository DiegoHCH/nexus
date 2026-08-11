/// Los cuatro estados del orbe y del horizonte. Cada uno cambia el tipo de
/// movimiento del orbe y el tipo de línea del horizonte, nunca solo el color
/// — es lo que permite distinguir el estado a tres metros.
enum NexusOrbState {
  /// En reposo: solo puntos, sin malla. Respira lento, giro casi imperceptible.
  sleep,

  /// Escuchando: la malla aparece, un anillo de voz rodea el orbe, el
  /// horizonte se vuelve onda.
  listen,

  /// Trabajando: gira mucho más rápido, dos anillos lo barren, el horizonte
  /// es un riel con un pulso que viaja.
  think,

  /// Hablando: late con la voz simulada y emite ondas concéntricas; el
  /// horizonte se convierte en barras verticales.
  speak,
}
