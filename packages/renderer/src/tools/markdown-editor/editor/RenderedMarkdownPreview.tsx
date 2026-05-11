import { useEffect, useState } from "react";
import DOMPurify from "dompurify";
import { marked } from "marked";
import type { MarkdownPluginId } from "@codetool/shared";

interface RenderedMarkdownPreviewProps {
    value: string;
    enabledPlugins: MarkdownPluginId[];
    sourceDirectory?: string;
}

export function RenderedMarkdownPreview({ value, enabledPlugins, sourceDirectory }: RenderedMarkdownPreviewProps): JSX.Element {
    const [html, setHtml] = useState("");

    useEffect(() => {
        let active = true;
        void Promise.resolve(marked.parse(value, { gfm: enabledPlugins.includes("gfm") })).then((rendered) => {
            if (!active) return;
            const sanitized = DOMPurify.sanitize(rendered, { USE_PROFILES: { html: true } });
            setHtml(resolvePreviewReferences(sanitized, sourceDirectory));
        });
        return () => {
            active = false;
        };
    }, [enabledPlugins, sourceDirectory, value]);

    return <div className="markdown-preview" dangerouslySetInnerHTML={{ __html: html }} />;
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
