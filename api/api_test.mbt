///|
test "bridge rejects fractional nonfinite and out-of-range numeric options" {
  let source = "{\"format\":\"kiln.model/1\",\"variables\":[{\"name\":\"x\",\"domain\":[0,1]}],\"rules\":[],\"objective\":\"x\"}"
  for budget in [0.5, -1.0, 100000001.0, 0.0 / 0.0, 1.0 / 0.0] {
    assert_true(@api.solve_json(source, budget, 10.0).contains("error"))
    assert_true(@api.minimize_json(source, budget).contains("error"))
    assert_true(
      @api.compare_json(source, source, budget, 10.0).contains("error"),
    )
    assert_true(
      @api.closest_json(source, source, "{\"x\":0}", budget).contains("error"),
    )
  }
  for limit in [0.0, 0.5, 1000001.0, 0.0 / 0.0] {
    assert_true(@api.solve_json(source, 100.0, limit).contains("error"))
  }
}
