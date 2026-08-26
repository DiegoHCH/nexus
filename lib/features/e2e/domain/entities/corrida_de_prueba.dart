/// Cómo acabó una corrida de pruebas.
enum ComoAcabo {
  /// Todos los pasos completados.
  bien,

  /// Algún paso falló.
  mal,

  /// Corriendo ahora mismo.
  enMarcha,

  /// No se pudo saber: sin `commands.json`, que es lo que pasa cuando el proceso
  /// murió antes de escribirlo.
  vayaUstedASaber,
}

/// Una prueba de Maestro: un `.yaml` en el `.maestro/` de un proyecto.
class Prueba {
  const Prueba({required this.ruta, required this.nombre});

  final String ruta;

  /// El nombre del archivo sin extensión, que es el que usa Maestro para nombrar
  /// su carpeta de resultados. **De ahí sale la atribución** de las corridas que
  /// no lanzó Nexus.
  final String nombre;
}

/// Una corrida: lo que quedó de haber ejecutado una prueba.
class CorridaDePrueba {
  const CorridaDePrueba({
    required this.carpeta,
    required this.flow,
    required this.cuando,
    required this.comoAcabo,
    this.perfil,
    this.proyecto,
    this.dispositivo,
    this.pasos = 0,
    this.pasosBien = 0,
    this.capturas = const [],
  });

  /// Dónde vive lo que dejó. Es la clave: se borra borrándola.
  final String carpeta;

  /// Qué prueba se corrió, por su nombre de archivo.
  final String flow;

  final DateTime cuando;
  final ComoAcabo comoAcabo;

  /// De qué cuenta salió. `null` en las que no lanzó Nexus.
  final String? perfil;

  /// De qué proyecto. `null` cuando no se pudo atribuir — ver
  /// [atribuyePorNombre].
  final String? proyecto;

  /// Sobre qué dispositivo corrió, si lo dijo su `commands.json`.
  ///
  /// Sirve para reproducir, con un aviso: un `emulator-5554` de hace tres días
  /// no es el mismo emulador, así que se comprueba que siga vivo antes de usarlo.
  final String? dispositivo;

  final int pasos;
  final int pasosBien;

  /// Las capturas que dejó, por ruta.
  final List<String> capturas;

  /// Si se sabe de dónde salió. Las que no, se enseñan igual pero agrupadas
  /// aparte: esconderlas sería peor que no saber su proyecto.
  bool get atribuida => proyecto != null;
}
