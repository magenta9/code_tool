import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { toolCatalog } from "@codetool/shared";
import { App } from "./App";

describe("App smoke", () => {
  it("renders the shell and all catalog tools in navigation", () => {
    render(<App />);
    expect(screen.getByText("CodeTool")).toBeInTheDocument();
    for (const tool of toolCatalog) {
      expect(screen.getAllByText(tool.title).length).toBeGreaterThan(0);
    }
  });
});
