import Base
import ./types.bend as T
import ../../runtime/src/ref.bend as R
import ../../ai/src/types.bend as Ai
import ../../runtime/src/schema-value.bend as Schema

# A host owns one registry and shares it with its agent instances. Replacing a
# default never disposes providers: callers retain selected callbacks for runs
# already in flight, and their provider owner controls callback lifetime.
def Registry(-DiagnosticDetails: Data, -ToolDetails: Data, -Options: Data, -Error: Data) -> Data: R.Ref<Maybe<&2, T.StreamFn(DiagnosticDetails, ToolDetails, Options, Error)>>

type MissingDefault is Data:
  MissingDefault{}

def errorMessage(error: MissingDefault) -> String:
  "No default stream function configured. Pass streamFn explicitly or call setDefaultStreamFn()."

type Selection<-DiagnosticDetails: Data, -ToolDetails: Data, -Options: Data, -Error: Data> is Data:
  Explicit{stream: T.StreamFn(DiagnosticDetails, ToolDetails, Options, Error)}
  Fallback{registry: Registry(DiagnosticDetails, ToolDetails, Options, Error)}

def create(-DiagnosticDetails: Data, -ToolDetails: Data, -Options: Data, -Error: Data) -> IO(Registry(DiagnosticDetails, ToolDetails, Options, Error)):
  R.new(Maybe<&2, T.StreamFn(DiagnosticDetails, ToolDetails, Options, Error)>, None{})

def setDefaultStreamFn(-DiagnosticDetails: Data, -ToolDetails: Data, -Options: Data, -Error: Data, registry: Registry(DiagnosticDetails, ToolDetails, Options, Error), stream: Maybe<&2, T.StreamFn(DiagnosticDetails, ToolDetails, Options, Error)>) -> IO(Unit):
  R.write(Maybe<&2, T.StreamFn(DiagnosticDetails, ToolDetails, Options, Error)>, registry, stream)

def required(-DiagnosticDetails: Data, -ToolDetails: Data, -Options: Data, -Error: Data, stream: Maybe<&2, T.StreamFn(DiagnosticDetails, ToolDetails, Options, Error)>) -> Result<&2, &2, MissingDefault, T.StreamFn(DiagnosticDetails, ToolDetails, Options, Error)>:
  match stream:
    case None{}: Fail{MissingDefault{}}
    case Some{provider}: Done{provider}

def getDefaultStreamFn(-DiagnosticDetails: Data, -ToolDetails: Data, -Options: Data, -Error: Data, registry: Registry(DiagnosticDetails, ToolDetails, Options, Error)) -> IO(Result<&2, &2, MissingDefault, T.StreamFn(DiagnosticDetails, ToolDetails, Options, Error)>):
  do IO<Result<&2, &2, MissingDefault, T.StreamFn(DiagnosticDetails, ToolDetails, Options, Error)>>:
    stream : Maybe<&2, T.StreamFn(DiagnosticDetails, ToolDetails, Options, Error)> <- R.read(Maybe<&2, T.StreamFn(DiagnosticDetails, ToolDetails, Options, Error)>, registry)
    return required(DiagnosticDetails, ToolDetails, Options, Error, stream)

# Explicit selection does not read the registry. Resolve once at the public
# loop's entry boundary, not again for each provider request.
def resolve(-DiagnosticDetails: Data, -ToolDetails: Data, -Options: Data, -Error: Data, selection: Selection<DiagnosticDetails, ToolDetails, Options, Error>) -> IO(Result<&2, &2, MissingDefault, T.StreamFn(DiagnosticDetails, ToolDetails, Options, Error)>):
  match selection:
    case Explicit{stream}: IO.pure(Result<&2, &2, MissingDefault, T.StreamFn(DiagnosticDetails, ToolDetails, Options, Error)>, Done{stream})
    case Fallback{registry}: getDefaultStreamFn(DiagnosticDetails, ToolDetails, Options, Error, registry)

def dispose(-DiagnosticDetails: Data, -ToolDetails: Data, -Options: Data, -Error: Data, registry: Registry(DiagnosticDetails, ToolDetails, Options, Error)) -> IO(Unit):
  do IO<Unit>:
    previous : Maybe<&2, T.StreamFn(DiagnosticDetails, ToolDetails, Options, Error)> <- R.dispose(Maybe<&2, T.StreamFn(DiagnosticDetails, ToolDetails, Options, Error)>, registry)
    return Unit{}
