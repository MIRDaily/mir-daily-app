"""Genera los masters del icono de la app a partir de la ilustracion original.

Uso:
    python tools/make_app_icon.py assets/branding/icono_master.jpeg
    python tools/make_app_icon.py assets/branding/icono_master.jpeg --scale 0.52

Produce:
    assets/images/app_icon.png             1024x1024 opaco  (Android legacy + iOS)
    assets/images/app_icon_foreground.png  1024x1024 alpha  (adaptive icon Android 8+)
    assets/branding/preview_icono.png      comparativa de tamanos bajo la mascara real

Luego:
    flutter pub get
    dart run flutter_launcher_icons

El dado se aisla por croma (saturacion), no por color de fondo: el circulo beige
del original tiene degradado y el JPEG mete ruido, asi que un recorte por
tolerancia plana dejaria halo en el borde.
"""

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

CANVAS = 1024
WORKING = 2048  # resolucion de analisis; el resultado final es 1024

# Geometria del icono adaptativo de Android, sobre un lienzo de 108 dp:
#   - solo se ve el cuadrado central de 72 dp (la mascara se aplica ahi dentro)
#   - el contenido deberia caber en un circulo de 66 dp
VIEWPORT = 72 / 108  # 0.667 -> 683 px sobre 1024
SAFE = 66 / 108      # 0.611 -> 626 px sobre 1024

CHROMA_MIN = 30  # el beige queda en ~13, el rojo del dado en ~120

# En el adaptativo solo se ve el 66,7% central del lienzo; en el legacy se ve
# entero. Para que el dado se perciba del mismo tamano en ambos hay que
# reescalar el legacy por ese factor.
LEGACY_MAX = 0.88


def legacy_scale(scale):
    return min(scale / VIEWPORT, LEGACY_MAX)


def isolate_subject(img):
    """Devuelve (dado RGBA recortado, color del circulo de fondo)."""
    img = img.convert("RGB")
    if max(img.size) > WORKING:
        ratio = WORKING / max(img.size)
        img = img.resize(
            (round(img.width * ratio), round(img.height * ratio)), Image.LANCZOS
        )

    a = np.asarray(img).astype(np.int16)
    chroma = a.max(axis=2) - a.min(axis=2)
    mask = chroma > CHROMA_MIN
    if not mask.any():
        sys.exit("No se detecta el sujeto: baja CHROMA_MIN")

    mask = fill_convex(mask)

    # El circulo beige: ni blanco del lienzo ni dado. Mediana = robusta al degradado.
    near_white = (a > 248).all(axis=2)
    ring = ~near_white & ~mask
    circle = tuple(int(v) for v in np.median(a[ring], axis=0)) if ring.any() else (250, 247, 244)

    alpha = Image.fromarray((mask * 255).astype(np.uint8), "L")
    alpha = alpha.filter(ImageFilter.GaussianBlur(1))
    out = img.convert("RGBA")
    out.putalpha(alpha)

    ys, xs = np.where(mask)
    return out.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)), circle


def fill_convex(mask):
    """Rellena huecos interiores (ojos, brillos) asumiendo sujeto convexo.

    El dado es un hexagono, asi que rellenar por filas y por columnas y quedarse
    con la interseccion reconstruye la silueta exacta sin necesitar scipy.
    """
    def span(m):
        any_line = m.any(axis=1)
        first = m.argmax(axis=1)
        last = m.shape[1] - 1 - m[:, ::-1].argmax(axis=1)
        idx = np.arange(m.shape[1])[None, :]
        return (idx >= first[:, None]) & (idx <= last[:, None]) & any_line[:, None]

    return span(mask) & span(mask.T).T


def compose(subject, scale, background=None):
    """Centra el sujeto en un lienzo CANVAS x CANVAS al tamano indicado."""
    target = CANVAS * scale
    ratio = target / max(subject.size)
    resized = subject.resize(
        (max(1, round(subject.width * ratio)), max(1, round(subject.height * ratio))),
        Image.LANCZOS,
    )
    base = Image.new("RGBA", (CANVAS, CANVAS), background or (0, 0, 0, 0))
    base.alpha_composite(
        resized, ((CANVAS - resized.width) // 2, (CANVAS - resized.height) // 2)
    )
    return base


def through_mask(adaptive, radius_ratio):
    """Simula lo que ve el usuario: recorte al viewport de 72 dp + mascara."""
    inset = round(CANVAS * (1 - VIEWPORT) / 2)
    view = adaptive.crop((inset, inset, CANVAS - inset, CANVAS - inset))
    mask = Image.new("L", view.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, view.size[0] - 1, view.size[1] - 1],
        radius=round(view.size[0] * radius_ratio),
        fill=255,
    )
    view.putalpha(mask)
    return view


def font(size):
    try:
        return ImageFont.load_default(size=size)
    except TypeError:
        return ImageFont.load_default()


def build_preview(subject, bg_rgba, chosen, path):
    """Hoja comparativa: tres tamanos bajo mascara circular + el icono legacy."""
    options = [
        (0.44, "44%  fiel al original"),
        (0.52, "52%  equilibrado"),
        (0.60, "60%  al limite del area segura"),
    ]
    cell, pad, label_h = 300, 24, 64
    width = (cell + pad) * (len(options) + 1) + pad
    sheet = Image.new("RGB", (width, cell + label_h + pad * 2), (255, 255, 255))
    draw = ImageDraw.Draw(sheet)
    f = font(19)

    checker = Image.new("RGB", (cell, cell), (238, 238, 238))
    for i, (scale, label) in enumerate(options):
        adaptive = compose(subject, scale, bg_rgba)
        tile = through_mask(adaptive, 0.5).resize((cell, cell), Image.LANCZOS)
        x = pad + i * (cell + pad)
        cellbg = checker.copy()
        cellbg.paste(tile, (0, 0), tile)
        sheet.paste(cellbg, (x, pad))
        mark = "  <-- generado" if abs(scale - chosen) < 1e-6 else ""
        draw.text((x, pad + cell + 14), label + mark, fill=(30, 30, 30), font=f)

    legacy = compose(subject, legacy_scale(chosen), bg_rgba).resize(
        (cell, cell), Image.LANCZOS
    )
    x = pad + len(options) * (cell + pad)
    sheet.paste(legacy.convert("RGB"), (x, pad))
    draw.text((x, pad + cell + 14), "legacy / iOS (cuadrado)", fill=(30, 30, 30), font=f)

    sheet.save(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("master", type=Path)
    ap.add_argument(
        "--scale",
        type=float,
        default=0.52,
        help="ancho del dado como fraccion del lienzo de 1024 (area segura: 0.61)",
    )
    ap.add_argument("--bg", default=None, help="fondo en hex; por defecto, el del original")
    args = ap.parse_args()

    if not args.master.exists():
        sys.exit(f"No existe: {args.master}")
    if args.scale > SAFE:
        print(f"AVISO: {args.scale:.2f} supera el area segura ({SAFE:.2f}); puede recortarse")

    root = Path(__file__).resolve().parent.parent
    images = root / "assets" / "images"
    branding = root / "assets" / "branding"

    subject, circle = isolate_subject(Image.open(args.master))
    bg = (
        tuple(int(args.bg.lstrip("#")[i : i + 2], 16) for i in (0, 2, 4))
        if args.bg
        else circle
    )
    bg_rgba = bg + (255,)

    compose(subject, legacy_scale(args.scale), bg_rgba).convert("RGB").save(
        images / "app_icon.png"
    )
    compose(subject, args.scale).save(images / "app_icon_foreground.png")
    build_preview(subject, bg_rgba, args.scale, branding / "preview_icono.png")

    print(f"dado aislado:  {subject.width}x{subject.height} px")
    print(f"fondo del original: #{bg[0]:02X}{bg[1]:02X}{bg[2]:02X}")
    print(f"escala adaptive:    {args.scale:.2f}")
    print(f"escala legacy:      {legacy_scale(args.scale):.2f}")
    for p in ("app_icon.png", "app_icon_foreground.png"):
        print(f"escrito: assets/images/{p}")
    print("escrito: assets/branding/preview_icono.png")


if __name__ == "__main__":
    main()
