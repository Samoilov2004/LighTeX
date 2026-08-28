# Galerkin Elliptic Problems — LighTex demo project

This is a self-contained demonstration manuscript rather than a submitted
research paper. It is designed to look realistic on a product video while
remaining quick to compile with pdfLaTeX, XeLaTeX, or LuaLaTeX.

Open this entire folder as a project and use `main.tex` as the main document.
The source demonstrates multi-file navigation, Outline, cross-references,
BibTeX completion, theorem environments, a CSV-backed PGFPlots figure, project
search, and source/PDF SyncTeX navigation.

## Suggested 35-second recording

1. Open `sections/03-galerkin-method.tex` from Files, then drag it into the tab bar.
2. Use Outline to jump to “Galerkin orthogonality”.
3. Find the `DEMO:` comment and insert a display equation from Insert Shelf.
4. Type `\cref{thm:` and accept completion for `thm:cea`.
5. Wait for Auto Compile, then use source-to-PDF and inverse SyncTeX.
6. Open `figures/convergence-plot.tex` and briefly show the plotted CSV data.

Regenerate the deterministic data with:

```sh
python3 scripts/generate_convergence_data.py
```
