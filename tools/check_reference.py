"""Adversarial input checks for the independent reference checker boundary."""
from model_reference import strict_json, verify

doc = strict_json('{"format":"kiln.model/1","variables":[{"name":"x","domain":[0,1]}],"rules":[]}')
assert verify(doc, {"x": 1})
for value in [True, False, 1.0, 0.0, "1", None, 10**13]:
    assert not verify(doc, {"x": value}), value
for text in ['{"x":1,"x":0}', '{"x":1.0}', '{"x":1e0}', '{"x":1e-9999}', '{"x":NaN}', '{"x":Infinity}']:
    try:
        strict_json(text)
    except ValueError:
        pass
    else:
        raise AssertionError(text)
assert not verify(doc, {"x": 0, "extra": 1})
assert not verify(doc, {})
print('Reference boundary checks passed: 16')
