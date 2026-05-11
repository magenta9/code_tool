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
  "with",
  "一个",
  "一些",
  "以及",
  "他们",
  "你们",
  "我们",
  "这个",
  "那个",
  "这些",
  "那些",
  "然后",
  "因为",
  "所以",
  "如果",
  "但是",
  "就是",
  "可以",
  "没有",
  "不是",
  "还是",
  "进行",
  "通过",
  "需要",
  "为了",
  "的",
  "了",
  "和",
  "与",
  "及",
  "把",
  "被",
  "在",
  "是",
  "有",
  "也",
  "都",
  "就",
  "而",
  "并",
  "或",
  "从",
  "到",
  "为",
  "对",
  "中",
  "上",
  "下"
]);

type SegmenterEntry = {
  segment: string;
  isWordLike?: boolean;
};

type SegmenterInstance = {
  segment(input: string): Iterable<SegmenterEntry>;
};

type SegmenterConstructor = new (
  locales?: string | string[],
  options?: { granularity: "word" }
) => SegmenterInstance;

const fallbackWordPattern = /[\p{L}\p{N}][\p{L}\p{N}'’-]*/gu;
const edgePunctuationPattern = /^[\p{Pd}'’]+|[\p{Pd}'’]+$/gu;
const alphaNumericPattern = /[\p{Script=Latin}\p{N}]/u;
const cjkPattern = /\p{Script=Han}/u;

function normalizeToken(token: string): string {
  return token.normalize("NFKC").replaceAll("’", "'").trim().toLowerCase().replace(edgePunctuationPattern, "");
}

function isCountableToken(token: string, stopWords: ReadonlySet<string>): boolean {
  if (!token) {
    return false;
  }

  if (stopWords.has(token)) {
    return false;
  }

  if (alphaNumericPattern.test(token) && token.length < 2) {
    return false;
  }

  if (!alphaNumericPattern.test(token) && !cjkPattern.test(token) && token.length < 2) {
    return false;
  }

  return true;
}

function segmentWithIntl(text: string): string[] | null {
  const segmenterConstructor = (Intl as typeof Intl & { Segmenter?: SegmenterConstructor }).Segmenter;
  if (!segmenterConstructor) {
    return null;
  }

  const segmenter = new segmenterConstructor(["zh-Hans", "en"], { granularity: "word" });
  const tokens: string[] = [];

  for (const entry of segmenter.segment(text)) {
    if (entry.isWordLike === false) {
      continue;
    }

    const normalized = normalizeToken(entry.segment);
    if (!normalized || !/[\p{L}\p{N}]/u.test(normalized)) {
      continue;
    }

    tokens.push(normalized);
  }

  return tokens;
}

function tokenize(text: string): string[] {
  const segmented = segmentWithIntl(text);
  if (segmented) {
    return segmented;
  }

  return (text.toLowerCase().match(fallbackWordPattern) ?? []).map((word) => normalizeToken(word)).filter(Boolean);
}

export function analyzeWordCloud(text: string, stopWords = defaultStopWords): WordCloudResult {
  const words = tokenize(text);
  const counts = new Map<string, number>();
  for (const word of words) {
    if (!isCountableToken(word, stopWords)) continue;
    counts.set(word, (counts.get(word) ?? 0) + 1);
  }
  const max = Math.max(1, ...counts.values());
  const tokens = [...counts.entries()]
    .map(([token, count]) => ({ text: token, count, weight: Number((count / max).toFixed(3)) }))
    .sort((left, right) => right.count - left.count || left.text.localeCompare(right.text))
    .slice(0, 80);
  return { tokens, totalWords: words.length, uniqueWords: counts.size };
}
