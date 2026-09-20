import Base
import ./io-pair.bend as Parallel
import ./dns-pair-queries.bend as Queries
import ./dns-pair-setup.bend as Setup
import ./dns-address-lookup.bend as Lookup
import ./dns-address-answer.bend as Answer
import ./dns-exchange-source.bend as Source
import ./dns-query.bend as Request
import ./dns-name.bend as Name
import ./dns-id.bend as Id
import ./abort.bend as Abort
import ./deadline.bend as Deadline

type Reports<-Reason: Data> is Data:
  Reports{ipv4: Result<&2, &2, Lookup.Error<Reason>, Answer.Selection>, ipv6: Result<&2, &2, Lookup.Error<Reason>, Answer.Selection>}

def reports(-Reason: Data, pair: Result<&2, &2, Lookup.Error<Reason>, Answer.Selection> & Result<&2, &2, Lookup.Error<Reason>, Answer.Selection>) -> Reports<Reason>:
  match pair:
    case (ipv4, ipv6): Reports{ipv4, ipv6}

def execute(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), -Reason: Data, +environment: Environment, +signal: Abort.AbortSignal<Deadline.Cause<Reason>>, +maximum: U32, setup: Result<&2, &2, Setup.Error<Reason>, Setup.Prepared>) -> IO(Result<&2, &2, Setup.Error<Reason>, Reports<Reason>>):
  match setup:
    case Fail{error}: IO.pure(Result<&2, &2, Setup.Error<Reason>, Reports<Reason>>, Fail{error})
    case Done{Setup.Prepared{Queries.Queries{ipv4, ipv6}, +source}}:
      do IO<Result<&2, &2, Setup.Error<Reason>, Reports<Reason>>>:
        pair : Result<&2, &2, Lookup.Error<Reason>, Answer.Selection> & Result<&2, &2, Lookup.Error<Reason>, Answer.Selection> <- Parallel.both(Result<&2, &2, Lookup.Error<Reason>, Answer.Selection>, Result<&2, &2, Lookup.Error<Reason>, Answer.Selection>, Lookup.exchangeRequestWith(~Environment, ~draw, Reason, environment, source, signal, ipv4, maximum), Lookup.exchangeRequestWith(~Environment, ~draw, Reason, environment, source, signal, ipv6, maximum))
        return Done{reports(Reason, pair)}

# One candidate, one selected server order and one borrowed total deadline.
# Separate native exchanges isolate the two transactions. Each owns its retry,
# TCP fallback and alias work; both settle and close before this call returns.
# Setup failure is distinct from a started query's report; no sibling outcome
# is fabricated for a question that never started. Merge/search policy is external.
def exchangeWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), -Reason: Data, +environment: Environment, source: Source.Source, +signal: Abort.AbortSignal<Deadline.Cause<Reason>>, options: Request.Options, name: Name.Name, +maximum: U32) -> IO(Result<&2, &2, Setup.Error<Reason>, Reports<Reason>>):
  do IO<Result<&2, &2, Setup.Error<Reason>, Reports<Reason>>>:
    setup : Result<&2, &2, Setup.Error<Reason>, Setup.Prepared> <- Setup.prepareWith(~Environment, ~draw, Reason, environment, source, signal, options, name, maximum)
    execute(~Environment, ~draw, Reason, environment, signal, maximum, setup)
