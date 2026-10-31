"""Second independent full-product oracle, added after the pending/undefined audit.
Fixed seed 93021031; 10000 deep models; no shared reference evaluator.
"""
import itertools, json, random, subprocess, time
from pathlib import Path
R = random.Random(93021031)
LIM = 10 ** 12

class U(Exception):
    pass

def calc(t, e):
    if type(t) is int:
        z = t
    elif type(t) is str:
        z = e[t]
    elif t[0] == 'indicator':
        a = judge(t[1], e)
        if a is None:
            raise U()
        z = int(a)
    else:
        op, *rest = t
        a = calc(rest[0], e)
        if op == 'abs':
            z = abs(a)
        elif op == 'neg':
            z = -a
        else:
            b = calc(rest[1], e)
            if op == '+':
                z = a + b
            elif op == '-':
                z = a - b
            elif op == '*':
                z = a * b
            elif op in ('/', '%'):
                if b == 0:
                    raise U()
                q = abs(a) // abs(b) * (-1 if (a < 0) != (b < 0) else 1)
                z = q if op == '/' else a - q * b
            else:
                raise ValueError(op)
    if abs(z) > LIM:
        raise U()
    return z

def judge(r, e):
    op, *aa = r
    if op in ('all', 'any'):
        vs = [judge(a, e) for a in aa]
        if op == 'all':
            return False if any((v is False for v in vs)) else None if any((v is None for v in vs)) else True
        return True if any((v is True for v in vs)) else None if any((v is None for v in vs)) else False
    if op in ('not', 'holds'):
        v = judge(aa[0], e)
        return v is True if op == 'holds' else None if v is None else not v
    if op == 'implies':
        return judge(['any', ['not', aa[0]], aa[1]], e)
    if op == 'count':
        lo, hi, rs = aa
        vs = [judge(a, e) for a in rs]
        return None if any((v is None for v in vs)) else lo <= sum((v is True for v in vs)) <= hi
    try:
        if op == 'distinct':
            vs = [calc(a, e) for a in aa]
            return len(vs) == len(set(vs))
        if op == 'table':
            return [calc(a, e) for a in aa[0]] in aa[1]
        a, b = [calc(t, e) for t in aa]
        if op == '==':
            return a == b
        if op == '!=':
            return a != b
        if op == '<':
            return a < b
        if op == '<=':
            return a <= b
        if op == '>':
            return a > b
        if op == '>=':
            return a >= b
        raise ValueError(op)
    except U:
        return None

def tm(d=2):
    if d <= 0 or R.random() < 0.37:
        return R.choice(['x', 'y', 0, 1, -1, LIM, -LIM])
    op = R.choice(['abs', 'neg', '+', '-', '*', '/', '%', 'indicator'])
    if op == 'indicator':
        return [op, rr(1)]
    return [op, *[tm(d - 1) for _ in range(1 if op in ('abs', 'neg') else 2)]]

def rr(d=6):
    if d <= 0:
        return [R.choice(['==', '!=', '<', '<=', '>', '>=']), tm(), tm()]
    op = R.choice(['all', 'any', 'not', 'holds', 'implies', 'count', 'distinct', 'table', 'cmp'])
    if op in ('all', 'any'):
        return [op, *[rr(d - 1) for _ in range(R.randrange(4))]]
    if op in ('not', 'holds'):
        return [op, rr(d - 1)]
    if op == 'implies':
        return [op, rr(d - 1), rr(d - 1)]
    if op == 'count':
        rs = [rr(d - 1) for _ in range(R.randrange(4))]
        lo = R.randrange(len(rs) + 1)
        hi = R.randrange(lo, len(rs) + 1)
        return [op, lo, hi, rs]
    if op == 'distinct':
        return [op, *[tm() for _ in range(R.randrange(4))]]
    if op == 'table':
        ts = [tm() for _ in range(R.randrange(4))]
        return [op, ts, [[R.choice([-1, 0, 1, LIM]) for _ in ts] for _ in range(R.randrange(4))]]
    return rr(0)
P = subprocess.Popen(['node', 'tools/model_rpc.mjs'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, encoding='utf-8')

def call(doc, **kw):
    P.stdin.write(json.dumps({'model': doc, **kw}) + '\n')
    P.stdin.flush()
    s = P.stdout.readline()
    if not s:
        raise RuntimeError(P.stderr.read())
    return json.loads(s)

def key(items):
    return {tuple(sorted(e.items())) for e in items}

def exact(doc):
    return [dict(zip(['x', 'y'], v)) for v in itertools.product(*[x['domain'] for x in doc['variables']]) if all((judge(r['assert'], dict(zip(['x', 'y'], v))) is True for r in doc['rules']))]
start = time.perf_counter()
n = 0
compared = 0
opts = 0
bounded = 0
try:
    for i in range(10000):
        doc = {'format': 'kiln.model/1', 'variables': [{'name': v, 'domain': R.sample([-1, 0, 1, LIM, -LIM], R.randrange(1, 5))} for v in ['x', 'y']], 'rules': [{'id': f'r{k}', 'assert': rr()} for k in range(R.randrange(1, 4))], 'objective': tm()}
        expected = exact(doc)
        r = call(doc, budget=1000000, limit=100000)
        assert 'error' not in r, (i, r)
        assert r['complete'] and key(r['solutions']) == key(expected), (i, doc, r, expected)
        n += 1
        if i % 10 == 0:
            values = []
            for e in expected:
                try:
                    values.append(calc(doc['objective'], e))
                except U:
                    pass
            opt = call(doc, operation='minimize', budget=1000000)
            assert opt['value'] == (min(values) if values else None), (i, 'opt', doc, opt, values)
            assert opt['optimal'] == bool(values), (i, 'optflag', opt)
            opts += 1
        if i % 20 == 0:
            budget = R.randrange(20)
            limited = call(doc, budget=budget, limit=R.randrange(1, 3))
            assert key(limited['solutions']) <= key(expected) and limited['statistics']['probes'] <= budget
            if limited['complete']:
                assert key(limited['solutions']) == key(expected)
            bounded += 1
        if i % 10 == 0:
            after = {'format': 'kiln.model/1', 'variables': doc['variables'], 'rules': [{'id': 'new', 'assert': rr()}]}
            actual = call(doc, after=after, operation='compare', budget=1000000, limit=100000)
            delta = key(expected) ^ key(exact(after))
            assert actual['complete'] and key((c['assignment'] for c in actual['changes'])) == delta, (i, 'diff', doc, after, actual, delta)
            baseline = {v['name']: v['domain'][0] for v in doc['variables']}
            close = call(doc, after=after, operation='closest', baseline=baseline, budget=1000000)
            distance = min((sum((a != baseline[k] for k, a in e)) for e in delta), default=None)
            assert close['distance'] == distance and close['minimal'] == bool(delta), (i, 'closest', doc, after, close, distance)
            compared += 1
finally:
    P.stdin.close()
    P.wait(timeout=10)
summary = {'seed': 93021031, 'deep_models': n, 'complete_difference_and_hamming_pairs': compared, 'optimization_checks': opts, 'bounded_checks': bounded, 'elapsed_seconds': round(time.perf_counter() - start, 3), 'head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()}
Path('work/deep-semantics').mkdir(parents=True, exist_ok=True)
Path('work/deep-semantics/summary.json').write_text(json.dumps(summary, indent=2), encoding='utf-8')
print(json.dumps(summary, indent=2))
