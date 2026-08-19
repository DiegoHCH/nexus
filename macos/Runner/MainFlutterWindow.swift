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
    // Marcada como nuestra: el tema solo se pinta en las ventanas de la app.
    self.identifier = NexusAppearance.ourMark

    NexusStatusItem.register(
      with: flutterViewController.registrar(forPlugin: "NexusStatusItem")
    )
    NexusNotifications.register(
      with: flutterViewController.registrar(forPlugin: "NexusNotifications")
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

    // **No se puede encoger por debajo de una tablet en horizontal.**
    //
    // No es un límite técnico —medido, a 800×600 la interfaz todavía no
    // desborda— sino de producto: esto es un HUD de escritorio con el orbe
    // ocupando media pantalla y la conversación en la otra mitad, y por debajo
    // de este tamaño esa idea deja de tener sentido antes de que algo se rompa.
    //
    // `minSize` y no `contentMinSize`: la barra de título es transparente y
    // Flutter ocupa la ventana entera, así que aquí las dos medidas son la
    // misma y esta es la que macOS aplica al arrastrar el borde.
    let minimo = NSSize(width: 1024, height: 768)
    self.minSize = minimo
    // **Y se agranda si ya venía más pequeña.** `minSize` solo lo aplica AppKit
    // cuando arrastras un borde: no encoge ni estira la ventana que ya existe.
    // El `.xib` la crea en 800×600, así que sin esto una instalación nueva
    // abría por debajo del mínimo que se acaba de declarar y solo saltaba al
    // tocar un borde.
    if self.frame.width < minimo.width || self.frame.height < minimo.height {
      self.setContentSize(
        NSSize(
          width: max(self.frame.width, minimo.width),
          height: max(self.frame.height, minimo.height)
        )
      )
      self.center()
    }
    NexusAppearance.apply(dark: NexusAppearance.systemIsDark())

    super.awakeFromNib()
  }
}
