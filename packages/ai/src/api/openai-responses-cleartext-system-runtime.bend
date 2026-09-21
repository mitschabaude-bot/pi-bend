import Base
import ./openai-responses-cleartext-default-runtime.bend as Default
import ./openai-responses-cleartext-runtime.bend as Runtime
import ../../../runtime/src/resolver-system-config.bend as System
import ../../../runtime/src/hosts-load.bend as Hosts
import ../../../runtime/src/hosts.bend as Database
import ../../../runtime/src/hosts-file.bend as File
import ../../../runtime/src/utf8-strict.bend as UTF8
import ../../../runtime/src/http-resolved-exchange.bend as HTTP

def SourceError() -> Data: Hosts.Error<UTF8.Error>
def HostResult() -> Data: Result<&2, &2, SourceError(), List<&2, Database.Entry<File.Address>>>

type Files is Data:
  Files{resolver: String, hosts: String, chunkSize: U32, byteLimit: Nat, dnsMilliseconds: U32, dnsMaximum: U32}

# These paths and bounds are explicit and replaceable by embedders. Resolver
# environment/hostname/interface policy remains in the existing Linux loader.
def linuxFiles() -> Files:
  Files{"/etc/resolv.conf", "/etc/hosts", 4096, 1048576n, 5000, 65535}

type Snapshot is Data:
  Snapshot{resolver: System.Prepared, hosts: HostResult()}

type Error is Data:
  ConfigurationFailure{cause: System.Error<UTF8.Error>}
  InitializationFailure{cause: Runtime.Error}

type Owner<-Reason: Data> is Type:
  Owner{snapshot: Snapshot, runtime: Default.Owner<Reason, SourceError()>}

# A hosts-file failure remains a source error for named resolution. It does
# not prevent requests to numeric addresses, which never consult that source.
def loaded(files: Files, result: Result<&2, &2, System.Error<UTF8.Error>, System.Prepared>) -> IO(Result<&2, &2, Error, Snapshot>):
  match files result:
    case _ Fail{cause}: IO.pure(Result<&2, &2, Error, Snapshot>, Fail{ConfigurationFailure{cause}})
    case Files{_, path, chunkSize, byteLimit, _, _} Done{resolver}:
      do IO<Result<&2, &2, Error, Snapshot>>:
        hosts : HostResult() <- Hosts.read(path, chunkSize, byteLimit)
        return Done{Snapshot{resolver, hosts}}

def load(+files: Files) -> IO(Result<&2, &2, Error, Snapshot>):
  match files:
    case Files{path, _, chunkSize, byteLimit, milliseconds, maximum}:
      do IO<Result<&2, &2, Error, Snapshot>>:
        resolver : Result<&2, &2, System.Error<UTF8.Error>, System.Prepared> <- System.loadWith(~UTF8.Error, ~UTF8.decode, path, chunkSize, byteLimit, milliseconds, maximum)
        loaded(files, resolver)

def initialized(-Reason: Data, snapshot: Snapshot, result: Result<&2, &1, Runtime.Error, Default.Owner<Reason, SourceError()>>) -> Result<&2, &1, Error, Owner<Reason>>:
  match result:
    case Fail{cause}: Fail{InitializationFailure{cause}}
    case Done{runtime}: Done{Owner{snapshot, runtime}}

def configured(~Reason: Data, options: HTTP.Options, result: Result<&2, &2, Error, Snapshot>) -> IO(Result<&2, &1, Error, Owner<Reason>>):
  match result:
    case Fail{cause}: IO.pure(Result<&2, &1, Error, Owner<Reason>>, Fail{cause})
    case Done{Snapshot{System.Prepared{source, search, +config}, +hosts}}:
      do IO<Result<&2, &1, Error, Owner<Reason>>>:
        runtime : Result<&2, &1, Runtime.Error, Default.Owner<Reason, SourceError()>> <- Default.create(~Reason, ~(SourceError()), config, hosts, options)
        return initialized(Reason, Snapshot{System.Prepared{source, search, config}, hosts}, runtime)

def create(~Reason: Data, files: Files, options: HTTP.Options) -> IO(Result<&2, &1, Error, Owner<Reason>>):
  do IO<Result<&2, &1, Error, Owner<Reason>>>:
    snapshot : Result<&2, &2, Error, Snapshot> <- load(files)
    configured(~Reason, options, snapshot)

def borrowed(-Reason: Data, snapshot: Snapshot, pair: Default.Owner<Reason, SourceError()> & Runtime.Borrowed<Reason, SourceError()>) -> Owner<Reason> & Runtime.Borrowed<Reason, SourceError()>:
  match pair:
    case Tuple{runtime, dependencies}: (Owner{snapshot, runtime}, dependencies)

def borrow(-Reason: Data, owner: Owner<Reason>) -> Owner<Reason> & Runtime.Borrowed<Reason, SourceError()>:
  match owner:
    case Owner{snapshot, runtime}: borrowed(Reason, snapshot, Default.borrow(Reason, SourceError(), runtime))

def dispose(-Reason: Data, owner: Owner<Reason>) -> IO(Unit):
  match owner:
    case Owner{_, runtime}: Default.dispose(Reason, SourceError(), runtime)
