import Base
import ./json.bend as J
import ./native.bend as N
import ./util.bend as U
import ./http.bend as H

type Credential is Data:
  Credential{path: String, all: J.Json, access: String, refresh: String, expires: Nat, account: String}

def credential(+all: J.Json, path: String) -> Credential:
  +entry = J.get(all, "openai-codex")
  Credential{path, all, U.field(entry, "access"), U.field(entry, "refresh"), J.number(J.get(entry, "expires"), 0n), U.field(entry, "accountId")}

def fields_replace(xs: J.Json, +key: String, +value: J.Json) -> J.Json:
  match xs:
    case J.Field{+k, old, rest}: J.Field{k, Bool.pick(J.Json, String.eq(k, key), value, old), fields_replace(rest, key, value)}
    case _: J.End{}

def stored_entry(access: String, refresh: String, expires: Nat, account: String) -> J.Json:
  account_field = J.str_field("accountId", account, J.End{})
  expiry_field = {J.Field{"expires", J.Number{Nat.show(expires)}, account_field} : J.Json}
  J.Object{J.str_field("type", "oauth", J.str_field("access", access, J.str_field("refresh", refresh, expiry_field)))}


def persist(c: Credential, +fresh: J.Json, now: String) -> IO(Credential):
  match c:
    case Credential{+path, J.Object{all}, _, _, _, +account}:
      +expires = Nat.add(U.natural(now, 0n), Nat.mul(J.number(J.get(fresh, "expires_in"), 0n), U32.to_nat(1000)))
      +access = U.field(fresh, "access_token")
      +refresh = U.field(fresh, "refresh_token")
      +updated = {J.Object{fields_replace(all, "openai-codex", stored_entry(access, refresh, expires, account))} : J.Json}
      do IO<Credential>:
        ignored : String <- IO.try(String, N.atomic_write(path, J.encode(updated), 384n))
        return Credential{path, updated, access, refresh, expires, account}
    case _: IO.die(Credential, 1, "Invalid auth file")

def refresh_valid(ok: Bool, c: Credential, fresh: J.Json) -> IO(Credential):
  match ok:
    case False{}: IO.die(Credential, 1, "OpenAI OAuth refresh response is missing credentials")
    case True{}:
      do IO<Credential>:
        now : String <- N.epoch()
        persist(c, fresh, now)

def refresh_parsed(c: Credential, +fresh: J.Json) -> IO(Credential):
  refresh_valid(Bool.not(String.is_empty(U.field(fresh, "access_token"))) && Bool.not(String.is_empty(U.field(fresh, "refresh_token"))) && Nat.is_gt(J.number(J.get(fresh, "expires_in"), 0n), 0n), c, fresh)

def refresh_response(c: Credential, r: H.Response) -> IO(Credential):
  match r:
    case H.Response{200n, body}:
      do IO<Credential>:
        fresh : J.Json <- U.parsed(J.parse(body))
        refresh_parsed(c, fresh)
    case H.Response{status, body}: IO.die(Credential, 1, "OpenAI OAuth refresh failed (HTTP " ++ Nat.show(status) ++ "). Run pi /login.")

def refresh(+c: Credential) -> IO(Credential):
  match c:
    case Credential{_, _, _, token, _, _}:
      do IO<Credential>:
        response : H.Response <- H.fetch("https://auth.openai.com/oauth/token", "Content-Type: application/x-www-form-urlencoded", "grant_type=refresh_token&client_id=app_EMoamEEZ73f0CkXaXp7hrann&refresh_token=" ++ H.form(token))
        refresh_response(c, response)

def ensure_state(valid: Bool, expired: Bool, c: Credential) -> IO(Credential):
  match valid expired:
    case False{} _: IO.die(Credential, 1, "No OpenAI OAuth credentials in pi auth.json. Run pi /login.")
    case True{} True{}: refresh(c)
    case True{} False{}: IO.pure(Credential, c)

def ensure(+c: Credential, now: String) -> IO(Credential):
  match c:
    case Credential{_, _, access, _, expires, account}: ensure_state(Bool.not(String.is_empty(access)) && Bool.not(String.is_empty(account)), Nat.is_le(expires, Nat.add(U.natural(now, 0n), U32.to_nat(60000))), c)

def from_file(+path: String) -> IO(Credential):
  do IO<Credential>:
    all : J.Json <- U.read_json(path)
    now : String <- N.epoch()
    ensure(credential(all, path), now)

def load() -> IO(Credential):
  do IO<Credential>:
    home : String <- N.home()
    override : Result<&1, &1, U32 & String, String> <- IO.get_env("PI_CODING_AGENT_DIR")
    from_file(U.either_text(override, home ++ "/.pi/agent") ++ "/auth.json")

def headers(c: Credential, +session: String) -> String:
  match c:
    case Credential{_, _, access, _, _, account}: "Authorization: Bearer " ++ access ++ "\nchatgpt-account-id: " ++ account ++ "\noriginator: pi\nUser-Agent: pi-bend/0.1\nOpenAI-Beta: responses=experimental\naccept: text/event-stream\ncontent-type: application/json\nsession-id: " ++ session ++ "\nx-client-request-id: " ++ session
