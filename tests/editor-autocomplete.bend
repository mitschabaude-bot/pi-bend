import Base
import ../packages/tui/src/components/editor.bend as E
import ../packages/tui/src/autocomplete.bend as AC
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/src/deferred.bend as D

type Probe is Data: Probe{count: Ref.Ref<Nat>,entered: D.Deferred<Unit>,release: D.Deferred<Unit>,texts: Ref.Ref<List<&2,String>>}
def waitFirst(index: Nat,entered: D.Deferred<Unit>,release: D.Deferred<Unit>) -> IO(Unit):
  match index:
    case Zero{}:
      do IO<Unit>:
        settled : Bool <- D.resolve(Unit,entered,Unit{})
        D.result(Unit,release)
    case Succ{_}: IO.pure(Unit,Unit{})
def increment(+n: Nat) -> Nat & Nat: (n + 1n,n)
def suggestions(probe: Probe,request: AC.SuggestionRequest) -> IO(AC.ResultOf(Maybe<&2,AC.AutocompleteSuggestions>)):
  match probe request:
    case Probe{count,entered,release,texts} AC.SuggestionRequest{lines,_,_,_}:
      do IO<AC.ResultOf(Maybe<&2,AC.AutocompleteSuggestions>)>:
        index : Nat <- Ref.modify(Nat,Nat,count,n => increment(n))
        recorded : Unit <- Ref.modify(List<&2,String>,Unit,texts,previous => (String.join(lines,"\n") <> previous,Unit{}))
        waitFirst(index,entered,release)
        return Done{Some{AC.AutocompleteSuggestions{[AC.AutocompleteItem{"value","value",None{}}],"#"}}}
def completion(unused: Unit,request: AC.CompletionRequest) -> IO(AC.ResultOf(AC.Completion)):
  match request:
    case AC.CompletionRequest{lines,line,column,_,_}: IO.pure(AC.ResultOf(AC.Completion),Done{AC.Completion{lines,line,column}})
def awaitLatest(runtime: E.AutocompleteRuntime) -> IO(Unit):
  match runtime:
    case E.AutocompleteRuntime{_,_,None{}}: IO.pure(Unit,Unit{})
    case E.AutocompleteRuntime{_,_,Some{E.AutocompleteWork{_,done}}}: D.result(Unit,done)
def require(ok: Bool,message: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit,Unit{})
    case False{}: IO.die(Unit,1,message)
def oneEvent(events: List<&2,E.AutocompleteEvent>) -> Bool:
  match events:
    case E.AutocompleteEvent{_,E.EditorState{["newest"],0n,6n},_,Done{Some{_}}} <> Nil{}: True{}
    case _: False{}
def main() -> IO(Unit):
  do IO<Unit>:
    +count : Ref.Ref<Nat> <- Ref.new(Nat,0n)
    +texts : Ref.Ref<List<&2,String>> <- Ref.new(List<&2,String>,Nil{})
    +entered : D.Deferred<Unit> <- D.new(Unit)
    +release : D.Deferred<Unit> <- D.new(Unit)
    +get : C.Callback<AC.SuggestionRequest,AC.ResultOf(Maybe<&2,AC.AutocompleteSuggestions>)> <- C.create(~Probe,~AC.SuggestionRequest,~AC.ResultOf(Maybe<&2,AC.AutocompleteSuggestions>),~suggestions,Probe{count,entered,release,texts})
    +apply : C.Callback<AC.CompletionRequest,AC.ResultOf(AC.Completion)> <- C.create(~Unit,~AC.CompletionRequest,~AC.ResultOf(AC.Completion),~completion,Unit{})
    runtime : E.AutocompleteRuntime <- E.createAutocompleteRuntime(E.EditorState{["old"],0n,3n})
    +runtime : E.AutocompleteRuntime <- E.requestAutocomplete(runtime,E.EditorState{["old"],0n,3n},AC.AutocompleteProvider{get,apply,None{},Nil{}},E.AutocompleteRequestOptions{False{},True{}},0,None{})
    D.result(Unit,entered)
    +runtime : E.AutocompleteRuntime <- E.requestAutocomplete(runtime,E.EditorState{["new"],0n,3n},AC.AutocompleteProvider{get,apply,None{},Nil{}},E.AutocompleteRequestOptions{False{},False{}},20,None{})
    E.synchronizeAutocomplete(runtime,E.EditorState{["newest"],0n,6n})
    before : Nat <- Ref.read(Nat,count)
    require(Nat.is_eq(before,1n),"requests were not serialized")
    released : Bool <- D.resolve(Unit,release,Unit{})
    awaitLatest(runtime)
    events : List<&2,E.AutocompleteEvent> <- E.takeAutocompleteEvents(runtime)
    require(oneEvent(events),"stale result accepted or latest snapshot lost")
    +runtime : E.AutocompleteRuntime <- E.requestAutocomplete(runtime,E.EditorState{["cancelled"],0n,9n},AC.AutocompleteProvider{get,apply,None{},Nil{}},E.AutocompleteRequestOptions{False{},False{}},20,None{})
    E.cancelAutocompleteRequest(runtime,E.EditorState{["cancelled"],0n,9n})
    awaitLatest(runtime)
    events : List<&2,E.AutocompleteEvent> <- E.takeAutocompleteEvents(runtime)
    require(List.is_empty(&2,E.AutocompleteEvent,events),"cancelled debounce published")
    E.disposeAutocompleteRuntime(runtime)
    calls : Nat <- Ref.dispose(Nat,count)
    values : List<&2,String> <- Ref.dispose(List<&2,String>,texts)
    require(Nat.is_eq(calls,2n) && String.eq(String.join(values,"|"),"newest|old"),"unexpected provider calls")
    C.dispose(AC.SuggestionRequest,AC.ResultOf(Maybe<&2,AC.AutocompleteSuggestions>),get)
    C.dispose(AC.CompletionRequest,AC.ResultOf(AC.Completion),apply)
    D.dispose(Unit,entered)
    D.dispose(Unit,release)
    IO.print("serialized async suggestions, stale rejection, current snapshots, abortable 20ms debounce, and retirement pass")
