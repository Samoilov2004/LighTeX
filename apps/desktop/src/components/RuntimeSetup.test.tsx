import { render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it } from "vitest";
import { RuntimeSetup } from "./RuntimeSetup";
import { useAppStore } from "../store";

describe("RuntimeSetup", () => {
  beforeEach(() => useAppStore.setState({
    runtimeEnvironment: { platform: "linux", architecture: "x86_64" },
    runtimeManifest: {
      schemaVersion: 2,
      runtimeVersion: "2026.1",
      texLiveYear: 2026,
      assets: [{ variant: "standard", platform: "linux", architecture: "x86_64", downloadUrl: "https://example.invalid/runtime.zip", downloadParts: null, compressedSize: 2_800_000_000, installedSize: 4_000_000_000, sha256: "0".repeat(64), tools: {} }],
    },
    systemToolchain: { engines: {}, latexmk: null, synctex: null, tlmgr: null },
    runtimeEvent: null,
    runtimeError: null,
  }));

  it("uses the backend platform and real manifest sizes", () => {
    render(<RuntimeSetup />);
    expect(screen.getByText(/2\.8 GB download/)).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /install standard/i })).toBeEnabled();
  });
});
