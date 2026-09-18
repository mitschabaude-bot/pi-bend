# Native schema evaluation

`src/schema.bend` evaluates immutable `Schema` values against immutable `schema-value.Value` inputs. This supplies the checking dependency needed by pi's union coercion and optional-null normalization. It does not yet load JSON schemas or provide the complete TypeBox replacement.

`JsonKind` enforces a JSON type, including finite number/integer checks. `Constant` and `Enumeration` use structural equality: dictionary field order is irrelevant and list order matters. `All`, `Any`, `One` and `Not` compose schemas. `Object` checks declared properties, required keys and each additional property. `Array` checks a prefix of position-specific schemas and applies its item schema to the remainder. Object/array constraints apply only to matching instance kinds; combine them with `JsonKind` when the instance type must also be enforced. Use `Accept` for unrestricted additional properties/items and `Reject` to disallow them.

`Minimum` and `Maximum` carry a numeric limit and an inclusive/exclusive flag. `ItemCount` and `PropertyCount` use `CountBounds` with a natural minimum and optional maximum. `Contains` counts matching item schemas and applies its explicit bounds; the ordinary JSON-schema default is minimum one with no maximum. These keyword constraints leave instances of unrelated types alone, matching JSON Schema applicability rules. Contradictory bounds reject applicable instances.

The evaluator uses explicit immutable child tests, with no generated source, callback resources or object mutation. Ordinary dictionaries supply property lookup; names such as `__proto__` and `constructor` have no special behavior. Required fields distinguish an absent key from an explicit null value.

Still pending: JSON-schema compilation, uniqueItems, multipleOf, string-length and pattern/format handling, references and recursion, conditional/dependent schemas, remaining vocabulary, structured diagnostics and integration with normalization/coercion. String limits need the pinned TypeBox grapheme-counting behavior, not code-point or byte length. Unsupported functionality has no node in this typed vocabulary; there is no permissive JSON loader that silently drops unknown constraints.

Run `python3 tests/schema_check.py` for TypeBox comparisons and native-specific checks. This supplements the still-pending upstream validation suite.

A uniqueness decision is pending: TypeBox 1.3.27 accepts `[0, -0]` under `uniqueItems` because its hashing distinguishes their bit patterns; native numeric equality regards them as duplicates. No uniqueness node is enabled until that behavior is resolved with the user.
