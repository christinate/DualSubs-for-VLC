from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parent
ICON_SOURCE = ROOT / "dualsubs-icon.png"
LOGO_OUTPUT = ROOT / "dualsubs-logo.png"
ICON_OUTPUT = ROOT / "dualsubs-icon.ico"

WINDOWS_FONT_DIR = Path("C:/Windows/Fonts")
FONT_BOLD = WINDOWS_FONT_DIR / "segoeuib.ttf"
FONT_REGULAR = WINDOWS_FONT_DIR / "segoeui.ttf"

BG = (247, 243, 236, 255)
TEXT_DARK = (33, 39, 49, 255)
TEXT_MUTED = (89, 98, 112, 255)
TEAL = (17, 155, 170, 255)
ORANGE = (255, 134, 24, 255)


def fit_icon(image: Image.Image, max_size: int) -> Image.Image:
    icon = image.copy()
    icon.thumbnail((max_size, max_size), Image.Resampling.LANCZOS)
    return icon


def draw_shadow(base: Image.Image, box: tuple[int, int, int, int]) -> None:
    shadow = Image.new("RGBA", base.size, (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle(box, radius=36, fill=(0, 0, 0, 42))
    shadow = shadow.filter(ImageFilter.GaussianBlur(22))
    base.alpha_composite(shadow)


def render_logo() -> None:
    canvas = Image.new("RGBA", (1800, 700), BG)
    draw = ImageDraw.Draw(canvas)

    icon = Image.open(ICON_SOURCE).convert("RGBA")
    icon = fit_icon(icon, 360)

    icon_x = 120
    icon_y = (canvas.height - icon.height) // 2
    draw_shadow(canvas, (icon_x + 32, icon_y + 44, icon_x + icon.width + 12, icon_y + icon.height + 18))
    canvas.alpha_composite(icon, (icon_x, icon_y))

    title_font = ImageFont.truetype(str(FONT_BOLD), 228)
    tagline_font = ImageFont.truetype(str(FONT_REGULAR), 58)

    text_x = 560
    title_y = 170

    dual_text = "Dual"
    subs_text = "Subs"
    dual_bbox = draw.textbbox((0, 0), dual_text, font=title_font)
    dual_width = dual_bbox[2] - dual_bbox[0]

    draw.text((text_x, title_y), dual_text, font=title_font, fill=TEXT_DARK)
    draw.text((text_x + dual_width - 8, title_y), subs_text, font=title_font, fill=TEAL)

    accent_y = title_y + 265
    draw.rounded_rectangle((text_x + 6, accent_y, text_x + 208, accent_y + 16), radius=8, fill=ORANGE)
    draw.rounded_rectangle((text_x + 226, accent_y, text_x + 382, accent_y + 16), radius=8, fill=TEAL)

    tagline = "Two subtitles. One screen."
    draw.text((text_x + 8, accent_y + 42), tagline, font=tagline_font, fill=TEXT_MUTED)

    canvas.save(LOGO_OUTPUT)


def render_ico() -> None:
    icon = Image.open(ICON_SOURCE).convert("RGBA")
    sizes = [(256, 256), (128, 128), (64, 64), (48, 48), (32, 32), (16, 16)]
    resized = [icon.resize(size, Image.Resampling.LANCZOS) for size in sizes]
    resized[0].save(ICON_OUTPUT, format="ICO", sizes=sizes)


def main() -> None:
    render_logo()
    render_ico()


if __name__ == "__main__":
    main()
