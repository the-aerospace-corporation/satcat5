# -*- coding: utf-8 -*-

# Copyright 2024 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

'''
Python tools for manipulating monochrome pixel-art and auto-generating
C/C++ .h files in the SatCat5 format for 8x8, 16x16, and 32x32 icons.
'''

from PIL import Image
import imageio
import numpy as np

def load_png(filename, white_fg = False):
    '''Load a transparent PNG and convert it to monochrome.'''
    src = np.array(Image.open(filename))
    if white_fg:    # White = foreground
        return np.logical_and(src[:,:,1] > 64, src[:,:,3] > 128)
    else:           # Black = foreground
        return np.logical_and(src[:,:,1] < 64, src[:,:,3] > 128)

def to_code(label, data):
    '''
    Convert a binary icon or animation to C++ format.
        * Each frame is an 8x8, 16x16, or 32x32 pixel binary image.
        * Each entry is a uintXX_t containing one row of one frame.
        * Each entry is encoded with the leftmost pixel in the LSB.
    '''
    # First, determine the input format.
    if isinstance(data, list):
        anim  = True
        size0 = data[0].shape[0]
        size1 = data[0].shape[1]
    else:
        anim  = False
        size0 = data.shape[0]
        size1 = data.shape[1]
    assert (size0 <= 32 and size0 == size1)
    # Formatting based on the icon size:
    row2int = lambda row: int(np.sum([2**c for c in range(len(row)) if row[c]]))
    if size0 <= 8:
        typ = 'Icon8x8'
        fmt = lambda row: f'0x{row2int(row):02X}'
    elif size0 <= 16:
        typ = 'Icon16x16'
        fmt = lambda row: f'0x{row2int(row):04X}'
    else:
        typ = 'Icon32x32'
        fmt = lambda row: f'0x{row2int(row):08X}'
    img2str = lambda frm: '{' + ', '.join([fmt(row) for row in frm]) + '}'
    # Print the output in the form of C++ code.
    if anim:
        print(f'constexpr {typ} {label}[] = {{')
        for frame in data:
            print(f'    {img2str(frame)},')
        print('};')
    else:
        print(f'constexpr {typ} {label} =')
        print(f'    {img2str(data)};')

def display(label, data):
    '''Display a binary icon or animation in plaintext.'''
    print('-----' + label + '-----')
    row2str = lambda row: ''.join(['*' if row[c] else ' ' for c in range(len(row))])
    if isinstance(data, list):
        for frame in anim:
            for row in frame: print(row2str(row))
            print('----')
    else:
        for row in data: print(row2str(row))

def grayscale(icon, upscale=1):
    ''''Convert monochrome icon to an Image, with optional upscaling.'''
    repeat   = lambda frm: np.repeat(np.repeat(frm, upscale, 0), upscale, 1)
    to_uint8 = lambda frm: 255 * (1 - frm.astype(np.uint8))
    return Image.fromarray(to_uint8(repeat(icon)))

def to_gif(filename, anim, upscale=1):
    '''Convert an animation to an animated GIF.'''
    frames = [grayscale(frm, upscale) for frm in anim]
    imageio.mimsave(filename, frames)

def to_png(filename, icon, upscale=1):
    '''Convert an icon back to a PNG image.'''
    grayscale(icon, upscale).save(filename, 'PNG')

def aerologo():
    '''
    Extract the Aerospace logo in various sizes.
    (Requires download of 'aerologo.png'.)
    '''
    # Load the input (1568 x 355 pixels) and convert to monochrome.
    src1 = load_png('images/aerologo.png', True)
    size = np.min(src1.shape)
    # Downsample to various sizes.
    icon = lambda x, y: src1[2:x*y:y, 2:x*y:y]
    return {
        'AEROLOGO16':   icon(16, size // 16),
        'AEROLOGO32':   icon(32, size // 32),
    }

def elthen_pixel_art_cat():
    '''
    Extract specific animations from Elthen's cat sprites.
    https://elthen.itch.io/2d-pixel-art-cat-sprites
    (Requires download of 'elthen_pixel_art_cat.png'.)
    '''
    # Load the input and convert to monochrome.
    src1 = load_png('images/elthen_pixel_art_cat.png', False)
    # Each animation frames is 16 pixels wide and 8-18 pixels tall.
    #   * One frame centered every 32 columns: 8-23, 40-55, ...
    #   * One animation per 32 rows, height varies: 0-31, 32-63, ...
    # For simplicity we lock all frames to exactly 16 x 16 pixels
    get_frame = lambda r, c: src1[(32*r+16):(32*r+32), (32*c+8):(32*c+24)]
    # The sheet contains ten animations:
    get_anim = lambda r, ct: [get_frame(r,c) for c in range(ct)]
    sit1    = get_anim(0, 4)    # Sit #1    (4 frames, 12 tall)
    sit2    = get_anim(1, 4)    # Sit #2    (4 frames, 12 tall)
    groom1  = get_anim(2, 4)    # Groom #1  (4 frames, 12 tall)
    groom2  = get_anim(3, 4)    # Groom #2  (4 frames, 12 tall)
    walk    = get_anim(4, 8)    # Walk      (8 frames, 12 tall)
    run     = get_anim(5, 8)    # Run       (8 frames, 13 tall)
    sleep   = get_anim(6, 4)    # Sleep     (4 frames,  8 tall)
    paw     = get_anim(7, 6)    # Paw       (6 frames, 12 tall)
    pounce  = get_anim(8, 7)    # Pounce    (7 frames, 18 tall)
    hiss    = get_anim(9, 8)    # Hiss      (8 frames, 11 tall)
    # Create eight-frame looping animations with labels:
    return {
        'CAT_SIT':      sit1 + sit2,
        'CAT_GROOM':    groom1 + groom2,
        'CAT_WALK':     walk,
        'CAT_RUN':      run,
        'CAT_SLEEP':    [sleep[n]  for n in [0,0,0,0,0,1,2,3]],
        'CAT_PAW':      [paw[n]    for n in [0,0,0,1,2,3,4,5]],
        'CAT_POUNCE':   [pounce[n] for n in [0,0,1,2,3,4,5,6]],
        'CAT_HISS':     hiss,
    }

# Default when run from command line:
if __name__ == "__main__":
    # Example using a static image.
    aero = aerologo()
    for label, icon in aero.items():
        display(label, icon)
    for label, icon in aero.items():
        to_code(label, icon)
    for label, icon in aero.items():
        to_png(f'images/{label}.png', icon, 4)
    # Example using animations.
    elthen = elthen_pixel_art_cat()
    for label, anim in elthen.items():
        to_code(label, anim)
    for label, anim in elthen.items():
        to_gif(f'images/{label}.gif', anim, 4)
