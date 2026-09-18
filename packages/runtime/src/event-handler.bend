import Base
import ./event-target.bend as T
import ./callback.bend as C
import ./ref.bend as R
import ./listener-registry.bend as L

# An on-event property owns a stable wrapper. First assignment (including null)
# establishes its listener position; replacement never removes that wrapper.
# This typed interface covers callable/null values. Dynamic non-callable values
# and Node's listener-count hooks still require the dynamic/warning layers.
type Handler<-Host: Data, -Error: Data> is Data:
  Handler{current: R.Ref<Maybe<&2, T.HostListener(Host, Error)>>, wrapper: T.HostListener(Host, Error)}

def invoke(-Host: Data, -Error: Data, callback: Maybe<&2, T.HostListener(Host, Error)>, input: T.HostInput(Host)) -> IO(T.Output(Error)):
  match callback:
    case None{}: IO.pure(T.Output(Error), Done{Unit{}})
    case Some{value}: C.call(T.HostInput(Host), T.Output(Error), value, input)

def body(-Host: Data, -Error: Data, current: R.Ref<Maybe<&2, T.HostListener(Host, Error)>>, input: T.HostInput(Host)) -> IO(T.Output(Error)):
  do IO<T.Output(Error)>:
    callback : Maybe<&2, T.HostListener(Host, Error)> <- R.read(Maybe<&2, T.HostListener(Host, Error)>, current)
    invoke(Host, Error, callback, input)

def new(~Host: Data, ~Error: Data) -> IO(Handler<Host, Error>):
  do IO<Handler<Host, Error>>:
    +current : R.Ref<Maybe<&2, T.HostListener(Host, Error)>> <- R.new(Maybe<&2, T.HostListener(Host, Error)>, None{})
    wrapper : T.HostListener(Host, Error) <- C.create(~R.Ref<Maybe<&2, T.HostListener(Host, Error)>>, ~T.HostInput(Host), ~T.Output(Error), ~(body(Host, Error)), current)
    return Handler{current, wrapper}

def get(-Host: Data, -Error: Data, handler: Handler<Host, Error>) -> IO(Maybe<&2, T.HostListener(Host, Error)>):
  match handler:
    case Handler{current, _}: R.read(Maybe<&2, T.HostListener(Host, Error)>, current)

def set(-Host: Data, -Error: Data, handler: Handler<Host, Error>, dispatcher: T.Dispatcher<Host, Error>, eventType: String, callback: Maybe<&2, T.HostListener(Host, Error)>) -> IO(Unit):
  match handler:
    case Handler{current, wrapper}:
      do IO<Unit>:
        R.write(Maybe<&2, T.HostListener(Host, Error)>, current, callback)
        # Registry deduplication retains the first assignment's position. The
        # original user callback is not the registered wrapper's identity.
        T.addEventListenerDispatcher(Host, Error, dispatcher, eventType, Some{wrapper}, L.Options{False{}, False{}, False{}})

# Retire the containing target and all active dispatches before disposal.
# User callbacks remain caller-owned; only this property's wrapper is owned.
def dispose(-Host: Data, -Error: Data, handler: Handler<Host, Error>) -> IO(Unit):
  match handler:
    case Handler{current, wrapper}:
      do IO<Unit>:
        previous : Maybe<&2, T.HostListener(Host, Error)> <- R.dispose(Maybe<&2, T.HostListener(Host, Error)>, current)
        C.dispose(T.HostInput(Host), T.Output(Error), wrapper)
