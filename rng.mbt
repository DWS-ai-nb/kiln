///|
/// Deterministic pseudo-random source (splitmix64).
///
/// Why not `@random`? Two reasons that both matter for this project:
///   * reproducibility is a contract — the same seed must produce the same
///     paper on wasm-gc, js and native, byte for byte;
///   * the generator must not depend on platform entropy fallbacks.
/// splitmix64 is ten lines, has no state beyond one word, and produces the same
/// stream everywhere.
pub struct Rng {
  mut state : UInt64
}

///|
pub fn Rng::new(seed : Int32) -> Rng {
  { state: 0x9E3779B97F4A7C15UL ^ seed.to_int64().reinterpret_as_uint64(), }
}

///|
pub fn Rng::next_u64(self : Rng) -> UInt64 {
  self.state = self.state + 0x9E3779B97F4A7C15UL
  let mut z = self.state
  z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9UL
  z = (z ^ (z >> 27)) * 0x94D049BB133111EBUL
  z ^ (z >> 31)
}

///|
/// Uniform-ish integer in `[0, n)`. `n <= 0` yields 0.
pub fn Rng::below(self : Rng, n : Int32) -> Int32 {
  if n <= 1 {
    return 0
  }
  (self.next_u64() % n.to_uint64()).to_int()
}

///|
/// In-place Fisher-Yates. The permutation depends only on the seed and the
/// input length, never on hash iteration order.
pub fn[T] shuffle(rng : Rng, xs : Array[T]) -> Unit {
  let mut i = xs.length() - 1
  while i > 0 {
    let j = rng.below(i + 1)
    let tmp = xs[i]
    xs[i] = xs[j]
    xs[j] = tmp
    i = i - 1
  }
}

///|
test "same seed gives the same stream" {
  let a = Rng::new(42)
  let b = Rng::new(42)
  inspect(a.next_u64() == b.next_u64(), content="true")
  inspect(a.next_u64() == b.next_u64(), content="true")
}

///|
test "different seeds diverge" {
  let a = Rng::new(1)
  let b = Rng::new(2)
  inspect(a.next_u64() == b.next_u64(), content="false")
}

///|
test "shuffle is deterministic and is a permutation" {
  let xs = [1, 2, 3, 4, 5, 6, 7, 8]
  let ys = [1, 2, 3, 4, 5, 6, 7, 8]
  let r1 = Rng::new(7)
  shuffle(r1, xs)
  let r2 = Rng::new(7)
  shuffle(r2, ys)
  inspect(xs == ys, content="true")
  let mut sum = 0
  for x in xs {
    sum = sum + x
  }
  inspect(sum, content="36")
}
