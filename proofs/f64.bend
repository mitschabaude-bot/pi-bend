import Base
import ../laws/f64.bend as Laws
import ../packages/runtime/src/f64.bend as F

def Laws.finite_values_are_finite(negative, exponent, significand): {==}

def Laws.infinities_are_not_finite(negative): {==}

def Laws.nan_is_not_finite(): {==}

def Laws.at_least_is_equal_or_greater(order):
  match order:
    case None{}: {==}
    case Some{LT{}}: {==}
    case Some{EQ{}}: {==}
    case Some{GT{}}: {==}

def Laws.at_most_excludes_greater_and_unordered(order):
  match order:
    case None{}: {==}
    case Some{LT{}}: {==}
    case Some{EQ{}}: {==}
    case Some{GT{}}: {==}

def Laws.unordered_comparisons_satisfy_nothing(): {==}

def Laws.minimum_of_unordered_is_nan(value): {==}

def Laws.maximum_of_unordered_is_nan(value): {==}
