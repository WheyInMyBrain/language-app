// frontend/src/lib/services/morphologyStory.js
import { fetchGlyphDetails } from './glyphLexicon.js';

/**
 * Parses Unicode Ideographic Description Characters (IDS)
 * Returns { operator, parts }
 * e.g. "⿰足各" -> operator: "⿰" (left-right), parts: ["足", "各"]
 */
export function parseMorphDecomposition(decomp = '') {
  if (!decomp) return { operator: 'atom', parts: [] };

  const idsOperators = ['⿰', '⿱', '⿲', '⿳', '⿴', '⿵', '⿶', '⿷', '⿸', '⿹', '⿺', '⿻'];
  let operator = 'atom';

  const opChar = decomp.charAt(0);
  if (idsOperators.includes(opChar)) {
    operator = opChar;
  }

  // Strip all IDS operators to isolate pure component glyphs
  const cleanParts = Array.from(decomp.replace(/[\u2FF0-\u2FFB]/g, '')).filter(Boolean);

  return { operator, parts: cleanParts };
}

export function getSpatialLayout(operator) {
  switch (operator) {
    case '⿰':
    case '⿲':
      return { type: 'horizontal', label: 'Side by Side', icon: 'left-right' };
    case '⿱':
    case '⿳':
      return { type: 'vertical', label: 'Top & Bottom', icon: 'top-bottom' };
    case '⿴':
    case '⿵':
    case '⿶':
    case '⿷':
    case '⿸':
    case '⿹':
    case '⿺':
      return { type: 'enclosure', label: 'Surrounded', icon: 'surround' };
    default:
      return { type: 'atom', label: 'Unified', icon: 'single' };
  }
}

/**
 * Resolves which stroke indices in the parent belong to Component 1 vs Component 2
 */
export async function resolveMorphPartitions(lang, parentData) {
  const totalStrokes = parentData?.strokes?.length || 0;
  if (totalStrokes === 0) {
    return { comp1Indices: new Set(), comp2Indices: new Set() };
  }

  // Tier 1: Explicit DB indices
  if (parentData.component1_strokes && parentData.component1_strokes.length > 0) {
    const comp1 = new Set(parentData.component1_strokes);
    const comp2 = new Set();
    for (let i = 0; i < totalStrokes; i++) {
      if (!comp1.has(i)) comp2.add(i);
    }
    return { comp1Indices: comp1, comp2Indices: comp2 };
  }

  const { operator, parts } = parseMorphDecomposition(parentData.component2 || parentData.decomposition);
  const comp1Char = parentData.component1 || parts[0];

  // Tier 2: Check standalone component stroke count
  if (comp1Char) {
    try {
      const childData = await fetchGlyphDetails(lang, comp1Char);
      const childCount = childData?.strokes?.length;
      if (childCount && childCount > 0 && childCount < totalStrokes) {
        const comp1 = new Set();
        for (let i = 0; i < childCount; i++) comp1.add(i);
        const comp2 = new Set();
        for (let i = childCount; i < totalStrokes; i++) comp2.add(i);
        return { comp1Indices: comp1, comp2Indices: comp2 };
      }
    } catch {}
  }

  // Tier 3: Spatial Median Partitioning (99% heuristic based on operator)
  // '⿰' left-right split: strokes with average X < 512 belong to left
  const comp1 = new Set();
  const comp2 = new Set();

  if (parentData.medians && parentData.medians.length === totalStrokes) {
    parentData.medians.forEach((pts, idx) => {
      if (!pts || pts.length === 0) return;
      const avgX = pts.reduce((sum, p) => sum + p[0], 0) / pts.length;
      const avgY = pts.reduce((sum, p) => sum + p[1], 0) / pts.length;

      if (operator === '⿱' || operator === '⿳') {
        // Top-bottom split: higher Y in font coords means top component
        if (avgY > 500) comp1.add(idx);
        else comp2.add(idx);
      } else {
        // Default / Left-right split: left X belongs to comp 1
        if (avgX < 490) comp1.add(idx);
        else comp2.add(idx);
      }
    });

    if (comp1.size > 0 && comp2.size > 0) {
      return { comp1Indices: comp1, comp2Indices: comp2 };
    }
  }

  // Fallback: Equal split
  const half = Math.ceil(totalStrokes / 2);
  for (let i = 0; i < half; i++) comp1.add(i);
  for (let i = half; i < totalStrokes; i++) comp2.add(i);

  return { comp1Indices: comp1, comp2Indices: comp2 };
}