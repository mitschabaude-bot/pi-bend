import Base
import ./openai-responses-cleartext-runtime.bend as Runtime
import ../utils/provider-http-date.bend as Date
import ../../../runtime/src/resolver-configuration.bend as Settings
import ../../../runtime/src/socket-endpoint.bend as Endpoint
import ../../../runtime/src/http-resolved-exchange.bend as HTTP
import ../../../runtime/src/hosts.bend as Hosts
import ../../../runtime/src/hosts-file.bend as File
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/f64.bend as F

# The default date callback is owned here. The lower-level runtime borrows it,
# so its retry users must retire before the callback on every success path.
type Owner<-Reason: Data, -Source: Data> is Type:
  Owner{date: C.Callback<String, F.F64>, runtime: Runtime.Owner<Reason, Source>}

def initialized(-Reason: Data, -Source: Data, date: C.Callback<String, F.F64>, result: Result<&2, &1, Runtime.Error, Runtime.Owner<Reason, Source>>) -> IO(Result<&2, &1, Runtime.Error, Owner<Reason, Source>>):
  match result:
    case Fail{cause}:
      do IO<Result<&2, &1, Runtime.Error, Owner<Reason, Source>>>:
        C.dispose(String, F.F64, date)
        return Fail{cause}
    case Done{runtime}: IO.pure(Result<&2, &1, Runtime.Error, Owner<Reason, Source>>, Done{Owner{date, runtime}})

def create(~Reason: Data, ~Source: Data, config: Settings.Config<Endpoint.Endpoint>, hosts: Result<&2, &2, Source, List<&2, Hosts.Entry<File.Address>>>, options: HTTP.Options) -> IO(Result<&2, &1, Runtime.Error, Owner<Reason, Source>>):
  do IO<Result<&2, &1, Runtime.Error, Owner<Reason, Source>>>:
    +date : C.Callback<String, F.F64> <- Date.create()
    runtime : Result<&2, &1, Runtime.Error, Runtime.Owner<Reason, Source>> <- Runtime.create(~Reason, ~Source, config, hosts, options, date)
    initialized(Reason, Source, date, runtime)

def borrowed(-Reason: Data, -Source: Data, date: C.Callback<String, F.F64>, pair: Runtime.Owner<Reason, Source> & Runtime.Borrowed<Reason, Source>) -> Owner<Reason, Source> & Runtime.Borrowed<Reason, Source>:
  match pair:
    case Tuple{runtime, dependencies}: (Owner{date, runtime}, dependencies)

def borrow(-Reason: Data, -Source: Data, owner: Owner<Reason, Source>) -> Owner<Reason, Source> & Runtime.Borrowed<Reason, Source>:
  match owner:
    case Owner{date, runtime}: borrowed(Reason, Source, date, Runtime.borrow(Reason, Source, runtime))

def dispose(-Reason: Data, -Source: Data, owner: Owner<Reason, Source>) -> IO(Unit):
  match owner:
    case Owner{date, runtime}:
      do IO<Unit>:
        Runtime.dispose(Reason, Source, runtime)
        C.dispose(String, F.F64, date)
