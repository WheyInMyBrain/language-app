// frontend/src/lib/services/decompositionResolver.js

/**
 * Calculates the bounding centroid (center x, y) of specific stroke indices in 1024x1024 space.
 */
export function getStrokesCentroid(medians, strokeIndices) {
  if (!medians || !strokeIndices || strokeIndices.length === 0) {
    return { x: 512, y: 512 };
  }

  let totalX = 0;
  let totalY = 0;
  let count = 0;

  for (const idx of strokeIndices) {
    const pts = medians[idx];
    if (pts && pts.length > 0) {
      for (const [x, y] of pts) {
        totalX += x;
        // Inverted coordinate conversion to standard SVG top-left
        totalY += (900 - y);
        count++;
      }
    }
  }

  if (count === 0) return { x: 512, y: 512 };
  return {
    x: Math.round(totalX / count),
    y: Math.round(totalY / count)
  };
}

/**
 * Extracts distinct component characters from Unicode IDS decomposition string
 * e.g., "⿰亻尔" -> ["亻", "尔"], "⿱艹化" -> ["艹", "化"]
 */
export function parseDecomposition(decompStr) {
  if (!decompStr) return [];
  // Strip Unicode Ideographic Description Characters (U+2FF0 to U+2FFB)
  const cleaned = decompStr.replace(/[\u2FF0-\u2FFB]/g, '');
  return Array.from(cleaned).filter(Boolean);
}