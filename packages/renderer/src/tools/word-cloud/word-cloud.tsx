import { startTransition, useEffect, useRef, useState } from "react";
import type { WordCloudResult } from "@codetool/shared";
import { Cloud } from "lucide-react";
import { getApi } from "../../api";
import { ActionButton, Panel, StatusStrip, TextArea, ToolLayout } from "../../components/tool-layout";

type PreviewPhase = "idle" | "drawing" | "ready" | "empty" | "unsupported" | "error";

type WordCloudModule = ((element: HTMLElement | HTMLElement[], options: WordCloudOptions) => void) & {
  isSupported: boolean;
  stop(): void;
};

type WordCloudOptions = {
  list: Array<[string, number]>;
  backgroundColor: string;
  clearCanvas: boolean;
  color: (word: string, weight: string | number, fontSize: number, distance: number, theta: number) => string;
  fontFamily: string;
  gridSize: number;
  minRotation: number;
  maxRotation: number;
  rotateRatio: number;
  rotationSteps: number;
  shape: string;
  shrinkToFit: boolean;
  shuffle: boolean;
  wait: number;
  weightFactor: (weight: number) => number;
};

const sampleText = "CodeTool helps teams inspect logs, compare JSON, decode tokens, and generate reliable word clouds.";
const previewPalette = ["#d8ff63", "#9ee7ff", "#ffd27a", "#ff9e7a", "#b9f27e"];
const fallbackPreviewColor = "#d8ff63";
let wordCloudModulePromise: Promise<WordCloudModule> | null = null;

async function loadWordCloudModule(): Promise<WordCloudModule> {
  if (!wordCloudModulePromise) {
    wordCloudModulePromise = import("wordcloud").then((module) => (module.default ?? module) as WordCloudModule);
  }

  return wordCloudModulePromise;
}

function pickPreviewColor(word: string, weight: string | number): string {
  const numericWeight = typeof weight === "number" ? weight : Number(weight);
  const seed = [...word].reduce((total, char) => total + char.charCodeAt(0), Math.round(numericWeight));
  return previewPalette[seed % previewPalette.length] ?? fallbackPreviewColor;
}

export function WordCloudPage(): JSX.Element {
  const [text, setText] = useState(sampleText);
  const [result, setResult] = useState<WordCloudResult | null>(null);
  const [isAnalyzing, setIsAnalyzing] = useState(false);
  const [previewPhase, setPreviewPhase] = useState<PreviewPhase>("idle");
  const [previewError, setPreviewError] = useState<string | null>(null);
  const [previewSize, setPreviewSize] = useState({ width: 0, height: 0 });
  const previewRef = useRef<HTMLDivElement | null>(null);
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const wordCloudRef = useRef<WordCloudModule | null>(null);

  useEffect(() => {
    const previewElement = previewRef.current;
    if (!previewElement) {
      return;
    }

    const updateSize = (): void => {
      const bounds = previewElement.getBoundingClientRect();
      const nextWidth = Math.round(bounds.width);
      const nextHeight = Math.round(bounds.height || 420);
      setPreviewSize((current) =>
        current.width === nextWidth && current.height === nextHeight
          ? current
          : { width: nextWidth, height: nextHeight }
      );
    };

    updateSize();

    if (typeof ResizeObserver === "undefined") {
      window.addEventListener("resize", updateSize);
      return () => window.removeEventListener("resize", updateSize);
    }

    const resizeObserver = new ResizeObserver(updateSize);
    resizeObserver.observe(previewElement);
    return () => resizeObserver.disconnect();
  }, []);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) {
      return;
    }

    if (!result) {
      setPreviewPhase("idle");
      setPreviewError(null);
      return;
    }

    if (result.tokens.length === 0) {
      setPreviewPhase("empty");
      setPreviewError(null);
      canvas.width = canvas.width;
      return;
    }

    if (previewSize.width === 0 || previewSize.height === 0) {
      return;
    }

    let disposed = false;
    let handleStop: EventListener | null = null;
    let handleAbort: EventListener | null = null;

    const renderPreview = async (): Promise<void> => {
      const wordCloud = wordCloudRef.current ?? (await loadWordCloudModule());
      wordCloudRef.current = wordCloud;

      if (disposed) {
        return;
      }

      if (!wordCloud.isSupported) {
        setPreviewPhase("unsupported");
        setPreviewError("Current browser runtime does not support canvas word cloud rendering.");
        canvas.width = canvas.width;
        return;
      }

      canvas.width = previewSize.width;
      canvas.height = previewSize.height;
      setPreviewPhase("drawing");
      setPreviewError(null);

      handleStop = () => {
        if (!disposed) {
          setPreviewPhase("ready");
        }
      };

      handleAbort = () => {
        if (!disposed) {
          setPreviewPhase("error");
          setPreviewError("Preview rendering took too long and was stopped.");
        }
      };

      canvas.addEventListener("wordcloudstop", handleStop);
      canvas.addEventListener("wordcloudabort", handleAbort);
      wordCloud.stop();
      wordCloud(canvas, {
        list: result.tokens.slice(0, 60).map((token) => [token.text, Math.round(18 + token.weight * 72)]),
        backgroundColor: "#ffffff",
        clearCanvas: true,
        color: pickPreviewColor,
        fontFamily: '"Aptos", "Segoe UI", system-ui, sans-serif',
        gridSize: Math.max(10, Math.round(previewSize.width / 30)),
        minRotation: -Math.PI / 4,
        maxRotation: Math.PI / 4,
        rotateRatio: 0.16,
        rotationSteps: 2,
        shape: "circle",
        shrinkToFit: true,
        shuffle: false,
        wait: 0,
        weightFactor: (weight) => Number(weight)
      });
    };

    void renderPreview();

    return () => {
      disposed = true;
      if (handleStop) {
        canvas.removeEventListener("wordcloudstop", handleStop);
      }
      if (handleAbort) {
        canvas.removeEventListener("wordcloudabort", handleAbort);
      }
      wordCloudRef.current?.stop();
    };
  }, [previewSize.height, previewSize.width, result]);

  const topToken = result?.tokens[0] ?? null;

  const handleAnalyze = async (): Promise<void> => {
    if (!text.trim()) {
      return;
    }

    setIsAnalyzing(true);
    setPreviewError(null);

    try {
      const nextResult = await getApi().tools.analyzeWordCloud({ text });
      startTransition(() => {
        setResult(nextResult);
        setPreviewPhase(nextResult.tokens.length > 0 ? "drawing" : "empty");
      });
    } finally {
      setIsAnalyzing(false);
    }
  };

  return (
    <ToolLayout
      title="Word Cloud"
      description="Generate a canvas word cloud from text with deterministic ranking and better multilingual segmentation."
    >
      <div className="grid gap-5 xl:grid-cols-[420px_minmax(0,1fr)]">
        <Panel
          title="Source text"
          actions={
            <ActionButton type="button" variant="primary" onClick={() => void handleAnalyze()} disabled={!text.trim() || isAnalyzing}>
              <Cloud size={14} /> {isAnalyzing ? "Generating..." : result ? "Recompute" : "Generate cloud"}
            </ActionButton>
          }
        >
          <TextArea value={text} onChange={(event) => setText(event.target.value)} className="min-h-[360px]" />
          <div className="mt-3 text-[12px] leading-6 text-[var(--app-text-muted)]">
            Supports deterministic English ranking and improved Chinese segmentation when the runtime exposes Intl.Segmenter.
          </div>
        </Panel>
        <div className="grid gap-4">
          <StatusStrip>
            <div className="grid gap-3 sm:grid-cols-3">
              <MetricCard label="Total words" value={result ? String(result.totalWords) : "--"} />
              <MetricCard label="Unique words" value={result ? String(result.uniqueWords) : "--"} />
              <MetricCard
                label="Top token"
                value={topToken ? `${topToken.text} x${topToken.count}` : previewPhase === "idle" ? "Run analysis" : "--"}
              />
            </div>
          </StatusStrip>
          <Panel title="Preview" className="overflow-hidden">
            <div
              ref={previewRef}
              className="relative min-h-[420px] overflow-hidden rounded-[8px] border border-[var(--ui-border)] bg-[var(--ui-surface)]"
            >
              <canvas ref={canvasRef} className="h-full w-full" />
              {previewPhase === "idle" ? (
                <EmptyState
                  title="Preview is ready"
                  description={text.trim() ? "Generate the cloud to render the current text sample." : "Add text to enable the preview."}
                />
              ) : null}
              {previewPhase === "empty" ? (
                <EmptyState title="No terms survived filtering" description="Try removing stop words or adding more repeated terms." />
              ) : null}
              {previewPhase === "unsupported" || previewPhase === "error" ? (
                <EmptyState title="Preview unavailable" description={previewError ?? "Canvas rendering is unavailable in this environment."} />
              ) : null}
              {previewPhase === "drawing" ? (
                <div className="pointer-events-none absolute inset-x-4 top-4 rounded-[8px] border border-[var(--ui-border)] bg-[rgba(255,255,255,0.88)] px-3.5 py-2.5 text-[12px] text-[var(--ui-text)] backdrop-blur">
                  Rendering preview for {result?.tokens.length ?? 0} ranked terms...
                </div>
              ) : null}
            </div>
            <div className="mt-3 flex flex-wrap items-center justify-between gap-3 text-[12px] text-[var(--ui-text-muted)]">
              <span>Resize the window to reflow the cloud inside the current panel.</span>
              <span>{result ? `Showing up to ${Math.min(result.tokens.length, 60)} words` : "No preview generated yet"}</span>
            </div>
          </Panel>
        </div>
      </div>
    </ToolLayout>
  );
}

function MetricCard({ label, value }: { label: string; value: string }): JSX.Element {
  return (
    <div className="rounded-[8px] border border-[var(--ui-border)] bg-[var(--ui-surface)] px-3.5 py-3">
      <div className="text-[11px] uppercase tracking-[0.14em] text-[var(--ui-text-muted)]">{label}</div>
      <div className="mt-1.5 text-[16px] font-semibold tracking-normal text-[var(--ui-text)]">{value}</div>
    </div>
  );
}

function EmptyState({ title, description }: { title: string; description: string }): JSX.Element {
  return (
    <div className="absolute inset-0 grid place-items-center p-6 text-center">
      <div className="max-w-sm rounded-[8px] border border-[var(--ui-border)] bg-[rgba(255,255,255,0.9)] px-5 py-4 shadow-[0_1px_2px_rgba(24,24,22,0.05)] backdrop-blur-sm">
        <div className="text-[15px] font-semibold tracking-normal text-[var(--ui-text)]">{title}</div>
        <div className="mt-2 text-[13px] leading-6 text-[var(--ui-text-muted)]">{description}</div>
      </div>
    </div>
  );
}
