"""Generate Windows and Android icons from the Ocean Maboy master artwork."""

from __future__ import annotations

import os
import time
from io import BytesIO
from pathlib import Path
from typing import List, Tuple
from PIL import Image, ImageDraw, ImageFilter, ImageOps


def save_png_atomic(image: Image.Image, output_path: Path) -> None:
    """Replace a PNG safely even when Windows briefly scans the old file.

    Android resource folders are watched by Gradle, Explorer, and antivirus
    software. Writing through a sibling temporary file prevents a partially
    truncated mipmap; short retries cover transient Windows sharing locks.
    """
    output_path.parent.mkdir(parents=True, exist_ok=True)
    buffer = BytesIO()
    image.save(buffer, format="PNG")
    temporary_path = output_path.with_name(f".{output_path.name}.{os.getpid()}.tmp")
    temporary_path.write_bytes(buffer.getvalue())

    for attempt in range(5):
        try:
            os.replace(temporary_path, output_path)
            return
        except OSError:
            if attempt == 4:
                temporary_path.unlink(missing_ok=True)
                raise
            time.sleep(0.2 * (attempt + 1))


def extract_centered_disc(
    source_image: Image.Image,
    center_x: int = 831,
    center_y: int = 416,
    disc_radius: int = 385,
) -> Image.Image:
    """Crop the circular glowing disc centered around (center_x, center_y).

    Masks out the bottom text label ('MABOY') with deep black.
    """
    diameter: int = disc_radius * 2
    square_crop: Image.Image = Image.new("RGB", (diameter, diameter), (0, 0, 0))

    src_x1: int = center_x - disc_radius
    src_y1: int = center_y - disc_radius
    src_x2: int = center_x + disc_radius
    src_y2: int = center_y + disc_radius

    # Clamp coordinates to image dimensions
    clamp_x1: int = max(0, src_x1)
    clamp_y1: int = max(0, src_y1)
    clamp_x2: int = min(source_image.width, src_x2)
    clamp_y2: int = min(source_image.height, src_y2)

    dest_x1: int = clamp_x1 - src_x1
    dest_y1: int = clamp_y1 - src_y1

    region: Image.Image = source_image.crop((clamp_x1, clamp_y1, clamp_x2, clamp_y2))
    square_crop.paste(region, (dest_x1, dest_y1))

    # Mask out the text area if within crop bounds:
    # Text is between Y=819 and Y=832 in source coordinates
    text_src_y_start: int = 810
    text_src_y_end: int = 845
    if src_y1 <= text_src_y_end and src_y2 >= text_src_y_start:
        mask_y1: int = max(0, text_src_y_start - src_y1)
        mask_y2: int = min(diameter, text_src_y_end - src_y1)
        draw = ImageDraw.Draw(square_crop)
        draw.rectangle([0, mask_y1, diameter, mask_y2], fill=(0, 0, 0))

    return square_crop


def create_master_icon(
    disc_crop: Image.Image,
    target_canvas_size: int = 1024,
    content_scale: float = 0.84,
) -> Image.Image:
    """Create a high-res square master icon with comfortable padding for desktop/legacy icons."""
    target_disc_size: int = int(round(target_canvas_size * content_scale))
    resized_disc: Image.Image = disc_crop.resize(
        (target_disc_size, target_disc_size), Image.Resampling.LANCZOS
    )

    canvas: Image.Image = Image.new("RGBA", (target_canvas_size, target_canvas_size), (0, 0, 0, 255))
    offset: int = (target_canvas_size - target_disc_size) // 2
    canvas.paste(resized_disc, (offset, offset))
    return canvas


def create_adaptive_foreground(
    disc_crop: Image.Image,
    target_canvas_size: int = 1024,
    safe_zone_scale: float = 0.66,
) -> Image.Image:
    """Create the Android adaptive icon foreground layer fitting inside the 66-70% safe zone.

    The Android adaptive icon canvas is 108x108 dp, with the safe circle viewport being 72x72 dp (66.6%).
    """
    target_disc_size: int = int(round(target_canvas_size * safe_zone_scale))
    resized_disc: Image.Image = disc_crop.resize(
        (target_disc_size, target_disc_size), Image.Resampling.LANCZOS
    )

    # Transparent canvas with centered glowing disc
    canvas: Image.Image = Image.new("RGBA", (target_canvas_size, target_canvas_size), (0, 0, 0, 0))
    offset: int = (target_canvas_size - target_disc_size) // 2
    canvas.paste(resized_disc, (offset, offset))
    return canvas


def generate_windows_ico(master_icon: Image.Image, output_path: Path) -> None:
    """Generate a multi-resolution Windows .ico file with all standard layer sizes."""
    output_path.parent.mkdir(parents=True, exist_ok=True)
    sizes: List[int] = [16, 24, 32, 48, 64, 128, 256]
    images: List[Image.Image] = []

    for sz in sizes:
        resized: Image.Image = master_icon.resize((sz, sz), Image.Resampling.LANCZOS)
        # Apply subtle unsharp mask to crisp up small icon resolutions
        if sz <= 32:
            resized = resized.filter(ImageFilter.UnsharpMask(radius=1, percent=120, threshold=3))
        images.append(resized)

    # Save as ICO with all embedded sizes using standard Windows BMP/DIB bitmaps
    # so Windows Explorer (explorer.exe) can natively extract and display the icon in all views.
    images[-1].save(
        output_path,
        format="ICO",
        sizes=[(s, s) for s in sizes],
        bitmap_format="bmp",
    )


def generate_android_resources(
    master_icon: Image.Image,
    adaptive_foreground: Image.Image,
    res_dir: Path,
) -> None:
    """Generate all legacy and adaptive mipmap icon densities for Android."""
    # Standard mipmap density scale: mdpi=1x (48px), hdpi=1.5x (72px), xhdpi=2x (96px),
    # xxhdpi=3x (144px), xxxhdpi=4x (192px)
    densities: List[Tuple[str, int, int]] = [
        ("mipmap-mdpi", 48, 108),
        ("mipmap-hdpi", 72, 162),
        ("mipmap-xhdpi", 96, 216),
        ("mipmap-xxhdpi", 144, 324),
        ("mipmap-xxxhdpi", 192, 432),
    ]

    for folder_name, legacy_size, adaptive_size in densities:
        folder_path: Path = res_dir / folder_name
        folder_path.mkdir(parents=True, exist_ok=True)

        # 1. Legacy ic_launcher.png
        legacy_icon: Image.Image = master_icon.resize(
            (legacy_size, legacy_size), Image.Resampling.LANCZOS
        )
        if legacy_size <= 48:
            legacy_icon = legacy_icon.filter(ImageFilter.UnsharpMask(radius=1, percent=120, threshold=3))
        save_png_atomic(legacy_icon.convert("RGBA"), folder_path / "ic_launcher.png")

        # 2. Legacy ic_launcher_round.png
        # Create circular masked version for launchers that use round icons
        round_mask: Image.Image = Image.new("L", (legacy_size, legacy_size), 0)
        draw = ImageDraw.Draw(round_mask)
        draw.ellipse((0, 0, legacy_size - 1, legacy_size - 1), fill=255)
        round_icon: Image.Image = Image.new("RGBA", (legacy_size, legacy_size), (0, 0, 0, 0))
        round_icon.paste(legacy_icon, (0, 0), round_mask)
        save_png_atomic(round_icon, folder_path / "ic_launcher_round.png")

        # 3. Adaptive ic_launcher_foreground.png
        fg_icon: Image.Image = adaptive_foreground.resize(
            (adaptive_size, adaptive_size), Image.Resampling.LANCZOS
        )
        save_png_atomic(fg_icon, folder_path / "ic_launcher_foreground.png")

    # 4. XML for adaptive icons in mipmap-anydpi-v26
    anydpi_dir: Path = res_dir / "mipmap-anydpi-v26"
    anydpi_dir.mkdir(parents=True, exist_ok=True)

    adaptive_xml_content = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        '</adaptive-icon>\n'
    )
    (anydpi_dir / "ic_launcher.xml").write_text(adaptive_xml_content, encoding="utf-8")
    (anydpi_dir / "ic_launcher_round.xml").write_text(adaptive_xml_content, encoding="utf-8")

    # 5. Ocean navy fills the area exposed by Android launcher masks.
    values_dir: Path = res_dir / "values"
    values_dir.mkdir(parents=True, exist_ok=True)
    colors_file: Path = values_dir / "colors.xml"

    colors_xml_content = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<resources>\n'
        '    <color name="ic_launcher_background">#10151D</color>\n'
        '</resources>\n'
    )
    colors_file.write_text(colors_xml_content, encoding="utf-8")


def main() -> None:
    root_dir: Path = Path(__file__).resolve().parent.parent.parent
    source_image_path: Path = (
        root_dir / "client" / "assets" / "icon" / "app_icon_source_ocean.png"
    )

    if not source_image_path.exists():
        raise FileNotFoundError(f"Source artwork not found at {source_image_path}")

    print(f"Loading source artwork from {source_image_path}...")
    source_img: Image.Image = Image.open(source_image_path).convert("RGBA")
    master_source: Image.Image = ImageOps.fit(
        source_img,
        (1024, 1024),
        method=Image.Resampling.LANCZOS,
        centering=(0.5, 0.5),
    )

    # Master icons
    assets_dir: Path = root_dir / "client" / "assets" / "icon"
    assets_dir.mkdir(parents=True, exist_ok=True)

    master_icon: Image.Image = master_source
    save_png_atomic(master_icon, assets_dir / "app_icon.png")
    print(f"Generated {assets_dir / 'app_icon.png'}")

    adaptive_fg: Image.Image = create_adaptive_foreground(
        master_source, 1024, safe_zone_scale=0.70
    )
    save_png_atomic(adaptive_fg, assets_dir / "app_icon_adaptive.png")
    print(f"Generated {assets_dir / 'app_icon_adaptive.png'}")

    # Windows .ico
    windows_ico_path: Path = root_dir / "client" / "windows" / "runner" / "resources" / "app_icon.ico"
    generate_windows_ico(master_icon, windows_ico_path)
    print(f"Generated Windows icon {windows_ico_path}")

    # Android mipmaps
    res_dir: Path = root_dir / "client" / "android" / "app" / "src" / "main" / "res"
    generate_android_resources(master_icon, adaptive_fg, res_dir)
    print(f"Generated Android mipmaps and adaptive icons in {res_dir}")

    print("Icon generation completed successfully.")


if __name__ == "__main__":
    main()
