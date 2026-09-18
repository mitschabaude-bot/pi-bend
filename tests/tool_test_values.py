"""Bend expressions shared by tool-declaration/state differential tests."""
from schema_test_values import bend, string

def text(value):
    return string(map(ord, value))

def sampling(config):
    if config is None:
        return 'None{}'
    if config is False:
        return 'Some{T.SamplingDisabled{}}'
    if config['type'] == 'json_schema':
        strict = 'T.Prefer{}' if config['strict'] == 'prefer' else 'T.Require{}'
        value = f'T.JsonSchemaSampling{{{strict}}}'
    else:
        variants = 'G.empty()'
        for key, value in config['variants'].items():
            format_value = 'T.OpenAILark{}' if key == 'openai_lark' else 'T.OpenAIRegex{}'
            variants = f'G.set({variants}, {format_value}, Some{{{text(value)}}})'
        value = f'T.GrammarSampling{{{variants}}}'
    return f'Some{{T.SamplingConfigured{{{value}}}}}'

def tool_bend(value):
    return 'T.Tool{' + ', '.join([text(value['name']), text(value['description']),
                                bend(value['parameters']), sampling(value['sampling'])]) + '}'

