import Base
import ./http-header.bend as H
import ./http-head.bend as Head
import ./http-status.bend as Status
import ./http-framing-fields.bend as Fields
import ./http-body.bend as Body

type ResponsePlan is Data:
  Informational{}
  Final{framing: Body.Framing, exposeBody: Bool}

type PolicyError is Data:
  UnsupportedVersion{major: U32, minor: U32}
  InvalidStatus{status: U32}
  UnexpectedContinue{}
  UnsupportedUpgrade{}
  FramingError{error: Fields.FieldError}

# Accepted HTTP/1 parser version labels; accepting "2.0" here does not provide
# the HTTP/2 binary protocol. Request method normalization occurs upstream.
def supportedVersion(major: U32, minor: U32) -> Bool:
  match major minor:
    case 0 9: True{}
    case 1 0: True{}
    case 1 1: True{}
    case 2 0: True{}
    case _ _: False{}

def nullBody(status: U32) -> Bool:
  match status:
    case 204: True{}
    case 205: True{}
    case 304: True{}
    case _: False{}

def wireNoBody(status: U32) -> Bool:
  match status:
    case 204: True{}
    case 304: True{}
    case _: False{}

def finalPlan(headMethod: Bool, +status: U32, fields: Fields.Fields) -> ResponsePlan:
  match headMethod:
    case True{}: Final{Body.NoBody{}, False{}}
    case False{}:
      Final{Bool.pick(Body.Framing, wireNoBody(status), Body.NoBody{}, Fields.bodyFraming(fields)), Bool.not(nullBody(status))}

def checkedStatus(valid: Bool, +status: U32, method: String, fields: Fields.Fields) -> Result<&2, &2, PolicyError, ResponsePlan>:
  match valid status:
    case False{} _: Fail{InvalidStatus{status}}
    case True{} 100: Fail{UnexpectedContinue{}}
    case True{} 101: Fail{UnsupportedUpgrade{}}
    case True{} other:
      Done{Bool.pick(ResponsePlan, U32.is_lt(other, 200), Informational{}, finalPlan(String.eq(method, "HEAD"), other, fields))}

def analyzed(result: Result<&2, &2, Fields.FieldError, Fields.Fields>, +status: U32, method: String) -> Result<&2, &2, PolicyError, ResponsePlan>:
  match result:
    case Fail{error}: Fail{FramingError{error}}
    case Done{fields}: checkedStatus(U32.is_ge(status, 100) && U32.is_le(status, 999), status, method, fields)

def checkedVersion(valid: Bool, major: U32, minor: U32, status: U32, fields: List<&2, H.Header>, method: String) -> Result<&2, &2, PolicyError, ResponsePlan>:
  match valid:
    case False{}: Fail{UnsupportedVersion{major, minor}}
    case True{}: analyzed(Fields.analyze(fields), status, method)

# Policy for ordinary Fetch requests, after request-method validation. Upgrade
# requests and CONNECT tunnels have separate transport contracts.
def plan(method: String, head: Head.ResponseHead) -> Result<&2, &2, PolicyError, ResponsePlan>:
  match head:
    case Head.ResponseHead{Status.StatusLine{+major, +minor, status, _}, fields}:
      checkedVersion(supportedVersion(major, minor), major, minor, status, fields, method)
