const Jimp = require('jimp');

const MAX_EDGE = 1080;
const BLUR_PX = 22;

/**
 * Processes a profile photo for one viewer (PRD §4.3):
 *   - resize to a sane max edge
 *   - blur when the owner's privacy mode hasn't revealed to this viewer
 *   - stamp a light diagonal watermark carrying the VIEWER's id, so any
 *     leaked screenshot is traceable to who saw it
 * Pure transform: bytes in, JPEG bytes out. No I/O, no permissions here.
 */
async function processPhoto(buffer, { blur, watermarkText }) {
  const img = await Jimp.read(buffer);
  img.scaleToFit(MAX_EDGE, MAX_EDGE);

  if (blur) {
    img.blur(BLUR_PX);
    // Darken slightly so a blurred photo reads as intentionally veiled.
    img.brightness(-0.15);
  }

  if (watermarkText) {
    const font = await Jimp.loadFont(Jimp.FONT_SANS_16_WHITE);
    const { width, height } = img.bitmap;
    const mark = new Jimp(width, height, 0x00000000);
    const label = `ikhlas · ${watermarkText}`;
    for (let y = -height; y < height * 2; y += 140) {
      for (let x = -width; x < width * 2; x += 360) {
        mark.print(font, x, y, label);
      }
    }
    mark.rotate(-30, false);
    mark.opacity(0.10);
    // Center the rotated (larger) layer over the photo.
    const ox = Math.round((width - mark.bitmap.width) / 2);
    const oy = Math.round((height - mark.bitmap.height) / 2);
    img.composite(mark, ox, oy);
  }

  img.quality(82);
  return img.getBufferAsync(Jimp.MIME_JPEG);
}

/**
 * Decides whether `viewer` may see `owner`'s photos and whether they must
 * be blurred, from the owner's privacy mode and the relationship.
 * @returns {{allowed:boolean, blur:boolean}}
 */
function decideVisibility({ privacy, matched, revealGranted, inViewerBatch }) {
  // No relationship at all → never served.
  if (!matched && !inViewerBatch) return { allowed: false, blur: false };

  switch (privacy) {
    case 'public': // (legacy: 'visible')
    case 'visible':
      return { allowed: true, blur: false };
    case 'on_mutual_hidden': // (legacy: 'request_only')
    case 'request_only':
      // Hidden even after matching until the owner approves a reveal request.
      // Pre-match (batch only) it is never shown.
      if (!matched) return { allowed: false, blur: false };
      return revealGranted
        ? { allowed: true, blur: false }
        : { allowed: false, blur: false };
    case 'on_mutual_blur': // (legacy: 'blur_until_match')
    case 'blur_until_match':
    default:
      // Symmetric auto-reveal on a mutual match; blurred to a same-day batch.
      return { allowed: true, blur: !matched };
  }
}

module.exports = { processPhoto, decideVisibility };
