import { useEffect, useMemo, useState } from "react";
import {
    closestCenter,
    DndContext,
    KeyboardSensor,
    PointerSensor,
    useSensor,
    useSensors,
    type DragEndEvent
} from "@dnd-kit/core";
import { SortableContext, sortableKeyboardCoordinates, useSortable, verticalListSortingStrategy } from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";
import { useEditor, EditorContent } from "@tiptap/react";
import StarterKit from "@tiptap/starter-kit";
import type { JSONContent } from "@tiptap/react";
import type { KanbanBoard, KanbanCard, KanbanColumn, KanbanLabel, KanbanPriority, KanbanRichTextDocument } from "@codetool/shared";
import {
    Archive,
    Bold,
    ChevronDown,
    Columns3,
    Download,
    GripVertical,
    Italic,
    KanbanSquare,
    List,
    Plus,
    RotateCcw,
    Search,
    Trash2,
    Upload,
    X
} from "lucide-react";
import { getApi } from "../../api";

type ViewMode = "kanban" | "list" | "archive";
type ThemeMode = "light" | "dark";

const priorities: KanbanPriority[] = ["none", "low", "medium", "high", "urgent"];

export function KanbanPage(): JSX.Element {
    const [boards, setBoards] = useState<KanbanBoard[]>([]);
    const [selectedBoardId, setSelectedBoardId] = useState<string>("");
    const [columns, setColumns] = useState<KanbanColumn[]>([]);
    const [cards, setCards] = useState<KanbanCard[]>([]);
    const [labels, setLabels] = useState<KanbanLabel[]>([]);
    const [selectedCardId, setSelectedCardId] = useState<string>("");
    const [view, setView] = useState<ViewMode>("kanban");
    const [theme, setTheme] = useState<ThemeMode>("light");
    const [search, setSearch] = useState("");
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState<string | null>(null);
    const [exportText, setExportText] = useState("");
    const [importText, setImportText] = useState("");

    const sensors = useSensors(
        useSensor(PointerSensor, { activationConstraint: { distance: 6 } }),
        useSensor(KeyboardSensor, { coordinateGetter: sortableKeyboardCoordinates })
    );
    const selectedBoard = boards.find((board) => board.id === selectedBoardId);
    const selectedCard = cards.find((card) => card.id === selectedCardId);
    const visibleColumns = columns.filter((column) => !column.archivedAt).sort((left, right) => left.sortOrder - right.sortOrder);
    const activeCards = filterCards(cards.filter((card) => !card.archivedAt), search);
    const archivedCards = filterCards(cards.filter((card) => card.archivedAt), search);

    async function loadBoards(): Promise<void> {
        try {
            setLoading(true);
            const api = getApi();
            const nextBoards = await api.kanban.listBoards();
            setBoards(nextBoards);
            const nextSelectedId = selectedBoardId && nextBoards.some((board) => board.id === selectedBoardId) ? selectedBoardId : nextBoards[0]?.id ?? "";
            setSelectedBoardId(nextSelectedId);
            if (nextSelectedId) await loadBoardData(nextSelectedId);
            setError(null);
        } catch (caught) {
            setError(errorMessage(caught));
        } finally {
            setLoading(false);
        }
    }

    async function loadBoardData(boardId: string): Promise<void> {
        const api = getApi();
        const [nextColumns, nextCards, nextLabels] = await Promise.all([
            api.kanban.listColumns({ boardId, includeArchived: true }),
            api.kanban.listCards({ boardId, includeArchived: true }),
            api.kanban.listLabels({ boardId })
        ]);
        setColumns(nextColumns);
        setCards(nextCards);
        setLabels(nextLabels);
    }

    useEffect(() => {
        void loadBoards();
    }, []);

    async function selectBoard(boardId: string): Promise<void> {
        setSelectedBoardId(boardId);
        setSelectedCardId("");
        await loadBoardData(boardId);
    }

    async function createBoard(): Promise<void> {
        const name = window.prompt("Board name", "Product Roadmap")?.trim();
        if (!name) return;
        const board = await getApi().kanban.createBoard({ name });
        await loadBoards();
        await selectBoard(board.id);
    }

    async function renameBoard(): Promise<void> {
        if (!selectedBoard) return;
        const name = window.prompt("Rename board", selectedBoard.name)?.trim();
        if (!name) return;
        await getApi().kanban.renameBoard({ id: selectedBoard.id, name });
        await loadBoards();
    }

    async function deleteBoard(): Promise<void> {
        if (!selectedBoard || !window.confirm(`Delete board "${selectedBoard.name}" and all cards?`)) return;
        await getApi().kanban.deleteBoard({ id: selectedBoard.id });
        setSelectedCardId("");
        await loadBoards();
    }

    async function createColumn(): Promise<void> {
        if (!selectedBoardId) return;
        const name = window.prompt("Column name", "Review")?.trim();
        if (!name) return;
        await getApi().kanban.createColumn({ boardId: selectedBoardId, name });
        await loadBoardData(selectedBoardId);
    }

    async function renameColumn(column: KanbanColumn): Promise<void> {
        const name = window.prompt("Rename column", column.name)?.trim();
        if (!name) return;
        await getApi().kanban.updateColumn({ id: column.id, patch: { name } });
        await loadBoardData(column.boardId);
    }

    async function archiveColumn(column: KanbanColumn): Promise<void> {
        try {
            await getApi().kanban.archiveColumn({ id: column.id });
            await loadBoardData(column.boardId);
        } catch (caught) {
            window.alert(errorMessage(caught));
        }
    }

    async function createCard(columnId: string): Promise<void> {
        if (!selectedBoardId) return;
        const title = window.prompt("Card title", "New task")?.trim();
        if (!title) return;
        const card = await getApi().kanban.createCard({ boardId: selectedBoardId, columnId, title });
        await loadBoardData(selectedBoardId);
        setSelectedCardId(card.id);
    }

    async function updateCard(cardId: string, patch: Partial<KanbanCard>): Promise<void> {
        const card = cards.find((item) => item.id === cardId);
        if (!card || !selectedBoardId) return;
        const nextPatch = {
            title: patch.title,
            columnId: patch.columnId,
            descriptionJson: patch.descriptionJson,
            descriptionText: patch.descriptionText,
            priority: patch.priority,
            dueDate: patch.dueDate
        };
        await getApi().kanban.updateCard({ id: cardId, patch: nextPatch });
        await loadBoardData(selectedBoardId);
    }

    async function archiveCard(cardId: string): Promise<void> {
        if (!selectedBoardId) return;
        await getApi().kanban.archiveCard({ id: cardId });
        setSelectedCardId("");
        await loadBoardData(selectedBoardId);
    }

    async function restoreCard(cardId: string): Promise<void> {
        if (!selectedBoardId) return;
        await getApi().kanban.restoreCard({ id: cardId });
        await loadBoardData(selectedBoardId);
    }

    async function deleteCard(cardId: string): Promise<void> {
        if (!selectedBoardId || !window.confirm("Delete this card permanently?")) return;
        await getApi().kanban.deleteCard({ id: cardId });
        setSelectedCardId("");
        await loadBoardData(selectedBoardId);
    }

    async function createLabel(): Promise<void> {
        if (!selectedBoardId) return;
        const name = window.prompt("Label name", "Design")?.trim();
        if (!name) return;
        await getApi().kanban.createLabel({ boardId: selectedBoardId, name, color: randomLabelColor(labels.length) });
        await loadBoardData(selectedBoardId);
    }

    async function toggleCardLabel(card: KanbanCard, labelId: string): Promise<void> {
        const next = card.labelIds.includes(labelId) ? card.labelIds.filter((id) => id !== labelId) : [...card.labelIds, labelId];
        await getApi().kanban.setCardLabels({ cardId: card.id, labelIds: next });
        if (selectedBoardId) await loadBoardData(selectedBoardId);
    }

    async function exportBoard(): Promise<void> {
        if (!selectedBoardId) return;
        const payload = await getApi().kanban.exportBoard({ boardId: selectedBoardId });
        const text = JSON.stringify(payload, null, 2);
        setExportText(text);
        await navigator.clipboard?.writeText(text);
    }

    async function importBoard(): Promise<void> {
        if (!importText.trim()) return;
        const payload = JSON.parse(importText);
        const board = await getApi().kanban.importBoard({ payload });
        setImportText("");
        await loadBoards();
        await selectBoard(board.id);
    }

    async function handleDragEnd(event: DragEndEvent): Promise<void> {
        if (!event.over || !selectedBoardId) return;
        const activeId = String(event.active.id);
        const overId = String(event.over.id);
        if (activeId === overId) return;

        if (activeId.startsWith("column:") && overId.startsWith("column:")) {
            await getApi().kanban.reorderColumn({ id: activeId.slice(7), beforeId: overId.slice(7) });
            await loadBoardData(selectedBoardId);
            return;
        }

        if (!activeId.startsWith("card:")) return;
        const cardId = activeId.slice(5);
        const overCard = overId.startsWith("card:") ? cards.find((card) => card.id === overId.slice(5)) : undefined;
        const toColumnId = overId.startsWith("column:") ? overId.slice(7) : overCard?.columnId;
        if (!toColumnId) return;
        await getApi().kanban.reorderCard({ id: cardId, toColumnId, beforeId: overCard?.id });
        await loadBoardData(selectedBoardId);
    }

    return (
        <section className={`kanban-tool kanban-${theme}`}>
            <aside className="kanban-boards" aria-label="Boards">
                <div className="kanban-brand">
                    <KanbanSquare size={18} />
                    <span>Kanban</span>
                </div>
                <button type="button" className="kanban-command" onClick={createBoard}>
                    <Plus size={15} /> New board
                </button>
                <div className="kanban-board-list">
                    {boards.map((board) => (
                        <button
                            type="button"
                            key={board.id}
                            className={board.id === selectedBoardId ? "active" : ""}
                            onClick={() => void selectBoard(board.id)}
                        >
                            <span>{board.name}</span>
                            <small>{new Date(board.updatedAt).toLocaleDateString()}</small>
                        </button>
                    ))}
                </div>
                <div className="kanban-io">
                    <button type="button" onClick={exportBoard} disabled={!selectedBoardId}>
                        <Download size={14} /> Export
                    </button>
                    <button type="button" onClick={() => setExportText("")}>Clear</button>
                    {exportText ? <textarea readOnly value={exportText} aria-label="Export JSON" /> : null}
                    <textarea value={importText} onChange={(event) => setImportText(event.target.value)} placeholder="Paste board JSON" aria-label="Import JSON" />
                    <button type="button" onClick={() => void importBoard()}>
                        <Upload size={14} /> Import
                    </button>
                </div>
            </aside>

            <main className="kanban-main">
                <header className="kanban-topbar">
                    <div>
                        <label className="kanban-board-select">
                            <select value={selectedBoardId} onChange={(event) => void selectBoard(event.target.value)}>
                                {boards.map((board) => (
                                    <option key={board.id} value={board.id}>{board.name}</option>
                                ))}
                            </select>
                            <ChevronDown size={16} />
                        </label>
                        <p>{selectedBoard ? `${columns.length} columns, ${cards.filter((card) => !card.archivedAt).length} active cards` : "Create a board to start"}</p>
                    </div>
                    <div className="kanban-actions">
                        <div className="kanban-search">
                            <Search size={15} />
                            <input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Search cards" />
                        </div>
                        <Segmented value={view} onChange={setView} />
                        <button type="button" className="kanban-icon-button" onClick={() => setTheme(theme === "light" ? "dark" : "light")}>
                            {theme === "light" ? "Dark" : "Light"}
                        </button>
                        <button type="button" className="kanban-icon-button" onClick={renameBoard} disabled={!selectedBoard}>Rename</button>
                        <button type="button" className="kanban-danger-button" onClick={deleteBoard} disabled={!selectedBoard}>
                            <Trash2 size={15} />
                        </button>
                    </div>
                </header>

                {error ? <div className="kanban-error">{error}</div> : null}
                {loading ? <div className="kanban-empty">Loading boards...</div> : null}
                {!loading && boards.length === 0 ? <EmptyBoard onCreate={createBoard} /> : null}

                {selectedBoard ? (
                    <DndContext sensors={sensors} collisionDetection={closestCenter} onDragEnd={(event) => void handleDragEnd(event)}>
                        {view === "kanban" ? (
                            <SortableContext items={visibleColumns.map((column) => `column:${column.id}`)} strategy={verticalListSortingStrategy}>
                                <div className="kanban-board-canvas">
                                    {visibleColumns.map((column) => (
                                        <SortableColumn
                                            key={column.id}
                                            column={column}
                                            cards={activeCards.filter((card) => card.columnId === column.id).sort((left, right) => left.sortOrder - right.sortOrder)}
                                            labels={labels}
                                            onCreateCard={() => void createCard(column.id)}
                                            onOpenCard={setSelectedCardId}
                                            onRename={() => void renameColumn(column)}
                                            onArchive={() => void archiveColumn(column)}
                                        />
                                    ))}
                                    <button type="button" className="kanban-add-column" onClick={createColumn}>
                                        <Plus size={15} /> Add column
                                    </button>
                                </div>
                            </SortableContext>
                        ) : null}

                        {view === "list" ? (
                            <ListView columns={visibleColumns} cards={activeCards} labels={labels} onOpenCard={setSelectedCardId} onMoveCard={(cardId, columnId) => void updateCard(cardId, { columnId })} />
                        ) : null}

                        {view === "archive" ? <ArchiveView cards={archivedCards} labels={labels} onRestore={restoreCard} onDelete={deleteCard} /> : null}
                    </DndContext>
                ) : null}
            </main>

            {selectedCard ? (
                <CardDetails
                    card={selectedCard}
                    columns={visibleColumns}
                    labels={labels}
                    onClose={() => setSelectedCardId("")}
                    onSave={updateCard}
                    onArchive={archiveCard}
                    onDelete={deleteCard}
                    onCreateLabel={createLabel}
                    onToggleLabel={toggleCardLabel}
                />
            ) : null}
        </section>
    );
}

function Segmented({ value, onChange }: { value: ViewMode; onChange: (value: ViewMode) => void }): JSX.Element {
    return (
        <div className="kanban-segmented" role="tablist" aria-label="View mode">
            <button type="button" className={value === "kanban" ? "active" : ""} onClick={() => onChange("kanban")}>
                <Columns3 size={14} /> Kanban
            </button>
            <button type="button" className={value === "list" ? "active" : ""} onClick={() => onChange("list")}>
                <List size={14} /> List
            </button>
            <button type="button" className={value === "archive" ? "active" : ""} onClick={() => onChange("archive")}>
                <Archive size={14} /> Archive
            </button>
        </div>
    );
}

function EmptyBoard({ onCreate }: { onCreate: () => void }): JSX.Element {
    return (
        <div className="kanban-empty">
            <KanbanSquare size={28} />
            <button type="button" onClick={onCreate}>Create first board</button>
        </div>
    );
}

function SortableColumn({ column, cards, labels, onCreateCard, onOpenCard, onRename, onArchive }: {
    column: KanbanColumn;
    cards: KanbanCard[];
    labels: KanbanLabel[];
    onCreateCard: () => void;
    onOpenCard: (id: string) => void;
    onRename: () => void;
    onArchive: () => void;
}): JSX.Element {
    const { attributes, listeners, setNodeRef, transform, transition } = useSortable({ id: `column:${column.id}` });
    return (
        <section ref={setNodeRef} className="kanban-column" style={{ transform: CSS.Transform.toString(transform), transition }}>
            <header>
                <button type="button" className="kanban-drag-handle" {...attributes} {...listeners} aria-label={`Drag ${column.name}`}>
                    <GripVertical size={15} />
                </button>
                <span className="kanban-column-dot" style={{ background: column.color ?? "#9ca3af" }} />
                <strong>{column.name}</strong>
                <small>{cards.length}</small>
                <button type="button" onClick={onRename}>Rename</button>
                <button type="button" onClick={onArchive}>Archive</button>
            </header>
            <SortableContext items={cards.map((card) => `card:${card.id}`)} strategy={verticalListSortingStrategy}>
                <div className="kanban-card-stack">
                    {cards.map((card) => <SortableCard key={card.id} card={card} labels={labels} onOpen={() => onOpenCard(card.id)} />)}
                    {cards.length === 0 ? <div className="kanban-column-empty">Drop cards here</div> : null}
                </div>
            </SortableContext>
            <button type="button" className="kanban-add-card" onClick={onCreateCard}>
                <Plus size={14} /> Add card
            </button>
        </section>
    );
}

function SortableCard({ card, labels, onOpen }: { card: KanbanCard; labels: KanbanLabel[]; onOpen: () => void }): JSX.Element {
    const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({ id: `card:${card.id}` });
    const cardLabels = labels.filter((label) => card.labelIds.includes(label.id));
    return (
        <article ref={setNodeRef} className={`kanban-card ${isDragging ? "dragging" : ""}`} style={{ transform: CSS.Transform.toString(transform), transition }}>
            <button type="button" className="kanban-card-open" onClick={onOpen}>
                <span>{card.title}</span>
                {card.descriptionText ? <small>{card.descriptionText}</small> : null}
            </button>
            <div className="kanban-card-meta">
                <button type="button" className="kanban-drag-handle" {...attributes} {...listeners} aria-label={`Drag ${card.title}`}>
                    <GripVertical size={14} />
                </button>
                <PriorityBadge priority={card.priority} />
                {cardLabels.map((label) => <LabelChip key={label.id} label={label} />)}
                {card.dueDate ? <span>{new Date(card.dueDate).toLocaleDateString()}</span> : null}
            </div>
        </article>
    );
}

function ListView({ columns, cards, labels, onOpenCard, onMoveCard }: {
    columns: KanbanColumn[];
    cards: KanbanCard[];
    labels: KanbanLabel[];
    onOpenCard: (id: string) => void;
    onMoveCard: (cardId: string, columnId: string) => void;
}): JSX.Element {
    return (
        <div className="kanban-list-view">
            {columns.map((column) => {
                const columnCards = cards.filter((card) => card.columnId === column.id).sort((left, right) => left.sortOrder - right.sortOrder);
                return (
                    <section key={column.id}>
                        <h3><span style={{ background: column.color ?? "#9ca3af" }} />{column.name}<small>{columnCards.length}</small></h3>
                        {columnCards.map((card) => (
                            <div className="kanban-list-row" key={card.id}>
                                <button type="button" onClick={() => onOpenCard(card.id)}>{card.title}</button>
                                <PriorityBadge priority={card.priority} />
                                {labels.filter((label) => card.labelIds.includes(label.id)).map((label) => <LabelChip key={label.id} label={label} />)}
                                <select value={card.columnId} onChange={(event) => onMoveCard(card.id, event.target.value)}>
                                    {columns.map((target) => <option key={target.id} value={target.id}>{target.name}</option>)}
                                </select>
                            </div>
                        ))}
                    </section>
                );
            })}
        </div>
    );
}

function ArchiveView({ cards, labels, onRestore, onDelete }: {
    cards: KanbanCard[];
    labels: KanbanLabel[];
    onRestore: (id: string) => Promise<void>;
    onDelete: (id: string) => Promise<void>;
}): JSX.Element {
    return (
        <div className="kanban-list-view">
            <section>
                <h3><Archive size={15} /> Archived cards <small>{cards.length}</small></h3>
                {cards.map((card) => (
                    <div className="kanban-list-row" key={card.id}>
                        <button type="button">{card.title}</button>
                        <PriorityBadge priority={card.priority} />
                        {labels.filter((label) => card.labelIds.includes(label.id)).map((label) => <LabelChip key={label.id} label={label} />)}
                        <button type="button" onClick={() => void onRestore(card.id)}><RotateCcw size={14} /> Restore</button>
                        <button type="button" onClick={() => void onDelete(card.id)}><Trash2 size={14} /> Delete</button>
                    </div>
                ))}
            </section>
        </div>
    );
}

function CardDetails({ card, columns, labels, onClose, onSave, onArchive, onDelete, onCreateLabel, onToggleLabel }: {
    card: KanbanCard;
    columns: KanbanColumn[];
    labels: KanbanLabel[];
    onClose: () => void;
    onSave: (cardId: string, patch: Partial<KanbanCard>) => Promise<void>;
    onArchive: (cardId: string) => Promise<void>;
    onDelete: (cardId: string) => Promise<void>;
    onCreateLabel: () => Promise<void>;
    onToggleLabel: (card: KanbanCard, labelId: string) => Promise<void>;
}): JSX.Element {
    const [title, setTitle] = useState(card.title);
    const [columnId, setColumnId] = useState(card.columnId);
    const [priority, setPriority] = useState<KanbanPriority>(card.priority);
    const [dueDate, setDueDate] = useState(card.dueDate ? dateInputValue(card.dueDate) : "");
    const [descriptionJson, setDescriptionJson] = useState<KanbanRichTextDocument | undefined>(card.descriptionJson);
    const [descriptionText, setDescriptionText] = useState(card.descriptionText ?? "");

    useEffect(() => {
        setTitle(card.title);
        setColumnId(card.columnId);
        setPriority(card.priority);
        setDueDate(card.dueDate ? dateInputValue(card.dueDate) : "");
        setDescriptionJson(card.descriptionJson);
        setDescriptionText(card.descriptionText ?? "");
    }, [card.id]);

    return (
        <aside className="kanban-details" aria-label="Card details">
            <header>
                <strong>Card details</strong>
                <button type="button" onClick={onClose} aria-label="Close details"><X size={16} /></button>
            </header>
            <input className="kanban-title-input" value={title} onChange={(event) => setTitle(event.target.value)} />
            <div className="kanban-field-grid">
                <label>Column<select value={columnId} onChange={(event) => setColumnId(event.target.value)}>{columns.map((column) => <option key={column.id} value={column.id}>{column.name}</option>)}</select></label>
                <label>Priority<select value={priority} onChange={(event) => setPriority(event.target.value as KanbanPriority)}>{priorities.map((item) => <option key={item} value={item}>{item}</option>)}</select></label>
                <label>Due<input type="date" value={dueDate} onChange={(event) => setDueDate(event.target.value)} /></label>
            </div>
            <div className="kanban-labels">
                {labels.map((label) => (
                    <button type="button" key={label.id} className={card.labelIds.includes(label.id) ? "active" : ""} onClick={() => void onToggleLabel(card, label.id)}>
                        <LabelChip label={label} />
                    </button>
                ))}
                <button type="button" onClick={() => void onCreateLabel()}><Plus size={14} /> Label</button>
            </div>
            <RichTextEditor value={descriptionJson} onChange={(json, text) => { setDescriptionJson(json); setDescriptionText(text); }} />
            <footer>
                <button type="button" className="kanban-command primary" onClick={() => void onSave(card.id, { title, columnId, priority, dueDate: dueDate ? new Date(`${dueDate}T00:00:00`).getTime() : undefined, descriptionJson, descriptionText })}>Save</button>
                <button type="button" onClick={() => void onArchive(card.id)}><Archive size={14} /> Archive</button>
                <button type="button" className="danger" onClick={() => void onDelete(card.id)}><Trash2 size={14} /> Delete</button>
            </footer>
        </aside>
    );
}

function RichTextEditor({ value, onChange }: { value?: KanbanRichTextDocument; onChange: (json: KanbanRichTextDocument, text: string) => void }): JSX.Element {
    const editor = useEditor({
        extensions: [StarterKit],
        content: (value as JSONContent | undefined) ?? { type: "doc", content: [{ type: "paragraph" }] },
        editorProps: { attributes: { class: "kanban-editor-content" } },
        onUpdate: ({ editor: current }) => onChange(current.getJSON() as KanbanRichTextDocument, current.getText())
    });

    useEffect(() => {
        if (!editor) return;
        editor.commands.setContent((value as JSONContent | undefined) ?? { type: "doc", content: [{ type: "paragraph" }] });
    }, [editor, value]);

    return (
        <div className="kanban-editor">
            <div className="kanban-editor-toolbar">
                <button type="button" onClick={() => editor?.chain().focus().toggleBold().run()}><Bold size={14} /></button>
                <button type="button" onClick={() => editor?.chain().focus().toggleItalic().run()}><Italic size={14} /></button>
                <button type="button" onClick={() => editor?.chain().focus().toggleBulletList().run()}>List</button>
                <button type="button" onClick={() => editor?.chain().focus().toggleCodeBlock().run()}>Code</button>
            </div>
            <EditorContent editor={editor} />
        </div>
    );
}

function PriorityBadge({ priority }: { priority: KanbanPriority }): JSX.Element {
    return <span className={`kanban-priority priority-${priority}`}>{priority}</span>;
}

function LabelChip({ label }: { label: KanbanLabel }): JSX.Element {
    return <span className="kanban-label-chip" style={{ borderColor: label.color, color: label.color }}>{label.name}</span>;
}

function filterCards(cards: KanbanCard[], search: string): KanbanCard[] {
    const query = search.trim().toLowerCase();
    if (!query) return cards;
    return cards.filter((card) => `${card.title} ${card.descriptionText ?? ""}`.toLowerCase().includes(query));
}

function randomLabelColor(index: number): string {
    return ["#2563eb", "#16a34a", "#dc2626", "#9333ea", "#d97706"][index % 5] ?? "#2563eb";
}

function dateInputValue(timestamp: number): string {
    return new Date(timestamp).toISOString().slice(0, 10);
}

function errorMessage(error: unknown): string {
    return error instanceof Error ? error.message : String(error);
}
