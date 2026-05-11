import { useEffect, useState } from "react";
import DOMPurify from "dompurify";
import katex from "katex";
import { marked } from "marked";
import type { MarkdownPluginId } from "@codetool/shared";
import "katex/dist/katex.min.css";

interface RenderedMarkdownPreviewProps {
    value: string;
    enabledPlugins: MarkdownPluginId[];
    sourceDirectory?: string;
}

export function RenderedMarkdownPreview({ value, enabledPlugins, sourceDirectory }: RenderedMarkdownPreviewProps): JSX.Element {
    const [html, setHtml] = useState("");
    const [mermaidHtml, setMermaidHtml] = useState(html);

    useEffect(() => {
        let active = true;
        const markdown = enabledPlugins.includes("math") ? renderMathMarkdown(value) : value;
        void Promise.resolve(marked.parse(markdown, { gfm: enabledPlugins.includes("gfm") })).then((rendered) => {
            if (!active) return;
            const sanitized = DOMPurify.sanitize(rendered, { USE_PROFILES: { html: true } });
            setHtml(resolvePreviewReferences(sanitized, sourceDirectory));
        });
        return () => {
            active = false;
        };
    }, [enabledPlugins, sourceDirectory, value]);

    useEffect(() => {
        if (!enabledPlugins.includes("mermaid")) {
            setMermaidHtml(html);
            return;
        }
        let active = true;
        void renderMermaidBlocks(html).then((rendered) => {
            if (active) setMermaidHtml(rendered);
        });
        return () => {
            active = false;
        };
    }, [enabledPlugins, html]);

    return <div className="markdown-preview" dangerouslySetInnerHTML={{ __html: mermaidHtml }} />;
}

function renderMathMarkdown(markdown: string): string {
    const lines = markdown.split(/\r?\n/);
    const output: string[] = [];
    let inFence = false;
    let mathBuffer: string[] | null = null;
    for (const line of lines) {
        if (/^\s*```/.test(line) || /^\s*~~~/.test(line)) {
            inFence = !inFence;
            output.push(line);
            continue;
        }
        if (!inFence && line.trim() === "$$") {
            if (mathBuffer) {
                output.push(katex.renderToString(mathBuffer.join("\n"), { displayMode: true, throwOnError: false }));
                mathBuffer = null;
            } else {
                mathBuffer = [];
            }
            continue;
        }
        if (mathBuffer) {
            mathBuffer.push(line);
            continue;
        }
        output.push(inFence ? line : renderInlineMath(line));
    }
    if (mathBuffer) output.push("$$", ...mathBuffer);
    return output.join("\n");
}

function renderInlineMath(line: string): string {
    return line.replace(/(^|[^\\])\$([^$\n]+?)\$/g, (_match, prefix: string, expression: string) => {
        return `${prefix}${katex.renderToString(expression, { displayMode: false, throwOnError: false })}`;
    });
}

async function renderMermaidBlocks(html: string): Promise<string> {
    const mermaid = await loadMermaid();
    const template = document.createElement("template");
    template.innerHTML = html;
    const blocks = Array.from(template.content.querySelectorAll("pre > code.language-mermaid"));
    await Promise.all(
        blocks.map(async (block, index) => {
            const parent = block.parentElement;
            if (!parent) return;
            const container = document.createElement("div");
            container.className = "markdown-mermaid";
            try {
                if (!mermaid) throw new Error("Unable to load Mermaid renderer");
                const { svg } = await mermaid.render(`markdown-mermaid-${Date.now()}-${index}`, block.textContent ?? "");
                container.innerHTML = DOMPurify.sanitize(svg, { USE_PROFILES: { svg: true, svgFilters: true } });
            } catch (error) {
                container.textContent = error instanceof Error ? error.message : "Unable to render Mermaid diagram";
                container.classList.add("markdown-mermaid-error");
            }
            parent.replaceWith(container);
        })
    );
    return template.innerHTML;
}

let mermaidLoad: Promise<MermaidApi | null> | null = null;

function loadMermaid(): Promise<MermaidApi | null> {
    mermaidLoad ??= new Promise((resolve) => {
        if (window.mermaid) {
            window.mermaid.initialize({ startOnLoad: false, securityLevel: "strict", theme: "neutral" });
            resolve(window.mermaid);
            return;
        }
        const script = document.createElement("script");
        script.src = "https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js";
        script.async = true;
        script.onload = () => {
            window.mermaid?.initialize({ startOnLoad: false, securityLevel: "strict", theme: "neutral" });
            resolve(window.mermaid ?? null);
        };
        script.onerror = () => resolve(null);
        document.head.appendChild(script);
    });
    return mermaidLoad;
}

interface MermaidApi {
    initialize(config: { startOnLoad: boolean; securityLevel: "strict"; theme: "neutral" }): void;
    render(id: string, source: string): Promise<{ svg: string }>;
}

declare global {
    interface Window {
        mermaid?: MermaidApi;
    }
}

function resolvePreviewReferences(html: string, sourceDirectory?: string): string {
    if (!sourceDirectory) return html;
    const baseUrl = directoryFileUrl(sourceDirectory);
    return html.replace(/\bsrc="([^"]+)"/g, (match, reference: string) => {
        if (isExternalReference(reference)) return match;
        const resolved = new URL(reference, baseUrl);
        if (!resolved.href.startsWith(baseUrl)) return match;
        return `src="${resolved.href}"`;
    });
}

function directoryFileUrl(path: string): string {
    const encoded = path
        .split("/")
        .map((segment, index) => (index === 0 ? "" : encodeURIComponent(segment)))
        .join("/");
    return `file://${encoded.endsWith("/") ? encoded : `${encoded}/`}`;
}

function isExternalReference(reference: string): boolean {
    return /^([a-z][a-z0-9+.-]*:|#|\/)/i.test(reference);
}
