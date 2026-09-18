import Base
import ./types.bend as T
import ../../runtime/src/ref.bend as R

# A host owns one registry and shares it with its agent instances. Replacing a
# default never disposes providers: callers retain selected callbacks for runs
# already in flight, and their provider owner controls callback lifetime.
def Registry(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Value: Data, -Options: Data) -> Data: R.Ref<Maybe<&2, T.StreamFn(Parameters, Arguments, DiagnosticDetails, ToolDetails, Value, Options)>>

type MissingDefault is Data:
  MissingDefault{}

def errorMessage(error: MissingDefault) -> String:
  "No default stream function configured. Pass streamFn explicitly or call setDefaultStreamFn()."

type Selection<-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Value: Data, -Options: Data> is Data:
  Explicit{stream: T.StreamFn(Parameters, Arguments, DiagnosticDetails, ToolDetails, Value, Options)}
  Fallback{registry: Registry(Parameters, Arguments, DiagnosticDetails, ToolDetails, Value, Options)}

def create(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Value: Data, -Options: Data) -> IO(Registry(Parameters, Arguments, DiagnosticDetails, ToolDetails, Value, Options)):
  R.new(Maybe<&2, T.StreamFn(Parameters, Arguments, DiagnosticDetails, ToolDetails, Value, Options)>, None{})

def setDefaultStreamFn(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Value: Data, -Options: Data, registry: Registry(Parameters, Arguments, DiagnosticDetails, ToolDetails, Value, Options), stream: Maybe<&2, T.StreamFn(Parameters, Arguments, DiagnosticDetails, ToolDetails, Value, Options)>) -> IO(Unit):
  R.write(Maybe<&2, T.StreamFn(Parameters, Arguments, DiagnosticDetails, ToolDetails, Value, Options)>, registry, stream)

def required(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Value: Data, -Options: Data, stream: Maybe<&2, T.StreamFn(Parameters, Arguments, DiagnosticDetails, ToolDetails, Value, Options)>) -> Result<&2, &2, MissingDefault, T.StreamFn(Parameters, Arguments, DiagnosticDetails, ToolDetails, Value, Options)>:
  match stream:
    case None{}: Fail{MissingDefault{}}
    case Some{provider}: Done{provider}

def getDefaultStreamFn(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Value: Data, -Options: Data, registry: Registry(Parameters, Arguments, DiagnosticDetails, ToolDetails, Value, Options)) -> IO(Result<&2, &2, MissingDefault, T.StreamFn(Parameters, Arguments, DiagnosticDetails, ToolDetails, Value, Options)>):
  do IO<Result<&2, &2, MissingDefault, T.StreamFn(Parameters, Arguments, DiagnosticDetails, ToolDetails, Value, Options)>>:
    stream : Maybe<&2, T.StreamFn(Parameters, Arguments, DiagnosticDetails, ToolDetails, Value, Options)> <- R.read(Maybe<&2, T.StreamFn(Parameters, Arguments, DiagnosticDetails, ToolDetails, Value, Options)>, registry)
    return required(Parameters, Arguments, DiagnosticDetails, ToolDetails, Value, Options, stream)

# Explicit selection does not read the registry. Resolve once at the public
# loop's entry boundary, not again for each provider request.
def resolve(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Value: Data, -Options: Data, selection: Selection<Parameters, Arguments, DiagnosticDetails, ToolDetails, Value, Options>) -> IO(Result<&2, &2, MissingDefault, T.StreamFn(Parameters, Arguments, DiagnosticDetails, ToolDetails, Value, Options)>):
  match selection:
    case Explicit{stream}: IO.pure(Result<&2, &2, MissingDefault, T.StreamFn(Parameters, Arguments, DiagnosticDetails, ToolDetails, Value, Options)>, Done{stream})
    case Fallback{registry}: getDefaultStreamFn(Parameters, Arguments, DiagnosticDetails, ToolDetails, Value, Options, registry)

def dispose(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Value: Data, -Options: Data, registry: Registry(Parameters, Arguments, DiagnosticDetails, ToolDetails, Value, Options)) -> IO(Unit):
  do IO<Unit>:
    previous : Maybe<&2, T.StreamFn(Parameters, Arguments, DiagnosticDetails, ToolDetails, Value, Options)> <- R.dispose(Maybe<&2, T.StreamFn(Parameters, Arguments, DiagnosticDetails, ToolDetails, Value, Options)>, registry)
    return Unit{}
