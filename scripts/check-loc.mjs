import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";

const minimum = 5_000;
const maximum = 12_000;
const excluded = /^(?:assets|lib|node_modules|tests\/private)\//;
const binary = /\.(?:gif|ico|jpe?g|png|webp)$/i;

const tracked = execFileSync("git", ["ls-files"], { encoding: "utf8" })
  .trim()
  .split(/\r?\n/)
  .filter((file) => file && !excluded.test(file) && !binary.test(file));

const nonblank = tracked.reduce((total, file) => {
  const count = readFileSync(file, "utf8")
    .split(/\r?\n/)
    .filter((line) => line.trim().length > 0).length;
  return total + count;
}, 0);

if (nonblank < minimum || nonblank > maximum) {
  throw new Error(`tracked nonblank text LOC ${nonblank} is outside ${minimum}..${maximum}`);
}

console.log(`tracked nonblank text LOC: ${nonblank}`);
