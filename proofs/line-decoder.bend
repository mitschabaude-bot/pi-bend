import Base
import ./list-reverse.bend as Reverse
import ../laws/line-decoder.bend as Laws
import ../packages/runtime/src/sse.bend as Line

law prepend_reverse:
  for +lines: List<&2, String>
  for +acc: List<&2, String>
  {Line.prepend(lines, acc) == List.reverse.go(&2, String, lines, acc) : List<&2, String>}

def prepend_reverse(lines, acc):
  match lines:
    case Nil{}: {==}
    case head <> tail: prepend_reverse(tail, head <> acc)

law prepend_reversed:
  for +lines: List<&2, String>
  {Line.prepend(List.reverse(&2, String, lines), Nil{}) == lines : List<&2, String>}

def prepend_reversed(lines):
  Equal.trans(List<&2, String>, Line.prepend(List.reverse(&2, String, lines), Nil{}), List.reverse(&2, String, List.reverse(&2, String, lines)), lines, prepend_reverse(List.reverse(&2, String, lines), Nil{}), Reverse.involution(String, lines))

law collect_normalize:
  for +bytes: List<&2, U32>
  for +decoder: Line.LineDecoder
  for +lines: List<&2, String>
  for +acc: List<&2, String>
  {Line.collect(bytes, Line.Decoded{decoder, lines}, acc) == Line.collect(bytes, Line.Decoded{decoder, Nil{}}, Line.prepend(lines, acc)) : Line.Decoded}

def collect_normalize(bytes, decoder, lines, acc):
  match bytes:
    case Nil{}: {==}
    case _ <> _: {==}

law resume_reversed:
  for +bytes: List<&2, U32>
  for +decoder: Line.LineDecoder
  for +acc: List<&2, String>
  {Line.collect(bytes, Line.Decoded{decoder, List.reverse(&2, String, acc)}, Nil{}) == Line.collect(bytes, Line.Decoded{decoder, Nil{}}, acc) : Line.Decoded}

def resume_reversed(bytes, decoder, acc):
  %prepend_reversed(acc) : {Line.collect(bytes, Line.Decoded{decoder, List.reverse(&2, String, acc)}, Nil{}) == Line.collect(bytes, Line.Decoded{decoder, Nil{}}, _) : Line.Decoded}
  collect_normalize(bytes, decoder, List.reverse(&2, String, acc), Nil{})

law resume_finalized:
  for +bytes: List<&2, U32>
  for +result: Line.Decoded
  for +acc: List<&2, String>
  {Line.collect(bytes, Line.collect(Nil{}, result, acc), Nil{}) == Line.collect(bytes, result, acc) : Line.Decoded}

def resume_finalized(bytes, result, acc):
  match result:
    case Line.Decoded{decoder, lines}:
      Equal.trans(Line.Decoded,
        Line.collect(bytes, Line.Decoded{decoder, List.reverse(&2, String, Line.prepend(lines, acc))}, Nil{}),
        Line.collect(bytes, Line.Decoded{decoder, Nil{}}, Line.prepend(lines, acc)),
        Line.collect(bytes, Line.Decoded{decoder, lines}, acc),
        resume_reversed(bytes, decoder, Line.prepend(lines, acc)),
        Equal.sym(Line.Decoded, Line.collect(bytes, Line.Decoded{decoder, lines}, acc), Line.collect(bytes, Line.Decoded{decoder, Nil{}}, Line.prepend(lines, acc)), collect_normalize(bytes, decoder, lines, acc)))

law collect_composition:
  for +first: List<&2, U32>
  for +second: List<&2, U32>
  for +result: Line.Decoded
  for +acc: List<&2, String>
  {Line.collect(second, Line.collect(first, result, acc), Nil{}) == Line.collect(List.append(&2, U32, first, second), result, acc) : Line.Decoded}

def collect_composition(first, second, result, acc):
  match first:
    case Nil{}: resume_finalized(second, result, acc)
    case head <> tail:
      match result:
        case Line.Decoded{decoder, lines}: collect_composition(tail, second, Line.consume(decoder, head), Line.prepend(lines, acc))

def Laws.empty_chunk(decoder): {==}

def Laws.chunk_composition(decoder, first, second):
  collect_composition(first, second, Line.Decoded{decoder, Nil{}}, Nil{})

law prepend_append:
  for +lines: List<&2, String>
  for +acc: List<&2, String>
  for +prior: List<&2, String>
  {Line.prepend(lines, List.append(&2, String, acc, prior)) == List.append(&2, String, Line.prepend(lines, acc), prior) : List<&2, String>}

def prepend_append(lines, acc, prior):
  match lines:
    case Nil{}: {==}
    case head <> tail: prepend_append(tail, head <> acc, prior)

law collect_prefixed:
  for +bytes: List<&2, U32>
  for +result: Line.Decoded
  for +acc: List<&2, String>
  for +prior: List<&2, String>
  {Line.collect(bytes, result, List.append(&2, String, acc, prior)) == Laws.withPrefix(List.reverse(&2, String, prior), Line.collect(bytes, result, acc)) : Line.Decoded}

def collect_prefixed(bytes, result, acc, prior):
  match bytes result:
    case Nil{} Line.Decoded{decoder, lines}:
      %Equal.sym(List<&2, String>, Line.prepend(lines, List.append(&2, String, acc, prior)), List.append(&2, String, Line.prepend(lines, acc), prior), prepend_append(lines, acc, prior)) : {Line.Decoded{decoder, List.reverse(&2, String, _)} == Line.Decoded{decoder, List.append(&2, String, List.reverse(&2, String, prior), List.reverse(&2, String, Line.prepend(lines, acc)))} : Line.Decoded}
      Equal.cong(List<&2, String>, Line.Decoded, emitted => Line.Decoded{decoder, emitted}, List.reverse(&2, String, List.append(&2, String, Line.prepend(lines, acc), prior)), List.append(&2, String, List.reverse(&2, String, prior), List.reverse(&2, String, Line.prepend(lines, acc))), Reverse.reverse_append(String, Line.prepend(lines, acc), prior))
    case head <> tail Line.Decoded{decoder, lines}:
      %Equal.sym(List<&2, String>, Line.prepend(lines, List.append(&2, String, acc, prior)), List.append(&2, String, Line.prepend(lines, acc), prior), prepend_append(lines, acc, prior)) : {Line.collect(tail, Line.consume(decoder, head), _) == Laws.withPrefix(List.reverse(&2, String, prior), Line.collect(tail, Line.consume(decoder, head), Line.prepend(lines, acc))) : Line.Decoded}
      collect_prefixed(tail, Line.consume(decoder, head), Line.prepend(lines, acc), prior)

def Laws.continuation_output(decoder, lines, bytes):
  %Equal.sym(Line.Decoded, Line.collect(bytes, Line.Decoded{decoder, lines}, Nil{}), Line.collect(bytes, Line.Decoded{decoder, Nil{}}, Line.prepend(lines, Nil{})), collect_normalize(bytes, decoder, lines, Nil{})) : {_ == Laws.withPrefix(lines, Line.decode(decoder, bytes)) : Line.Decoded}
  %Equal.sym(List<&2, String>, Line.prepend(lines, Nil{}), List.reverse(&2, String, lines), prepend_reverse(lines, Nil{})) : {Line.collect(bytes, Line.Decoded{decoder, Nil{}}, _) == Laws.withPrefix(lines, Line.decode(decoder, bytes)) : Line.Decoded}
  %Reverse.involution(String, lines) : {Line.collect(bytes, Line.Decoded{decoder, Nil{}}, List.reverse(&2, String, lines)) == Laws.withPrefix(_, Line.decode(decoder, bytes)) : Line.Decoded}
  collect_prefixed(bytes, Line.Decoded{decoder, Nil{}}, Nil{}, List.reverse(&2, String, lines))

def Laws.flush_result(pending):
  match pending:
    case Line.Reading{Nil{}}: {==}
    case Line.Reading{_ <> _}: {==}
    case Line.AfterCarriageReturn{_, Nil{}}: {==}
    case Line.AfterCarriageReturn{_, _ <> _}: {==}

def Laws.repeated_flush(decoder):
  match decoder:
    case Line.LineDecoder{pending}:
      %Equal.sym(Line.Decoded, Line.flush(Line.LineDecoder{pending}), Line.Decoded{Line.create(), Laws.pendingLines(pending)}, Laws.flush_result(pending)) : {Line.flush(Laws.decoderOf(_)) == Line.Decoded{Line.create(), Nil{}} : Line.Decoded}
      {==}
