import { Editor, defaultValueCtx, rootCtx } from "@milkdown/kit/core";
import { listener, listenerCtx } from "@milkdown/kit/plugin/listener";
import { commonmark } from "@milkdown/kit/preset/commonmark";
import { gfm } from "@milkdown/kit/preset/gfm";
import { Milkdown, MilkdownProvider, useEditor } from "@milkdown/react";
import "@milkdown/kit/prose/view/style/prosemirror.css";
import type { MarkdownPluginId } from "@codetool/shared";

interface MilkdownMarkdownEditorProps {
    value: string;
    enabledPlugins: MarkdownPluginId[];
    onChange: (value: string) => void;
}

export function MilkdownMarkdownEditor(props: MilkdownMarkdownEditorProps): JSX.Element {
    return (
        <MilkdownProvider>
            <MilkdownEditor {...props} />
        </MilkdownProvider>
    );
}

function MilkdownEditor({ value, enabledPlugins, onChange }: MilkdownMarkdownEditorProps): JSX.Element {
    useEditor((root) => {
        const editor = Editor.make()
            .config((ctx) => {
                ctx.set(rootCtx, root);
                ctx.set(defaultValueCtx, value);
                ctx.get(listenerCtx).markdownUpdated((_, markdown, previousMarkdown) => {
                    if (markdown !== previousMarkdown) {
                        onChange(markdown);
                    }
                });
            })
            .use(commonmark)
            .use(listener);
        return enabledPlugins.includes("gfm") ? editor.use(gfm) : editor;
    });

    return <Milkdown />;
}
