"""Generate the transparent Maboy m> mark for Windows and Android."""

from __future__ import annotations

import os
import time
from io import BytesIO
from pathlib import Path

from PIL import Image, ImageDraw


MASTER_SIZE = 1024
SUPERSAMPLE = 2
MARK_COLOR = (165, 170, 178, 255)
OUTLINE_COLOR = (28, 30, 35, 255)
ICON_SIZES = (16, 24, 32, 48, 64, 128, 256)
ANDROID_DENSITIES = (
    ("mipmap-mdpi", 48, 108),
    ("mipmap-hdpi", 72, 162),
    ("mipmap-xhdpi", 96, 216),
    ("mipmap-xxhdpi", 144, 324),
    ("mipmap-xxxhdpi", 192, 432),
)


def replace_bytes_atomic(data: bytes, output_path: Path) -> None:
    """Avoid partially written launcher resources while Gradle watches them."""
    output_path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path = output_path.with_name(f".{output_path.name}.{os.getpid()}.tmp")
    temporary_path.write_bytes(data)
    for attempt in range(5):
        try:
            os.replace(temporary_path, output_path)
            return
        except OSError:
            if attempt == 4:
                temporary_path.unlink(missing_ok=True)
                raise
            time.sleep(0.2 * (attempt + 1))


def save_image(image: Image.Image, path: Path, image_format: str = "PNG", **options: object) -> None:
    buffer = BytesIO()
    image.save(buffer, format=image_format, **options)
    replace_bytes_atomic(buffer.getvalue(), path)


def cubic_points(
    start: tuple[int, int],
    control_a: tuple[int, int],
    control_b: tuple[int, int],
    end: tuple[int, int],
    steps: int = 40,
) -> list[tuple[int, int]]:
    points: list[tuple[int, int]] = []
    for step in range(steps + 1):
        t = step / steps
        reverse = 1 - t
        x = (
            reverse**3 * start[0]
            + 3 * reverse**2 * t * control_a[0]
            + 3 * reverse * t**2 * control_b[0]
            + t**3 * end[0]
        )
        y = (
            reverse**3 * start[1]
            + 3 * reverse**2 * t * control_a[1]
            + 3 * reverse * t**2 * control_b[1]
            + t**3 * end[1]
        )
        points.append((round(x * SUPERSAMPLE), round(y * SUPERSAMPLE)))
    return points


def draw_rounded_stroke(
    draw: ImageDraw.ImageDraw,
    points: list[tuple[int, int]],
    width: int,
    color: tuple[int, int, int, int],
) -> None:
    scaled_width = width * SUPERSAMPLE
    draw.line(points, fill=color, width=scaled_width, joint="curve")
    radius = scaled_width // 2
    for x, y in (points[0], points[-1]):
        draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=color)


def create_mark() -> Image.Image:
    """Draw only m> strokes; alpha remains zero outside the letterform.

    The dark edge keeps the light mark legible on both dark taskbars and light
    launchers. Bezier arches stay in the Android adaptive icon safe zone.
    """
    canvas = Image.new(
        "RGBA", (MASTER_SIZE * SUPERSAMPLE, MASTER_SIZE * SUPERSAMPLE), (0, 0, 0, 0)
    )
    draw = ImageDraw.Draw(canvas)
    first_arch = cubic_points((142, 445), (142, 310), (366, 310), (366, 445))
    second_arch = cubic_points((366, 445), (366, 310), (590, 310), (590, 445))
    letter_m = [
        (142 * SUPERSAMPLE, 686 * SUPERSAMPLE),
        *first_arch,
        (366 * SUPERSAMPLE, 686 * SUPERSAMPLE),
    ]
    second_hump = [*second_arch, (590 * SUPERSAMPLE, 686 * SUPERSAMPLE)]
    chevron = [
        (665 * SUPERSAMPLE, 375 * SUPERSAMPLE),
        (855 * SUPERSAMPLE, 520 * SUPERSAMPLE),
        (665 * SUPERSAMPLE, 665 * SUPERSAMPLE),
    ]
    for color, width in ((OUTLINE_COLOR, 100), (MARK_COLOR, 78)):
        for points in (letter_m, second_hump, chevron):
            draw_rounded_stroke(draw, points, width, color)
    return canvas.resize((MASTER_SIZE, MASTER_SIZE), Image.Resampling.LANCZOS)


def create_adaptive_foreground(master: Image.Image) -> Image.Image:
    # The mark occupies about 79% of the master. At 82% scale it fits the
    # Android adaptive icon's central 66% safe region, including the stroke.
    content_size = round(MASTER_SIZE * 0.82)
    content = master.resize((content_size, content_size), Image.Resampling.LANCZOS)
    foreground = Image.new("RGBA", (MASTER_SIZE, MASTER_SIZE), (0, 0, 0, 0))
    offset = (MASTER_SIZE - content_size) // 2
    foreground.alpha_composite(content, (offset, offset))
    return foreground


def generate_android_resources(
    master: Image.Image,
    foreground: Image.Image,
    monochrome_foreground: Image.Image,
    res_dir: Path,
) -> None:
    for folder_name, legacy_size, adaptive_size in ANDROID_DENSITIES:
        folder = res_dir / folder_name
        legacy = master.resize((legacy_size, legacy_size), Image.Resampling.LANCZOS)
        adaptive = foreground.resize(
            (adaptive_size, adaptive_size), Image.Resampling.LANCZOS
        )
        themed = monochrome_foreground.resize(
            (adaptive_size, adaptive_size), Image.Resampling.LANCZOS
        )
        save_image(legacy, folder / "ic_launcher.png")
        save_image(legacy, folder / "ic_launcher_round.png")
        save_image(adaptive, folder / "ic_launcher_foreground.png")
        save_image(themed, folder / "ic_launcher_monochrome.png")

    xml = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>\n'
        '</adaptive-icon>\n'
    )
    anydpi = res_dir / "mipmap-anydpi-v26"
    anydpi.mkdir(parents=True, exist_ok=True)
    (anydpi / "ic_launcher.xml").write_text(xml, encoding="utf-8")
    (anydpi / "ic_launcher_round.xml").write_text(xml, encoding="utf-8")

    colors = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<resources>\n'
        '    <color name="ic_launcher_background">#00000000</color>\n'
        '</resources>\n'
    )
    values = res_dir / "values"
    values.mkdir(parents=True, exist_ok=True)
    (values / "colors.xml").write_text(colors, encoding="utf-8")


def main() -> None:
    client = Path(__file__).resolve().parent.parent
    assets = client / "assets" / "icon"
    master = create_mark()
    foreground = create_adaptive_foreground(master)
    monochrome = Image.new("RGBA", master.size, (255, 255, 255, 0))
    monochrome.putalpha(master.getchannel("A"))
    monochrome_foreground = create_adaptive_foreground(monochrome)
    save_image(master, assets / "app_icon.png")
    save_image(foreground, assets / "app_icon_adaptive.png")
    save_image(monochrome_foreground, assets / "app_icon_monochrome.png")
    save_image(
        master,
        client / "windows" / "runner" / "resources" / "app_icon.ico",
        image_format="ICO",
        sizes=[(size, size) for size in ICON_SIZES],
    )
    generate_android_resources(
        master,
        foreground,
        monochrome_foreground,
        client / "android" / "app" / "src" / "main" / "res",
    )
    print("Generated transparent m> icons for Windows and Android.")


if __name__ == "__main__":
    main()
