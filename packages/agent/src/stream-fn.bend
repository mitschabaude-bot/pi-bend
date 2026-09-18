import Base
import ./types.bend as T
import ../../runtime/src/ref.bend as R

# A host owns one registry and shares it with its agent instances. Replacing a
# default never disposes providers: callers retain selected callbacks for runs
# already in flight, and their provider owner controls callback lifetime.
def Registry(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Value: Data, -Options: Data, -Error: Data) -> Data: R.Ref<Maybe<&2, T.StreamFn(Parameters, Arguments, DiagnosticDetails, ToolDetails, Value, Options, Error)>>

type MissingDefault is Data:
  MissingDefault{}

def errorMessage(error: MissingDefault) -> String:
  "No default stream function configured. Pass streamFn explicitly or call setDefaultStreamFn()."

type Selection<-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Value: Data, -Options: Data, -Error: Data> is Data:
  Explicit{stream: T.StreamFn(Parameters, Arguments, DiagnosticDetails, ToolDetails, Value, Options, Error)}
  Fallback{registry: Registry(Parameters, Arguments, DiagnosticDetails, ToolDetails, Value, Options, Error)}

def create(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Value: Data, -Options: Data, -Error: Data) -> IO(Registry(Parameters, Arguments, DiagnosticDetails, ToolDetails, Value, Options, Error)):
  R.new(Maybe<&2, T.StreamFn(Parameters, Arguments, DiagnosticDetails, ToolDetails, Value, Options, Error)>, None{})

def setDefaultStreamFn(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Value: Data, -Options: Data, -Error: Data, registry: Registry(Parameters, Arguments, DiagnosticDetails, ToolDetails, Value, Options, Error), stream: Maybe<&2, T.StreamFn(Parameters, Arguments, DiagnosticDetails, ToolDetails, Value, Options, Error)>) -> IO(Unit):
  R.write(Maybe<&2, T.StreamFn(Parameters, Arguments, DiagnosticDetails, ToolDetails, Value, Options, Error)>, registry, stream)

def required(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Value: Data, -Options: Data, -Error: Data, stream: Maybe<&2, T.StreamFn(Parameters, Arguments, DiagnosticDetails, ToolDetails, Value, Options, Error)>) -> Result<&2, &2, MissingDefault, T.StreamFn(Parameters, Arguments, DiagnosticDetails, ToolDetails, Value, Options, Error)>:
  match stream:
    case None{}: Fail{MissingDefault{}}
    case Some{provider}: Done{provider}

def getDefaultStreamFn(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Value: Data, -Options: Data, -Error: Data, registry: Registry(Parameters, Arguments, DiagnosticDetails, ToolDetails, Value, Options, Error)) -> IO(Result<&2, &2, MissingDefault, T.StreamFn(Parameters, Arguments, DiagnosticDetails, ToolDetails, Value, Options, Error)>):
  do IO<Result<&2, &2, MissingDefault, T.StreamFn(Parameters, Arguments, DiagnosticDetails, ToolDetails, Value, Options, Error)>>:
    stream : Maybe<&2, T.StreamFn(Parameters, Arguments, DiagnosticDetails, ToolDetails, Value, Options, Error)> <- R.read(Maybe<&2, T.StreamFn(Parameters, Arguments, DiagnosticDetails, ToolDetails, Value, Options, Error)>, registry)
    return required(Parameters, Arguments, DiagnosticDetails, ToolDetails, Value, Options, Error, stream)

# Explicit selection does not read the registry. Resolve once at the public
# loop's entry boundary, not again for each provider request.
def resolve(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Value: Data, -Options: Data, -Error: Data, selection: Selection<Parameters, Arguments, DiagnosticDetails, ToolDetails, Value, Options, Error>) -> IO(Result<&2, &2, MissingDefault, T.StreamFn(Parameters, Arguments, DiagnosticDetails, ToolDetails, Value, Options, Error)>):
  match selection:
    case Explicit{stream}: IO.pure(Result<&2, &2, MissingDefault, T.StreamFn(Parameters, Arguments, DiagnosticDetails, ToolDetails, Value, Options, Error)>, Done{stream})
    case Fallback{registry}: getDefaultStreamFn(Parameters, Arguments, DiagnosticDetails, ToolDetails, Value, Options, Error, registry)

def dispose(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Value: Data, -Options: Data, -Error: Data, registry: Registry(Parameters, Arguments, DiagnosticDetails, ToolDetails, Value, Options, Error)) -> IO(Unit):
  do IO<Unit>:
    previous : Maybe<&2, T.StreamFn(Parameters, Arguments, DiagnosticDetails, ToolDetails, Value, Options, Error)> <- R.dispose(Maybe<&2, T.StreamFn(Parameters, Arguments, DiagnosticDetails, ToolDetails, Value, Options, Error)>, registry)
    return Unit{}
