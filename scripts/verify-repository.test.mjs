import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import test from "node:test";

const expectedDocuments = [
  "docs/arquitectura.md",
  "docs/despliegue.md",
  "docs/gobierno.md",
  "docs/integracion.md",
  "docs/modelo-economico.md",
  "docs/modelo-seguridad.md",
  "docs/operaciones.md",
];

const textExtensions = new Set([
  "",
  ".json",
  ".md",
  ".mjs",
  ".ps1",
  ".sh",
  ".sol",
  ".toml",
  ".ts",
  ".txt",
  ".yml",
]);

test("repository exposes the required production artifacts", () => {
  const tracked = execFileSync("git", ["ls-files"], { encoding: "utf8" }).trim().split(/\r?\n/);
  for (const file of ["README.md", "SECURITY.md", "assets/banner.png", ...expectedDocuments]) {
    assert.ok(tracked.includes(file), `${file} must be tracked`);
  }
  assert.equal(
    tracked.filter((file) => file.startsWith("docs/") && file.endsWith(".md")).length,
    7,
  );
  assert.match(
    readFileSync("README.md", "utf8"),
    /!\[BastionCDPProtocol\]\(\.\/assets\/banner\.png\)/,
  );
});

test("banner is the approved deterministic asset", () => {
  const banner = readFileSync("assets/banner.png");
  assert.equal(banner.subarray(1, 4).toString("ascii"), "PNG");
  assert.equal(banner.readUInt32BE(16), 1672);
  assert.equal(banner.readUInt32BE(20), 941);
  assert.equal(
    createHash("sha256").update(banner).digest("hex"),
    "9e6b7ed595cb174db1f22008fea687bd3acc46312df6638bd01c73590661f9e5",
  );
});

test("public narrative keeps internal review material private", () => {
  const tracked = execFileSync("git", ["ls-files"], { encoding: "utf8" }).trim().split(/\r?\n/);
  const expressions = [
    "c" + "tf",
    "la" + "b(?:oratorio)?s?",
    "vulnera" + "b(?:le|ilidad|ility|ilities)?",
    "explo" + "it(?:able|ation)?",
    "bu" + "g(?:s)?",
  ];
  const restricted = new RegExp(`\\b(?:${expressions.join("|")})\\b`, "i");
  for (const file of tracked) {
    const extension = file.includes(".") ? file.slice(file.lastIndexOf(".")) : "";
    if (!textExtensions.has(extension) || file === "package-lock.json") continue;
    assert.doesNotMatch(
      readFileSync(file, "utf8"),
      restricted,
      `${file} contains internal terminology`,
    );
  }
});
