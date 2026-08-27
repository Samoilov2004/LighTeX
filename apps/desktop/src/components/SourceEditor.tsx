import { useEffect, useRef } from "react";
import { acceptCompletion, autocompletion, closeBrackets, completionKeymap, type Completion, type CompletionContext } from "@codemirror/autocomplete";
import { defaultKeymap, history, historyKeymap, indentWithTab } from "@codemirror/commands";
import { HighlightStyle, StreamLanguage, syntaxHighlighting } from "@codemirror/language";
import { searchKeymap } from "@codemirror/search";
import { Compartment, EditorState } from "@codemirror/state";
import { EditorView, drawSelection, dropCursor, highlightSpecialChars, keymap, lineNumbers } from "@codemirror/view";
import { tags } from "@lezer/highlight";
import type { AppConfigV1, ProjectCompletionIndex } from "../types";

interface SourceEditorProps {
  path: string;
  value: string;
  config: AppConfigV1;
  completion: ProjectCompletionIndex;
  onChange(value: string): void;
}

const settingsCompartment = new Compartment();

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

export function SourceEditor({ path, value, config, completion, onChange }: SourceEditorProps) {
  const host = useRef<HTMLDivElement>(null);
  const view = useRef<EditorView | null>(null);
  const applyingExternal = useRef(false);
  const onChangeRef = useRef(onChange);
  const completionRef = useRef(completion);
  onChangeRef.current = onChange;
  completionRef.current = completion;

  useEffect(() => {
    if (!host.current) return;
    const editor = new EditorView({
      parent: host.current,
      state: EditorState.create({
        doc: value,
        extensions: [
          latexLanguage,
          syntaxHighlighting(latexHighlight),
          history(),
          highlightSpecialChars(),
          drawSelection(),
          dropCursor(),
          autocompletion({ override: [(context) => latexCompletions(context, completionRef.current)] }),
          keymap.of([
            ...completionKeymap,
            { key: "Tab", run: acceptCompletion },
            indentWithTab,
            ...defaultKeymap,
            ...historyKeymap,
            ...searchKeymap,
          ]),
          settingsCompartment.of(editorSettings(config)),
          EditorView.updateListener.of((update) => {
            if (update.docChanged && !applyingExternal.current) {
              onChangeRef.current(update.state.doc.toString());
            }
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
        ],
      }),
    });
    editor.contentDOM.setAttribute("aria-label", `LaTeX source: ${path}`);
    view.current = editor;
    const jump = (event: Event) => {
      const detail = (event as CustomEvent<{ path: string; line?: number }>).detail;
      if (detail.path !== path || !detail.line) return;
      const line = editor.state.doc.line(Math.max(1, Math.min(detail.line, editor.state.doc.lines)));
      editor.dispatch({ selection: { anchor: line.from }, scrollIntoView: true });
      editor.focus();
    };
    const insert = (event: Event) => {
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
      editor.destroy();
      view.current = null;
    };
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

  return <div className="source-editor" ref={host} data-testid="source-editor" />;
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
      ".cm-content": { padding: "8px 6px", caretColor: "var(--text-primary)" },
      ".cm-line": { padding: "0 6px" },
      ".cm-gutters": {
        backgroundColor: "var(--surface-editor)",
        color: "var(--text-tertiary)",
        borderRight: "1px solid var(--separator)",
      },
      ".cm-lineNumbers .cm-gutterElement": {
        minWidth: "44px",
        padding: "0 10px 0 4px",
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
