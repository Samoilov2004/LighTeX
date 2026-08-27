import * as pdfjs from "pdfjs-dist/legacy/build/pdf.mjs";
import pdfWorker from "pdfjs-dist/legacy/build/pdf.worker.min.mjs?url";

pdfjs.GlobalWorkerOptions.workerSrc = pdfWorker;

export { pdfjs };

export async function renderFirstPagePreview(base64: string): Promise<string | null> {
  try {
    const binary = Uint8Array.from(atob(base64), (character) => character.charCodeAt(0));
    const task = pdfjs.getDocument({ data: binary });
    const document = await task.promise;
    const page = await document.getPage(1);
    const original = page.getViewport({ scale: 1 });
    const viewport = page.getViewport({ scale: Math.min(1, 300 / original.width) });
    const ratio = Math.min(window.devicePixelRatio || 1, 2);
    const canvas = window.document.createElement("canvas");
    canvas.width = Math.max(1, Math.floor(viewport.width * ratio));
    canvas.height = Math.max(1, Math.floor(viewport.height * ratio));
    const context = canvas.getContext("2d");
    if (!context) return null;
    await page.render({ canvasContext: context, viewport, transform: ratio === 1 ? undefined : [ratio, 0, 0, ratio, 0, 0] }).promise;
    const data = canvas.toDataURL("image/png");
    await document.destroy();
    return data.slice(data.indexOf(",") + 1);
  } catch {
    return null;
  }
}
