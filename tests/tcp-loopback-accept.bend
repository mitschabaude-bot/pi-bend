import Base

# The callback listener binds loopback and lets its owner observe an idle
# accept without parking, so cancellation can retire the listener promptly.
def idle(pair: Listener & Result<&1,&1,U32 & String,Socket>) -> IO(Listener):
  match pair:
    case (listener,Fail{(code,_)}):
      Bool.pick(Unit -> IO(Listener),U32.is_eq(code,11),_ => IO.pure(Listener,listener),_ => IO.die(Listener,1,"accept error"))(Unit{})
    case (listener,Done{socket}):
      do IO<Listener>:
        Socket.close(socket)
        Listener.close(listener)
        IO.die(Listener,1,"idle accept unexpectedly succeeded")
def accepted(pair: Listener & Result<&1,&1,U32 & String,Socket>,client: Socket) -> IO(Unit):
  match pair:
    case (listener,Fail{_}):
      do IO<Unit>:
        Socket.close(client)
        Listener.close(listener)
        IO.die(Unit,1,"ready accept failed")
    case (listener,Done{server}):
      do IO<Unit>:
        Socket.close(server)
        Socket.close(client)
        Listener.close(listener)
        IO.print("loopback accept ready")
def connected(listener: Listener,result: Result<&1,&1,U32 & String,Socket>) -> IO(Unit):
  match result:
    case Fail{_}:
      do IO<Unit>:
        Listener.close(listener)
        IO.die(Unit,1,"loopback connect failed")
    case Done{client}:
      do IO<Unit>:
        pair : Listener & Result<&1,&1,U32 & String,Socket> <- TCP.accept_try(listener)
        accepted(pair,client)
def listening(result: Result<&1,&1,U32 & String,Listener>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit,1,"loopback bind failed")
    case Done{listener}:
      do IO<Unit>:
        pair : Listener & Result<&1,&1,U32 & String,Socket> <- TCP.accept_try(listener)
        ready : Listener <- idle(pair)
        client : Result<&1,&1,U32 & String,Socket> <- TCP.connect("127.0.0.1",47839)
        connected(ready,client)
def main() -> IO(Unit):
  do IO<Unit>:
    bound : Result<&1,&1,U32 & String,Listener> <- TCP.listen_host("127.0.0.1",47839)
    listening(bound)
