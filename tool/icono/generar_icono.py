"""Los ocho tamaños del icono, cada uno dibujado para su tamaño.

**Un icono no es un dibujo escalado.** Reducir la malla completa a 16 px la
convierte en una mancha: comprobado antes de escribir esto. Así que se dibuja
en tres registros, que es exactamente para lo que existe un `appiconset`:

  512, 1024 ······ la malla entera. Hay sitio para los 140 puntos.
  128, 256 ······· malla aligerada y con más peso: a 128 las aristas finas se
                   empastan entre sí y el conjunto se vuelve gris.
  16, 32, 64 ····· solo lo que sobrevive — el anillo del contorno y el
                   horizonte, con el contraste subido. La esfera se reconoce
                   por su silueta, no por su trama.

Es la misma pieza leída a tres distancias, no tres iconos distintos.
"""
import math
from PIL import Image, ImageChops, ImageDraw, ImageFilter

VOID = (0x04, 0x07, 0x0D)
CYAN = (0x56, 0xE1, 0xEA)

N = 140
ANGULO_AUREO = math.pi * (3 - math.sqrt(5))


def _puntos():
    out = []
    for i in range(N):
        y = 1 - (i / (N - 1)) * 2
        r = math.sqrt(max(0.0, 1 - y * y))
        t = ANGULO_AUREO * i
        out.append((math.cos(t) * r, y, math.sin(t) * r))
    return out


def _aristas(ps):
    umbral = 2.2 * (4 * math.pi / N)
    return [
        (i, j)
        for i in range(N)
        for j in range(i + 1, N)
        if sum((ps[i][k] - ps[j][k]) ** 2 for k in range(3)) < umbral
    ]


PS = _puntos()
ES = _aristas(PS)

# La misma orientación en todos los tamaños: girar el orbe entre uno y otro
# haría que el icono «saltara» al cambiar de vista en el Finder.
YAW, PITCH = 0.9, 0.22


def _girar(p):
    x, y, z = p
    x, z = (x * math.cos(YAW) - z * math.sin(YAW),
            x * math.sin(YAW) + z * math.cos(YAW))
    y, z = (y * math.cos(PITCH) - z * math.sin(PITCH),
            y * math.sin(PITCH) + z * math.cos(PITCH))
    return x, y, z


ROT = [_girar(p) for p in PS]


def _mezcla(fondo, color, a):
    return tuple(int(fondo[i] + (color[i] - fondo[i]) * a) for i in range(3))


def render(lado, *, super_=4):
    S = lado * super_
    margen = 100 * S / 1024
    radio_placa = 185 * S / 1024
    cx = cy = S / 2
    # El orbe ocupa algo más en los tamaños mínimos: con once píxeles de ancho,
    # cada décima de radio es un pixel de silueta.
    R = S * (0.230 if lado >= 64 else 0.265)

    # El registro según el tamaño final, no según el lienzo de trabajo.
    if lado >= 512:
        registro = "malla"
    elif lado >= 128:
        registro = "media"
    elif lado >= 64:
        registro = "silueta"
    else:
        # A 32 y a 16 el orbe mide once píxeles de ancho. Ahí no caben puntos
        # —se alían hasta desaparecer— ni halo, que solo emborrona. Sobreviven
        # un círculo y una recta, y eso es exactamente lo que se dibuja: la
        # esfera se reconoce por su silueta y el horizonte dice que hay algo
        # mirándola. Comprobado reduciendo: con puntos era una mancha.
        registro = "minimo"

    img = Image.new("RGB", (S, S), VOID)

    # Halo: apretado al objeto y apenas perceptible. Emite, no ilumina.
    capa = Image.new("RGB", (S, S), (0, 0, 0))
    dh = ImageDraw.Draw(capa)
    fuerza = {"malla": 0.13, "media": 0.16, "silueta": 0.22,
              "minimo": 0.0}[registro]
    for k in range(26, 0, -1):
        rr = R * (1 + 0.17 * k / 26)
        dh.ellipse([cx - rr, cy - rr, cx + rr, cy + rr],
                   fill=_mezcla((0, 0, 0), CYAN, fuerza * (1 - k / 26) ** 2.4))
    img = ImageChops.add(
        img, capa.filter(ImageFilter.GaussianBlur(radius=max(1, int(13 * S / 4096))))
    )

    d = ImageDraw.Draw(img)
    esc = S / 4096  # los grosores se calibraron a 4096

    # El horizonte, de borde a borde. En los tamaños pequeños es lo que hace
    # que la mancha se lea como «un objeto mirado», así que sube de peso.
    alfa_h = {"malla": 0.52, "media": 0.62, "silueta": 0.85,
              "minimo": 1.0}[registro]
    peso_h = {"malla": 1.3, "media": 1.8, "silueta": 3.2,
              "minimo": 4.2}[registro]
    # Un pixel del icono terminado, medido en el lienzo de trabajo.
    #
    # Hace falta porque los grosores están calibrados «a 4096» y los tamaños
    # pequeños se dibujan en un lienzo de 256: al reducir, lo que se pintó como
    # trazo se queda en una fracción de pixel y se promedia con la placa. Medido:
    # a 16 px el aro acababa midiendo **0,14 píxeles finales** y el horizonte
    # 0,07. Por eso llegaban grises — no era opacidad, era que casi no llegaban.
    pixel = super_

    d.line([margen, cy, S - margen, cy],
           fill=_mezcla(VOID, CYAN, alfa_h),
           width=(max(1, round(pixel * 1.0)) if registro == "minimo"
                  else max(1, int(esc * SUPER_TRAZO * peso_h))))

    if registro == "minimo":
        # El aro, de un trazo. Sin puntos: a este tamaño cada uno cae en medio
        # píxel y el antialias los convierte en niebla.
        # Grueso de verdad: un trazo fino se promedia con el fondo al reducir
        # y el aro llega apagado. A 16 px la única forma de que el cian llegue
        # como cian es que ocupe un pixel entero.
        # Uno y pico, no nueve entre cuatro mil: a este tamaño el aro tiene que
        # ocupar **un pixel entero del icono** para que el cian llegue como cian.
        # Por debajo de uno, el antialias lo mezcla con el fondo y sale gris.
        w = max(2, round(pixel * 1.3))
        d.ellipse([cx - R, cy - R, cx + R, cy + R],
                  outline=_mezcla(VOID, CYAN, 1.0), width=w)
        m = Image.new("L", (S, S), 0)
        ImageDraw.Draw(m).rounded_rectangle(
            [margen, margen, S - margen, S - margen], radius=radio_placa, fill=255
        )
        fuera = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        fuera.paste(img, (0, 0), m)
        # `BOX` y no `LANCZOS` en este registro.
        #
        # Aquí se reduce por un factor entero y grande —de 256 a 16—, y para eso
        # el promedio de área es el filtro correcto. Lanczos está pensado para
        # fotografía y **sobreimpulsa en los bordes duros**: con el aro ya visible
        # aparecían motas de azul puro (0,0,255) y cian puro (0,255,255) fuera
        # de la placa, colores que ni siquiera están en la paleta. Se veían al
        # ampliar y no eran del dibujo, eran del filtro.
        return fuera.resize((lado, lado), Image.BOX)

    if registro != "silueta":
        alfa_a = {"malla": 0.62, "media": 0.74}[registro]
        peso_a = {"malla": 1.25, "media": 1.9}[registro]
        for (i, j) in ES:
            x1, y1, z1 = ROT[i]
            x2, y2, z2 = ROT[j]
            prof = ((z1 + z2) / 2 + 1) / 2
            d.line(
                [cx + x1 * R, cy - y1 * R, cx + x2 * R, cy - y2 * R],
                fill=_mezcla(VOID, CYAN, alfa_a * (0.30 + 0.70 * prof ** 1.4)),
                width=max(1, int(esc * SUPER_TRAZO * peso_a * (0.9 + 1.5 * prof))),
            )

    for x, y, z in ROT:
        prof = (z + 1) / 2
        if registro == "silueta":
            # Solo el anillo: sin trama que sostener, la silueta es el objeto.
            if abs(z) > 0.34:
                continue
            a, peso = 1.0, 2.6
        else:
            a = 0.22 + 0.78 * prof ** 1.9
            peso = {"malla": 1.25, "media": 1.7}[registro]
        r = esc * SUPER_TRAZO * (1.5 + 3.6 * prof) * peso
        px, py = cx + x * R, cy - y * R
        d.ellipse([px - r, py - r, px + r, py + r], fill=_mezcla(VOID, CYAN, a))

    # Recorte a la placa: fuera no se pinta nada, ni el halo.
    m = Image.new("L", (S, S), 0)
    ImageDraw.Draw(m).rounded_rectangle(
        [margen, margen, S - margen, S - margen], radius=radio_placa, fill=255
    )
    fuera = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    fuera.paste(img, (0, 0), m)
    return fuera.resize((lado, lado), Image.LANCZOS)


SUPER_TRAZO = 4  # los grosores se escribieron pensando en super=4

if __name__ == "__main__":
    import sys

    destino = sys.argv[1] if len(sys.argv) > 1 else "."
    for lado in (16, 32, 64, 128, 256, 512, 1024):
        # Los pequeños se dibujan con más supermuestreo: cada pixel cuenta.
        s = 16 if lado <= 64 else (8 if lado <= 256 else 4)
        render(lado, super_=s).save(f"{destino}/app_icon_{lado}.png")
        print("escrito", f"app_icon_{lado}.png")
