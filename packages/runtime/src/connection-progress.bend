import Base
import ./connection-attempt-result.bend as Attempt
import ./abort.bend as Abort

type Mode is Data:
  NonFinal{}
  Final{}

type Error<-Reason: Data> is Data:
  NoAddresses{}
  Exhausted{}
  Aborted{reason: Abort.AbortReason<Reason>}
  UnexpectedDefaultAbort{}

type Decision<-Reason: Data> is Data:
  Accept{}
  Advance{}
  Stop{error: Error<Reason>}

def mode(-Address: Data, remaining: List<&2, Address>) -> Mode:
  match remaining:
    case Nil{}: Final{}
    case _ <> _: NonFinal{}

# Only ordinary socket errors and expiry permit fallback. A retained parent
# abort wins even over a successful connector, at this observation boundary.
def decide(-Reason: Data, outcome: Result<&2, &2, Attempt.Error<Reason>, Unit>, parent: Maybe<&2, Abort.AbortReason<Reason>>) -> Decision<Reason>:
  match outcome parent:
    case _ Some{reason}: Stop{Aborted{reason}}
    case Done{_} None{}: Accept{}
    case Fail{Attempt.SocketFailure{_, _}} None{}: Advance{}
    case Fail{Attempt.TimedOut{}} None{}: Advance{}
    case Fail{Attempt.Aborted{reason}} None{}: Stop{Aborted{reason}}
    case Fail{Attempt.UnexpectedDefaultAbort{}} None{}: Stop{UnexpectedDefaultAbort{}}

# Produce a duplicable observation without copying the owned success value.
def observed(-Reason: Data, -Value: Type, result: Result<&2, &1, Attempt.Error<Reason>, Value>) -> Result<&2, &1, Attempt.Error<Reason>, Value> & Result<&2, &2, Attempt.Error<Reason>, Unit>:
  match result:
    case Done{value}: (Done{value}, Done{Unit{}})
    case Fail{+error}: (Fail{error}, Fail{error})
