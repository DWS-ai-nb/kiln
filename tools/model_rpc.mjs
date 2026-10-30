// JSONL adapter around the actual compiled MoonBit library. No solver logic.
import { createInterface } from 'node:readline';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const compiled = process.argv[2] ?? '_build/js/debug/build/api/api.js';
const api = await import(pathToFileURL(resolve(compiled)).href);
const lines = createInterface({ input: process.stdin, crlfDelay: Infinity });
for await (const line of lines) {
  try {
    const req = JSON.parse(line);
    const source = typeof req.source === 'string' ? req.source : JSON.stringify(req.model);
    let output;
    if (req.operation === 'compare') {
      output = api.compare_json(source, JSON.stringify(req.after), req.budget ?? 1_000_000, req.limit ?? 100_000);
    } else if (req.operation === 'closest') {
      output = api.closest_json(source, JSON.stringify(req.after), JSON.stringify(req.baseline), req.budget ?? 1_000_000);
    } else if (req.operation === 'verify') {
      output = api.verify_json(source, JSON.stringify(req.assignment));
    } else if (req.operation === 'minimize') {
      output = api.minimize_json(source, req.budget ?? 1_000_000);
    } else {
      output = api.solve_json(source, req.budget ?? 1_000_000, req.limit ?? 100_000);
    }
    process.stdout.write(output + '\n');
  } catch (error) {
    process.stdout.write(JSON.stringify({ adapter_error: String(error) }) + '\n');
  }
}
