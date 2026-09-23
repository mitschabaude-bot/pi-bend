import Base

# TCP.readable over a loopback pair: an idle socket is not readable, pending
# bytes make it readable until received, and a peer close makes it readable.

def flag(value: Bool) -> String: Bool.pick(String, value, "true", "false")

def report(+label: String, pair: Socket & Result<&1, &1, U32 & String, Bool>) -> IO(Socket):
  match pair:
    case (socket, Done{value}):
      do IO<Socket>:
        IO.print(label ++ " " ++ flag(value))
        return socket
    case (socket, Fail{(code, _)}):
      do IO<Socket>:
        IO.print(label ++ " error " ++ U32.show(code))
        return socket

def check(+label: String, socket: Socket) -> IO(Socket):
  do IO<Socket>:
    pair : Socket & Result<&1, &1, U32 & String, Bool> <- TCP.readable(socket)
    report(label, pair)

def sent(pair: Socket & Result<&1, &1, U32 & String, Unit>) -> Socket:
  match pair:
    case (socket, _): socket

def received(pair: Socket & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Socket):
  match pair:
    case (socket, Done{bytes}):
      do IO<Socket>:
        IO.print("received " ++ Nat.show(List.length(&2, U32, bytes)))
        return socket
    case (socket, Fail{_}):
      do IO<Socket>:
        IO.print("receive failed")
        return socket

def connected(client: Socket, pair: Listener & Result<&1, &1, U32 & String, Socket>) -> IO(Unit):
  match pair:
    case (listener, Fail{_}):
      do IO<Unit>:
        Socket.close(client)
        Listener.close(listener)
        IO.print("accept failed")
    case (listener, Done{server}):
      do IO<Unit>:
        idle : Socket <- check("idle", client)
        written : Socket & Result<&1, &1, U32 & String, Unit> <- TCP.send_bytes(server, 104 <> 105 <> Nil{})
        IO.sleep(20)
        pending : Socket <- check("pending", idle)
        read : Socket & Result<&1, &1, U32 & String, List<&2, U32>> <- TCP.recv_bytes(pending, 16)
        drained : Socket <- received(read)
        after : Socket <- check("drained", drained)
        Socket.close(sent(written))
        IO.sleep(20)
        closed : Socket <- check("peer-closed", after)
        Socket.close(closed)
        Listener.close(listener)

def accepting(listener: Listener, client: Result<&1, &1, U32 & String, Socket>) -> IO(Unit):
  match client:
    case Fail{_}:
      do IO<Unit>:
        Listener.close(listener)
        IO.print("connect failed")
    case Done{socket}:
      do IO<Unit>:
        pair : Listener & Result<&1, &1, U32 & String, Socket> <- TCP.accept(listener)
        connected(socket, pair)

def listening(port: U32, result: Result<&1, &1, U32 & String, Listener>) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("listen failed")
    case Done{listener}:
      do IO<Unit>:
        client : Result<&1, &1, U32 & String, Socket> <- TCP.connect("127.0.0.1", port)
        accepting(listener, client)

def main() -> IO(Unit):
  do IO<Unit>:
    listener : Result<&1, &1, U32 & String, Listener> <- TCP.listen(47811)
    listening(47811, listener)
