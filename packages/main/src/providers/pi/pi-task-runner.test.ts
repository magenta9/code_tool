import { homedir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { normalizeWorkspaceRoot } from "./pi-task-runner";

describe("normalizeWorkspaceRoot", () => {
    it("expands a tilde-prefixed workspace root", () => {
        expect(normalizeWorkspaceRoot("~/code/ai/tiny-experimental-project")).toBe(
            join(homedir(), "code/ai/tiny-experimental-project")
        );
    });

    it("leaves absolute paths unchanged", () => {
        expect(normalizeWorkspaceRoot("/Users/demo/project")).toBe("/Users/demo/project");
    });
});
