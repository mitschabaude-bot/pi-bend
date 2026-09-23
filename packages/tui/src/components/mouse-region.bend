import Base
import ../component.bend as Component
import ../tui.bend as T
import ../../../runtime/src/callback.bend as Callback

# Both the child and callback handle are borrowed; MouseRegion owns neither.
type MouseRegion is Data:
  MouseRegion{child: Component.Component,onMouse: Callback.Callback<T.TuiMouseEvent,Maybe<&2,T.TuiMouseEventResult>>}

def new(child: Component.Component,onMouse: Callback.Callback<T.TuiMouseEvent,Maybe<&2,T.TuiMouseEventResult>>) -> MouseRegion:
  MouseRegion{child,onMouse}

def render(region: MouseRegion,width: Nat) -> IO(List<&2,String>):
  match region:
    case MouseRegion{child,_}: Component.render(child,width)

def invalidate(region: MouseRegion) -> IO(Unit):
  match region:
    case MouseRegion{child,_}: Component.invalidate(child)

def fallback(result: Maybe<&2,T.TuiMouseEventResult>) -> Maybe<&2,Component.MouseResponse>:
  match result:
    case None{}: None{}
    case Some{value}: Some{Component.LocalResult{value}}

def afterChild(result: Maybe<&2,Component.TuiMouseDispatchResult>,onMouse: Callback.Callback<T.TuiMouseEvent,Maybe<&2,T.TuiMouseEventResult>>,event: T.TuiMouseEvent) -> IO(Maybe<&2,Component.MouseResponse>):
  match result:
    case Some{value}: IO.pure(Maybe<&2,Component.MouseResponse>,Some{Component.DispatchedResult{value}})
    case None{}:
      do IO<Maybe<&2,Component.MouseResponse>>:
        response : Maybe<&2,T.TuiMouseEventResult> <- Callback.call(T.TuiMouseEvent,Maybe<&2,T.TuiMouseEventResult>,onMouse,event)
        return fallback(response)

def handleMouse(region: MouseRegion,+event: T.TuiMouseEvent) -> IO(Maybe<&2,Component.MouseResponse>):
  match region:
    case MouseRegion{child,onMouse}:
      do IO<Maybe<&2,Component.MouseResponse>>:
        result : Maybe<&2,Component.TuiMouseDispatchResult> <- Component.dispatchMouseEvent(child,event)
        afterChild(result,onMouse,event)
