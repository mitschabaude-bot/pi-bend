import Base
import ./abortable-socket.bend as SocketIO
import ./socket-interrupt.bend as Interrupt
import ./dns-tcp-frame.bend as Frame

type Error<-Reason: Data> is Data:
  Framing{error: Frame.Error}
  Transport{error: SocketIO.Error<Reason>}
  InvalidReadSize{}

type Position<-Reason: Data> is Data:
  Reading{reader: Frame.Reader, unread: List<&2, U32>}
  Ended{error: Maybe<&2, Error<Reason>>}

type Connection<-Reason: Data> is Type:
  Connection{socket: SocketIO.Owner<Reason>, position: Position<Reason>}

type Next<-Reason: Data> is Type:
  Next{connection: Connection<Reason>, result: Result<&2, &2, Error<Reason>, Maybe<&2, List<&2, U32>>>}

type Step<-Reason: Data> is Type:
  Ready{value: Next<Reason>}
  Pull{socket: SocketIO.Owner<Reason>, reader: Frame.Reader}

def adopt(-Reason: Data, socket: SocketIO.Owner<Reason>) -> Connection<Reason>:
  Connection{socket, Reading{Frame.new(), Nil{}}}

def terminal(-Reason: Data, error: Maybe<&2, Error<Reason>>) -> Result<&2, &2, Error<Reason>, Maybe<&2, List<&2, U32>>>:
  match error:
    case None{}: Done{None{}}
    case Some{why}: Fail{why}

def ended(-Reason: Data, socket: SocketIO.Owner<Reason>, +error: Maybe<&2, Error<Reason>>) -> Step<Reason>:
  Ready{Next{Connection{socket, Ended{error}}, terminal(Reason, error)}}

def decoded(-Reason: Data, socket: SocketIO.Owner<Reason>, result: Frame.ReadResult) -> Step<Reason>:
  match result:
    case Frame.More{reader}: Pull{socket, reader}
    case Frame.Frame{bytes, rest}: Ready{Next{Connection{socket, Reading{Frame.new(), rest}}, Done{Some{bytes}}}}
    case Frame.Failed{error}: ended(Reason, socket, Some{Framing{error}})

def eof(-Reason: Data, socket: SocketIO.Owner<Reason>, result: Result<&2, &2, Frame.Error, Unit>) -> Step<Reason>:
  match result:
    case Done{_}: ended(Reason, socket, None{})
    case Fail{error}: ended(Reason, socket, Some{Framing{error}})

def received(-Reason: Data, reader: Frame.Reader, pair: SocketIO.Owner<Reason> & Result<&2, &2, SocketIO.Error<Reason>, List<&2, U32>>) -> Step<Reason>:
  match pair:
    case (socket, Fail{error}): ended(Reason, socket, Some{Transport{error}})
    case (socket, Done{Nil{}}): eof(Reason, socket, Frame.finish(reader))
    case (socket, Done{byte <> rest}): decoded(Reason, socket, Frame.read(reader, byte <> rest))

# Every recursive step awaits a read. A nonempty read advances the bounded
# frame; EOF and errors settle it. The checker cannot express IO progress.
@unsafe def drive(-Reason: Data, +maximum: U32, step: Step<Reason>) -> IO(Next<Reason>):
  match step:
    case Ready{value}: IO.pure(Next<Reason>, value)
    case Pull{socket, reader}:
      do IO<Next<Reason>>:
        result : SocketIO.Owner<Reason> & Result<&2, &2, SocketIO.Error<Reason>, List<&2, U32>> <- SocketIO.recv(Reason, socket, maximum)
        drive(Reason, maximum, received(Reason, reader, result))

def inspected(-Reason: Data, reader: Frame.Reader, unread: List<&2, U32>, pair: SocketIO.Owner<Reason> & Result<&2, &2, SocketIO.Error<Reason>, Unit>) -> Step<Reason>:
  match pair:
    case (socket, Fail{error}): ended(Reason, socket, Some{Transport{error}})
    case (socket, Done{_}): decoded(Reason, socket, Frame.read(reader, unread))

def pending(-Reason: Data, connection: Connection<Reason>) -> IO(Step<Reason>):
  match connection:
    case Connection{socket, Reading{reader, unread}}:
      do IO<Step<Reason>>:
        checked : SocketIO.Owner<Reason> & Result<&2, &2, SocketIO.Error<Reason>, Unit> <- SocketIO.run(Reason, Unit, socket, owned => IO.pure(Socket & Result<&1, &1, U32 & String, Unit>, (owned, Done{Unit{}})))
        return inspected(Reason, reader, unread, checked)
    case Connection{socket, Ended{error}}: IO.pure(Step<Reason>, ended(Reason, socket, error))

# Check retained abort state even when a complete frame is already buffered.
# Terminal read results repeat without further IO. The caller must still close
# the affine connection, including after EOF or failure, to join its watcher.
def receive(-Reason: Data, connection: Connection<Reason>, maximum: U32) -> IO(Next<Reason>):
  match maximum:
    case 0: IO.pure(Next<Reason>, Next{connection, Fail{InvalidReadSize{}}})
    case size:
      do IO<Next<Reason>>:
        step : Step<Reason> <- pending(Reason, connection)
        drive(Reason, size, step)

def sent(-Reason: Data, position: Position<Reason>, pair: SocketIO.Owner<Reason> & Result<&2, &2, SocketIO.Error<Reason>, Unit>) -> Connection<Reason> & Result<&2, &2, Error<Reason>, Unit>:
  match pair:
    case (socket, Done{_}): (Connection{socket, position}, Done{Unit{}})
    case (socket, Fail{error}): (Connection{socket, position}, Fail{Transport{error}})

def sendFrame(-Reason: Data, connection: Connection<Reason>, result: Result<&2, &2, Frame.Error, List<&2, U32>>) -> IO(Connection<Reason> & Result<&2, &2, Error<Reason>, Unit>):
  match connection result:
    case owner Fail{error}: IO.pure(Connection<Reason> & Result<&2, &2, Error<Reason>, Unit>, (owner, Fail{Framing{error}}))
    case Connection{socket, position} Done{wire}:
      do IO<Connection<Reason> & Result<&2, &2, Error<Reason>, Unit>>:
        result : SocketIO.Owner<Reason> & Result<&2, &2, SocketIO.Error<Reason>, Unit> <- SocketIO.send(Reason, socket, wire)
        return sent(Reason, position, result)

# Encoding failure leaves the connection untouched. A transport write failure
# may follow a partial write; the caller must close rather than retry that frame.
# Multiple sends before receive support pipelining; transaction IDs are managed
# above this layer, and frames are returned in their actual arrival order.
def send(-Reason: Data, connection: Connection<Reason>, bytes: List<&2, U32>) -> IO(Connection<Reason> & Result<&2, &2, Error<Reason>, Unit>):
  sendFrame(Reason, connection, Frame.encode(bytes))

def close(-Reason: Data, connection: Connection<Reason>) -> IO(Result<&2, &2, Interrupt.Error, Unit>):
  match connection:
    case Connection{socket, _}: SocketIO.close(Reason, socket)
