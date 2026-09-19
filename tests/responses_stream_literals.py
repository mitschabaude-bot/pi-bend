"""Typed Bend literals for Responses wire content and events."""
from schema_literals import string, seq, value

def optional(v):return 'None{}' if v is None else 'Some{'+string(v)+'}'
def record(v,enc=value):return 'R.Record{'+seq('R.Property{'+string(k)+', '+enc(x)+'}' for k,x in v.items())+'}'
def item(v):
    kind=v['type']
    if kind=='reasoning':return 'C.ReasoningItem{'+record(v)+'}'
    if kind=='message':
        phase='None{}' if v.get('phase') is None else 'Some{T.'+{'commentary':'Commentary','final_answer':'FinalAnswer'}[v['phase']]+'{}}'
        return 'C.MessageItem{'+string(v['id'])+', '+phase+', '+seq(string(x.get('text',x.get('refusal',''))) for x in v['content'])+'}'
    if kind in ['function_call','custom_tool_call']:
        args=string(v.get('arguments','')) if kind=='function_call' else optional(v.get('input'))
        return 'C.'+('FunctionItem' if kind=='function_call' else 'CustomItem')+'{'+', '.join([string(v['id']),string(v['call_id']),string(v['name']),args,optional(v.get('namespace'))])+'}'
    return 'C.OtherItem{}'
def event_literal(e):
    kind=e['type'].removeprefix('response.')
    if kind=='output_item.done':return 'C.ItemDone{'+item(e['item'])+'}'
    if kind=='reasoning_summary_part.done':return 'C.SummaryPartDone{}'
    ctor,field={
        'reasoning_summary_text.delta':('ThinkingDelta','delta'), 'reasoning_text.delta':('ThinkingDelta','delta'),
        'output_text.delta':('TextDelta','delta'), 'refusal.delta':('TextDelta','delta'),
        'function_call_arguments.delta':('FunctionDelta','delta'), 'function_call_arguments.done':('FunctionDone','arguments'),
        'custom_tool_call_input.delta':('CustomDelta','delta'), 'custom_tool_call_input.done':('CustomDone','input'),
    }[kind]
    return 'C.'+ctor+'{'+string(e[field])+'}'
