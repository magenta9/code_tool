import { useEffect, useMemo, useState } from "react";
import {
    closestCenter,
    DragOverlay,
    DndContext,
    KeyboardSensor,
    PointerSensor,
    useSensor,
    useSensors,
    type DragEndEvent,
    type DragStartEvent
} from "@dnd-kit/core";
import { horizontalListSortingStrategy, SortableContext, sortableKeyboardCoordinates, useSortable, verticalListSortingStrategy } from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";
import { useEditor, EditorContent } from "@tiptap/react";
import StarterKit from "@tiptap/starter-kit";
import type { JSONContent } from "@tiptap/react";
import type { KanbanBoard, KanbanCard, KanbanCardPatch, KanbanColumn, KanbanLabel, KanbanPriority, KanbanRichTextDocument } from "@codetool/shared";
import {
    Archive,
    Bold,
    CalendarDays,
    ChevronDown,
    Columns3,
    Italic,
    KanbanSquare,
    List,
    Pencil,
    Plus,
    RotateCcw,
    Save,
    Search,
    Tag,
    Trash2,
    X
} from "lucide-react";
import { getApi } from "../../api";

type ViewMode = "kanban" | "list" | "archive";

interface SelectOption {
    value: string;
    label: string;
}

interface TextDialogState {
    title: string;
    label: string;
    initialValue: string;
    confirmLabel: string;
    onSubmit: (value: string) => Promise<void>;
}

interface ConfirmDialogState {
    title: string;
    message: string;
    confirmLabel: string;
    onConfirm: () => Promise<void>;
}

const priorities: KanbanPriority[] = ["none", "low", "medium", "high", "urgent"];

export function KanbanPage(): JSX.Element {
    const [boards, setBoards] = useState<KanbanBoard[]>([]);
    const [selectedBoardId, setSelectedBoardId] = useState<string>("");
    const [columns, setColumns] = useState<KanbanColumn[]>([]);
    const [cards, setCards] = useState<KanbanCard[]>([]);
    const [labels, setLabels] = useState<KanbanLabel[]>([]);
    const [selectedCardId, setSelectedCardId] = useState<string>("");
    const [view, setView] = useState<ViewMode>("kanban");
    const [search, setSearch] = useState("");
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState<string | null>(null);
    const [draftCardTitles, setDraftCardTitles] = useState<Record<string, string>>({});
    const [activeComposerColumnId, setActiveComposerColumnId] = useState<string>("");
    const [textDialog, setTextDialog] = useState<TextDialogState | null>(null);
    const [confirmDialog, setConfirmDialog] = useState<ConfirmDialogState | null>(null);
    const [activeDragId, setActiveDragId] = useState<string | null>(null);

    const sensors = useSensors(
        useSensor(PointerSensor, { activationConstraint: { distance: 6 } }),
        useSensor(KeyboardSensor, { coordinateGetter: sortableKeyboardCoordinates })
    );
    const selectedBoard = boards.find((board) => board.id === selectedBoardId);
    const selectedCard = cards.find((card) => card.id === selectedCardId);
    const visibleColumns = columns.filter((column) => !column.archivedAt).sort((left, right) => left.sortOrder - right.sortOrder);
    const activeCards = filterCards(cards.filter((card) => !card.archivedAt), search);
    const archivedCards = filterCards(cards.filter((card) => card.archivedAt), search);
    const activeDraggingCard = activeDragId?.startsWith("card:") ? cards.find((card) => card.id === activeDragId.slice(5)) : undefined;
    const activeDraggingColumn = activeDragId?.startsWith("column:") ? columns.find((column) => column.id === activeDragId.slice(7)) : undefined;

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

    function createBoard(): void {
        setTextDialog({
            title: "New board",
            label: "Board name",
            initialValue: "Product Roadmap",
            confirmLabel: "Create board",
            onSubmit: async (name) => {
                const board = await getApi().kanban.createBoard({ name });
                await loadBoards();
                await selectBoard(board.id);
            }
        });
    }

    function renameBoard(): void {
        if (!selectedBoard) return;
        setTextDialog({
            title: "Rename board",
            label: "Board name",
            initialValue: selectedBoard.name,
            confirmLabel: "Save name",
            onSubmit: async (name) => {
                await getApi().kanban.renameBoard({ id: selectedBoard.id, name });
                await loadBoards();
            }
        });
    }

    async function deleteBoard(): Promise<void> {
        if (!selectedBoard) return;
        setConfirmDialog({
            title: "Delete board",
            message: `Delete "${selectedBoard.name}" and all cards? This cannot be undone.`,
            confirmLabel: "Delete board",
            onConfirm: async () => {
                await getApi().kanban.deleteBoard({ id: selectedBoard.id });
                setSelectedCardId("");
                await loadBoards();
            }
        });
    }

    function createColumn(): void {
        if (!selectedBoardId) return;
        setTextDialog({
            title: "New column",
            label: "Column name",
            initialValue: "Review",
            confirmLabel: "Create column",
            onSubmit: async (name) => {
                await getApi().kanban.createColumn({ boardId: selectedBoardId, name });
                await loadBoardData(selectedBoardId);
            }
        });
    }

    function renameColumn(column: KanbanColumn): void {
        setTextDialog({
            title: "Rename column",
            label: "Column name",
            initialValue: column.name,
            confirmLabel: "Save name",
            onSubmit: async (name) => {
                await getApi().kanban.updateColumn({ id: column.id, patch: { name } });
                await loadBoardData(column.boardId);
            }
        });
    }

    async function archiveColumn(column: KanbanColumn): Promise<void> {
        try {
            await getApi().kanban.archiveColumn({ id: column.id });
            await loadBoardData(column.boardId);
        } catch (caught) {
            setError(errorMessage(caught));
        }
    }

    function setDraftCardTitle(columnId: string, value: string): void {
        setDraftCardTitles((current) => ({ ...current, [columnId]: value }));
    }

    async function createCard(columnId: string): Promise<void> {
        if (!selectedBoardId) return;
        const title = draftCardTitles[columnId]?.trim();
        if (!title) return;
        try {
            const card = await getApi().kanban.createCard({ boardId: selectedBoardId, columnId, title });
            setDraftCardTitles((current) => ({ ...current, [columnId]: "" }));
            setActiveComposerColumnId("");
            await loadBoardData(selectedBoardId);
            setSelectedCardId(card.id);
            setError(null);
        } catch (caught) {
            setError(errorMessage(caught));
        }
    }

    function renameCard(card: KanbanCard): void {
        setTextDialog({
            title: "Rename task",
            label: "Task title",
            initialValue: card.title,
            confirmLabel: "Save title",
            onSubmit: async (title) => {
                if (title === card.title) return;
                await updateCard(card.id, { title });
            }
        });
    }

    async function updateCard(cardId: string, patch: Partial<KanbanCardPatch>): Promise<void> {
        const card = cards.find((item) => item.id === cardId);
        if (!card || !selectedBoardId) return;
        const nextPatch: Partial<KanbanCardPatch> = {
            title: patch.title,
            columnId: patch.columnId,
            descriptionJson: patch.descriptionJson,
            descriptionText: patch.descriptionText,
            priority: patch.priority
        };
        if (Object.prototype.hasOwnProperty.call(patch, "dueDate")) nextPatch.dueDate = patch.dueDate ?? null;
        await getApi().kanban.updateCard({ id: cardId, patch: nextPatch });
        await loadBoardData(selectedBoardId);
        setError(null);
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
        if (!selectedBoardId) return;
        setConfirmDialog({
            title: "Delete task",
            message: "Delete this task permanently? This cannot be undone.",
            confirmLabel: "Delete task",
            onConfirm: async () => {
                await getApi().kanban.deleteCard({ id: cardId });
                setSelectedCardId("");
                await loadBoardData(selectedBoardId);
            }
        });
    }

    async function createLabel(): Promise<void> {
        if (!selectedBoardId) return;
        setTextDialog({
            title: "New label",
            label: "Label name",
            initialValue: "Design",
            confirmLabel: "Create label",
            onSubmit: async (name) => {
                await getApi().kanban.createLabel({ boardId: selectedBoardId, name, color: randomLabelColor(labels.length) });
                await loadBoardData(selectedBoardId);
            }
        });
    }

    async function toggleCardLabel(card: KanbanCard, labelId: string): Promise<void> {
        const next = card.labelIds.includes(labelId) ? card.labelIds.filter((id) => id !== labelId) : [...card.labelIds, labelId];
        await getApi().kanban.setCardLabels({ cardId: card.id, labelIds: next });
        if (selectedBoardId) await loadBoardData(selectedBoardId);
    }

    function handleDragStart(event: DragStartEvent): void {
        setActiveDragId(String(event.active.id));
    }

    async function handleDragEnd(event: DragEndEvent): Promise<void> {
        setActiveDragId(null);
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
        <section className="kanban-tool">
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
                    <DndContext sensors={sensors} collisionDetection={closestCenter} onDragStart={handleDragStart} onDragCancel={() => setActiveDragId(null)} onDragEnd={(event) => void handleDragEnd(event)}>
                        {view === "kanban" ? (
                            <SortableContext items={visibleColumns.map((column) => `column:${column.id}`)} strategy={horizontalListSortingStrategy}>
                                <div key="kanban" className="kanban-board-canvas kanban-view-panel">
                                    {visibleColumns.map((column) => (
                                        <SortableColumn
                                            key={column.id}
                                            column={column}
                                            cards={activeCards.filter((card) => card.columnId === column.id).sort((left, right) => left.sortOrder - right.sortOrder)}
                                            labels={labels}
                                            draftTitle={draftCardTitles[column.id] ?? ""}
                                            composerOpen={activeComposerColumnId === column.id}
                                            onDraftTitleChange={(value) => setDraftCardTitle(column.id, value)}
                                            onOpenComposer={() => setActiveComposerColumnId(column.id)}
                                            onCloseComposer={() => { setDraftCardTitle(column.id, ""); setActiveComposerColumnId(""); }}
                                            onCreateCard={() => void createCard(column.id)}
                                            onOpenCard={setSelectedCardId}
                                            onRenameCard={(card) => void renameCard(card)}
                                            onArchiveCard={(cardId) => void archiveCard(cardId)}
                                            onDeleteCard={(cardId) => void deleteCard(cardId)}
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
                            <ListView
                                key="list"
                                columns={visibleColumns}
                                cards={activeCards}
                                labels={labels}
                                onOpenCard={setSelectedCardId}
                                onMoveCard={(cardId, columnId) => void updateCard(cardId, { columnId })}
                                onArchiveCard={(cardId) => void archiveCard(cardId)}
                                onDeleteCard={(cardId) => void deleteCard(cardId)}
                            />
                        ) : null}

                        {view === "archive" ? <ArchiveView key="archive" cards={archivedCards} labels={labels} onOpenCard={setSelectedCardId} onRestore={restoreCard} onDelete={deleteCard} /> : null}
                        <DragOverlay dropAnimation={{ duration: 180, easing: "cubic-bezier(0.2, 0, 0, 1)" }}>
                            {activeDraggingCard ? <CardDragPreview card={activeDraggingCard} labels={labels} /> : null}
                            {activeDraggingColumn ? <ColumnDragPreview column={activeDraggingColumn} /> : null}
                        </DragOverlay>
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
            {textDialog ? <TextDialog state={textDialog} onClose={() => setTextDialog(null)} /> : null}
            {confirmDialog ? <ConfirmDialog state={confirmDialog} onClose={() => setConfirmDialog(null)} /> : null}
        </section>
    );
}

function TextDialog({ state, onClose }: { state: TextDialogState; onClose: () => void }): JSX.Element {
    const [value, setValue] = useState(state.initialValue);
    const [pending, setPending] = useState(false);
    const [error, setError] = useState<string | null>(null);
    const trimmedValue = value.trim();

    return (
        <div className="kanban-dialog-backdrop" role="presentation">
            <form
                className="kanban-dialog"
                role="dialog"
                aria-modal="true"
                aria-label={state.title}
                onSubmit={(event) => {
                    event.preventDefault();
                    if (!trimmedValue) return;
                    setPending(true);
                    void state.onSubmit(trimmedValue)
                        .then(onClose)
                        .catch((caught) => setError(errorMessage(caught)))
                        .finally(() => setPending(false));
                }}
            >
                <header>
                    <strong>{state.title}</strong>
                    <button type="button" onClick={onClose} disabled={pending} aria-label="Close dialog"><X size={16} /></button>
                </header>
                <label>
                    <span>{state.label}</span>
                    <input autoFocus value={value} onChange={(event) => setValue(event.target.value)} />
                </label>
                {error ? <p>{error}</p> : null}
                <footer>
                    <button type="button" onClick={onClose} disabled={pending}>Cancel</button>
                    <button type="submit" className="primary" disabled={!trimmedValue || pending}>{pending ? "Saving..." : state.confirmLabel}</button>
                </footer>
            </form>
        </div>
    );
}

function ConfirmDialog({ state, onClose }: { state: ConfirmDialogState; onClose: () => void }): JSX.Element {
    const [pending, setPending] = useState(false);
    const [error, setError] = useState<string | null>(null);

    return (
        <div className="kanban-dialog-backdrop" role="presentation">
            <section className="kanban-dialog" role="dialog" aria-modal="true" aria-label={state.title}>
                <header>
                    <strong>{state.title}</strong>
                    <button type="button" onClick={onClose} disabled={pending} aria-label="Close dialog"><X size={16} /></button>
                </header>
                <div className="kanban-dialog-message">{state.message}</div>
                {error ? <p>{error}</p> : null}
                <footer>
                    <button type="button" onClick={onClose} disabled={pending}>Cancel</button>
                    <button
                        type="button"
                        className="danger"
                        disabled={pending}
                        onClick={() => {
                            setPending(true);
                            void state.onConfirm()
                                .then(onClose)
                                .catch((caught) => setError(errorMessage(caught)))
                                .finally(() => setPending(false));
                        }}
                    >
                        {pending ? "Deleting..." : state.confirmLabel}
                    </button>
                </footer>
            </section>
        </div>
    );
}

function Segmented({ value, onChange }: { value: ViewMode; onChange: (value: ViewMode) => void }): JSX.Element {
    const options: Array<{ value: ViewMode; label: string; icon: JSX.Element }> = [
        { value: "kanban", label: "Kanban", icon: <Columns3 size={14} /> },
        { value: "list", label: "List", icon: <List size={14} /> },
        { value: "archive", label: "Archive", icon: <Archive size={14} /> }
    ];

    return (
        <div className="kanban-segmented" role="tablist" aria-label="View mode" data-view={value}>
            <span className="kanban-segmented-thumb" aria-hidden="true" />
            {options.map((option) => (
                <button
                    key={option.value}
                    type="button"
                    role="tab"
                    aria-selected={value === option.value}
                    className={value === option.value ? "active" : ""}
                    onClick={() => onChange(option.value)}
                >
                    {option.icon} {option.label}
                </button>
            ))}
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

function SortableColumn({
    column,
    cards,
    labels,
    draftTitle,
    composerOpen,
    onDraftTitleChange,
    onOpenComposer,
    onCloseComposer,
    onCreateCard,
    onOpenCard,
    onRenameCard,
    onArchiveCard,
    onDeleteCard,
    onRename,
    onArchive
}: {
    column: KanbanColumn;
    cards: KanbanCard[];
    labels: KanbanLabel[];
    draftTitle: string;
    composerOpen: boolean;
    onDraftTitleChange: (value: string) => void;
    onOpenComposer: () => void;
    onCloseComposer: () => void;
    onCreateCard: () => void;
    onOpenCard: (id: string) => void;
    onRenameCard: (card: KanbanCard) => void;
    onArchiveCard: (id: string) => void;
    onDeleteCard: (id: string) => void;
    onRename: () => void;
    onArchive: () => void;
}): JSX.Element {
    const { attributes, isDragging, isOver, listeners, setNodeRef, transform, transition } = useSortable({ id: `column:${column.id}` });
    return (
        <section ref={setNodeRef} className={`kanban-column ${isOver ? "over" : ""} ${isDragging ? "dragging" : ""}`} style={{ transform: CSS.Transform.toString(transform), transition }}>
            <header>
                <span className="kanban-column-dot" style={{ background: column.color ?? "#9ca3af" }} />
                <div className="kanban-column-title" {...attributes} {...listeners} aria-label={`Drag ${column.name}`}>
                    <strong>{column.name}</strong>
                    <small>{cards.length} cards</small>
                </div>
                <span className="kanban-column-count">{cards.length}</span>
                <button type="button" onClick={onRename} aria-label={`Rename ${column.name}`}><Pencil size={13} /></button>
                <button type="button" onClick={onArchive} aria-label={`Archive ${column.name}`}><Archive size={13} /></button>
            </header>
            <SortableContext items={cards.map((card) => `card:${card.id}`)} strategy={verticalListSortingStrategy}>
                <div className="kanban-card-stack">
                    {cards.map((card) => (
                        <SortableCard
                            key={card.id}
                            card={card}
                            labels={labels}
                            onOpen={() => onOpenCard(card.id)}
                            onRename={() => onRenameCard(card)}
                            onArchive={() => onArchiveCard(card.id)}
                            onDelete={() => onDeleteCard(card.id)}
                        />
                    ))}
                    {cards.length === 0 ? <div className="kanban-column-empty">Drop cards here</div> : null}
                </div>
            </SortableContext>
            {composerOpen ? (
                <form className="kanban-card-composer open" onSubmit={(event) => { event.preventDefault(); onCreateCard(); }}>
                    <input value={draftTitle} onChange={(event) => onDraftTitleChange(event.target.value)} placeholder="Task title" autoFocus />
                    <div className="kanban-card-composer-actions">
                        <button type="submit" disabled={!draftTitle.trim()} aria-label={`Add task to ${column.name}`}>
                            <Plus size={14} /> Add
                        </button>
                        <button type="button" onClick={onCloseComposer} aria-label={`Cancel task in ${column.name}`}>
                            <X size={14} />
                        </button>
                    </div>
                </form>
            ) : (
                <button type="button" className="kanban-card-add-trigger" onClick={onOpenComposer} aria-label={`Add task to ${column.name}`}>
                    <Plus size={14} /> Add card
                </button>
            )}
        </section>
    );
}

function ColumnDragPreview({ column }: { column: KanbanColumn }): JSX.Element {
    return (
        <section className="kanban-column kanban-drag-preview">
            <header>
                <span className="kanban-column-dot" style={{ background: column.color ?? "#9ca3af" }} />
                <div className="kanban-column-title">
                    <strong>{column.name}</strong>
                    <small>Moving column</small>
                </div>
            </header>
            <div className="kanban-column-preview-fill">
                <span />
                <span />
                <span />
            </div>
        </section>
    );
}

function CardDragPreview({ card, labels }: { card: KanbanCard; labels: KanbanLabel[] }): JSX.Element {
    const cardLabels = labels.filter((label) => card.labelIds.includes(label.id));
    return (
        <article className="kanban-card kanban-drag-preview">
            <div className="kanban-card-topline">
                <PriorityBadge priority={card.priority} />
                <span>{formatDisplayDate(card.updatedAt)}</span>
            </div>
            <div className="kanban-card-open">
                <span>{card.title}</span>
                {card.descriptionText ? <small>{card.descriptionText}</small> : null}
            </div>
            <div className="kanban-card-meta-band">
                {cardLabels.map((label) => <LabelChip key={label.id} label={label} />)}
            </div>
        </article>
    );
}

function SortableCard({ card, labels, onOpen, onRename, onArchive, onDelete }: {
    card: KanbanCard;
    labels: KanbanLabel[];
    onOpen: () => void;
    onRename: () => void;
    onArchive: () => void;
    onDelete: () => void;
}): JSX.Element {
    const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({ id: `card:${card.id}` });
    const cardLabels = labels.filter((label) => card.labelIds.includes(label.id));
    return (
        <article ref={setNodeRef} className={`kanban-card ${isDragging ? "dragging" : ""}`} style={{ transform: CSS.Transform.toString(transform), transition }} {...attributes} {...listeners} aria-label={`Drag ${card.title}`}>
            <div className="kanban-card-topline">
                <PriorityBadge priority={card.priority} />
                <span className="kanban-card-id">Updated {formatDisplayDate(card.updatedAt)}</span>
                <span className="kanban-card-actions">
                    <button type="button" onClick={onOpen} aria-label={`Edit ${card.title}`}><Pencil size={13} /></button>
                    <button type="button" onClick={onRename} aria-label={`Rename ${card.title}`}>Title</button>
                    <button type="button" onClick={onArchive} aria-label={`Archive ${card.title}`}><Archive size={13} /></button>
                    <button type="button" onClick={onDelete} aria-label={`Delete ${card.title}`}><Trash2 size={13} /></button>
                </span>
            </div>
            <button type="button" className="kanban-card-open" onClick={onOpen}>
                <span>{card.title}</span>
                {card.descriptionText ? <small>{card.descriptionText}</small> : null}
            </button>
            <div className="kanban-card-meta-band">
                {cardLabels.length > 0 ? cardLabels.map((label) => <LabelChip key={label.id} label={label} />) : <span className="kanban-card-muted"><Tag size={12} /> No labels</span>}
            </div>
            <div className="kanban-card-footerline">
                <span className="kanban-date-chip"><CalendarDays size={12} /> {card.dueDate ? formatDisplayDate(card.dueDate) : "No due date"}</span>
            </div>
        </article>
    );
}

function ListView({ columns, cards, labels, onOpenCard, onMoveCard, onArchiveCard, onDeleteCard }: {
    columns: KanbanColumn[];
    cards: KanbanCard[];
    labels: KanbanLabel[];
    onOpenCard: (id: string) => void;
    onMoveCard: (cardId: string, columnId: string) => void;
    onArchiveCard: (cardId: string) => void;
    onDeleteCard: (cardId: string) => void;
}): JSX.Element {
    return (
        <div className="kanban-list-view kanban-view-panel">
            {columns.map((column) => {
                const columnCards = cards.filter((card) => card.columnId === column.id).sort((left, right) => left.sortOrder - right.sortOrder);
                return (
                    <section key={column.id} className="kanban-list-section">
                        <h3><span style={{ background: column.color ?? "#9ca3af" }} />{column.name}<small>{columnCards.length} cards</small></h3>
                        {columnCards.map((card) => (
                            <article className="kanban-list-row" key={card.id}>
                                <button type="button" className="kanban-list-title" onClick={() => onOpenCard(card.id)}>
                                    <span>{card.title}</span>
                                    <small>{card.descriptionText || `Updated ${formatDisplayDate(card.updatedAt)}`}</small>
                                </button>
                                <span className="kanban-list-labels">
                                    {labels.filter((label) => card.labelIds.includes(label.id)).map((label) => <LabelChip key={label.id} label={label} />)}
                                </span>
                                <PriorityBadge priority={card.priority} />
                                <span className="kanban-date-chip"><CalendarDays size={12} /> {card.dueDate ? formatDisplayDate(card.dueDate) : "No due"}</span>
                                <select value={card.columnId} onChange={(event) => onMoveCard(card.id, event.target.value)}>
                                    {columns.map((target) => <option key={target.id} value={target.id}>{target.name}</option>)}
                                </select>
                                <span className="kanban-list-actions">
                                    <button type="button" onClick={() => onArchiveCard(card.id)} aria-label={`Archive ${card.title}`}><Archive size={14} /></button>
                                    <button type="button" onClick={() => onDeleteCard(card.id)} aria-label={`Delete ${card.title}`}><Trash2 size={14} /></button>
                                </span>
                            </article>
                        ))}
                    </section>
                );
            })}
        </div>
    );
}

function ArchiveView({ cards, labels, onOpenCard, onRestore, onDelete }: {
    cards: KanbanCard[];
    labels: KanbanLabel[];
    onOpenCard: (id: string) => void;
    onRestore: (id: string) => Promise<void>;
    onDelete: (id: string) => Promise<void>;
}): JSX.Element {
    return (
        <div className="kanban-list-view kanban-archive-view kanban-view-panel">
            <section className="kanban-list-section">
                <h3><Archive size={15} /> Archived cards <small>{cards.length}</small></h3>
                {cards.map((card) => (
                    <article className="kanban-list-row" key={card.id}>
                        <button type="button" className="kanban-list-title" onClick={() => onOpenCard(card.id)}>
                            <span>{card.title}</span>
                            <small>Archived {card.archivedAt ? formatDisplayDate(card.archivedAt) : "recently"}</small>
                        </button>
                        <span className="kanban-list-labels">
                            {labels.filter((label) => card.labelIds.includes(label.id)).map((label) => <LabelChip key={label.id} label={label} />)}
                        </span>
                        <PriorityBadge priority={card.priority} />
                        <span className="kanban-date-chip"><CalendarDays size={12} /> {card.dueDate ? formatDisplayDate(card.dueDate) : "No due"}</span>
                        <span className="kanban-list-actions">
                            <button type="button" onClick={() => void onRestore(card.id)} aria-label={`Restore ${card.title}`}><RotateCcw size={14} /></button>
                            <button type="button" onClick={() => void onDelete(card.id)} aria-label={`Delete ${card.title}`}><Trash2 size={14} /></button>
                        </span>
                    </article>
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
    onSave: (cardId: string, patch: Partial<KanbanCardPatch>) => Promise<void>;
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
                <div>
                    <strong>Card details</strong>
                    <span>Updated {formatDisplayDate(card.updatedAt)}</span>
                </div>
                <button type="button" onClick={onClose} aria-label="Close details"><X size={16} /></button>
            </header>
            <div className="kanban-details-body">
                <div className="kanban-details-main">
                    <label className="kanban-title-label">
                        <span>Title</span>
                        <input className="kanban-title-input" value={title} onChange={(event) => setTitle(event.target.value)} />
                    </label>
                    <section className="kanban-detail-section">
                        <h4>Labels</h4>
                        <div className="kanban-labels">
                            {labels.map((label) => (
                                <button type="button" key={label.id} className={`label-toggle ${card.labelIds.includes(label.id) ? "active" : ""}`} onClick={() => void onToggleLabel(card, label.id)}>
                                    <LabelChip label={label} />
                                </button>
                            ))}
                            <button type="button" className="kanban-label-create" onClick={() => void onCreateLabel()}><Plus size={14} /> Label</button>
                        </div>
                    </section>
                    <section className="kanban-detail-section kanban-detail-description">
                        <h4>Description</h4>
                        <RichTextEditor value={descriptionJson} onChange={(json, text) => { setDescriptionJson(json); setDescriptionText(text); }} />
                    </section>
                </div>
                <aside className="kanban-details-meta" aria-label="Card metadata">
                    <CustomSelect label="Column" value={columnId} options={columns.map((column) => ({ value: column.id, label: column.name }))} onChange={setColumnId} />
                    <CustomSelect label="Priority" value={priority} options={priorities.map((item) => ({ value: item, label: item }))} onChange={(value) => setPriority(value as KanbanPriority)} />
                    <label>Due<input type="date" value={dueDate} onChange={(event) => setDueDate(event.target.value)} /></label>
                    <button type="button" className="kanban-command primary" onClick={() => void onSave(card.id, { title, columnId, priority, dueDate: dueDate ? new Date(`${dueDate}T00:00:00`).getTime() : null, descriptionJson, descriptionText })}><Save size={14} /> Save</button>
                    <button type="button" onClick={() => void onArchive(card.id)}><Archive size={14} /> Archive</button>
                    <button type="button" className="danger" onClick={() => void onDelete(card.id)}><Trash2 size={14} /> Delete</button>
                </aside>
            </div>
            <footer>
                <button type="button" className="kanban-command primary" onClick={() => void onSave(card.id, { title, columnId, priority, dueDate: dueDate ? new Date(`${dueDate}T00:00:00`).getTime() : null, descriptionJson, descriptionText })}><Save size={14} /> Save</button>
                <button type="button" onClick={() => void onArchive(card.id)}><Archive size={14} /> Archive</button>
                <button type="button" className="danger" onClick={() => void onDelete(card.id)}><Trash2 size={14} /> Delete</button>
            </footer>
        </aside>
    );
}

function CustomSelect({ label, value, options, onChange }: {
    label: string;
    value: string;
    options: SelectOption[];
    onChange: (value: string) => void;
}): JSX.Element {
    const [open, setOpen] = useState(false);
    const selected = options.find((option) => option.value === value) ?? options[0];

    return (
        <div
            className={`kanban-select ${open ? "open" : ""}`}
            onBlur={(event) => {
                if (!event.currentTarget.contains(event.relatedTarget)) setOpen(false);
            }}
        >
            <span className="kanban-select-label">{label}</span>
            <button type="button" className="kanban-select-trigger" onClick={() => setOpen((current) => !current)} aria-expanded={open}>
                <span>{selected?.label ?? "Select"}</span>
                <ChevronDown size={14} />
            </button>
            {open ? (
                <div className="kanban-select-menu" role="listbox" aria-label={label}>
                    {options.map((option) => (
                        <button
                            type="button"
                            key={option.value}
                            className={option.value === value ? "active" : ""}
                            role="option"
                            aria-selected={option.value === value}
                            onClick={() => { onChange(option.value); setOpen(false); }}
                        >
                            <span>{option.label}</span>
                        </button>
                    ))}
                </div>
            ) : null}
        </div>
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

function formatDisplayDate(timestamp: number): string {
    return new Date(timestamp).toLocaleDateString(undefined, { month: "short", day: "numeric" });
}

function errorMessage(error: unknown): string {
    return error instanceof Error ? error.message : String(error);
}
