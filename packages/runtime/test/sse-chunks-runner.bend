import Base
import ../src/sse.bend as Chunks
import ./utf8-runner.bend as H

def showChunks(chunks: List<&2, List<&2, U32>>) -> List<&2, String>:
  match chunks:
    case Nil{}: Nil{}
    case head <> tail: ("[" ++ String.join(H.showNumbers(head), ",") ++ "]") <> showChunks(tail)

def showResult(result: Chunks.ChunksDecoded) -> String:
  match result:
    case Chunks.ChunksDecoded{_, chunks}: String.join(showChunks(chunks), ";")

def instruction(decoder: Chunks.ChunkDecoder, operation: String) -> Chunks.ChunksDecoded:
  match operation:
    case SCon{Chr{98}, bytes}: Chunks.decodeChunks(decoder, H.parseNumbers(bytes))
    case SCon{Chr{116}, scalars}: Chunks.decodeTextChunks(decoder, H.fromScalars(H.parseNumbers(scalars)))
    case _: Chunks.decodeOptionalChunks(decoder, None{})

def execute(operations: List<&2, String>, result: Chunks.ChunksDecoded) -> List<&2, String>:
  match operations result:
    case Nil{} Chunks.ChunksDecoded{decoder, chunks}: String.join(showChunks(chunks), ";") <> showResult(Chunks.finish(decoder)) <> Nil{}
    case operation <> rest Chunks.ChunksDecoded{decoder, chunks}: String.join(showChunks(chunks), ";") <> execute(rest, instruction(decoder, operation))

def start(operations: List<&2, String>) -> String:
  match operations:
    case Nil{}: showResult(Chunks.finish(Chunks.createChunks()))
    case operation <> rest: String.join(execute(rest, instruction(Chunks.createChunks(), operation)), "|")

def run(argument: String) -> IO(Unit):
  match argument:
    case SCon{Chr{115}, text}: IO.print(start(String.split(text, '|')))
    case _: IO.pure(Unit, Unit{})

def all(arguments: List<String>) -> IO(Unit):
  match arguments:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> tail:
      do IO<Unit>:
        run(head)
        all(tail)

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    all(arguments)
