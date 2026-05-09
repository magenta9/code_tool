export interface WordCloudToken {
  text: string;
  count: number;
  weight: number;
}

export interface WordCloudResult {
  tokens: WordCloudToken[];
  totalWords: number;
  uniqueWords: number;
}

const defaultStopWords = new Set([
  "a",
  "an",
  "and",
  "are",
  "as",
  "at",
  "be",
  "but",
  "by",
  "for",
  "from",
  "in",
  "is",
  "it",
  "of",
  "on",
  "or",
  "that",
  "the",
  "this",
  "to",
  "with"
]);

export function analyzeWordCloud(text: string, stopWords = defaultStopWords): WordCloudResult {
  const words = text
    .toLowerCase()
    .match(/[\p{L}\p{N}][\p{L}\p{N}'-]*/gu) ?? [];
  const counts = new Map<string, number>();
  for (const word of words) {
    if (word.length < 2 || stopWords.has(word)) continue;
    counts.set(word, (counts.get(word) ?? 0) + 1);
  }
  const max = Math.max(1, ...counts.values());
  const tokens = [...counts.entries()]
    .map(([token, count]) => ({ text: token, count, weight: Number((count / max).toFixed(3)) }))
    .sort((left, right) => right.count - left.count || left.text.localeCompare(right.text))
    .slice(0, 80);
  return { tokens, totalWords: words.length, uniqueWords: counts.size };
}
