// frontend/src/lib/mediaCache.js

const decodedImageUrls = new Set();
const decodingPromises = new Map();

/**
 * Decodes an image off the main thread before inserting into the DOM.
 * Prevents UI thread stutter on swipe.
 */
export async function ensureImageDecoded(url) {
  if (!url || decodedImageUrls.has(url)) return true;
  if (decodingPromises.has(url)) return decodingPromises.get(url);

  const promise = (async () => {
    try {
      const img = new Image();
      img.src = url;
      img.decoding = 'async';
      await img.decode();
      decodedImageUrls.add(url);
      return true;
    } catch {
      return false;
    } finally {
      decodingPromises.delete(url);
    }
  })();

  decodingPromises.set(url, promise);
  return promise;
}

export function isImageDecoded(url) {
  return decodedImageUrls.has(url);
}