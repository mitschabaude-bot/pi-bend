import Base
import ../packages/coding-agent/src/cli/file-processor.bend as Files
import ../packages/coding-agent/src/utils/paths.bend as Paths
import ../packages/ai/src/types.bend as Ai
import ../packages/runtime/src/json.bend as Json
import ../packages/runtime/src/url.bend as URL
import ../packages/runtime/src/idna.bend as IDNA
import ../packages/runtime/src/unicode-17-idna-mapping.bend as Mapping
import ../packages/runtime/src/unicode-17-normalization.bend as Normalization
import ../packages/runtime/src/unicode-17-idna-properties.bend as Properties

def environment(cwd: String, home: String) -> Paths.Environment:
  Paths.Environment{cwd,home,URL.Context{IDNA.Context{Mapping.table(),Normalization.tables(),Properties.table()},IDNA.Options{IDNA.LabelOptions{False{},False{},True{},IDNA.Nontransitional{}},True{},False{}}}}


def images(values: List<&2,Ai.ImageContent>) -> List<&2,String>:
  match values:
    case Nil{}: Nil{}
    case Ai.ImageContent{data,mime} <> rest:
      ("{\"type\":\"image\",\"data\":" ++ Json.quote(data) ++ ",\"mimeType\":" ++ Json.quote(mime) ++ "}") <> images(rest)

def error(kind: String,path: String) -> String:
  "{\"error\":" ++ Json.quote(kind) ++ ",\"path\":" ++ Json.quote(path) ++ "}"

def report(value: Files.ResultOf(Files.ProcessedFiles)) -> String:
  match value:
    case Fail{Files.InvalidPath{path,_}}: error("path",path)
    case Fail{Files.NotFound{path,_}}: error("missing",path)
    case Fail{Files.Stat{path,_}}: error("stat",path)
    case Fail{Files.Read{path,_}}: error("read",path)
    case Fail{Files.InvalidEncoding{path,_}}: error("encoding",path)
    case Done{Files.ProcessedFiles{text,values}}:
      "{\"text\":" ++ Json.quote(text) ++ ",\"images\":[" ++ String.join(images(values),",") ++ "]}"

def arguments(values: List<String>,result: List<&2,String>) -> List<&2,String>:
  match values:
    case Nil{}: List.reverse(&2,String,result)
    case value <> rest: arguments(rest,value <> result)

def options(mode: String) -> Files.ProcessFileOptions:
  match mode:
    case "false": Files.ProcessFileOptions{Some{False{}}}
    case "true": Files.ProcessFileOptions{Some{True{}}}
    case _: Files.defaults()

def run(args: List<String>) -> IO(Unit):
  match args:
    case cwd <> home <> mode <> rest:
      do IO<Unit>:
        result : Files.ResultOf(Files.ProcessedFiles) <- Files.processFileArguments(environment(cwd,home),arguments(rest,Nil{}),options(mode))
        IO.print(report(result))
    case _: IO.die(Unit,1,"expected cwd, home, resize mode, filenames")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
