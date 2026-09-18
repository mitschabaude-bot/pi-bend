# Native schema evaluation

`src/schema.bend` evaluates immutable `Schema` values against immutable `schema-value.Value` inputs. This supplies the checking dependency needed by pi's union coercion and optional-null normalization. It does not yet load JSON schemas or provide the complete TypeBox replacement.

`JsonKind` enforces a JSON type, including finite number/integer checks. `Constant` and `Enumeration` use structural equality: dictionary field order is irrelevant and list order matters. `All`, `Any`, `One` and `Not` compose schemas. `Object` checks declared properties, required keys and each additional property. `Array` checks a prefix of position-specific schemas and applies its item schema to the remainder. Object/array constraints apply only to matching instance kinds; combine them with `JsonKind` when the instance type must also be enforced. Use `Accept` for unrestricted additional properties/items and `Reject` to disallow them.

The evaluator uses explicit immutable child tests, with no generated source, callback resources or object mutation. Ordinary dictionaries supply property lookup; names such as `__proto__` and `constructor` have no special behavior. Required fields distinguish an absent key from an explicit null value.

Still pending: JSON-schema compilation, numeric/string/collection bounds, pattern/format handling, references and recursion, conditional/dependent schemas, remaining vocabulary, structured diagnostics and integration with normalization/coercion. Unsupported functionality has no node in this typed vocabulary; there is no permissive JSON loader that silently drops unknown constraints.

Run `python3 tests/schema_check.py` for TypeBox comparisons and native-specific checks. This supplements the still-pending upstream validation suite.
