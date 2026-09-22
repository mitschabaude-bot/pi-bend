import Base
import ./tls13-client.bend as TLS
import ./tls13-record.bend as Record
import ./socket.bend as Socket
import ./serial-resource.bend as Resource
import ./deferred.bend as Deferred
import ./ref.bend as Ref

# TLS state transitions reserve wire order under a short lock. A separate
# writer performs network IO: a blocked upload must not prevent the reader
# from authenticating an early response or processing a peer key update.
type Error<-Reason: Data> is Data:
  Protocol{cause: TLS.Error}
  Network{cause: Socket.SocketErrorOfSocket<Reason>}
  WriteQueueFull{maximum: U32}
  Closed{}
  ShutdownFailure{cause: Socket.InterruptError}
  InvalidOptions{}

type Job<-Reason: Data> is Data:
  Job{records: List<&2, List<&2, U32>>, size: Nat, completion: Maybe<&2, Deferred.Deferred<Result<&2, &2, Error<Reason>, Unit>>>, next: Chan(Job<Reason>)}

type State<-Reason: Data> is Type:
  State{client: Result<&2, &1, Error<Reason>, TLS.Client>, tail: Chan(Job<Reason>), queued: Nat, maximum: U32}

type Options is Data:
  Options{messageLimit: U32, pendingWriteBytes: U32, readSize: U32}

def defaults() -> Options:
  Options{1048576, 1048576, 16384}

type Connection<-Reason: Data> is Type:
  Connection{socket: Socket.Owner<Reason>, owner: Resource.Owner<State<Reason>>, shared: Resource.Handle<State<Reason>>, interrupt: Socket.Handle, task: Chan(Unit), pending: List<&2, U32>, readSize: U32}

# Borrowed handles remain valid until their connection is disposed. Callers
# finish/join operations before disposal, as for the underlying socket owner.
type Writer<-Reason: Data> is Data:
  Writer{shared: Resource.Handle<State<Reason>>, interrupt: Socket.Handle}

def byteCount(records: List<&2, List<&2, U32>>, count: Nat) -> Nat:
  match records:
    case Nil{}: count
    case head <> rest: byteCount(rest, (count + Record.length(head, 0n) : Nat))

def settled(-Reason: Data, completion: Maybe<&2, Deferred.Deferred<Result<&2, &2, Error<Reason>, Unit>>>, result: Result<&2, &2, Error<Reason>, Unit>) -> IO(Unit):
  match completion:
    case None{}: IO.pure(Unit, Unit{})
    case Some{promise}:
      do IO<Unit>:
        won : Bool <- Deferred.resolve(Result<&2, &2, Error<Reason>, Unit>, promise, result)
        return Unit{}

def failed(-Reason: Data, client: Result<&2, &1, Error<Reason>, TLS.Client>, cause: Error<Reason>) -> Result<&2, &1, Error<Reason>, TLS.Client>:
  match client:
    case Fail{first}: Fail{first}
    case Done{_}: Fail{cause}

def status(-Reason: Data, state: State<Reason>) -> State<Reason> & Result<&2, &2, Error<Reason>, Unit>:
  match state:
    case State{Fail{+cause}, tail, queued, maximum}: (State{Fail{cause}, tail, queued, maximum}, Fail{cause})
    case State{Done{client}, tail, queued, maximum}: (State{Done{client}, tail, queued, maximum}, Done{Unit{}})

def acknowledge(-Reason: Data, state: State<Reason>, size: Nat, result: Result<&2, &2, Error<Reason>, Unit>) -> State<Reason> & Result<&2, &2, Error<Reason>, Unit>:
  match state result:
    case State{client, tail, queued, maximum} Fail{cause}: status(Reason, State{failed(Reason, client, cause), tail, Nat.sub(queued, size), maximum})
    case State{client, tail, queued, maximum} Done{_}: status(Reason, State{client, tail, Nat.sub(queued, size), maximum})

def enqueueRejected(-Reason: Data, completion: Maybe<&2, Deferred.Deferred<Result<&2, &2, Error<Reason>, Unit>>>, pair: State<Reason> & Result<&2, &2, Error<Reason>, Unit>) -> IO(State<Reason> & Result<&2, &2, Error<Reason>, Unit>):
  match pair:
    case (state, +result):
      do IO<State<Reason> & Result<&2, &2, Error<Reason>, Unit>>:
        settled(Reason, completion, result)
        return (state, result)

def enqueueAllowed(-Reason: Data, allowed: Bool, state: State<Reason>, records: List<&2, List<&2, U32>>, +size: Nat, completion: Maybe<&2, Deferred.Deferred<Result<&2, &2, Error<Reason>, Unit>>>) -> IO(State<Reason> & Result<&2, &2, Error<Reason>, Unit>):
  match allowed state:
    case False{} State{client, tail, queued, +maximum}:
      enqueueRejected(Reason, completion, status(Reason, State{failed(Reason, client, WriteQueueFull{maximum}), tail, queued, maximum}))
    case True{} State{client, tail, queued, maximum}:
      do IO<State<Reason> & Result<&2, &2, Error<Reason>, Unit>>:
        +next : Chan(Job<Reason>) <- Chan.new(Job<Reason>, 1)
        sent : Bool <- Chan.send(Job<Reason>, tail, Job{records, size, completion, next})
        Ref.requireSent(sent)
        return (State{client, next, (queued + size : Nat), maximum}, Done{Unit{}})

# The current tail is always empty: it is created fresh when its predecessor
# is filled. Even with a stopped writer, this send cannot wait for queue space.
# The explicit byte budget bounds pending records; overflow fails the session.
def enqueue(-Reason: Data, state: State<Reason>, records: List<&2, List<&2, U32>>, completion: Maybe<&2, Deferred.Deferred<Result<&2, &2, Error<Reason>, Unit>>>) -> IO(State<Reason> & Result<&2, &2, Error<Reason>, Unit>):
  match state records:
    case State{Fail{+cause}, tail, queued, maximum} _:
      enqueueRejected(Reason, completion, (State{Fail{cause}, tail, queued, maximum}, Fail{cause}))
    case state Nil{}:
      do IO<State<Reason> & Result<&2, &2, Error<Reason>, Unit>>:
        settled(Reason, completion, Done{Unit{}})
        return (state, Done{Unit{}})
    case State{Done{client}, tail, +queued, +maximum} +records:
      +size = byteCount(records, 0n)
      enqueueAllowed(Reason, Nat.is_le((queued + size : Nat), U32.to_nat(maximum)), State{Done{client}, tail, queued, maximum}, records, size, completion)

def written(-Reason: Data, pair: Socket.Writer<Reason> & Result<&2, &2, Socket.SocketErrorOfSocket<Reason>, Unit>) -> Socket.Writer<Reason> & Result<&2, &2, Error<Reason>, Unit>:
  match pair:
    case (writer, Done{_}): (writer, Done{Unit{}})
    case (writer, Fail{cause}): (writer, Fail{Network{cause}})

def writeRecords(-Reason: Data, records: List<&2, List<&2, U32>>, pair: Socket.Writer<Reason> & Result<&2, &2, Error<Reason>, Unit>) -> IO(Socket.Writer<Reason> & Result<&2, &2, Error<Reason>, Unit>):
  match records pair:
    case _ Tuple{writer, Fail{cause}}: IO.pure(Socket.Writer<Reason> & Result<&2, &2, Error<Reason>, Unit>, (writer, Fail{cause}))
    case Nil{} Tuple{writer, Done{_}}: IO.pure(Socket.Writer<Reason> & Result<&2, &2, Error<Reason>, Unit>, (writer, Done{Unit{}}))
    case head <> rest Tuple{writer, Done{_}}:
      do IO<Socket.Writer<Reason> & Result<&2, &2, Error<Reason>, Unit>>:
        result : Socket.Writer<Reason> & Result<&2, &2, Socket.SocketErrorOfSocket<Reason>, Unit> <- Socket.sendWriter(Reason, writer, head)
        writeRecords(Reason, rest, written(Reason, result))

def interruptFailure(-Reason: Data, interrupt: Socket.Handle, result: Result<&2, &2, Error<Reason>, Unit>) -> IO(Unit):
  match result:
    case Done{_}: IO.pure(Unit, Unit{})
    case Fail{_}:
      do IO<Unit>:
        interrupted : Result<&2, &2, Socket.InterruptError, Bool> <- Socket.cancelInterrupt(interrupt)
        return Unit{}

def finishJob(-Reason: Data, shared: Resource.Handle<State<Reason>>, interrupt: Socket.Handle, size: Nat, completion: Maybe<&2, Deferred.Deferred<Result<&2, &2, Error<Reason>, Unit>>>, pair: Socket.Writer<Reason> & Result<&2, &2, Error<Reason>, Unit>) -> IO(Socket.Writer<Reason>):
  match pair:
    case (writer, result):
      do IO<Socket.Writer<Reason>>:
        +outcome : Result<&2, &2, Error<Reason>, Unit> <- Resource.run(State<Reason>, Result<&2, &2, Error<Reason>, Unit>, shared, state => IO.pure(State<Reason> & Result<&2, &2, Error<Reason>, Unit>, acknowledge(Reason, state, size, result)))
        interruptFailure(Reason, interrupt, outcome)
        settled(Reason, completion, outcome)
        return writer

# This loop waits for externally produced jobs. It owns the sole network
# writer; each consumed link is closed, including the final empty link.
@unsafe def writeLoop(-Reason: Data, +shared: Resource.Handle<State<Reason>>, +interrupt: Socket.Handle, writer: Socket.Writer<Reason>, message: Maybe<&1, Job<Reason>>) -> IO(Unit):
  match message:
    case None{}: Socket.closeWriter(Reason, writer)
    case Some{Job{records, size, completion, +next}}:
      do IO<Unit>:
        current : Result<&2, &2, Error<Reason>, Unit> <- Resource.run(State<Reason>, Result<&2, &2, Error<Reason>, Unit>, shared, state => IO.pure(State<Reason> & Result<&2, &2, Error<Reason>, Unit>, status(Reason, state)))
        result : Socket.Writer<Reason> & Result<&2, &2, Error<Reason>, Unit> <- writeRecords(Reason, records, (writer, current))
        successor : Socket.Writer<Reason> <- finishJob(Reason, shared, interrupt, size, completion, result)
        message : Maybe<&1, Job<Reason>> <- Chan.recv(Job<Reason>, next)
        Chan.close(Job<Reason>, next)
        writeLoop(Reason, shared, interrupt, successor, message)

def runWriter(-Reason: Data, shared: Resource.Handle<State<Reason>>, interrupt: Socket.Handle, writer: Socket.Writer<Reason>, +head: Chan(Job<Reason>)) -> IO(Unit):
  do IO<Unit>:
    message : Maybe<&1, Job<Reason>> <- Chan.recv(Job<Reason>, head)
    Chan.close(Job<Reason>, head)
    writeLoop(Reason, shared, interrupt, writer, message)

type Packet<-Reason: Data> is Data:
  Packet{status: Result<&2, &2, Error<Reason>, TLS.Status>, chunks: List<&2, List<&2, U32>>}

def sessionResult(-Reason: Data, result: Result<&2, &1, TLS.Error, TLS.Client>) -> Result<&2, &1, Error<Reason>, TLS.Client>:
  match result:
    case Fail{cause}: Fail{Protocol{cause}}
    case Done{client}: Done{client}

def inspected(-Reason: Data, tail: Chan(Job<Reason>), queued: Nat, maximum: U32, pair: TLS.Client & TLS.Status) -> State<Reason> & Result<&2, &2, Error<Reason>, TLS.Status>:
  match pair:
    case (client, observation): (State{Done{client}, tail, queued, maximum}, Done{observation})

def inspect(-Reason: Data, state: State<Reason>) -> State<Reason> & Result<&2, &2, Error<Reason>, TLS.Status>:
  match state:
    case State{Fail{+cause}, tail, queued, maximum}: (State{Fail{cause}, tail, queued, maximum}, Fail{cause})
    case State{Done{client}, tail, queued, maximum}: inspected(Reason, tail, queued, maximum, TLS.observe(client))

def queuedPacket(-Reason: Data, observation: Result<&2, &2, Error<Reason>, TLS.Status>, chunks: List<&2, List<&2, U32>>, pair: State<Reason> & Result<&2, &2, Error<Reason>, Unit>) -> State<Reason> & Packet<Reason>:
  match pair:
    case (state, Fail{cause}): (state, Packet{Fail{cause}, chunks})
    case (state, Done{_}): (state, Packet{observation, chunks})

def publish(-Reason: Data, records: List<&2, List<&2, U32>>, chunks: List<&2, List<&2, U32>>, pair: State<Reason> & Result<&2, &2, Error<Reason>, TLS.Status>) -> IO(State<Reason> & Packet<Reason>):
  match pair:
    case (state, observation):
      do IO<State<Reason> & Packet<Reason>>:
        next : State<Reason> & Result<&2, &2, Error<Reason>, Unit> <- enqueue(Reason, state, records, None{})
        return queuedPacket(Reason, observation, chunks, next)

def accepted(-Reason: Data, tail: Chan(Job<Reason>), queued: Nat, maximum: U32, reception: TLS.Reception) -> IO(State<Reason> & Packet<Reason>):
  match reception:
    case TLS.Reception{result, outgoing, incoming}:
      publish(Reason, outgoing, incoming, inspect(Reason, State{sessionResult(Reason, result), tail, queued, maximum}))

def receiveState(-Reason: Data, state: State<Reason>, bytes: List<&2, U32>) -> IO(State<Reason> & Packet<Reason>):
  match state:
    case State{Fail{+cause}, tail, queued, maximum}:
      IO.pure(State<Reason> & Packet<Reason>, (State{Fail{cause}, tail, queued, maximum}, Packet{Fail{cause}, Nil{}}))
    case State{Done{client}, tail, queued, maximum}: accepted(Reason, tail, queued, maximum, TLS.receive(client, bytes))

def endState(-Reason: Data, state: State<Reason>) -> State<Reason> & Result<&2, &2, Error<Reason>, TLS.Status>:
  match state:
    case State{Fail{+cause}, tail, queued, maximum}: (State{Fail{cause}, tail, queued, maximum}, Fail{cause})
    case State{Done{client}, tail, queued, maximum}:
      inspect(Reason, State{sessionResult(Reason, TLS.endInput(client)), tail, queued, maximum})

def sendResult(-Reason: Data, tail: Chan(Job<Reason>), queued: Nat, maximum: U32, completion: Deferred.Deferred<Result<&2, &2, Error<Reason>, Unit>>, result: Result<&2, &1, TLS.Error, TLS.Step>) -> IO(State<Reason> & Result<&2, &2, Error<Reason>, Unit>):
  match result:
    case Fail{cause}:
      enqueueRejected(Reason, Some{completion}, status(Reason, State{Fail{Protocol{cause}}, tail, queued, maximum}))
    case Done{TLS.Step{client, records, _}}: enqueue(Reason, State{Done{client}, tail, queued, maximum}, records, Some{completion})

def applyState(-Reason: Data, state: State<Reason>, operation: TLS.Client -> Result<&2, &1, TLS.Error, TLS.Step>, completion: Deferred.Deferred<Result<&2, &2, Error<Reason>, Unit>>) -> IO(State<Reason> & Result<&2, &2, Error<Reason>, Unit>):
  match state:
    case State{Fail{+cause}, tail, queued, maximum}:
      enqueueRejected(Reason, Some{completion}, (State{Fail{cause}, tail, queued, maximum}, Fail{cause}))
    case State{Done{client}, tail, queued, maximum}: sendResult(Reason, tail, queued, maximum, completion, operation(client))

# Finish all public operations before retiring the resource. Closing this tail
# wakes an idle writer and terminates it after draining any preceding jobs.
def stopState(-Reason: Data, state: State<Reason>) -> IO(State<Reason> & Unit):
  match state:
    case State{client, +tail, queued, maximum}:
      do IO<State<Reason> & Unit>:
        Chan.close(Job<Reason>, tail)
        return (State{failed(Reason, client, Closed{}), tail, queued, maximum}, Unit{})

def shutdownResult(-Reason: Data, interrupt: Result<&2, &2, Socket.InterruptError, Bool>, closed: Result<&2, &2, Socket.InterruptError, Unit>) -> Result<&2, &2, Error<Reason>, Unit>:
  match interrupt closed:
    case Fail{cause} _: Fail{ShutdownFailure{cause}}
    case Done{_} Fail{cause}: Fail{ShutdownFailure{cause}}
    case Done{_} Done{_}: Done{Unit{}}

# Destructive disposal interrupts pending writes before joining their task.
# Graceful write shutdown is a separate operation, and may await the peer.
def dispose(-Reason: Data, connection: Connection<Reason>) -> IO(Result<&2, &2, Error<Reason>, Unit>):
  match connection:
    case Connection{socket, owner, shared, interrupt, task, _, _}:
      do IO<Result<&2, &2, Error<Reason>, Unit>>:
        Resource.run(State<Reason>, Unit, shared, state => stopState(Reason, state))
        interrupted : Result<&2, &2, Socket.InterruptError, Bool> <- Socket.cancelInterrupt(interrupt)
        IO.join(Unit, task)
        retired : State<Reason> <- Resource.retire(State<Reason>, owner)
        closed : Result<&2, &2, Socket.InterruptError, Unit> <- Socket.close(Reason, socket)
        return shutdownResult(Reason, interrupted, closed)

def failedOpen(-Reason: Data, socket: Socket.Owner<Reason>, cause: Error<Reason>) -> IO(Result<&2, &1, Error<Reason>, Connection<Reason>>):
  do IO<Result<&2, &1, Error<Reason>, Connection<Reason>>>:
    cleanup : Result<&2, &2, Socket.InterruptError, Unit> <- Socket.close(Reason, socket)
    return Fail{cause}

def initialQueued(-Reason: Data, connection: Connection<Reason>, result: Result<&2, &2, Error<Reason>, Unit>) -> IO(Result<&2, &1, Error<Reason>, Connection<Reason>>):
  match result:
    case Done{_}: IO.pure(Result<&2, &1, Error<Reason>, Connection<Reason>>, Done{connection})
    case Fail{cause}:
      do IO<Result<&2, &1, Error<Reason>, Connection<Reason>>>:
        cleanup : Result<&2, &2, Error<Reason>, Unit> <- dispose(Reason, connection)
        return Fail{cause}

def launchWriter(-Reason: Data, socket: Socket.Owner<Reason>, +interrupt: Socket.Handle, writer: Socket.Writer<Reason>, head: Chan(Job<Reason>), records: List<&2, List<&2, U32>>, readSize: U32, pair: Resource.Owner<State<Reason>> & Resource.Handle<State<Reason>>) -> IO(Result<&2, &1, Error<Reason>, Connection<Reason>>):
  match pair:
    case (owner, +shared):
      do IO<Result<&2, &1, Error<Reason>, Connection<Reason>>>:
        task : Chan(Unit) <- IO.fork(Unit, runWriter(Reason, shared, interrupt, writer, head))
        queued : Result<&2, &2, Error<Reason>, Unit> <- Resource.run(State<Reason>, Result<&2, &2, Error<Reason>, Unit>, shared, state => enqueue(Reason, state, records, None{}))
        initialQueued(Reason, Connection{socket, owner, shared, interrupt, task, Nil{}, readSize}, queued)

def createState(-Reason: Data, client: TLS.Client, records: List<&2, List<&2, U32>>, options: Options, writer: Socket.Writer<Reason>, pair: Socket.Owner<Reason> & Socket.Handle) -> IO(Result<&2, &1, Error<Reason>, Connection<Reason>>):
  match options pair:
    case Options{_, maximum, readSize} Tuple{socket, interrupt}:
      do IO<Result<&2, &1, Error<Reason>, Connection<Reason>>>:
        +head : Chan(Job<Reason>) <- Chan.new(Job<Reason>, 1)
        owner : Resource.Owner<State<Reason>> <- Resource.create(State<Reason>, State{Done{client}, head, 0n, maximum})
        launchWriter(Reason, socket, interrupt, writer, head, records, readSize, Resource.borrow(State<Reason>, owner))

def attached(-Reason: Data, step: TLS.Step, options: Options, pair: Socket.Owner<Reason> & Result<&2, &1, Socket.SocketErrorOfSocket<Reason>, Socket.Writer<Reason>>) -> IO(Result<&2, &1, Error<Reason>, Connection<Reason>>):
  match step pair:
    case _ Tuple{socket, Fail{cause}}: failedOpen(Reason, socket, Network{cause})
    case TLS.Step{client, records, _} Tuple{socket, Done{writer}}:
      createState(Reason, client, records, options, writer, Socket.borrowConnection(Reason, socket))

# Attach starts the protocol; awaitHandshake below completes authentication.
# The caller supplies an already connected, abort-aware socket owner.
def attach(-Reason: Data, socket: Socket.Owner<Reason>, step: TLS.Step, options: Options) -> IO(Result<&2, &1, Error<Reason>, Connection<Reason>>):
  do IO<Result<&2, &1, Error<Reason>, Connection<Reason>>>:
    pair : Socket.Owner<Reason> & Result<&2, &1, Socket.SocketErrorOfSocket<Reason>, Socket.Writer<Reason>> <- Socket.createWriter(Reason, socket)
    attached(Reason, step, options, pair)

def initialized(-Reason: Data, socket: Socket.Owner<Reason>, options: Options, result: Result<&2, &1, TLS.Error, TLS.Step>) -> IO(Result<&2, &1, Error<Reason>, Connection<Reason>>):
  match result:
    case Fail{cause}: failedOpen(Reason, socket, Protocol{cause})
    case Done{step}: attach(Reason, socket, step, options)

def startAllowed(-Reason: Data, valid: Bool, socket: Socket.Owner<Reason>, name: Maybe<&2, String>, authorization: TLS.Authorization, options: Options) -> IO(Result<&2, &1, Error<Reason>, Connection<Reason>>):
  match valid options:
    case False{} _: failedOpen(Reason, socket, InvalidOptions{})
    case True{} Options{+limit, maximum, readSize}:
      do IO<Result<&2, &1, Error<Reason>, Connection<Reason>>>:
        result : Result<&2, &1, TLS.Error, TLS.Step> <- TLS.start(name, authorization, limit)
        initialized(Reason, socket, Options{limit, maximum, readSize}, result)

def start(-Reason: Data, socket: Socket.Owner<Reason>, name: Maybe<&2, String>, authorization: TLS.Authorization, options: Options) -> IO(Result<&2, &1, Error<Reason>, Connection<Reason>>):
  match options:
    case Options{limit, maximum, +readSize}:
      startAllowed(Reason, U32.is_gt(readSize, 0) && U32.is_le(readSize, 65536), socket, name, authorization, Options{limit, maximum, readSize})

def borrowWriter(-Reason: Data, connection: Connection<Reason>) -> Connection<Reason> & Writer<Reason>:
  match connection:
    case Connection{socket, owner, +shared, +interrupt, task, pending, readSize}:
      (Connection{socket, owner, shared, interrupt, task, pending, readSize}, Writer{shared, interrupt})

def submit(-Reason: Data, handle: Writer<Reason>, operation: TLS.Client -> Result<&2, &1, TLS.Error, TLS.Step>) -> IO(Result<&2, &2, Error<Reason>, Unit>):
  match handle:
    case Writer{shared, interrupt}:
      do IO<Result<&2, &2, Error<Reason>, Unit>>:
        +completion : Deferred.Deferred<Result<&2, &2, Error<Reason>, Unit>> <- Deferred.new(Result<&2, &2, Error<Reason>, Unit>)
        queued : Result<&2, &2, Error<Reason>, Unit> <- Resource.run(State<Reason>, Result<&2, &2, Error<Reason>, Unit>, shared, state => applyState(Reason, state, operation, completion))
        interruptFailure(Reason, interrupt, queued)
        result : Result<&2, &2, Error<Reason>, Unit> <- Deferred.result(Result<&2, &2, Error<Reason>, Unit>, completion)
        Deferred.dispose(Result<&2, &2, Error<Reason>, Unit>, completion)
        return result

def sendRecord(-Reason: Data, handle: Writer<Reason>, bytes: List<&2, U32>) -> IO(Result<&2, &2, Error<Reason>, Unit>):
  submit(Reason, handle, client => TLS.send(client, bytes))

def shutdownWrite(-Reason: Data, handle: Writer<Reason>) -> IO(Result<&2, &2, Error<Reason>, Unit>):
  submit(Reason, handle, TLS.close)

def packetStatus(-Reason: Data, pair: State<Reason> & Result<&2, &2, Error<Reason>, TLS.Status>) -> State<Reason> & Packet<Reason>:
  match pair:
    case (state, observation): (state, Packet{observation, Nil{}})

def readState(-Reason: Data, state: State<Reason>, result: Result<&2, &2, Socket.SocketErrorOfSocket<Reason>, List<&2, U32>>) -> IO(State<Reason> & Packet<Reason>):
  match state result:
    case State{Fail{+cause}, tail, queued, maximum} _:
      IO.pure(State<Reason> & Packet<Reason>, (State{Fail{cause}, tail, queued, maximum}, Packet{Fail{cause}, Nil{}}))
    case State{Done{_}, tail, queued, maximum} Fail{cause}:
      IO.pure(State<Reason> & Packet<Reason>, packetStatus(Reason, inspect(Reason, State{Fail{Network{cause}}, tail, queued, maximum})))
    case state Done{Nil{}}: IO.pure(State<Reason> & Packet<Reason>, packetStatus(Reason, endState(Reason, state)))
    case state Done{bytes}: receiveState(Reason, state, bytes)

def flatten(chunks: List<&2, List<&2, U32>>, reverse: List<&2, U32>) -> List<&2, U32>:
  match chunks:
    case Nil{}: List.reverse(&2, U32, reverse)
    case head <> rest: flatten(rest, List.reverse.go(&2, U32, head, reverse))

def outcome(-Reason: Data, observation: Result<&2, &2, Error<Reason>, TLS.Status>) -> Result<&2, &2, Error<Reason>, Unit>:
  match observation:
    case Fail{cause}: Fail{cause}
    case Done{_}: Done{Unit{}}

def bufferPacket(-Reason: Data, connection: Connection<Reason>, packet: Packet<Reason>) -> IO(Connection<Reason> & Result<&2, &2, Error<Reason>, TLS.Status>):
  match connection packet:
    case Connection{socket, owner, shared, +interrupt, task, pending, readSize} Packet{+observation, chunks}:
      do IO<Connection<Reason> & Result<&2, &2, Error<Reason>, TLS.Status>>:
        interruptFailure(Reason, interrupt, outcome(Reason, observation))
        return (Connection{socket, owner, shared, interrupt, task, Record.append(pending, flatten(chunks, Nil{})), readSize}, observation)

def received(-Reason: Data, shared: Resource.Handle<State<Reason>>, restore: Socket.Owner<Reason> -> Connection<Reason>, pair: Socket.Owner<Reason> & Result<&2, &2, Socket.SocketErrorOfSocket<Reason>, List<&2, U32>>) -> IO(Connection<Reason> & Result<&2, &2, Error<Reason>, TLS.Status>):
  match pair:
    case (socket, result):
      do IO<Connection<Reason> & Result<&2, &2, Error<Reason>, TLS.Status>>:
        packet : Packet<Reason> <- Resource.run(State<Reason>, Packet<Reason>, shared, state => readState(Reason, state, result))
        bufferPacket(Reason, restore(socket), packet)

# The network read waits outside shared TLS state; only its completed bytes
# enter receiveState. This remains independent of a blocked network writer.
def pump(-Reason: Data, connection: Connection<Reason>) -> IO(Connection<Reason> & Result<&2, &2, Error<Reason>, TLS.Status>):
  match connection:
    case Connection{socket, owner, +shared, interrupt, task, pending, +readSize}:
      do IO<Connection<Reason> & Result<&2, &2, Error<Reason>, TLS.Status>>:
        pair : Socket.Owner<Reason> & Result<&2, &2, Socket.SocketErrorOfSocket<Reason>, List<&2, U32>> <- Socket.recvSocket(Reason, socket, readSize)
        received(Reason, shared, next => Connection{next, owner, shared, interrupt, task, pending, readSize}, pair)

def observation(-Reason: Data, connection: Connection<Reason>) -> IO(Connection<Reason> & Result<&2, &2, Error<Reason>, TLS.Status>):
  match connection:
    case Connection{socket, owner, +shared, interrupt, task, pending, readSize}:
      do IO<Connection<Reason> & Result<&2, &2, Error<Reason>, TLS.Status>>:
        result : Result<&2, &2, Error<Reason>, TLS.Status> <- Resource.run(State<Reason>, Result<&2, &2, Error<Reason>, TLS.Status>, shared, state => IO.pure(State<Reason> & Result<&2, &2, Error<Reason>, TLS.Status>, inspect(Reason, state)))
        return (Connection{socket, owner, shared, interrupt, task, pending, readSize}, result)

@unsafe def handshakeLoop(-Reason: Data, pair: Connection<Reason> & Result<&2, &2, Error<Reason>, TLS.Status>) -> IO(Result<&2, &1, Error<Reason>, Connection<Reason>>):
  match pair:
    case (connection, Fail{cause}):
      do IO<Result<&2, &1, Error<Reason>, Connection<Reason>>>:
        cleanup : Result<&2, &2, Error<Reason>, Unit> <- dispose(Reason, connection)
        return Fail{cause}
    case (connection, Done{TLS.Established{_, _}}): IO.pure(Result<&2, &1, Error<Reason>, Connection<Reason>>, Done{connection})
    case (connection, Done{TLS.Handshaking{}}):
      do IO<Result<&2, &1, Error<Reason>, Connection<Reason>>>:
        next : Connection<Reason> & Result<&2, &2, Error<Reason>, TLS.Status> <- pump(Reason, connection)
        handshakeLoop(Reason, next)

def awaitHandshake(-Reason: Data, connection: Connection<Reason>) -> IO(Result<&2, &1, Error<Reason>, Connection<Reason>>):
  do IO<Result<&2, &1, Error<Reason>, Connection<Reason>>>:
    current : Connection<Reason> & Result<&2, &2, Error<Reason>, TLS.Status> <- observation(Reason, connection)
    handshakeLoop(Reason, current)

# Used for both application write fragmentation and bounded application reads.
# Unlike a length-then-take/drop sequence, small reads traverse only their prefix.
def split(bytes: List<&2, U32>, count: Nat, reverse: List<&2, U32>) -> Record.Fragment:
  match bytes count:
    case rest 0n: Record.Fragment{List.reverse(&2, U32, reverse), rest}
    case Nil{} _: Record.Fragment{List.reverse(&2, U32, reverse), Nil{}}
    case head <> rest 1n+count: split(rest, count, head <> reverse)

def readBuffered(-Reason: Data, socket: Socket.Owner<Reason>, owner: Resource.Owner<State<Reason>>, shared: Resource.Handle<State<Reason>>, interrupt: Socket.Handle, task: Chan(Unit), readSize: U32, fragment: Record.Fragment) -> Connection<Reason> & Result<&2, &2, Error<Reason>, List<&2, U32>>:
  match fragment:
    case Record.Fragment{bytes, rest}: (Connection{socket, owner, shared, interrupt, task, rest, readSize}, Done{bytes})

@unsafe def readLoop(-Reason: Data, +maximum: U32, pair: Connection<Reason> & Result<&2, &2, Error<Reason>, TLS.Status>) -> IO(Connection<Reason> & Result<&2, &2, Error<Reason>, List<&2, U32>>):
  match pair:
    case (Connection{socket, owner, shared, interrupt, task, head <> rest, readSize}, _):
      IO.pure(Connection<Reason> & Result<&2, &2, Error<Reason>, List<&2, U32>>, readBuffered(Reason, socket, owner, shared, interrupt, task, readSize, split(head <> rest, U32.to_nat(maximum), Nil{})))
    case (connection, Fail{cause}): IO.pure(Connection<Reason> & Result<&2, &2, Error<Reason>, List<&2, U32>>, (connection, Fail{cause}))
    case (connection, Done{TLS.Established{True{}, _}}): IO.pure(Connection<Reason> & Result<&2, &2, Error<Reason>, List<&2, U32>>, (connection, Done{Nil{}}))
    case (connection, Done{_}):
      do IO<Connection<Reason> & Result<&2, &2, Error<Reason>, List<&2, U32>>>:
        next : Connection<Reason> & Result<&2, &2, Error<Reason>, TLS.Status> <- pump(Reason, connection)
        readLoop(Reason, maximum, next)

def recv(-Reason: Data, connection: Connection<Reason>, maximum: U32) -> IO(Connection<Reason> & Result<&2, &2, Error<Reason>, List<&2, U32>>):
  match maximum:
    case 0: IO.pure(Connection<Reason> & Result<&2, &2, Error<Reason>, List<&2, U32>>, (connection, Done{Nil{}}))
    case maximum:
      do IO<Connection<Reason> & Result<&2, &2, Error<Reason>, List<&2, U32>>>:
        current : Connection<Reason> & Result<&2, &2, Error<Reason>, TLS.Status> <- observation(Reason, connection)
        readLoop(Reason, maximum, current)

def sendParts(-Reason: Data, fuel: Nat, +handle: Writer<Reason>, fragment: Record.Fragment, result: Result<&2, &2, Error<Reason>, Unit>) -> IO(Result<&2, &2, Error<Reason>, Unit>):
  match fuel fragment result:
    case _ _ Fail{cause}: IO.pure(Result<&2, &2, Error<Reason>, Unit>, Fail{cause})
    case _ Record.Fragment{Nil{}, Nil{}} Done{_}: IO.pure(Result<&2, &2, Error<Reason>, Unit>, Done{Unit{}})
    case 0n _ Done{_}: IO.die(Result<&2, &2, Error<Reason>, Unit>, 1, "TLS write: invalid internal byte bound")
    case 1n+fuel Record.Fragment{bytes, rest} Done{_}:
      do IO<Result<&2, &2, Error<Reason>, Unit>>:
        result : Result<&2, &2, Error<Reason>, Unit> <- sendRecord(Reason, handle, bytes)
        sendParts(Reason, fuel, handle, split(rest, 16384n, Nil{}), result)

def send(-Reason: Data, handle: Writer<Reason>, +bytes: List<&2, U32>) -> IO(Result<&2, &2, Error<Reason>, Unit>):
  sendParts(Reason, Record.length(bytes, 0n), handle, split(bytes, 16384n, Nil{}), Done{Unit{}})
