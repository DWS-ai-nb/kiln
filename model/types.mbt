///|
/// Arithmetic is exact inside [-10^12, 10^12]. Every operation is checked.
/// Division truncates toward zero; modulo has the dividend's sign.
pub(all) enum Term {
  Int(Int64)
  Var(String)
  Add(Term, Term)
  Sub(Term, Term)
  Mul(Term, Term)
  Div(Term, Term)
  Mod(Term, Term)
  Neg(Term)
  Abs(Term)
  /// 1 for a true predicate, 0 for false; undefined remains undefined.
  Indicator(Rule)
} derive(Debug, Eq)

///|
/// Rules have no business-specific or exercise-family variants.
pub(all) enum Rule {
  Eq(Term, Term)
  Ne(Term, Term)
  Lt(Term, Term)
  Le(Term, Term)
  Gt(Term, Term)
  Ge(Term, Term)
  All(Array[Rule])
  Any(Array[Rule])
  Not(Rule)
  /// Totalize acceptance: undefined arithmetic is rejection, never acceptance.
  Holds(Rule)
  Implies(Rule, Rule)
  AllDifferent(Array[Term])
  Table(Array[Term], Array[Array[Int64]])
  Count(Array[Rule], Int32, Int32)
} derive(Debug, Eq)

///|
pub(all) struct Variable {
  name : String
  values : Array[Int64]
} derive(Debug, Eq)

///|
pub(all) struct NamedRule {
  id : String
  rule : Rule
} derive(Debug, Eq)

///|
pub(all) struct Model {
  variables : Array[Variable]
  rules : Array[NamedRule]
} derive(Debug, Eq)

///|
pub(all) struct Options {
  /// Counts candidate-assignment probes, not just accepted search nodes.
  budget : Int32
  /// Maximum stored solutions. Reaching it is not proof of exhaustion.
  max_solutions : Int32
} derive(Debug, Eq)

///|
pub fn options(
  budget~ : Int32 = 100000,
  max_solutions~ : Int32 = 1000,
) -> Options {
  { budget, max_solutions, }
}

///|
pub(all) enum Stop {
  Exhausted
  SolutionLimit
  BudgetLimit
} derive(Debug, Eq)

///|
pub(all) struct Statistics {
  probes : Int32
  nodes : Int32
  pruned : Int32
  solutions_seen : Int32
} derive(Debug, Eq)

///|
pub(all) struct SearchResult {
  solutions : Array[Map[String, Int64]]
  stop : Stop
  stats : Statistics
} derive(Debug)

///|
/// Unique and Unsatisfiable require exhaustion. Two witnesses prove Multiple.
pub(all) enum Classification {
  Unsatisfiable
  Unique(Map[String, Int64])
  Multiple(Map[String, Int64], Map[String, Int64])
  Unknown
} derive(Debug)

///|
pub(all) struct CheckReport {
  valid : Bool
  violations : Array[String]
} derive(Debug, Eq)

///|
pub(all) struct Optimization {
  assignment : Map[String, Int64]?
  value : Int64?
  optimal : Bool
  stop : Stop
  stats : Statistics
} derive(Debug)

///|
pub(all) struct Conflict {
  rule_ids : Array[String]
  /// Subset-minimal relative to the original variable domains; not minimum size.
  irreducible : Bool
  checks : Int32
} derive(Debug, Eq)

///|
const LIMIT : Int64 = 1000000000000L

///|
pub extend Term with @debug.Debug::{to_repr}

///|
pub extend Term with Eq::{equal, not_equal}

///|
pub extend Rule with @debug.Debug::{to_repr}

///|
pub extend Rule with Eq::{equal, not_equal}

///|
pub extend Variable with @debug.Debug::{to_repr}

///|
pub extend Variable with Eq::{equal, not_equal}

///|
pub extend NamedRule with @debug.Debug::{to_repr}

///|
pub extend NamedRule with Eq::{equal, not_equal}

///|
pub extend Model with @debug.Debug::{to_repr}

///|
pub extend Model with Eq::{equal, not_equal}

///|
pub extend Options with @debug.Debug::{to_repr}

///|
pub extend Options with Eq::{equal, not_equal}

///|
pub extend Stop with @debug.Debug::{to_repr}

///|
pub extend Stop with Eq::{equal, not_equal}

///|
pub extend Statistics with @debug.Debug::{to_repr}

///|
pub extend Statistics with Eq::{equal, not_equal}

///|
pub extend SearchResult with @debug.Debug::{to_repr}

///|
pub extend Classification with @debug.Debug::{to_repr}

///|
pub extend CheckReport with @debug.Debug::{to_repr}

///|
pub extend CheckReport with Eq::{equal, not_equal}

///|
pub extend Optimization with @debug.Debug::{to_repr}

///|
pub extend Conflict with @debug.Debug::{to_repr}

///|
pub extend Conflict with Eq::{equal, not_equal}
