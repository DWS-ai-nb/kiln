// Exercise the actual untyped JS export boundary, including non-JSON values.
import assert from 'node:assert/strict';
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';
const api = await import(pathToFileURL(resolve('_build/js/debug/build/api/api.js')));
const source = JSON.stringify({format:'kiln.model/1', variables:[{name:'x',domain:[0,1]}], rules:[], objective:'x'});
const rejected = JSON.stringify({format:'kiln.model/1', variables:[{name:'x',domain:[0,1]}], rules:[{id:'no',assert:['any']}]});
const invalid = [NaN, Infinity, -Infinity, undefined, null, '1', 'oops', true, false, {}, [], 1n, Symbol('n'), 0.5, -1, 100000001];
let checks = 0;
for (const value of invalid) {
  const calls = [
    () => api.solve_json(source, value, 100),
    () => api.compare_json(source, rejected, value, 100),
    () => api.closest_json(source, rejected, '{"x":0}', value),
    () => api.minimize_json(source, value),
  ];
  for (const call of calls) { assert.equal(typeof JSON.parse(call()).error, 'string'); checks++; }
}
for (const value of [...invalid, 0, 1000001]) {
  assert.equal(typeof JSON.parse(api.solve_json(source, 100, value)).error, 'string'); checks++;
  assert.equal(typeof JSON.parse(api.compare_json(source, rejected, 100, value)).error, 'string'); checks++;
}
assert.equal(JSON.parse(api.solve_json(source,0,100)).stop,'budget_limit'); checks++;
assert.equal(JSON.parse(api.solve_json(source,100,1)).stop,'solution_limit'); checks++;
console.log(`JS ABI checks passed: ${checks}`);
