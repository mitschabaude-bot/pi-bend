import Base
import ../../../runtime/src/f64.bend as Number

# Record definitions from utils/diagnostics.ts. Opaque diagnostic details stay
# caller-typed; formatting/extraction of thrown values is a separate pending API.
type DiagnosticCode is Data:
  StringCode{value: String}
  NumberCode{value: F64}

type DiagnosticErrorInfo is Data:
  DiagnosticErrorInfo{name: Maybe<&2, String>, message: String, stack: Maybe<&2, String>, code: Maybe<&2, DiagnosticCode>}

# diagnosticType maps to upstream `type`, which is a Bend keyword.
type AssistantMessageDiagnostic<-Details: Data> is Data:
  AssistantMessageDiagnostic{diagnosticType: String, timestamp: F64, error: Maybe<&2, DiagnosticErrorInfo>, details: Maybe<&2, Details>}
