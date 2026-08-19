"""El fondo de la ventana del instalador.

La ventana del DMG salía **sin fondo**: una lista de iconos sobre el gris del
Finder, sin decir qué hay que hacer con ellos. La de La Oficina tiene su flecha y
se entiende sin leer nada, y eso no lo pone el DMG: lo pone una imagen de fondo.

Se dibuja aquí en vez de guardar un PNG a mano por lo mismo que el icono de la
app: es la misma paleta y los mismos trazos, y un PNG suelto se desincroniza el día
que el vacío cambie de tono.

Sin texto a propósito. La app es bilingüe y un fondo con «Arrastra a Aplicaciones»
solo estaría bien en la mitad de los casos; la flecha se lee en los dos idiomas.
"""

from PIL import Image, ImageDraw

VOID = (0x04, 0x07, 0x0D)
CYAN = (0x56, 0xE1, 0xEA)
ANCHO, ALTO = 660, 420


def dibujar(escala: int) -> Image.Image:
    w, h = ANCHO * escala, ALTO * escala
    img = Image.new("RGB", (w, h), VOID)
    d = ImageDraw.Draw(img, "RGBA")

    # Sin halos detrás de los iconos: se probaron y salían con bandas —cada
    # elipse con alfa plano deja un borde visible— y además competían con los
    # iconos, que es justo lo único que hay que mirar aquí. El vacío de esta app
    # es vacío.

    # La flecha, a trazos. A trazos y no maciza porque el registro de esta app es
    # de líneas —la malla del orbe, el horizonte— y una flecha rellena se vería
    # pegada de otro sitio.
    y = h * 0.47
    x0, x1 = w * 0.42, w * 0.56
    paso = 11 * escala
    largo = 7 * escala
    x = x0
    while x < x1 - largo:
        d.line([x, y, x + largo, y], fill=(*CYAN, 150), width=max(1, 2 * escala))
        x += paso

    # La punta, dos trazos.
    p = 13 * escala
    d.line([x1 - p, y - p, x1, y], fill=(*CYAN, 190), width=max(1, 2 * escala))
    d.line([x1 - p, y + p, x1, y], fill=(*CYAN, 190), width=max(1, 2 * escala))

    return img


if __name__ == "__main__":
    import pathlib
    import subprocess
    import tempfile

    aqui = pathlib.Path(__file__).parent
    # Una sola imagen con las dos resoluciones dentro: es lo que hace que no se
    # vea borroso en Retina. Los PNG son intermedios y no se versionan — lo que
    # necesita el DMG es el `.tiff`, y `tiffutil` viene en el sistema.
    with tempfile.TemporaryDirectory() as tmp:
        uno = pathlib.Path(tmp) / "1x.png"
        dos = pathlib.Path(tmp) / "2x.png"
        dibujar(1).save(uno)
        dibujar(2).save(dos)
        subprocess.run(
            ["tiffutil", "-cathidpicheck", str(uno), str(dos),
             "-out", str(aqui / "fondo.tiff")],
            check=True, capture_output=True,
        )
    print(f"  fondo.tiff {ANCHO}x{ALTO} con su @2x dentro")
