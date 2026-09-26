import Base
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/deadline.bend as Deadline
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/fetch.bend as Fetch
import ../../../runtime/src/ref.bend as Ref
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/websocket-client.bend as Socket

# Continuation is a value owned by its session connection. A failed prefix or
# changed request configuration invalidates it and sends the full context.
type CachedWebSocketContinuationState is Data:
  CachedWebSocketContinuationState{lastRequestBody: R.Record<V.Value>, lastResponseId: String, lastResponseItems: List<&2, V.Value>}
type CachedWebSocketRequest is Data:
  CachedWebSocketRequest{body: R.Record<V.Value>, continuation: Maybe<&2, CachedWebSocketContinuationState>}

def requestBodyWithoutInput(body: R.Record<V.Value>) -> R.Record<V.Value>:
  R.remove(V.Value, R.remove(V.Value, body, "input"), "previous_response_id")

def responseInput(value: Maybe<&2, V.Value>) -> Maybe<&2, List<&2, V.Value>>:
  match value:
    case None{}: Some{Nil{}}
    case Some{V.ArrayValue{items}}: Some{items}
    case _: None{}

def requestBodiesMatchExceptInput(left: R.Record<V.Value>, right: R.Record<V.Value>) -> Bool:
  V.equal(V.ObjectValue{requestBodyWithoutInput(left)}, V.ObjectValue{requestBodyWithoutInput(right)})

# Remove the baseline only if the entire prefix matches, preserving the
# current input's suffix and array order. An empty delta is valid.
def cachedInputSuffix(current: List<&2, V.Value>, baseline: List<&2, V.Value>, matched: Bool) -> Maybe<&2, List<&2, V.Value>>:
  match matched current baseline:
    case False{} _ _: None{}
    case True{} remaining Nil{}: Some{remaining}
    case True{} Nil{} _ <> _: None{}
    case True{} first <> rest expected <> tail: cachedInputSuffix(rest, tail, V.equal(first, expected))

def cachedInputFields(current: Maybe<&2, List<&2, V.Value>>, previous: Maybe<&2, List<&2, V.Value>>, response: List<&2, V.Value>, matched: Bool) -> Maybe<&2, List<&2, V.Value>>:
  match current previous:
    case Some{input} Some{baseline}: cachedInputSuffix(input, List.append(&2, V.Value, baseline, response), matched)
    case _ _: None{}

def getCachedWebSocketInputDelta(+body: R.Record<V.Value>, continuation: CachedWebSocketContinuationState) -> Maybe<&2, List<&2, V.Value>>:
  match continuation:
    case CachedWebSocketContinuationState{+previous, _, items}:
      cachedInputFields(responseInput(R.get(V.Value, body, "input")), responseInput(R.get(V.Value, previous, "input")), items, requestBodiesMatchExceptInput(body, previous))

def cachedWebSocketBody(+body: R.Record<V.Value>, continuation: CachedWebSocketContinuationState, delta: Maybe<&2, List<&2, V.Value>>) -> CachedWebSocketRequest:
  match continuation delta:
    case CachedWebSocketContinuationState{_, SNil{}, _} _: CachedWebSocketRequest{body, None{}}
    case _ None{}: CachedWebSocketRequest{body, None{}}
    case CachedWebSocketContinuationState{previous, +id, items} Some{input}:
      CachedWebSocketRequest{R.set(V.Value, R.set(V.Value, body, "previous_response_id", V.Text{id}), "input", V.ArrayValue{input}), Some{CachedWebSocketContinuationState{previous, id, items}}}

def buildCachedWebSocketRequestBody(+body: R.Record<V.Value>, continuation: Maybe<&2, CachedWebSocketContinuationState>) -> CachedWebSocketRequest:
  match continuation:
    case None{}: CachedWebSocketRequest{body, None{}}
    case Some{+value}: cachedWebSocketBody(body, value, getCachedWebSocketInputDelta(body, value))

# The cache owns idle resources. Taking an entry moves its connection into the
# request, leaving a reservation so concurrent requests use one-shot sockets.
type Policy is Data:
  Policy{idleMilliseconds: U32, maximumAgeMilliseconds: U32}

def defaults() -> Policy: Policy{300000, 3300000}

type Reservation is Data:
  Reservation{sessionId: String, accountId: String, generation: Nat}

type Entry<-Reason: Data> is Type:
  Entry{connection: Socket.Connection<Deadline.Cause<Reason>>, controller: Abort.AbortController<Deadline.Cause<Reason>>, runtime: Fetch.Runtime, createdAt: F64, expiresAt: F64, continuation: Maybe<&2, CachedWebSocketContinuationState>}

type Slot<-Reason: Data> is Type:
  Idle{reservation: Reservation, entry: Entry<Reason>}
  Busy{reservation: Reservation, controller: Maybe<&2, Abort.AbortController<Deadline.Cause<Reason>>>}

type State<-Reason: Data> is Type:
  State{slots: List<&1, Slot<Reason>>, nextGeneration: Nat}

type Pool<-Reason: Data> is Data:
  Pool{state: Ref.Ref<State<Reason>>, policy: Policy}

type Checkout<-Reason: Data> is Type:
  Reused{reservation: Reservation, entry: Entry<Reason>}
  Fresh{reservation: Maybe<&2, Reservation>}

type Selection<-Reason: Data> is Type:
  Selection{remaining: List<&1, Slot<Reason>>, expired: List<&1, Entry<Reason>>, found: Maybe<&1, Checkout<Reason>>}

type Place is Data:
  Other{}
  Expired{}
  Match{}

def sameKey(reservation: Reservation, session: String, account: String) -> Bool:
  match reservation:
    case Reservation{id, owner, _}: String.eq(id, session) && String.eq(owner, account)

def sameReservation(left: Reservation, right: Reservation) -> Bool:
  match left right:
    case Reservation{a, b, n} Reservation{c, d, m}: String.eq(a, c) && String.eq(b, d) && Nat.is_eq(n, m)

def placement(+now: F64, created: F64, expires: F64, policy: Policy, matched: Bool) -> Place:
  match policy:
    case Policy{_, maximum}: Bool.pick(Place, F.isAtLeast(F.compare(now, expires)) || F.isAtLeast(F.compare(F.subtract(now, created), F.fromU32(maximum))), Expired{}, Bool.pick(Place, matched, Match{}, Other{}))

def placeBusy(-Reason: Data, reservation: Reservation, controller: Maybe<&2, Abort.AbortController<Deadline.Cause<Reason>>>, matched: Bool, selection: Selection<Reason>) -> Selection<Reason>:
  match selection:
    case Selection{remaining, expired, None{}}:
      Selection{Busy{reservation, controller} <> remaining, expired, Bool.pick(Maybe<&1, Checkout<Reason>>, matched, Some{Fresh{None{}}}, None{})}
    case Selection{remaining, expired, found}: Selection{Busy{reservation, controller} <> remaining, expired, found}

def placeIdle(-Reason: Data, +reservation: Reservation, entry: Entry<Reason>, place: Place, selection: Selection<Reason>) -> Selection<Reason>:
  match place selection entry:
    case Expired{} Selection{remaining, expired, found} value: Selection{remaining, value <> expired, found}
    case Match{} Selection{remaining, expired, None{}} Entry{connection, +controller, runtime, created, expires, continuation}:
      Selection{Busy{reservation, Some{controller}} <> remaining, expired, Some{Reused{reservation, Entry{connection, controller, runtime, created, expires, continuation}}}}
    case _ Selection{remaining, expired, found} value: Selection{Idle{reservation, value} <> remaining, expired, found}

def selectSlot(-Reason: Data, slot: Slot<Reason>, +session: String, +account: String, +now: F64, policy: Policy, selection: Selection<Reason>) -> Selection<Reason>:
  match slot:
    case Busy{+reservation, controller}: placeBusy(Reason, reservation, controller, sameKey(reservation, session, account), selection)
    case Idle{+reservation, Entry{connection, controller, runtime, +created, +expires, continuation}}:
      placeIdle(Reason, reservation, Entry{connection, controller, runtime, created, expires, continuation}, placement(now, created, expires, policy, sameKey(reservation, session, account)), selection)

def selectAll(-Reason: Data, slots: List<&1, Slot<Reason>>, +session: String, +account: String, +now: F64, +policy: Policy, selection: Selection<Reason>) -> Selection<Reason>:
  match slots:
    case Nil{}: selection
    case first <> rest: selectAll(Reason, rest, session, account, now, policy, selectSlot(Reason, first, session, account, now, policy, selection))

def selected(-Reason: Data, +session: String, +account: String, +generation: Nat, selection: Selection<Reason>) -> State<Reason> & (Checkout<Reason> & List<&1, Entry<Reason>>):
  match selection:
    case Selection{remaining, expired, Some{found}}: (State{List.reverse(&1, Slot<Reason>, remaining), generation}, (found, expired))
    case Selection{remaining, expired, None{}}:
      +ticket = {Reservation{session, account, generation} : Reservation}
      (State{Busy{ticket, None{}} <> List.reverse(&1, Slot<Reason>, remaining), generation + 1n}, (Fresh{Some{ticket}}, expired))

def takeState(-Reason: Data, +session: String, +account: String, now: F64, policy: Policy, state: State<Reason>) -> State<Reason> & (Checkout<Reason> & List<&1, Entry<Reason>>):
  match state:
    case State{slots, generation}: selected(Reason, session, account, generation, selectAll(Reason, slots, session, account, now, policy, Selection{Nil{}, Nil{}, None{}}))

def disposeEntry(-Reason: Data, entry: Entry<Reason>) -> IO(Unit):
  match entry:
    case Entry{connection, controller, runtime, _, _, _}:
      do IO<Unit>:
        Socket.dispose(Deadline.Cause<Reason>, connection)
        Abort.dispose(Deadline.Cause<Reason>, controller)
        Fetch.dispose(runtime)

def disposeEntries(-Reason: Data, entries: List<&1, Entry<Reason>>) -> IO(Unit):
  match entries:
    case Nil{}: IO.pure(Unit, Unit{})
    case first <> rest:
      do IO<Unit>:
        disposeEntry(Reason, first)
        disposeEntries(Reason, rest)

def takeSelected(-Reason: Data, pair: Checkout<Reason> & List<&1, Entry<Reason>>) -> IO(Checkout<Reason>):
  match pair:
    case (checkout, expired):
      do IO<Checkout<Reason>>:
        disposeEntries(Reason, expired)
        return checkout

def take(-Reason: Data, pool: Pool<Reason>, session: String, account: String, now: F64) -> IO(Checkout<Reason>):
  match pool:
    case Pool{reference, policy}:
      do IO<Checkout<Reason>>:
        pair : Checkout<Reason> & List<&1, Entry<Reason>> <- Ref.modify(State<Reason>, Checkout<Reason> & List<&1, Entry<Reason>>, reference, state => takeState(Reason, session, account, now, policy, state))
        takeSelected(Reason, pair)

# Removing a reservation is identity-based: releasing an older request cannot
# replace an entry established after session invalidation.
type Removal<-Reason: Data> is Type:
  Removal{remaining: List<&1, Slot<Reason>>, reversed: List<&1, Slot<Reason>>, found: Bool}

def removeBusy(-Reason: Data, rest: List<&1, Slot<Reason>>, reversed: List<&1, Slot<Reason>>, found: Bool, ticket: Reservation, controller: Maybe<&2, Abort.AbortController<Deadline.Cause<Reason>>>, matches: Bool) -> Removal<Reason>:
  match matches:
    case True{}: Removal{rest, reversed, True{}}
    case False{}: Removal{rest, Busy{ticket, controller} <> reversed, found}

# Each transition consumes one remaining slot; removeBusy hides that decrease.
@unsafe
def removeReservation(-Reason: Data, +wanted: Reservation, removal: Removal<Reason>) -> List<&1, Slot<Reason>> & Bool:
  match removal:
    case Removal{Nil{}, reversed, found}: (List.reverse(&1, Slot<Reason>, reversed), found)
    case Removal{Busy{+ticket, controller} <> rest, reversed, found}: removeReservation(Reason, wanted, removeBusy(Reason, rest, reversed, found, ticket, controller, sameReservation(ticket, wanted)))
    case Removal{first <> rest, reversed, found}: removeReservation(Reason, wanted, Removal{rest, first <> reversed, found})

def putSelected(-Reason: Data, generation: Nat, +ticket: Reservation, entry: Entry<Reason>, keep: Bool, pair: List<&1, Slot<Reason>> & Bool) -> State<Reason> & Maybe<&1, Entry<Reason>>:
  match keep pair:
    case True{} Tuple{slots, True{}}: (State{Idle{ticket, entry} <> slots, generation}, None{})
    case _ Tuple{slots, _}: (State{slots, generation}, Some{entry})

def putState(-Reason: Data, +ticket: Reservation, entry: Entry<Reason>, keep: Bool, state: State<Reason>) -> State<Reason> & Maybe<&1, Entry<Reason>>:
  match state:
    case State{slots, generation}: putSelected(Reason, generation, ticket, entry, keep, removeReservation(Reason, ticket, Removal{slots, Nil{}, False{}}))

def disposeMaybeEntry(-Reason: Data, entry: Maybe<&1, Entry<Reason>>) -> IO(Unit):
  match entry:
    case None{}: IO.pure(Unit, Unit{})
    case Some{value}: disposeEntry(Reason, value)

def parkedEntry(-Reason: Data, policy: Policy, now: F64, entry: Entry<Reason>) -> Entry<Reason>:
  match policy entry:
    case Policy{duration, _} Entry{connection, controller, runtime, created, _, continuation}:
      Entry{connection, controller, runtime, created, F.add(now, F.fromU32(duration)), continuation}

def release(-Reason: Data, pool: Pool<Reason>, reservation: Maybe<&2, Reservation>, entry: Entry<Reason>, keep: Bool, now: F64) -> IO(Unit):
  match pool reservation:
    case _ None{}: disposeEntry(Reason, entry)
    case Pool{reference, policy} Some{ticket}:
      do IO<Unit>:
        discarded : Maybe<&1, Entry<Reason>> <- Ref.modify(State<Reason>, Maybe<&1, Entry<Reason>>, reference, state => putState(Reason, ticket, parkedEntry(Reason, policy, now, entry), keep, state))
        disposeMaybeEntry(Reason, discarded)

def trackedBusy(-Reason: Data, ticket: Reservation, controller: Maybe<&2, Abort.AbortController<Deadline.Cause<Reason>>>, previous: Maybe<&2, Abort.AbortController<Deadline.Cause<Reason>>>, matched: Bool) -> Slot<Reason>:
  Busy{ticket, Bool.pick(Maybe<&2, Abort.AbortController<Deadline.Cause<Reason>>>, matched, controller, previous)}

def trackedResult(-Reason: Data, slot: Slot<Reason>, matched: Bool, remaining: List<&1, Slot<Reason>> & Bool) -> List<&1, Slot<Reason>> & Bool:
  match remaining:
    case (slots, found): (slot <> slots, matched || found)

def trackSlots(-Reason: Data, slots: List<&1, Slot<Reason>>, +wanted: Reservation, +controller: Abort.AbortController<Deadline.Cause<Reason>>) -> List<&1, Slot<Reason>> & Bool:
  match slots:
    case Nil{}: (Nil{}, False{})
    case Busy{+ticket, previous} <> rest:
      +matched = {sameReservation(ticket, wanted) : Bool}
      trackedResult(Reason, trackedBusy(Reason, ticket, Some{controller}, previous, matched), matched, trackSlots(Reason, rest, wanted, controller))
    case value <> rest: trackedResult(Reason, value, False{}, trackSlots(Reason, rest, wanted, controller))

def trackedState(-Reason: Data, generation: Nat, result: List<&1, Slot<Reason>> & Bool) -> State<Reason> & Bool:
  match result:
    case (slots, found): (State{slots, generation}, found)

def trackState(-Reason: Data, wanted: Reservation, controller: Abort.AbortController<Deadline.Cause<Reason>>, state: State<Reason>) -> State<Reason> & Bool:
  match state:
    case State{slots, generation}: trackedState(Reason, generation, trackSlots(Reason, slots, wanted, controller))

def tracked(-Reason: Data, controller: Abort.AbortController<Deadline.Cause<Reason>>, found: Bool) -> IO(Unit):
  match found:
    case True{}: IO.pure(Unit, Unit{})
    case False{}:
      do IO<Unit>:
        won : Bool <- Abort.abort(Deadline.Cause<Reason>, controller, None{})
        return Unit{}

# A session may be invalidated during dial. Registering a removed reservation
# cancels that dial instead of allowing the old request to outlive its session.
def track(-Reason: Data, pool: Pool<Reason>, reservation: Maybe<&2, Reservation>, +controller: Abort.AbortController<Deadline.Cause<Reason>>) -> IO(Unit):
  match pool reservation:
    case _ None{}: IO.pure(Unit, Unit{})
    case Pool{reference, _} Some{ticket}:
      do IO<Unit>:
        found : Bool <- Ref.modify(State<Reason>, Bool, reference, state => trackState(Reason, ticket, controller, state))
        tracked(Reason, controller, found)

type Cleared<-Reason: Data> is Type:
  Cleared{remaining: List<&1, Slot<Reason>>, entries: List<&1, Entry<Reason>>, controllers: List<&2, Abort.AbortController<Deadline.Cause<Reason>>>}

def matchesSession(reservation: Reservation, session: Maybe<&2, String>) -> Bool:
  match reservation session:
    case _ None{}: True{}
    case Reservation{id, _, _} Some{value}: String.eq(id, value)

def clearPlaced(-Reason: Data, slot: Slot<Reason>, matched: Bool, state: Cleared<Reason>) -> Cleared<Reason>:
  match matched slot state:
    case False{} value Cleared{remaining, entries, controllers}: Cleared{value <> remaining, entries, controllers}
    case True{} Idle{_, entry} Cleared{remaining, entries, controllers}: Cleared{remaining, entry <> entries, controllers}
    case True{} Busy{_, None{}} state: state
    case True{} Busy{_, Some{controller}} Cleared{remaining, entries, controllers}: Cleared{remaining, entries, controller <> controllers}

def clearSlot(-Reason: Data, slot: Slot<Reason>, session: Maybe<&2, String>, state: Cleared<Reason>) -> Cleared<Reason>:
  match slot:
    case Idle{+ticket, entry}: clearPlaced(Reason, Idle{ticket, entry}, matchesSession(ticket, session), state)
    case Busy{+ticket, controller}: clearPlaced(Reason, Busy{ticket, controller}, matchesSession(ticket, session), state)

def clearSlots(-Reason: Data, slots: List<&1, Slot<Reason>>, +session: Maybe<&2, String>, state: Cleared<Reason>) -> Cleared<Reason>:
  match slots:
    case Nil{}: state
    case first <> rest: clearSlots(Reason, rest, session, clearSlot(Reason, first, session, state))

def clearedState(-Reason: Data, generation: Nat, cleared: Cleared<Reason>) -> State<Reason> & (List<&1, Entry<Reason>> & List<&2, Abort.AbortController<Deadline.Cause<Reason>>>):
  match cleared:
    case Cleared{remaining, entries, controllers}: (State{List.reverse(&1, Slot<Reason>, remaining), generation}, (entries, controllers))

def clearState(-Reason: Data, session: Maybe<&2, String>, state: State<Reason>) -> State<Reason> & (List<&1, Entry<Reason>> & List<&2, Abort.AbortController<Deadline.Cause<Reason>>>):
  match state:
    case State{slots, generation}: clearedState(Reason, generation, clearSlots(Reason, slots, session, Cleared{Nil{}, Nil{}, Nil{}}))

def abortControllers(-Reason: Data, controllers: List<&2, Abort.AbortController<Deadline.Cause<Reason>>>) -> IO(Unit):
  match controllers:
    case Nil{}: IO.pure(Unit, Unit{})
    case first <> rest:
      do IO<Unit>:
        won : Bool <- Abort.abort(Deadline.Cause<Reason>, first, None{})
        abortControllers(Reason, rest)

def closeCleared(-Reason: Data, pair: List<&1, Entry<Reason>> & List<&2, Abort.AbortController<Deadline.Cause<Reason>>>) -> IO(Unit):
  match pair:
    case (entries, controllers):
      do IO<Unit>:
        abortControllers(Reason, controllers)
        disposeEntries(Reason, entries)

def clear(-Reason: Data, pool: Pool<Reason>, session: Maybe<&2, String>) -> IO(Unit):
  match pool:
    case Pool{reference, _}:
      do IO<Unit>:
        discarded : List<&1, Entry<Reason>> & List<&2, Abort.AbortController<Deadline.Cause<Reason>>> <- Ref.modify(State<Reason>, List<&1, Entry<Reason>> & List<&2, Abort.AbortController<Deadline.Cause<Reason>>>, reference, state => clearState(Reason, session, state))
        closeCleared(Reason, discarded)

def create(-Reason: Data, policy: Policy) -> IO(Pool<Reason>):
  do IO<Pool<Reason>>:
    reference : Ref.Ref<State<Reason>> <- Ref.new(State<Reason>, State{Nil{}, 0n})
    return Pool{reference, policy}

def disposeSlots(-Reason: Data, slots: List<&1, Slot<Reason>>) -> IO(Unit):
  match slots:
    case Nil{}: IO.pure(Unit, Unit{})
    case Busy{_, _} <> rest: disposeSlots(Reason, rest)
    case Idle{_, entry} <> rest:
      do IO<Unit>:
        disposeEntry(Reason, entry)
        disposeSlots(Reason, rest)

def disposeState(-Reason: Data, state: State<Reason>) -> IO(Unit):
  match state:
    case State{slots, _}: disposeSlots(Reason, slots)

# Borrowers finish their requests before retiring the pool, as for native fetch.
def dispose(-Reason: Data, pool: Pool<Reason>) -> IO(Unit):
  match pool:
    case Pool{reference, _}:
      do IO<Unit>:
        state : State<Reason> <- Ref.dispose(State<Reason>, reference)
        disposeState(Reason, state)
