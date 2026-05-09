import { describe, expect, it } from "vitest";
import { analyzeWordCloud, convertTimestamp, decodeJwt, diffJsonText, inspectImageBase64, runJsonTool } from "./index";

describe("DevTools core logic", () => {
  it("formats JSON and collects stats", () => {
    const result = runJsonTool({ text: '{"a":1,"b":[true]}', mode: "format" });
    expect(result.ok).toBe(true);
    expect(result.output).toContain('\n  "a": 1');
    expect(result.stats?.keys).toBe(2);
  });

  it("returns invalid JSON errors", () => {
    expect(runJsonTool({ text: "{", mode: "format" }).ok).toBe(false);
  });

  it("counts nested JSON diffs", () => {
    const result = diffJsonText('{"a":1,"b":{"c":2}}', '{"a":2,"b":{"d":3}}');
    expect(result.summary.modified).toBe(1);
    expect(result.summary.added).toBe(1);
    expect(result.summary.removed).toBe(1);
  });

  it("detects seconds and milliseconds", () => {
    expect(convertTimestamp({ value: "1700000000", timezone: "UTC" }).inputKind).toBe("seconds");
    expect(convertTimestamp({ value: "1700000000000", timezone: "UTC" }).inputKind).toBe("milliseconds");
  });

  it("decodes JWT payload safely", () => {
    const token = "eyJhbGciOiJub25lIn0.eyJzdWIiOiIxMjMiLCJleHAiOjE3MDAwMDAwMDB9.signature";
    const result = decodeJwt(token);
    expect(result.ok).toBe(true);
    expect(result.payload?.sub).toBe("123");
    expect(result.expiresAt).toBe("2023-11-14T22:13:20.000Z");
  });

  it("tokenizes word cloud input deterministically", () => {
    const result = analyzeWordCloud("the code code tool test");
    expect(result.tokens[0]).toMatchObject({ text: "code", count: 2 });
    expect(result.tokens.some((token) => token.text === "the")).toBe(false);
  });

  it("removes stop words and keeps tie ordering stable", () => {
    const result = analyzeWordCloud("the beta alpha beta alpha and gamma");
    expect(result.tokens.map((token) => token.text)).toEqual(["alpha", "beta", "gamma"]);
    expect(result.tokens.map((token) => token.count)).toEqual([2, 2, 1]);
  });

  it("segments chinese text into repeated terms", () => {
    const result = analyzeWordCloud("今天天气不错，今天适合散步。");
    expect(result.tokens[0]).toMatchObject({ text: "今天", count: 2 });
    expect(result.tokens.some((token) => token.text === "天气")).toBe(true);
    expect(result.totalWords).toBeGreaterThan(result.uniqueWords);
  });

  it("detects png base64 input", () => {
    const result = inspectImageBase64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAAB");
    expect(result.ok).toBe(true);
    expect(result.mimeType).toBe("image/png");
  });
});
