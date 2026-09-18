"""Native JSON schemas used to exercise upstream transcript behavior."""
from schema_test_values import tagged

def fixtures(root):
    schemas = [
        {'type': 'object', 'properties': {}},
        {'type': 'object', 'properties': {'path': {'type': 'string'}, 'limit': {'type': 'number', 'default': 0}}, 'required': ['path'], 'additionalProperties': False},
        {'type': 'object', 'properties': {'a': {'type': 'array', 'items': {'type': 'string'}}}},
        {'type': 'object', 'properties': {'value': {'anyOf': [{'const': 'a'}, {'type': 'null'}]}}},
        {'type': 'object', 'properties': {'override': {'type': 'string'}}, 'required': ['override']},
        {'type': 'string'},
        {'type': 'object', 'properties': {'count': {'type': 'integer'}}},
    ]
    return [{'input': tagged(schema)} for schema in schemas]
