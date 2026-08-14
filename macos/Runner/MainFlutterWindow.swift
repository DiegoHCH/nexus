import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Registro a mano: el motor de audio vive en el propio Runner y no como
    // paquete, porque es específico de esta app —un solo motor para escuchar y
    // hablar, que es lo que permite cancelar el eco— y no hay nada que
    // publicar.
    NexusAudioEngine.register(
      with: flutterViewController.registrar(forPlugin: "NexusAudioEngine")
    )
    NexusFiles.register(
      with: flutterViewController.registrar(forPlugin: "NexusFiles")
    )
    NexusThumbnails.register(
      with: flutterViewController.registrar(forPlugin: "NexusThumbnails")
    )
    NexusArtifacts.register(
      with: flutterViewController.registrar(forPlugin: "NexusArtifacts")
    )
    NexusPower.register(
      with: flutterViewController.registrar(forPlugin: "NexusPower")
    )
    NexusAppearance.register(
      with: flutterViewController.registrar(forPlugin: "NexusAppearance")
    )

    // Marco fundido, no sin marco: la barra de título se funde con el --void
    // del tema en vez de llevar el cromo por defecto de macOS. Eso no cambia.
    //
    // Lo que sí cambió: antes se forzaba `.darkAqua` **sin mirar nada**, y el
    // comentario lo llamaba identidad visual del HUD. Lo era mientras el tema
    // claro no se podía elegir; ahora que se elige, un contenido claro dentro
    // de una barra de título negra no es identidad, es un tema a medias.
    //
    // Aquí se arranca con lo que diga el sistema y **Dart corrige después** con
    // la preferencia guardada. Al revés —arrancar siempre oscuro— parpadeaba en
    // negro un fotograma antes de aclararse, que es justo lo que se nota.
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.isOpaque = true
    NexusAppearance.apply(dark: NexusAppearance.systemIsDark())

    super.awakeFromNib()
  }
}
