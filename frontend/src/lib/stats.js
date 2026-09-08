export function formatHoursMins(totalSeconds) {
  const secs = Math.max(0, Math.round(totalSeconds || 0));
  const hrs = Math.floor(secs / 3600);
  const mins = Math.floor((secs % 3600) / 60);
  if (hrs === 0) return `${mins}m`;
  return `${hrs}h ${mins}m`;
}

export function formatMinutes(totalSeconds) {
  const mins = Math.round((totalSeconds || 0) / 60);
  return `${mins}m`;
}

export function calculateMedian(values) {
  if (!values || values.length === 0) return 0;
  const sorted = [...values].filter((v) => v > 0).sort((a, b) => a - b);
  if (sorted.length === 0) return 0;
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 !== 0 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}

export function calculateETA(current, target, medianDailyRate, isTime = false) {
  if (current >= target) {
    return { badge: 'Done', pace: 'Target reached', est: 'Complete', remainingDays: 0 };
  }
  if (!medianDailyRate || medianDailyRate <= 0) {
    return { badge: 'Pending', pace: 'No active pace', est: 'TBD', remainingDays: null };
  }

  const remaining = target - current;
  const daysNeeded = Math.ceil(remaining / medianDailyRate);

  const targetDate = new Date();
  targetDate.setDate(targetDate.getDate() + daysNeeded);

  const estDateStr = targetDate.toLocaleDateString(undefined, {
    month: 'short',
    year: 'numeric'
  });

  const formattedRate = isTime
    ? `${Math.round(medianDailyRate / 60)}m/d`
    : `${medianDailyRate % 1 === 0 ? medianDailyRate : medianDailyRate.toFixed(1)}/d`;

  return {
    badge: `${daysNeeded}d left`,
    pace: formattedRate,
    est: estDateStr,
    remainingDays: daysNeeded
  };
}

export function buildSmoothPath(points) {
  if (!points || points.length === 0) return '';
  if (points.length === 1) return `M ${points[0][0]},${points[0][1]}`;

  let d = `M ${points[0][0]},${points[0][1]}`;
  for (let i = 0; i < points.length - 1; i++) {
    const p0 = points[i === 0 ? 0 : i - 1];
    const p1 = points[i];
    const p2 = points[i + 1];
    const p3 = points[i + 2] || p2;

    const cp1x = p1[0] + (p2[0] - p0[0]) / 6;
    const cp1y = p1[1] + (p2[1] - p0[1]) / 6;
    const cp2x = p2[0] - (p3[0] - p1[0]) / 6;
    const cp2y = p2[1] - (p3[1] - p1[1]) / 6;

    d += ` C ${cp1x},${cp1y} ${cp2x},${cp2y} ${p2[0]},${p2[1]}`;
  }
  return d;
}