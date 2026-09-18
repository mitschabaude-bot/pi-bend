import Base
import ./agent-loop.bend as Loop
import ../../ai/src/utils/validation.bend as Validation
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/callback.bend as C

# The schema library retains structured failure categories. Applications map
# them into their execution-error type at this boundary, without discarding
# unsupported-schema or normalization failures that have no public formatter.
def Input() -> Data: Loop.ToolValidationInput<V.Value, V.Value, V.Value>
def Output(-Error: Data) -> Data: Result<&2, &2, Error, V.Value>
def Validator(-Error: Data) -> Data: C.Callback<Input(), Output(Error)>

def validatePlain(input: Input()) -> Validation.ToolValidation():
  match input:
    case Loop.ToolValidationInput{tool, Loop.OriginalCall{call}}: Validation.validatePlainToolArguments(tool, call)
    case Loop.ToolValidationInput{tool, Loop.ReplacedCall{call}}: Validation.validatePlainToolArguments(tool, call)

def mapped(-Error: Data, mapError: Validation.ToolValidationError -> Error, result: Validation.ToolValidation()) -> Output(Error):
  match result:
    case Done{value}: Done{value}
    case Fail{error}: Fail{mapError(error)}

def body(-Error: Data, mapError: Validation.ToolValidationError -> Error, unused: Unit, input: Input()) -> IO(Output(Error)):
  IO.pure(Output(Error), mapped(Error, mapError, validatePlain(input)))

# Caller owns this service and disposes it after all borrowing Agents/runs.
def createPlain(~Error: Data, ~mapError: Validation.ToolValidationError -> Error) -> IO(Validator(Error)):
  C.create(~Unit, ~Input(), ~Output(Error), ~(body(Error, mapError)), Unit{})

def dispose(-Error: Data, validator: Validator(Error)) -> IO(Unit):
  C.dispose(Input(), Output(Error), validator)
