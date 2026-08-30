import type { DetailedHTMLProps, HTMLAttributes } from "react";

type MathMLAttributes = DetailedHTMLProps<HTMLAttributes<HTMLElement>, HTMLElement> & {
  display?: "block" | "inline";
  linethickness?: string;
  width?: string;
};

declare module "react" {
  namespace JSX {
    interface IntrinsicElements {
      math: MathMLAttributes;
      mi: MathMLAttributes;
      mn: MathMLAttributes;
      mo: MathMLAttributes;
      mrow: MathMLAttributes;
      mfrac: MathMLAttributes;
      mroot: MathMLAttributes;
      msqrt: MathMLAttributes;
      msub: MathMLAttributes;
      msup: MathMLAttributes;
      msubsup: MathMLAttributes;
      munder: MathMLAttributes;
      mover: MathMLAttributes;
      mspace: MathMLAttributes;
      mtable: MathMLAttributes;
      mtr: MathMLAttributes;
      mtd: MathMLAttributes;
    }
  }
}
