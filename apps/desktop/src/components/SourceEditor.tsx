import { forwardRef, useCallback, useEffect, useImperativeHandle, useRef, useState, type MouseEvent as ReactMouseEvent } from "react";
import { createPortal } from "react-dom";
import { createRoot, type Root } from "react-dom/client";
import { acceptCompletion, autocompletion, closeBrackets, completionKeymap, type Completion, type CompletionContext } from "@codemirror/autocomplete";
import { defaultKeymap, history, historyField, historyKeymap, indentWithTab, undo, undoDepth } from "@codemirror/commands";
import { HighlightStyle, StreamLanguage, syntaxHighlighting } from "@codemirror/language";
import { searchKeymap } from "@codemirror/search";
import { Compartment, EditorState, StateField } from "@codemirror/state";
import { Decoration, EditorView, GutterMarker, WidgetType, drawSelection, dropCursor, gutter, highlightSpecialChars, keymap, lineNumbers, type DecorationSet } from "@codemirror/view";
import { tags } from "@lezer/highlight";
import { CircleX, TriangleAlert } from "lucide-react";
import type { AppConfigV1, BuildDiagnosticGroup, ProjectCompletionIndex, VersionDiffLine, VersionFileDiff } from "../types";
import { BuildLogPopover, type BuildLogAnchor } from "./BuildLogPopover";

interface SourceEditorProps {
  path: string;
  historyKey: string;
  value: string;
  config: AppConfigV1;
  completion: ProjectCompletionIndex;
  onChange(value: string): void;
  onUndoAvailabilityChange?(canUndo: boolean): void;
  readOnly?: boolean;
  diff?: VersionFileDiff | null;
  diagnostics?: BuildDiagnosticGroup[];
  buildLog?: string;
}

export interface SourceEditorHandle {
  undo(): boolean;
  focus(): void;
}

const settingsCompartment = new Compartment();
const diagnosticsCompartment = new Compartment();
const cachedEditorStates = new Map<string, unknown>();
const maximumCachedEditorStates = 40;

const latexLanguage = StreamLanguage.define({
  token(stream) {
    if (stream.match(/^%.*/)) return "comment";
    if (stream.match(/^\\[A-Za-z@]+\*?/)) return "keyword";
    if (stream.match(/^\\./)) return "keyword";
    if (stream.match(/^[{}[\]]/)) return "bracket";
    if (stream.match(/^\$\$?/)) return "operator";
    if (stream.match(/^&/)) return "operator";
    if (stream.match(/^\d+(?:\.\d+)?/)) return "number";
    stream.next();
    return null;
  },
});

const latexHighlight = HighlightStyle.define([
  { tag: tags.keyword, color: "#005cc5" },
  { tag: tags.comment, color: "#6a737d", fontStyle: "italic" },
  { tag: tags.bracket, color: "#735c0f" },
  { tag: tags.operator, color: "#b31d28" },
  { tag: tags.number, color: "#005cc5" },
]);

export const SourceEditor = forwardRef<SourceEditorHandle, SourceEditorProps>(function SourceEditor({ path, historyKey, value, config, completion, onChange, onUndoAvailabilityChange, readOnly = false, diff = null, diagnostics = [], buildLog = "" }, ref) {
  const host = useRef<HTMLDivElement>(null);
  const view = useRef<EditorView | null>(null);
  const applyingExternal = useRef(false);
  const [logAnchor, setLogAnchor] = useState<BuildLogAnchor | null>(null);
  const onChangeRef = useRef(onChange);
  const completionRef = useRef(completion);
  const onUndoAvailabilityChangeRef = useRef(onUndoAvailabilityChange);
  const diagnosticSignature = diagnostics.map((group) => `${group.primary.severity}:${group.primary.line}:${group.primary.message}`).join("|");
  onChangeRef.current = onChange;
  completionRef.current = completion;
  onUndoAvailabilityChangeRef.current = onUndoAvailabilityChange;

  useImperativeHandle(ref, () => ({
    undo() {
      const editor = view.current;
      if (!editor) return false;
      const changed = undo(editor);
      editor.focus();
      return changed;
    },
    focus() {
      view.current?.focus();
    },
  }), []);

  useEffect(() => {
    if (!host.current) return;
    const extensions = [
      latexLanguage,
      syntaxHighlighting(latexHighlight),
      history(),
      EditorState.readOnly.of(readOnly),
      EditorView.editable.of(!readOnly),
      highlightSpecialChars(),
      drawSelection(),
      dropCursor(),
      autocompletion({ override: [(context: CompletionContext) => latexCompletions(context, completionRef.current)] }),
      keymap.of([
        ...completionKeymap,
        { key: "Tab", run: acceptCompletion },
        indentWithTab,
        ...defaultKeymap,
        ...historyKeymap,
        ...searchKeymap,
      ]),
      settingsCompartment.of(editorSettings(config)),
      diffExtension(diff),
      diagnosticsCompartment.of(diagnosticsExtension(diagnostics)),
      EditorView.updateListener.of((update) => {
        if (update.docChanged && !applyingExternal.current) {
          onChangeRef.current(update.state.doc.toString());
        }
        if (update.docChanged) onUndoAvailabilityChangeRef.current?.(undoDepth(update.state) > 0);
      }),
      EditorView.domEventHandlers({
        dblclick(event, editorView) {
          const position = editorView.posAtCoords({ x: event.clientX, y: event.clientY });
          if (position == null) return false;
          const line = editorView.state.doc.lineAt(position);
          window.dispatchEvent(new CustomEvent("lightex:source-sync", {
            detail: { path, line: line.number, column: position - line.from + 1 },
          }));
          return false;
        },
      }),
    ];
    const cached = cachedEditorStates.get(historyKey) as { doc?: string } | undefined;
    const editorState = cached?.doc === value
      ? EditorState.fromJSON(cached, { doc: value, extensions }, { history: historyField })
      : EditorState.create({ doc: value, extensions });
    const editor = new EditorView({
      parent: host.current,
      state: editorState,
    });
    editor.contentDOM.setAttribute("aria-label", `LaTeX source: ${path}`);
    editor.contentDOM.setAttribute("aria-readonly", String(readOnly));
    view.current = editor;
    onUndoAvailabilityChangeRef.current?.(undoDepth(editor.state) > 0);
    const jump = (event: Event) => {
      const detail = (event as CustomEvent<{ path: string; line?: number }>).detail;
      if (detail.path !== path || !detail.line) return;
      const line = editor.state.doc.line(Math.max(1, Math.min(detail.line, editor.state.doc.lines)));
      editor.dispatch({ selection: { anchor: line.from }, scrollIntoView: true });
      editor.focus();
    };
    const insert = (event: Event) => {
      if (readOnly) return;
      const text = (event as CustomEvent<{ text: string }>).detail.text;
      const selection = editor.state.selection.main;
      editor.dispatch({
        changes: { from: selection.from, to: selection.to, insert: text },
        selection: { anchor: selection.from + text.length },
        scrollIntoView: true,
      });
      editor.focus();
    };
    window.addEventListener("lightex:editor-jump", jump);
    window.addEventListener("lightex:insert", insert);
    return () => {
      window.removeEventListener("lightex:editor-jump", jump);
      window.removeEventListener("lightex:insert", insert);
      cacheEditorState(historyKey, editor.state.toJSON({ history: historyField }));
      onUndoAvailabilityChangeRef.current?.(false);
      editor.destroy();
      view.current = null;
    };
  }, [historyKey, path, readOnly, diff]);

  useEffect(() => {
    const editor = view.current;
    if (!editor) return;
    editor.dispatch({ effects: diagnosticsCompartment.reconfigure(diagnosticsExtension(diagnostics)) });
    setLogAnchor(null);
  }, [diagnosticSignature, buildLog]);

  useEffect(() => {
    const toggle = (event: Event) => {
      const detail = (event as CustomEvent<{ path: string; trigger: HTMLElement; rect: BuildLogAnchor["rect"] }>).detail;
      if (detail.path !== path) return;
      setLogAnchor((current) => current ? null : { trigger: detail.trigger, rect: detail.rect });
    };
    window.addEventListener("lightex:toggle-build-log", toggle);
    return () => window.removeEventListener("lightex:toggle-build-log", toggle);
  }, [path]);

  useEffect(() => {
    const editor = view.current;
    if (!editor) return;
    editor.dispatch({ effects: settingsCompartment.reconfigure(editorSettings(config)) });
  }, [config.editorFontSize, config.tabWidth, config.showLineNumbers, config.wordWrap, config.autoCloseBrackets]);

  useEffect(() => {
    const editor = view.current;
    if (!editor || editor.state.doc.toString() === value) return;
    applyingExternal.current = true;
    editor.dispatch({ changes: { from: 0, to: editor.state.doc.length, insert: value } });
    applyingExternal.current = false;
  }, [value]);

  const closeLog = useCallback((restoreFocus = false) => {
    setLogAnchor((current) => {
      if (restoreFocus) current?.trigger.focus({ preventScroll: true });
      return null;
    });
  }, []);

  return <>
    <div className={`source-editor ${readOnly ? "read-only" : ""} ${diff?.lines.length ? "has-version-diff" : ""}`} ref={host} data-testid="source-editor" />
    {logAnchor && createPortal(<BuildLogPopover anchor={logAnchor} log={buildLog} failed={diagnostics.some((group) => group.primary.severity === "error")} onClose={closeLog} />, document.body)}
  </>;
});

const diagnosticRoots = new WeakMap<HTMLElement, Root>();

class InlineDiagnosticWidget extends WidgetType {
  constructor(readonly path: string, readonly diagnostic: BuildDiagnosticGroup["primary"]) {
    super();
  }

  eq(other: InlineDiagnosticWidget) {
    return this.path === other.path
      && this.diagnostic.severity === other.diagnostic.severity
      && this.diagnostic.line === other.diagnostic.line
      && this.diagnostic.message === other.diagnostic.message;
  }

  toDOM() {
    const host = document.createElement("div");
    host.className = "cm-inline-diagnostic-host";
    const root = createRoot(host);
    diagnosticRoots.set(host, root);
    root.render(<InlineDiagnosticRow path={this.path} diagnostic={this.diagnostic} />);
    return host;
  }

  destroy(dom: HTMLElement) {
    scheduleDiagnosticRootUnmount(dom);
    diagnosticRoots.delete(dom);
  }

  ignoreEvent() {
    return false;
  }
}

function InlineDiagnosticRow({ path, diagnostic }: { path: string; diagnostic: BuildDiagnosticGroup["primary"] }) {
  const Icon = diagnostic.severity === "error" ? CircleX : TriangleAlert;
  const copy = diagnosticCopy(diagnostic.message);
  const toggleLog = (event: ReactMouseEvent<HTMLButtonElement>) => {
    event.preventDefault();
    event.stopPropagation();
    const trigger = event.currentTarget;
    const rect = trigger.getBoundingClientRect();
    window.dispatchEvent(new CustomEvent("lightex:toggle-build-log", {
      detail: {
        path,
        trigger,
        rect: { top: rect.top, right: rect.right, bottom: rect.bottom, left: rect.left, width: rect.width, height: rect.height },
      },
    }));
  };
  return <div className={`cm-inline-diagnostic ${diagnostic.severity}`} role="alert">
    <Icon size={13} aria-hidden="true" />
    <strong>{copy.title}</strong>
    {copy.detail && <span>{copy.detail}</span>}
    <button type="button" className="cm-diagnostic-open-log" onMouseDown={(event) => event.preventDefault()} onClick={toggleLog}>Open Log</button>
  </div>;
}

class DiagnosticGutterMarker extends GutterMarker {
  constructor(readonly severity: BuildDiagnosticGroup["primary"]["severity"]) {
    super();
  }

  eq(other: DiagnosticGutterMarker) {
    return this.severity === other.severity;
  }

  toDOM() {
    const host = document.createElement("span");
    host.className = `cm-diagnostic-gutter-marker ${this.severity}`;
    const root = createRoot(host);
    diagnosticRoots.set(host, root);
    const Icon = this.severity === "error" ? CircleX : TriangleAlert;
    root.render(<Icon size={12} aria-hidden="true" />);
    return host;
  }

  destroy(dom: HTMLElement) {
    scheduleDiagnosticRootUnmount(dom);
    diagnosticRoots.delete(dom);
  }
}

function scheduleDiagnosticRootUnmount(dom: HTMLElement) {
  const root = diagnosticRoots.get(dom);
  if (root) window.queueMicrotask(() => root.unmount());
}

function diagnosticsExtension(groups: BuildDiagnosticGroup[]) {
  const visible = groups.filter((group) => group.primary.line && group.primary.line > 0);
  if (visible.length === 0) return [];
  const field = StateField.define<DecorationSet>({
    create(state) {
      return diagnosticDecorations(state, visible);
    },
    update(decorations, transaction) {
      return transaction.docChanged ? diagnosticDecorations(transaction.state, visible) : decorations;
    },
    provide: (value) => EditorView.decorations.from(value),
  });
  const markers = new Map<number, DiagnosticGutterMarker>();
  for (const group of visible) {
    const line = group.primary.line!;
    const current = markers.get(line);
    if (!current || group.primary.severity === "error") markers.set(line, new DiagnosticGutterMarker(group.primary.severity));
  }
  return [
    field,
    gutter({
      class: "cm-diagnostic-gutter",
      lineMarker(view, block) {
        return markers.get(view.state.doc.lineAt(block.from).number) ?? null;
      },
    }),
  ];
}

function diagnosticDecorations(state: EditorState, groups: BuildDiagnosticGroup[]) {
  const ranges = groups.flatMap((group) => {
    const lineNumber = Math.max(1, Math.min(group.primary.line ?? 1, state.doc.lines));
    const line = state.doc.line(lineNumber);
    const text = state.sliceDoc(line.from, line.to);
    const command = /\\[A-Za-z@]+\*?/.exec(text);
    const firstContent = text.search(/\S/);
    const underlineFrom = command ? line.from + command.index : line.from + Math.max(0, firstContent);
    const underlineTo = command ? underlineFrom + command[0].length : line.to;
    const result = [];
    if (underlineTo > underlineFrom) {
      result.push(Decoration.mark({ class: `cm-diagnostic-range ${group.primary.severity}` }).range(underlineFrom, underlineTo));
    }
    result.push(Decoration.widget({
      widget: new InlineDiagnosticWidget(group.primary.relativePath ?? "", group.primary),
      block: true,
      side: 1,
    }).range(line.to));
    return result;
  });
  return Decoration.set(ranges, true);
}

function diagnosticCopy(message: string) {
  const clean = message.trim();
  const firstSentence = /^(.+?)[.!?](?:\s+(.+))?$/.exec(clean);
  if (!firstSentence?.[2]) return { title: clean.replace(/[.]$/, ""), detail: "" };
  return { title: firstSentence[1], detail: firstSentence[2] };
}

class DeletedLineWidget extends WidgetType {
  constructor(readonly line: VersionDiffLine) {
    super();
  }

  eq(other: DeletedLineWidget) {
    return this.line.oldLine === other.line.oldLine && this.line.text === other.line.text;
  }

  toDOM() {
    const row = document.createElement("div");
    row.className = "cm-version-deleted-row";
    row.setAttribute("role", "note");
    row.setAttribute("aria-label", `Removed line ${this.line.oldLine ?? ""}: ${this.line.text}`);
    const number = document.createElement("span");
    number.className = "cm-version-deleted-number";
    number.textContent = String(this.line.oldLine ?? "");
    const sign = document.createElement("span");
    sign.className = "cm-version-deleted-sign";
    sign.textContent = "−";
    const text = document.createElement("span");
    text.className = "cm-version-deleted-text";
    text.textContent = this.line.text || " ";
    row.append(number, sign, text);
    return row;
  }

  ignoreEvent() {
    return true;
  }
}

class AddedLineMarker extends GutterMarker {
  toDOM() {
    const marker = document.createElement("span");
    marker.className = "cm-version-added-sign";
    marker.textContent = "+";
    marker.setAttribute("aria-hidden", "true");
    return marker;
  }
}

const addedLineMarker = new AddedLineMarker();

function diffExtension(diff: VersionFileDiff | null) {
  if (!diff || diff.binary || diff.lines.length === 0) return [];
  const decorationField = StateField.define<DecorationSet>({
    create(state) {
      return diffDecorations(state, diff);
    },
    update(decorations, transaction) {
      return transaction.docChanged ? diffDecorations(transaction.state, diff) : decorations;
    },
    provide: (field) => EditorView.decorations.from(field),
  });
  const additions = new Set(diff.lines.flatMap((line) => line.kind === "addition" && line.newLine ? [line.newLine] : []));
  return [
    decorationField,
    gutter({
      class: "cm-version-diff-gutter",
      lineMarker(view, block) {
        return additions.has(view.state.doc.lineAt(block.from).number) ? addedLineMarker : null;
      },
    }),
  ];
}

function diffDecorations(state: EditorState, diff: VersionFileDiff): DecorationSet {
  const ranges = diff.lines.flatMap((line) => {
    if (line.kind === "addition" && line.newLine && line.newLine <= state.doc.lines) {
      return [Decoration.line({
        class: "cm-version-added-line",
        attributes: { "data-version-diff": "added" },
      }).range(state.doc.line(line.newLine).from)];
    }
    if (line.kind === "deletion") {
      const afterDocument = line.anchorNewLine > state.doc.lines;
      const position = afterDocument ? state.doc.length : state.doc.line(Math.max(1, line.anchorNewLine)).from;
      return [Decoration.widget({
        widget: new DeletedLineWidget(line),
        block: true,
        side: afterDocument ? 1 : -1,
      }).range(position)];
    }
    return [];
  });
  return Decoration.set(ranges, true);
}

function cacheEditorState(key: string, state: unknown) {
  cachedEditorStates.delete(key);
  cachedEditorStates.set(key, state);
  if (cachedEditorStates.size <= maximumCachedEditorStates) return;
  const oldest = cachedEditorStates.keys().next().value;
  if (oldest) cachedEditorStates.delete(oldest);
}

function editorSettings(config: AppConfigV1) {
  return [
    config.showLineNumbers ? lineNumbers() : [],
    config.wordWrap ? EditorView.lineWrapping : [],
    config.autoCloseBrackets ? closeBrackets() : [],
    EditorState.tabSize.of(config.tabWidth),
    EditorView.theme({
      "&": {
        height: "100%",
        fontSize: `${config.editorFontSize}px`,
        backgroundColor: "var(--surface-editor)",
      },
      ".cm-scroller": {
        fontFamily: "var(--font-mono)",
        lineHeight: "18px",
        overflow: "auto",
      },
      ".cm-content": { padding: "8px 0", caretColor: "var(--text-primary)" },
      ".cm-line": { padding: "0 5px" },
      ".cm-gutters": {
        backgroundColor: "var(--surface-editor)",
        color: "var(--text-tertiary)",
        borderRight: "1px solid var(--separator)",
      },
      ".cm-lineNumbers .cm-gutterElement": {
        minWidth: "44px",
        padding: "0 7px 0 4px",
        lineHeight: "18px",
      },
      "&.cm-focused": { outline: "1px solid rgba(10, 122, 255, .65)", outlineOffset: "-1px" },
      ".cm-selectionBackground, ::selection": { backgroundColor: "var(--selection) !important" },
      ".cm-cursor": { borderLeftColor: "var(--text-primary)", borderLeftWidth: "1.5px" },
      ".cm-tooltip": {
        border: "1px solid var(--separator-strong)",
        borderRadius: "7px",
        boxShadow: "0 8px 24px rgba(0,0,0,.12)",
        overflow: "hidden",
      },
      ".cm-tooltip-autocomplete > ul > li": { padding: "4px 8px" },
      ".cm-tooltip-autocomplete > ul > li[aria-selected]": {
        backgroundColor: "var(--accent)",
        color: "white",
      },
    }),
  ];
}

function latexCompletions(context: CompletionContext, index: ProjectCompletionIndex) {
  const command = context.matchBefore(/\\[A-Za-z@]*/);
  const environment = context.matchBefore(/\\begin\{[A-Za-z*]*/);
  const reference = context.matchBefore(/\\(?:ref|eqref|autoref)\{[^}]*/);
  const citation = context.matchBefore(/\\cite[a-zA-Z*]*\{[^}]*/);
  const packageName = context.matchBefore(/\\usepackage(?:\[[^]]*\])?\{[^}]*/);
  const documentClass = context.matchBefore(/\\documentclass(?:\[[^]]*\])?\{[^}]*/);
  const image = context.matchBefore(/\\includegraphics(?:\[[^]]*\])?\{[^}]*/);
  const input = context.matchBefore(/\\(?:input|include)\{[^}]*/);
  if (!context.explicit && !command && !environment && !reference && !citation && !packageName && !documentClass && !image && !input) return null;

  if (environment) {
    const prefix = environment.text.split("{").pop() ?? "";
    return {
      from: environment.from + environment.text.lastIndexOf("{") + 1,
      options: environments
        .filter((name) => name.startsWith(prefix))
        .map(environmentCompletion),
    };
  }
  if (reference) return listInsideBraces(reference.from, reference.text, index.labels, "Reference");
  if (citation) return listInsideBraces(citation.from, citation.text, index.citations, "Citation");
  if (packageName) return listInsideBraces(packageName.from, packageName.text, [...commonPackages, ...index.packages], "Package");
  if (documentClass) return listInsideBraces(documentClass.from, documentClass.text, ["article", "report", "book", "beamer", ...index.classes], "Class");
  if (image) return listInsideBraces(image.from, image.text, index.imagePaths, "Image");
  if (input) return listInsideBraces(input.from, input.text, index.inputPaths, "Project file");
  return {
    from: command?.from ?? context.pos,
    options: commands,
    validFor: /^\\?[A-Za-z@]*$/,
  };
}

function listInsideBraces(from: number, text: string, values: string[], detail: string) {
  return {
    from: from + text.lastIndexOf("{") + 1,
    options: Array.from(new Set(values)).map((label) => ({ label, type: "text", detail })),
  };
}

function environmentCompletion(name: string): Completion {
  return {
    label: name,
    type: "keyword",
    detail: "Environment",
    apply(view, _completion, from, to) {
      const indentation = view.state.doc.lineAt(from).text.match(/^\s*/)?.[0] ?? "";
      const inserted = `${name}}\n${indentation}\t\n${indentation}\\end{${name}}`;
      const cursor = from + name.length + 2 + indentation.length + 1;
      view.dispatch({ changes: { from, to, insert: inserted }, selection: { anchor: cursor } });
    },
  };
}

const environments = [
  "equation", "equation*", "align", "align*", "gather", "multline", "cases",
  "matrix", "pmatrix", "bmatrix", "vmatrix", "theorem", "proof", "definition",
  "itemize", "enumerate", "figure", "table", "center", "abstract",
];

const commonPackages = [
  "amsmath", "amssymb", "amsthm", "mathtools", "graphicx", "booktabs", "geometry",
  "hyperref", "cleveref", "tikz", "pgfplots", "xcolor", "babel", "fontspec", "biblatex",
];

const commands: Completion[] = [
  ["\\section{}", "Section"], ["\\subsection{}", "Subsection"], ["\\textbf{}", "Bold text"],
  ["\\textit{}", "Italic text"], ["\\emph{}", "Emphasis"], ["\\frac{}{}", "Fraction"],
  ["\\sqrt{}", "Square root"], ["\\sum_{}^{}", "Summation"], ["\\int_{}^{}", "Integral"],
  ["\\label{}", "Label"], ["\\ref{}", "Reference"], ["\\cite{}", "Citation"],
  ["\\includegraphics{}", "Image"], ["\\input{}", "Input file"], ["\\item ", "List item"],
].map(([label, detail]) => ({ label, detail, type: "keyword", apply: label }));
