#!/usr/bin/env -S\_/bin/sh\_-c\_"source\_\${NINOMAE_SHELL_VIRTUAL_ENV:-\$HOME/.local/state/quickshell/.venv}/bin/activate&&exec\_python\_-E\_"\$0"\_"\$@""
import argparse
import math
from PIL import Image
from materialyoucolor.quantize import QuantizeCelebi
from materialyoucolor.score.score import Score
from materialyoucolor.hct import Hct
from materialyoucolor.dynamiccolor.material_dynamic_colors import MaterialDynamicColors
from materialyoucolor.utils.color_utils import (rgba_from_argb, argb_from_rgb)

parser = argparse.ArgumentParser(description='Color generation script')
parser.add_argument('--path', type=str, default=None, help='generate colorscheme from image')
parser.add_argument('--size', type=int , default=128 , help='bitmap image size')
parser.add_argument('--color', type=str, default=None, help='generate colorscheme from color')
parser.add_argument('--mode', type=str, choices=['dark', 'light'], default='dark', help='dark or light mode')
parser.add_argument('--scheme', type=str, default='vibrant', help='material scheme to use')
parser.add_argument('--smart', action='store_true', default=False, help='decide scheme type based on image color')
parser.add_argument('--transparency', type=str, choices=['opaque', 'transparent'], default='opaque', help='enable transparency')
parser.add_argument('--termscheme', action='store_true', default=False, help='also generate terminal colours (term0-15) from the theme')
parser.add_argument('--cache', type=str, default=None, help='file path to store the generated color')
parser.add_argument('--debug', action='store_true', default=False, help='debug mode')
args = parser.parse_args()

rgba_to_hex = lambda rgba: "#{:02X}{:02X}{:02X}".format(rgba[0], rgba[1], rgba[2])
argb_to_hex = lambda argb: "#{:02X}{:02X}{:02X}".format(*map(round, rgba_from_argb(argb)))
hex_to_argb = lambda hex_code: argb_from_rgb(int(hex_code[1:3], 16), int(hex_code[3:5], 16), int(hex_code[5:], 16))
display_color = lambda rgba : "\x1B[38;2;{};{};{}m{}\x1B[0m".format(rgba[0], rgba[1], rgba[2], "\x1b[7m   \x1b[7m")

def calculate_optimal_size (width: int, height: int, bitmap_size: int) -> (int, int):
    image_area = width * height;
    bitmap_area = bitmap_size ** 2
    scale = math.sqrt(bitmap_area/image_area) if image_area > bitmap_area else 1
    new_width = round(width * scale)
    new_height = round(height * scale)
    if new_width == 0:
        new_width = 1
    if new_height == 0:
        new_height = 1
    return new_width, new_height

darkmode = (args.mode == 'dark')
transparent = (args.transparency == 'transparent')

if args.path is not None:
    image = Image.open(args.path)

    if image.format == "GIF":
        image.seek(1)

    if image.mode in ["L", "P"]:
        image = image.convert('RGB')
    wsize, hsize = image.size
    wsize_new, hsize_new = calculate_optimal_size(wsize, hsize, args.size)
    if wsize_new < wsize or hsize_new < hsize:
        image = image.resize((wsize_new, hsize_new), Image.Resampling.BICUBIC)
    # get_flattened_data replaces getdata (removed in Pillow 14); older Pillow only has getdata
    pixels = image.get_flattened_data() if hasattr(image, "get_flattened_data") else image.getdata()
    colors = QuantizeCelebi(list(pixels), 128)
    argb = Score.score(colors)[0]

    if args.cache is not None:
        with open(args.cache, 'w') as file:
            file.write(argb_to_hex(argb))
    hct = Hct.from_int(argb)
    if(args.smart):
        if(hct.chroma < 20):
            args.scheme = 'neutral'
elif args.color is not None:
    argb = hex_to_argb(args.color)
    hct = Hct.from_int(argb)

if args.scheme == 'scheme-fruit-salad':
    from materialyoucolor.scheme.scheme_fruit_salad import SchemeFruitSalad as Scheme
elif args.scheme == 'scheme-expressive':
    from materialyoucolor.scheme.scheme_expressive import SchemeExpressive as Scheme
elif args.scheme == 'scheme-monochrome':
    from materialyoucolor.scheme.scheme_monochrome import SchemeMonochrome as Scheme
elif args.scheme == 'scheme-rainbow':
    from materialyoucolor.scheme.scheme_rainbow import SchemeRainbow as Scheme
elif args.scheme == 'scheme-tonal-spot':
    from materialyoucolor.scheme.scheme_tonal_spot import SchemeTonalSpot as Scheme
elif args.scheme == 'scheme-neutral':
    from materialyoucolor.scheme.scheme_neutral import SchemeNeutral as Scheme
elif args.scheme == 'scheme-fidelity':
    from materialyoucolor.scheme.scheme_fidelity import SchemeFidelity as Scheme
elif args.scheme == 'scheme-content':
    from materialyoucolor.scheme.scheme_content import SchemeContent as Scheme
elif args.scheme == 'scheme-vibrant':
    from materialyoucolor.scheme.scheme_vibrant import SchemeVibrant as Scheme
else:
    from materialyoucolor.scheme.scheme_tonal_spot import SchemeTonalSpot as Scheme
# Generate
scheme = Scheme(hct, darkmode, 0.0)

material_colors = {}
term_colors = {}

for color in vars(MaterialDynamicColors).keys():
    color_name = getattr(MaterialDynamicColors, color)
    if hasattr(color_name, "get_hct"):
        rgba = color_name.get_hct(scheme).to_rgba()
        material_colors[color] = rgba_to_hex(rgba)

# Extended material
if darkmode == True:
    material_colors['success'] = '#B5CCBA'
    material_colors['onSuccess'] = '#213528'
    material_colors['successContainer'] = '#374B3E'
    material_colors['onSuccessContainer'] = '#D1E9D6'
else:
    material_colors['success'] = '#4F6354'
    material_colors['onSuccess'] = '#FFFFFF'
    material_colors['successContainer'] = '#D1E8D5'
    material_colors['onSuccessContainer'] = '#0C1F13'

# Terminal colours: the theme colours VS Code's code editor uses (config/matugen/templates/vscode,
# tokenColors), so kitty looks like the editor and follows the wallpaper. ANSI slots go to roles by what
# terminals use them for: red = errors/removals (the editor's "invalid"), green = success/additions/the
# prompt (primary, the keyword colour), yellow = warnings (light tertiary, like constants), blue = types
# (light secondary), magenta = strings (tertiary), cyan = arguments (onSurfaceVariant, parameters).
# termbg/termfg are the window's background and text (terminal/sequences.txt).
# A colour is (role, tone step): the step moves it toward the text colour (lighter in dark mode, darker
# in light), the way the editor's *Fixed colours are lighter versions of its accents, but mode-aware
TERM_ROLES = {  # ansi number: (normal, bright)
    0: (('surfaceContainerHighest', 0), ('outline', 0)),
    1: (('error', 0), ('error', 10)),
    2: (('primary', 0), ('primary', 10)),
    3: (('tertiary', 10), ('tertiary', 16)),
    4: (('secondary', 10), ('secondary', 16)),
    5: (('tertiary', 0), ('tertiary', 6)),
    6: (('onSurfaceVariant', 0), ('onSurface', 0)),
    7: (('onSurfaceVariant', 0), ('onSurface', 0)),
}
def term_color(role: str, step: float) -> str:
    if step == 0:
        return material_colors[role]
    hct = Hct.from_int(hex_to_argb(material_colors[role]))
    tone = min(hct.tone + step, 96) if darkmode else max(hct.tone - step, 8)
    return argb_to_hex(Hct.from_hct(hct.hue, hct.chroma, tone).to_int())
if args.termscheme:
    for n, (normal, bright) in TERM_ROLES.items():
        term_colors[f'term{n}'] = term_color(*normal)
        term_colors[f'term{n + 8}'] = term_color(*bright)
    term_colors = {f'term{i}': term_colors[f'term{i}'] for i in range(16)}
    term_colors['termbg'] = material_colors['surface']
    term_colors['termfg'] = material_colors['onSurface']

if args.debug == False:
    print(f"$darkmode: {darkmode};")
    print(f"$transparent: {transparent};")
    for color, code in material_colors.items():
        print(f"${color}: {code};")
    for color, code in term_colors.items():
        print(f"${color}: {code};")
else:
    if args.path is not None:
        print('\n--------------Image properties-----------------')
        print(f"Image size: {wsize} x {hsize}")
        print(f"Resized image: {wsize_new} x {hsize_new}")
    print('\n---------------Selected color------------------')
    print(f"Dark mode: {darkmode}")
    print(f"Scheme: {args.scheme}")
    print(f"Accent color: {display_color(rgba_from_argb(argb))} {argb_to_hex(argb)}")
    print(f"HCT: {hct.hue:.2f}  {hct.chroma:.2f}  {hct.tone:.2f}")
    print('\n---------------Material colors-----------------')
    for color, code in material_colors.items():
        rgba = rgba_from_argb(hex_to_argb(code))
        print(f"{color.ljust(32)} : {display_color(rgba)}  {code}")
    print('\n---------------Terminal colors-----------------')
    for color, code in term_colors.items():
        print(f"{color.ljust(6)} : {display_color(rgba_from_argb(hex_to_argb(code)))} {code}")
    print('-----------------------------------------------')
