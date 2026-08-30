import { Fragment, type ReactNode } from "react";

const id = (value: string) => <mi>{value}</mi>;
const number = (value: string) => <mn>{value}</mn>;
const operator = (value: string) => <mo>{value}</mo>;
const row = (...children: ReactNode[]) => <mrow>{children.map((child, index) => <Fragment key={index}>{child}</Fragment>)}</mrow>;
const sub = (base: ReactNode, value: ReactNode) => <msub>{base}{value}</msub>;
const sup = (base: ReactNode, value: ReactNode) => <msup>{base}{value}</msup>;
const subSup = (base: ReactNode, lower: ReactNode, upper: ReactNode) => <msubsup>{base}{lower}{upper}</msubsup>;
const fraction = (top: ReactNode, bottom: ReactNode) => <mfrac>{top}{bottom}</mfrac>;

const previews: Record<string, ReactNode> = {
  fraction: fraction(id("a"), id("b")),
  root: <mroot>{id("x")}{id("n")}</mroot>,
  sum: row(subSup(operator("∑"), row(id("k"), operator("="), number("1")), id("n")), sub(id("a"), id("k"))),
  integral: row(subSup(operator("∫"), id("a"), id("b")), id("f"), operator("("), id("x"), operator(")"), operator("d"), id("x")),
  limit: row(<munder>{operator("lim")}{row(id("x"), operator("→"), number("0"))}</munder>, id("f"), operator("("), id("x"), operator(")")),
  "matrix-2": matrix([["a", "b"], ["c", "d"]]),
  cases: row(id("f"), operator("("), id("x"), operator(")"), operator("="), cases([[sup(id("x"), number("2")), row(id("x"), operator("≥"), number("0"))], [row(operator("−"), id("x")), row(id("x"), operator("<"), number("0"))]])),
  aligned: <mtable><mtr><mtd>{row(id("a"), operator("="), id("b"), operator("+"), id("c"))}</mtd></mtr><mtr><mtd>{row(id("d"), operator("="), id("e"), operator("+"), id("f"))}</mtd></mtr></mtable>,
  "double-integral": row(sub(operator("∬"), id("D")), id("f"), operator("d"), id("A")),
  derivative: row(fraction(row(operator("d"), id("f")), row(operator("d"), id("x"))), operator("("), id("x"), operator(")")),
  partial: fraction(row(operator("∂"), id("f")), row(operator("∂"), id("x"))),
  series: row(subSup(operator("∑"), row(id("n"), operator("="), number("0")), operator("∞")), sub(id("a"), id("n")), sup(id("x"), id("n"))),
  gradient: row(operator("∇"), id("f"), operator("("), id("x"), operator(")")),
  "matrix-3": matrix([["a", "b", "c"], ["d", "e", "f"], ["g", "h", "i"]]),
  determinant: row(operator("det"), operator("("), id("A"), operator(")"), operator("="), determinant([["a", "b"], ["c", "d"]])),
  vector: row(id("v"), operator("="), matrix([["x"], ["y"], ["z"]])),
  "dot-product": row(id("u"), operator("·"), id("v"), operator("="), subSup(operator("∑"), row(id("i"), operator("="), number("1")), id("n")), sub(id("u"), id("i")), sub(id("v"), id("i"))),
  "linear-system": cases([[row(id("a"), id("x"), operator("+"), id("b"), id("y"), operator("="), id("c"))], [row(id("d"), id("x"), operator("+"), id("e"), id("y"), operator("="), id("f"))]]),
  binomial: row(operator("("), <mfrac linethickness="0">{id("n")}{id("k")}</mfrac>, operator(")"), operator("="), fraction(row(id("n"), operator("!")), row(id("k"), operator("!"), operator("("), id("n"), operator("−"), id("k"), operator(")"), operator("!")))),
  "set-builder": row(operator("{"), id("x"), operator("∈"), operator("ℝ"), operator("∣"), id("x"), operator(">"), number("0"), operator("}")),
  expectation: row(operator("𝔼"), operator("["), id("X"), operator("]"), operator("="), sub(operator("∑"), id("x")), id("x"), operator("ℙ"), operator("("), id("X"), operator("="), id("x"), operator(")")),
  norm: row(sub(row(operator("‖"), id("x"), operator("‖")), number("2")), operator("="), <msqrt>{sub(operator("∑"), id("i"))}{sup(sub(id("x"), id("i")), number("2"))}</msqrt>),
};

export function MathSnippetPreview({ id: snippetId, fallback }: { id: string; fallback: string }) {
  const preview = previews[snippetId];
  if (!preview) return <>{fallback}</>;
  const compact = ["sum", "integral", "limit", "cases", "aligned", "series", "matrix-3", "determinant", "dot-product", "linear-system", "binomial", "set-builder", "expectation", "norm"].includes(snippetId);
  return <math className={compact ? "math-preview compact" : "math-preview"} display="block">{preview}</math>;
}

function matrix(values: string[][]) {
  return row(
    operator("("),
    <mtable>{values.map((valuesRow, rowIndex) => <mtr key={rowIndex}>{valuesRow.map((value, columnIndex) => <mtd key={columnIndex}>{id(value)}</mtd>)}</mtr>)}</mtable>,
    operator(")"),
  );
}

function determinant(values: string[][]) {
  return row(
    operator("|"),
    <mtable>{values.map((valuesRow, rowIndex) => <mtr key={rowIndex}>{valuesRow.map((value, columnIndex) => <mtd key={columnIndex}>{id(value)}</mtd>)}</mtr>)}</mtable>,
    operator("|"),
  );
}

function cases(values: ReactNode[][]) {
  return row(
    operator("{"),
    <mtable>{values.map((valuesRow, rowIndex) => <mtr key={rowIndex}>{valuesRow.map((value, columnIndex) => <mtd key={columnIndex}>{value}</mtd>)}</mtr>)}</mtable>,
  );
}
