import { useEffect, useRef } from "react";
import { defaultKeymap, history, historyKeymap } from "@codemirror/commands";
import { markdown } from "@codemirror/lang-markdown";
import { EditorState } from "@codemirror/state";
import { EditorView, keymap } from "@codemirror/view";

interface SourceMarkdownEditorProps {
    value: string;
    scrollTarget?: { line: number; nonce: number } | null;
    onChange: (value: string) => void;
}

export function SourceMarkdownEditor({ value, scrollTarget, onChange }: SourceMarkdownEditorProps): JSX.Element {
    const rootRef = useRef<HTMLDivElement | null>(null);
    const viewRef = useRef<EditorView | null>(null);
    const onChangeRef = useRef(onChange);

    useEffect(() => {
        onChangeRef.current = onChange;
    }, [onChange]);

    useEffect(() => {
        if (!rootRef.current) return;
        const view = new EditorView({
            parent: rootRef.current,
            state: EditorState.create({
                doc: value,
                extensions: [
                    history(),
                    markdown(),
                    keymap.of([...defaultKeymap, ...historyKeymap]),
                    EditorView.lineWrapping,
                    EditorView.updateListener.of((update) => {
                        if (update.docChanged) {
                            onChangeRef.current(update.state.doc.toString());
                        }
                    })
                ]
            })
        });
        viewRef.current = view;
        return () => {
            view.destroy();
            viewRef.current = null;
        };
    }, []);

    useEffect(() => {
        const view = viewRef.current;
        if (!view) return;
        const current = view.state.doc.toString();
        if (current === value) return;
        view.dispatch({
            changes: { from: 0, to: current.length, insert: value }
        });
    }, [value]);

    useEffect(() => {
        const view = viewRef.current;
        if (!view || !scrollTarget) return;
        const lineNumber = Math.max(1, Math.min(scrollTarget.line, view.state.doc.lines));
        const line = view.state.doc.line(lineNumber);
        view.dispatch({ effects: EditorView.scrollIntoView(line.from, { y: "center" }) });
        view.focus();
    }, [scrollTarget]);

    return <div ref={rootRef} className="markdown-source-editor" />;
}
