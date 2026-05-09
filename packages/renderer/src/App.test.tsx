import { render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it } from "vitest";
import { toolCatalog } from "@codetool/shared";
import { App } from "./App";

describe("App smoke", () => {
  beforeEach(() => {
    window.location.hash = "#/";
  });

  it("renders the shell and all catalog tools in navigation", () => {
    render(<App />);
    expect(screen.getAllByText("CodeTool").length).toBeGreaterThan(0);
    expect(screen.queryByText("local-first")).not.toBeInTheDocument();
    expect(screen.queryByText("macOS")).not.toBeInTheDocument();
    for (const tool of toolCatalog) {
      expect(screen.getAllByText(tool.title).length).toBeGreaterThan(0);
    }
  });

  it("renders the word cloud preview shell instead of the old token list", () => {
    window.location.hash = "#/tools/word-cloud";
    render(<App />);
    expect(screen.getByText("Preview")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Generate cloud" })).toBeInTheDocument();
    expect(screen.queryByText("Tokens")).not.toBeInTheDocument();
  });

  it("renders the Pi agent workspace with the prompt composer", () => {
    window.location.hash = "#/tools/pi-agent";
    render(<App />);
    expect(screen.getByRole("heading", { name: "Pi Agent" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Run prompt" })).toBeInTheDocument();
    expect(screen.getByPlaceholderText("/Users/you/code/project")).toBeInTheDocument();
  });
});
