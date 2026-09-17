import Base
import ./json.bend as J
import ./native.bend as N
import ./util.bend as U

type Session is Data:
  Session{file: String, id: String, leaf: String, history: J.Json}

def write_line(file: String, text: String) -> IO(Unit):
  match file:
    case SNil{}: IO.pure(Unit, Unit{})
    case SCon{c, t}:
      do IO<Unit>:
        ignored : String <- IO.try(String, N.append(SCon{c, t}, text ++ "\n"))
        IO.pure(Unit, Unit{})

def header(id: String, timestamp: String, cwd: String) -> J.Json:
  fields = J.str_field("id", id, J.str_field("timestamp", timestamp, J.str_field("cwd", cwd, J.End{})))
  J.Object{J.str_field("type", "session", J.Field{"version", J.Number{"3"}, fields})}

def entry(kind: String, id: String, +parent: String, timestamp: String, payload: J.Json) -> J.Json:
  fields = J.str_field("timestamp", timestamp, payload)
  linked = {J.Field{"parentId", Bool.pick(J.Json, String.is_empty(parent), J.Null{}, J.Text{parent}), fields} : J.Json}
  J.Object{J.str_field("type", kind, J.str_field("id", id, linked))}

def create_at(+file: String, +id: String, cwd: String) -> IO(Session):
  do IO<Session>:
    now : String <- N.timestamp()
    write_line(file, J.encode(header(id, now, cwd)))
    return Session{file, id, "", J.End{}}

def scan_entry(+event: J.Json, session: Session) -> Session:
  match session:
    case Session{file, +id, +leaf, +history}:
      +kind = U.field(event, "type")
      Session{file, Bool.pick(String, String.eq(kind, "session"), U.field(event, "id"), id), Bool.pick(String, String.eq(kind, "session") || String.is_empty(U.field(event, "id")), leaf, U.field(event, "id")), Bool.pick(J.Json, String.eq(U.field(event, "customType"), "pi-bend.transcript"), J.array(J.get(event, "data")), history)}

def scan_lines(lines: List<&2, String>, session: Session) -> Session:
  match lines:
    case Nil{}: session
    case line <> rest: scan_lines(rest, scan_entry(J.or_null(J.parse(line)), session))

def open_result(result: Result<&1, &1, U32 & String, String>, +file: String, id: String, cwd: String) -> IO(Session):
  match result:
    case Done{content}: IO.pure(Session, scan_lines(String.split(content, '\n'), Session{file, id, "", J.End{}}))
    case Fail{(2, message)}: create_at(file, id, cwd)
    case Fail{(code, message)}: IO.die(Session, code, message)

def open_at(+file: String, id: String, cwd: String) -> IO(Session):
  do IO<Session>:
    result : Result<&1, &1, U32 & String, String> <- N.read(file)
    open_result(result, file, id, cwd)

def open(no_session: Bool, file: String, +id: String, +cwd: String) -> IO(Session):
  match no_session file:
    case True{} _: IO.pure(Session, Session{"", id, "", J.End{}})
    case False{} SNil{}:
      do IO<Session>:
        home : String <- N.home()
        create_at(home ++ "/.pi-bend/agent/sessions/" ++ id ++ ".jsonl", id, cwd)
    case False{} SCon{c, t}: open_at(SCon{c, t}, id, cwd)

def append_id(+file: String, id: String, leaf: String, +next: String, now: String, kind: String, payload: J.Json, history: J.Json) -> IO(Session):
  do IO<Session>:
    write_line(file, J.encode(entry(kind, next, leaf, now, payload)))
    return Session{file, id, next, history}

def append(session: Session, kind: String, payload: J.Json, history: J.Json) -> IO(Session):
  match session:
    case Session{+file, id, leaf, _}:
      do IO<Session>:
        next : String <- N.uuid()
        now : String <- N.timestamp()
        append_id(file, id, leaf, next, now, kind, payload, history)

def snapshot(session: Session, +history: J.Json) -> IO(Session):
  append(session, "custom", J.str_field("customType", "pi-bend.transcript", J.Field{"data", J.Array{history}, J.End{}}), history)

def get_history(session: Session) -> J.Json:
  match session:
    case Session{_, _, _, history}: history

def get_id(session: Session) -> String:
  match session:
    case Session{_, id, _, _}: id

def append_message(+session: Session, value: J.Json) -> IO(Session):
  append(session, "message", J.Field{"message", value, J.End{}}, get_history(session))

def append_messages(items: J.Json, session: Session) -> IO(Session):
  match items:
    case J.Item{value, rest}:
      do IO<Session>:
        saved : Session <- append_message(session, value)
        append_messages(rest, saved)
    case _: IO.pure(Session, session)
