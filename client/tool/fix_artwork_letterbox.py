import os
import glob
from PIL import Image
import numpy as np

def fix_images(folder):
    files = glob.glob(os.path.join(folder, '*.jpg'))
    fixed = 0
    for f in files:
        if os.path.getsize(f) == 0:
            continue
        try:
            with Image.open(f) as im:
                w, h = im.size
                if w == 480 and h == 360:
                    cropped = im.crop((0, 45, 480, 315))
                    cropped.save(f, format='JPEG', quality=95)
                    fixed += 1
                else:
                    arr = np.array(im)
                    if len(arr.shape) == 3 and arr.shape[2] >= 3:
                        top_h = 0
                        for y in range(h // 4):
                            if arr[y, :, :3].mean() < 8:
                                top_h = y + 1
                            else:
                                break
                        bot_h = 0
                        for y in range(h - 1, h - 1 - h // 4, -1):
                            if arr[y, :, :3].mean() < 8:
                                bot_h = h - y
                            else:
                                break
                        if top_h >= 15 and bot_h >= 15:
                            cropped = im.crop((0, top_h, w, h - bot_h))
                            cropped.save(f, format='JPEG', quality=95)
                            fixed += 1
        except Exception:
            pass
    print(f'Done! Fixed {fixed} images.')

if __name__ == '__main__':
    folder = os.path.dirname(os.path.abspath(__file__))
    fix_images(folder)
