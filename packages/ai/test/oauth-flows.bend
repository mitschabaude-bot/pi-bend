import Base
import ../src/auth/types.bend as Auth
import ../src/types.bend as T
import ../src/auth/oauth/xai.bend as Xai
import ../src/auth/oauth/meta.bend as Meta
import ../src/auth/oauth/kimi-coding.bend as Kimi
import ../src/auth/oauth/github-copilot.bend as Copilot
import ../src/auth/oauth/openrouter.bend as OpenRouter
import ../src/auth/oauth/anthropic.bend as AnthropicOAuth
import ../src/auth/oauth/openai-codex.bend as CodexOAuth
import ../src/auth/oauth/radius.bend as RadiusOAuth
import ../src/auth/oauth/oauth-http.bend as H
import ../src/models.bend as Models
import ../src/auth/resolve.bend as Resolve
import ../src/auth/credential-store.bend as CredentialStore
import ../src/providers/github-copilot.bend as CopilotProvider
import ../src/api/credential-http.bend as Http
import ../../runtime/src/deferred.bend as Deferred
import ../../runtime/src/http-message.bend as Headers
import ../src/utils/json.bend as Wire
import ../src/utils/schema-json.bend as Convert
import ./anthropic-messages-client.bend as TestClient
import ../../runtime/src/abort.bend as Abort
import ../../runtime/src/callback.bend as C
import ../../runtime/src/date.bend as Date
import ../../runtime/src/f64.bend as F
import ../../runtime/src/fetch.bend as Fetch
import ../../runtime/src/filesystem.bend as FS
import ../../runtime/src/json.bend as Decode
import ../../runtime/src/record.bend as R
import ../../runtime/src/ref.bend as Ref
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/url.bend as URL
import ../../runtime/src/utf8.bend as Utf8
import ../../runtime/src/string.bend as Strings
import ../../runtime/test/utf8-runner.bend as Text

# The OAuth flows of packages/ai/src/auth/oauth against the loopback server of
# tests/oauth_flows_check.py (tests/oauth_flows_reference.ts runs pinned
# pi-mono's the same way). Upstream's tests stub the global fetch; here every
# request goes through a fetch that rewrites `https://<host><path>` to
# `<base>/<host><path>`, so the server sees each provider URL. Arguments: the
# base URL and a JSON case file
#   {flow, action: "login" | "refresh" | "toAuth" | "describe" | "available"
#    | "modelsLogin", credential?,
#    prompts?: [answer], abortOnDeviceCode?, abortOnAuthUrl?, pendingPrompt?
#    (prompts after the listed answers stay pending),
#    watchPromptSignal?, promptError?, callbackCode?, secondCallbackMs?,
#    preAborted?}
# Output (code-point encoded JSON): "S <start ms>", "N <event>" per notify,
# "P <prompt>" per prompt, then "C <credential>", "A <auth>", "D <facts>" or
# "E <error message>". The Copilot provider cases run through a Models
# collection over an InMemoryCredentialStore (github-copilot-oauth.test.ts):
# "available" stores `credential` and prints the ids getAvailable returns
# ("V <ids>"); "modelsLogin" logs in through Models.login and prints the
# credential, then the stored one ("T <credential or null>").
# Loopback-callback flows (OpenRouter) add the browser:
# on the auth_url event it GETs `callback_url` with `code=<callbackCode>`
# ("B <status>"), optionally again after secondCallbackMs ("B2 <status>");
# `{callback}`, `{redirect_uri}` and `{state}` in a prompt answer stand for
# the auth URL's parameters; a pending prompt waits for its signal and
# watchPromptSignal watches an answered prompt's ("M <aborted>");
# abortOnAuthUrl aborts the login and afterwards probes the callback URL
# ("R <status>" or "R refused").

# Rewriting fetch
# ---------------
type Rewrite is Data:
  Rewrite{fetch: Fetch.Fetch(Unit), base: String, url: URL.Context}

def withoutScheme(text: String) -> String:
  match text:
    case SCon{'h', SCon{'t', SCon{'t', SCon{'p', SCon{'s', SCon{':', SCon{'/', SCon{'/', rest}}}}}}}}: rest
    case SCon{'h', SCon{'t', SCon{'t', SCon{'p', SCon{':', SCon{'/', SCon{'/', rest}}}}}}}: rest
    case other: other

def rewrittenInput(input: Fetch.Input<Unit>, parsed: Result<&2, &2, URL.Error, URL.URL>) -> Fetch.Input<Unit>:
  match input parsed:
    case Fetch.Input{_, method, headers, body, signal} Done{url}: Fetch.Input{url, method, headers, body, signal}
    case other _: other

def rewritten(rewrite: Rewrite, input: Fetch.Input<Unit>) -> IO(Fetch.Result_(Unit)):
  match rewrite input:
    case Rewrite{fetch, base, context} Fetch.Input{+url, method, headers, body, signal}:
      C.call(Fetch.Input<Unit>, Fetch.Result_(Unit), fetch, rewrittenInput(Fetch.Input{url, method, headers, body, signal}, URL.parse(context, base ++ "/" ++ withoutScheme(URL.href(url)))))

# JSON output
# -----------
def J() -> Data: V.Value

def jsonText(value: V.Value) -> String: Maybe.default(&2, String, Wire.stringify(Convert.toJson(value)), "null")

def emit(+tag: String, value: V.Value) -> IO(Unit): IO.print(tag ++ " " ++ Text.showText(jsonText(value)))

def prop(name: String, value: V.Value) -> R.Property<V.Value>: R.Property{name, value}

def optionalNumber(name: String, value: Maybe<&2, F64>, rest: List<&2, R.Property<V.Value>>) -> List<&2, R.Property<V.Value>>:
  match value:
    case Some{number}: prop(name, V.Number{number}) <> rest
    case None{}: rest

def optionalText(name: String, value: Maybe<&2, String>, rest: List<&2, R.Property<V.Value>>) -> List<&2, R.Property<V.Value>>:
  match value:
    case Some{text}: prop(name, V.Text{text}) <> rest
    case None{}: rest

def selectOptionJson(option: Auth.AuthSelectOption) -> V.Value:
  match option:
    case Auth.AuthSelectOption{id,label,description}: V.ObjectValue{R.Record{prop("id",V.Text{id}) <> prop("label",V.Text{label}) <> optionalText("description",description,Nil{})}}

def selectOptions(options: List<&2,Auth.AuthSelectOption>) -> List<&2,V.Value>:
  match options:
    case Nil{}: Nil{}
    case option <> rest: selectOptionJson(option) <> selectOptions(rest)

def eventJson(event: Auth.AuthEvent) -> V.Value:
  match event:
    case Auth.InfoEvent{message, _}: V.ObjectValue{R.Record{[prop("type", V.Text{"info"}), prop("message", V.Text{message})]}}
    case Auth.AuthUrlEvent{url, instructions}: V.ObjectValue{R.Record{prop("type", V.Text{"auth_url"}) <> prop("url", V.Text{url}) <> optionalText("instructions", instructions, Nil{})}}
    case Auth.DeviceCodeEvent{userCode, uri, interval, expires}: V.ObjectValue{R.Record{prop("type", V.Text{"device_code"}) <> prop("userCode", V.Text{userCode}) <> prop("verificationUri", V.Text{uri}) <> optionalNumber("intervalSeconds", interval, optionalNumber("expiresInSeconds", expires, Nil{}))}}
    case Auth.ProgressEvent{message}: V.ObjectValue{R.Record{[prop("type", V.Text{"progress"}), prop("message", V.Text{message})]}}

def credentialJson(credential: Auth.Credential) -> V.Value:
  match credential:
    case Auth.OAuthCredential{refresh, access, expires, R.Record{extra}}: V.ObjectValue{R.Record{prop("type", V.Text{"oauth"}) <> prop("access", V.Text{access}) <> prop("refresh", V.Text{refresh}) <> prop("expires", V.Number{expires}) <> extra}}
    case Auth.ApiKeyCredential{key, _}: V.ObjectValue{R.Record{prop("type", V.Text{"api_key"}) <> optionalText("key", key, Nil{})}}

def headerProps(values: List<&2, R.Property<T.Nullable<String>>>) -> List<&2, R.Property<V.Value>>:
  match values:
    case Nil{}: Nil{}
    case R.Property{name, T.PresentValue{value}} <> rest: prop(name, V.Text{value}) <> headerProps(rest)
    case R.Property{name, _} <> rest: prop(name, V.Null{}) <> headerProps(rest)

def optionalHeaders(headers: Maybe<&2, T.ProviderHeaders()>, rest: List<&2, R.Property<V.Value>>) -> List<&2, R.Property<V.Value>>:
  match headers:
    case Some{R.Record{values}}: prop("headers", V.ObjectValue{R.Record{headerProps(values)}}) <> rest
    case None{}: rest

def authJson(auth: Auth.ModelAuth) -> V.Value:
  match auth:
    case Auth.ModelAuth{apiKey, headers, baseUrl}: V.ObjectValue{R.Record{optionalText("apiKey", apiKey, optionalHeaders(headers, optionalText("baseUrl", baseUrl, Nil{})))}}

# Interaction
# -----------
type Browser is Data:
  Browser{raw: H.Flow, authUrl: Ref.Ref<String>, code: Maybe<&2, String>, secondMs: Maybe<&2, U32>, abortOnAuthUrl: Bool, pending: Bool, watch: Bool, promptError: Maybe<&2, String>, promptAborted: Ref.Ref<Bool>, first: Deferred.Deferred<Maybe<&2, U32>>, second: Deferred.Deferred<Maybe<&2, U32>>}

type Interaction is Data:
  Interaction{answers: Ref.Ref<List<&2, String>>, controller: Abort.AbortController<Unit>, abortOnDeviceCode: Bool, browser: Browser}

def popped(answers: List<&2, String>) -> List<&2, String> & Maybe<&2, String>:
  match answers:
    case Nil{}: (Nil{}, None{})
    case first <> rest: (rest, Some{first})

def promptJson(prompt: Auth.AuthPrompt) -> V.Value:
  match prompt:
    case Auth.TextPrompt{message, placeholder, _}: V.ObjectValue{R.Record{prop("type", V.Text{"text"}) <> prop("message", V.Text{message}) <> optionalText("placeholder", placeholder, Nil{})}}
    case Auth.SecretPrompt{message, placeholder, _}: V.ObjectValue{R.Record{prop("type", V.Text{"secret"}) <> prop("message", V.Text{message}) <> optionalText("placeholder", placeholder, Nil{})}}
    case Auth.SelectPrompt{message, options, _}: V.ObjectValue{R.Record{[prop("type", V.Text{"select"}), prop("message", V.Text{message}), prop("options",V.ArrayValue{selectOptions(options)})]}}
    case Auth.ManualCodePrompt{message, placeholder, _}: V.ObjectValue{R.Record{prop("type", V.Text{"manual_code"}) <> prop("message", V.Text{message}) <> optionalText("placeholder", placeholder, Nil{})}}

# In an answer, `{callback}`, `{redirect_uri}` and `{state}` stand for the
# auth URL's callback_url, redirect_uri and state parameters.
def paramOf(parsed: Result<&2, &2, URL.Error, URL.URL>, name: String) -> String:
  match parsed:
    case Done{URL.URL{_, _, _, _, _, _, Some{query}, _}}: Maybe.default(&2, String, URL.get(URL.parseSearchParams(query), name), "")
    case _: ""

def authParam(context: URL.Context, authUrl: String, name: String) -> String: paramOf(URL.parse(context, authUrl), name)

def substituted(+context: URL.Context, text: String, +authUrl: String) -> String:
  Strings.replaceAll(Strings.replaceAll(Strings.replaceAll(text, "{callback}", authParam(context, authUrl, "callback_url")), "{redirect_uri}", authParam(context, authUrl, "redirect_uri")), "{state}", authParam(context, authUrl, "state"))

def answered(context: URL.Context, answer: Maybe<&2, String>, authUrl: String) -> Result<&2, &2, String, String>:
  match answer:
    case Some{text}: Done{substituted(context, text, authUrl)}
    case None{}: Fail{"Unexpected prompt"}

def promptSignalOf(prompt: Auth.AuthPrompt) -> Maybe<&2, Abort.AbortSignal<Unit>>:
  match prompt:
    case Auth.TextPrompt{_, _, signal}: signal
    case Auth.SecretPrompt{_, _, signal}: signal
    case Auth.SelectPrompt{_, _, signal}: signal
    case Auth.ManualCodePrompt{_, _, signal}: signal

# Upstream checks `prompt.signal.aborted` after login; the flow disposes the
# signal when it returns, so the driver observes it and records the abort.
def recordAbort(record: Ref.Ref<Bool>, observed: Maybe<&2, Abort.AbortReason<Unit>>) -> IO(Unit):
  match observed:
    case Some{_}: Ref.write(Bool, record, True{})
    case None{}: IO.pure(Unit, Unit{})

def awaitAbort(record: Ref.Ref<Bool>, observation: Deferred.Observation<Abort.AbortReason<Unit>>) -> IO(Unit):
  match observation:
    case Deferred.Observation{ticket, _}:
      do IO<Unit>:
        observed : Maybe<&2, Abort.AbortReason<Unit>> <- Deferred.wait(Maybe<&2, Abort.AbortReason<Unit>>, ticket)
        recordAbort(record, observed)

# upstream's `new Promise(() => {})`: settles only through the prompt signal.
def pendingUntilAborted(record: Ref.Ref<Bool>, signal: Maybe<&2, Abort.AbortSignal<Unit>>) -> IO(Result<&2, &2, String, String>):
  match signal:
    case None{}: IO.die(Result<&2, &2, String, String>, 1, "a pending prompt without a signal never settles")
    case Some{found}:
      do IO<Result<&2, &2, String, String>>:
        observation : Deferred.Observation<Abort.AbortReason<Unit>> <- Abort.observe(Unit, found)
        awaitAbort(record, observation)
        return Fail{"Prompt aborted"}

def watched(watch: Bool, record: Ref.Ref<Bool>, signal: Maybe<&2, Abort.AbortSignal<Unit>>) -> IO(Unit):
  match watch signal:
    case True{} Some{found}:
      do IO<Unit>:
        observation : Deferred.Observation<Abort.AbortReason<Unit>> <- Abort.observe(Unit, found)
        task : Chan(Unit) <- IO.fork(Unit, awaitAbort(record, observation))
        return Unit{}
    case _ _: IO.pure(Unit, Unit{})

# A pending prompt case answers its listed prompts first (the Codex method
# select), then leaves the rest pending.
def answeredOrPending(context: URL.Context, answer: Maybe<&2, String>, authUrl: String, record: Ref.Ref<Bool>, signal: Maybe<&2, Abort.AbortSignal<Unit>>) -> IO(Result<&2, &2, String, String>):
  match answer:
    case Some{text}: IO.pure(Result<&2, &2, String, String>, Done{substituted(context, text, authUrl)})
    case None{}: pendingUntilAborted(record, signal)

def promptedWith(answers: Ref.Ref<List<&2, String>>, browser: Browser, +prompt: Auth.AuthPrompt) -> IO(Result<&2, &2, String, String>):
  match browser:
    case Browser{raw, authUrl, _, _, _, True{}, _, _, promptAborted, _, _}:
      do IO<Result<&2, &2, String, String>>:
        answer : Maybe<&2, String> <- Ref.modify(List<&2, String>, Maybe<&2, String>, answers, popped)
        url : String <- Ref.read(String, authUrl)
        answeredOrPending(H.flowContext(raw), answer, url, promptAborted, promptSignalOf(prompt))
    case Browser{_, _, _, _, _, False{}, watch, Some{message}, promptAborted, _, _}:
      do IO<Result<&2, &2, String, String>>:
        watched(watch, promptAborted, promptSignalOf(prompt))
        return Fail{message}
    case Browser{raw, authUrl, _, _, _, False{}, watch, None{}, promptAborted, _, _}:
      do IO<Result<&2, &2, String, String>>:
        watched(watch, promptAborted, promptSignalOf(prompt))
        answer : Maybe<&2, String> <- Ref.modify(List<&2, String>, Maybe<&2, String>, answers, popped)
        url : String <- Ref.read(String, authUrl)
        return answered(H.flowContext(raw), answer, url)

def promptedShared(state: Interaction, +prompt: Auth.AuthPrompt) -> IO(Result<&2, &2, String, String>):
  match state:
    case Interaction{answers, _, _, browser}:
      do IO<Result<&2, &2, String, String>>:
        emit("P", promptJson(prompt))
        promptedWith(answers, browser, prompt)

def prompted(state: Interaction, prompt: Auth.AuthPrompt) -> IO(Result<&2, &2, String, String>): promptedShared(state, prompt)

def isDeviceCode(event: Auth.AuthEvent) -> Bool:
  match event:
    case Auth.DeviceCodeEvent{_, _, _, _}: True{}
    case _: False{}

def abortIf(hit: Bool, controller: Abort.AbortController<Unit>) -> IO(Unit):
  match hit:
    case False{}: IO.pure(Unit, Unit{})
    case True{}:
      do IO<Unit>:
        won : Bool <- Abort.abort(Unit, controller, None{})
        return Unit{}

def abortLater(controller: Abort.AbortController<Unit>) -> IO(Unit):
  do IO<Unit>:
    IO.sleep(200)
    abortIf(True{},controller)

def scheduleAbort(hit: Bool, controller: Abort.AbortController<Unit>) -> IO(Unit):
  match hit:
    case False{}: IO.pure(Unit,Unit{})
    case True{}:
      do IO<Unit>:
        task : Chan(Unit) <- IO.fork(Unit,abortLater(controller))
        return Unit{}

# The browser
# -----------
def statusOf(result: Result<&2, &2, Http.Failure, H.Reply>) -> Maybe<&2, U32>:
  match result:
    case Done{reply}: Some{H.replyStatus(reply)}
    case Fail{_}: None{}

def visit(raw: H.Flow, url: String) -> IO(Maybe<&2, U32>):
  do IO<Maybe<&2, U32>>:
    +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    result : Result<&2, &2, Http.Failure, H.Reply> <- H.send(raw, Abort.signal(Unit, controller), "GET", url, Nil{}, Headers.Absent{}, 30000)
    Abort.dispose(Unit, controller)
    return statusOf(result)

def visitInto(raw: H.Flow, url: String, delay: U32, into: Deferred.Deferred<Maybe<&2, U32>>) -> IO(Unit):
  do IO<Unit>:
    IO.sleep(delay)
    status : Maybe<&2, U32> <- visit(raw, url)
    done : Bool <- Deferred.resolve(Maybe<&2, U32>, into, status)
    return Unit{}

def secondVisit(raw: H.Flow, url: String, delay: Maybe<&2, U32>, into: Deferred.Deferred<Maybe<&2, U32>>) -> IO(Unit):
  match delay:
    case None{}: IO.pure(Unit, Unit{})
    case Some{ms}:
      do IO<Unit>:
        task : Chan(Unit) <- IO.fork(Unit, visitInto(raw, url, ms, into))
        return Unit{}

def visited(code: Maybe<&2, String>, raw: H.Flow, target: String, first: Deferred.Deferred<Maybe<&2, U32>>) -> IO(Unit):
  match code:
    case None{}: IO.pure(Unit, Unit{})
    case Some{_}:
      do IO<Unit>:
        task : Chan(Unit) <- IO.fork(Unit, visitInto(raw, target, 0, first))
        return Unit{}

def browse(browser: Browser, controller: Abort.AbortController<Unit>, +url: String) -> IO(Unit):
  match browser:
    case Browser{+raw, authUrl, +code, secondMs, abortOnAuthUrl, _, _, _, _, first, second}:
      +target = authParam(H.flowContext(raw), url, "callback_url") ++ Maybe.default(&2, String, Maybe.map(&2, String, String, value => "?code=" ++ value, code), "")
      do IO<Unit>:
        Ref.write(String, authUrl, url)
        abortIf(abortOnAuthUrl, controller)
        visited(code, raw, target, first)
        secondVisit(raw, target, secondMs, second)

def browsed(event: Auth.AuthEvent, browser: Browser, controller: Abort.AbortController<Unit>) -> IO(Unit):
  match event:
    case Auth.AuthUrlEvent{url, _}: browse(browser, controller, url)
    case _: IO.pure(Unit, Unit{})

def notifiedShared(state: Interaction, +event: Auth.AuthEvent) -> IO(Unit):
  match state:
    case Interaction{_, +controller, abortOnDeviceCode, browser}:
      do IO<Unit>:
        emit("N", eventJson(event))
        scheduleAbort(abortOnDeviceCode && isDeviceCode(event),controller)
        browsed(event, browser, controller)

def notified(state: Interaction, event: Auth.AuthEvent) -> IO(Unit): notifiedShared(state, event)

# Cases
# -----
def field(value: V.Value, name: String) -> Maybe<&2, V.Value>:
  match value:
    case V.ObjectValue{fields}: R.get(V.Value, fields, name)
    case _: None{}

def textOf(value: Maybe<&2, V.Value>) -> Maybe<&2, String>:
  match value:
    case Some{V.Text{text}}: Some{text}
    case _: None{}

def flagOf(value: Maybe<&2, V.Value>) -> Bool:
  match value:
    case Some{V.Boolean{flag}}: flag
    case _: False{}

def textItems(items: List<&2, V.Value>) -> List<&2, String>:
  match items:
    case Nil{}: Nil{}
    case V.Text{text} <> rest: text <> textItems(rest)
    case _ <> rest: textItems(rest)

def textList(values: Maybe<&2, V.Value>) -> List<&2, String>:
  match values:
    case Some{V.ArrayValue{items}}: textItems(items)
    case _: Nil{}

def withoutKnown(fields: List<&2, R.Property<V.Value>>) -> List<&2, R.Property<V.Value>>:
  match fields:
    case Nil{}: Nil{}
    case R.Property{+name, value} <> rest:
      +tail = withoutKnown(rest)
      Bool.pick(List<&2, R.Property<V.Value>>, String.eq(name, "type") || String.eq(name, "access") || String.eq(name, "refresh") || String.eq(name, "expires"), tail, R.Property{name, value} <> tail)

def numberOf(value: Maybe<&2, V.Value>) -> F64:
  match value:
    case Some{V.Number{number}}: number
    case _: F.fromU32(0)

def credentialOf(value: Maybe<&2, V.Value>) -> Auth.Credential:
  match value:
    case Some{V.ObjectValue{R.Record{+fields}}}: Auth.OAuthCredential{Maybe.default(&2, String, textOf(R.get(V.Value, R.Record{fields}, "refresh")), ""), Maybe.default(&2, String, textOf(R.get(V.Value, R.Record{fields}, "access")), ""), numberOf(R.get(V.Value, R.Record{fields}, "expires")), R.Record{withoutKnown(fields)}}
    case _: Auth.OAuthCredential{"", "", F.fromU32(0), R.new(V.Value)}

def flowOf(+name: String, fetch: Fetch.Fetch(Unit), url: URL.Context, codexExpires: Maybe<&2,F64>) -> IO(Maybe<&2, Auth.OAuthAuth>):
  match name:
    case "xai":
      do IO<Maybe<&2, Auth.OAuthAuth>>:
        oauth : Auth.OAuthAuth <- Xai.xaiOAuth(fetch, url)
        return Some{oauth}
    case "meta":
      do IO<Maybe<&2, Auth.OAuthAuth>>:
        oauth : Auth.OAuthAuth <- Meta.metaOAuth(fetch, url)
        return Some{oauth}
    case "kimi":
      do IO<Maybe<&2, Auth.OAuthAuth>>:
        oauth : Auth.OAuthAuth <- Kimi.kimiCodingOAuth(fetch, url)
        return Some{oauth}
    case "copilot":
      do IO<Maybe<&2, Auth.OAuthAuth>>:
        oauth : Auth.OAuthAuth <- Copilot.githubCopilotOAuth(fetch, url)
        return Some{oauth}
    case "codex":
      do IO<Maybe<&2, Auth.OAuthAuth>>:
        +expires : U32 = Maybe.default(&2,U32,Maybe.map(&2,F64,U32,value => F64.to_u32(value),codexExpires),CodexOAuth.DEVICE_EXPIRES_MS())
        oauth : Auth.OAuthAuth <- CodexOAuth.openaiCodexOAuthConfigured(fetch,url,CodexOAuth.deviceEndpoints(),expires)
        return Some{oauth}
    case "anthropic":
      do IO<Maybe<&2, Auth.OAuthAuth>>:
        oauth : Auth.OAuthAuth <- AnthropicOAuth.anthropicOAuth(fetch, url)
        return Some{oauth}
    case "radius":
      do IO<Maybe<&2, Auth.OAuthAuth>>:
        oauth : Auth.OAuthAuth <- RadiusOAuth.createRadiusOAuth("Radius", "https://radius.pi.dev", fetch, url)
        return Some{oauth}
    case "openrouter":
      do IO<Maybe<&2, Auth.OAuthAuth>>:
        oauth : Auth.OAuthAuth <- OpenRouter.openRouterOAuth(fetch, url)
        return Some{oauth}
    case _: IO.pure(Maybe<&2, Auth.OAuthAuth>, None{})

def loginResult(result: Auth.LoginOutcome()) -> IO(Unit):
  match result:
    case Done{credential}: emit("C", credentialJson(credential))
    case Fail{message}: IO.print("E " ++ Text.showText(message))

def authResult(result: Result<&2, &2, String, Auth.ModelAuth>) -> IO(Unit):
  match result:
    case Done{auth}: emit("A", authJson(auth))
    case Fail{message}: IO.print("E " ++ Text.showText(message))

def describe(oauth: Auth.OAuthAuth) -> IO(Unit):
  match oauth:
    case Auth.OAuthAuth{name, subscription, label, _, _, _}: emit("D", V.ObjectValue{R.Record{prop("name", V.Text{name}) <> prop("isSubscription", V.Boolean{subscription}) <> optionalText("loginLabel", label, Nil{})}})

def statusText(status: Maybe<&2, U32>) -> String:
  match status:
    case Some{code}: U32.show(code)
    case None{}: "refused"

def awaited(+tag: String, wanted: Bool, into: Deferred.Deferred<Maybe<&2, U32>>) -> IO(Unit):
  match wanted:
    case False{}: IO.pure(Unit, Unit{})
    case True{}:
      do IO<Unit>:
        status : Maybe<&2, U32> <- Deferred.result(Maybe<&2, U32>, into)
        IO.print(tag ++ " " ++ statusText(status))

# A watched signal is aborted as the flow returns; its observer may record it
# a moment later.
def settledAbort(+record: Ref.Ref<Bool>, tries: Nat) -> IO(Bool):
  match tries:
    case 0n: Ref.read(Bool, record)
    case 1n+rest:
      do IO<Bool>:
        aborted : Bool <- Ref.read(Bool, record)
        Bool.pick(IO(Bool), aborted, IO.pure(Bool, True{}), do IO<Bool>:
          IO.sleep(20)
          settledAbort(record, rest))

def pendingReport(reported: Bool, promptAborted: Ref.Ref<Bool>) -> IO(Unit):
  match reported:
    case False{}: IO.pure(Unit, Unit{})
    case True{}:
      do IO<Unit>:
        aborted : Bool <- settledAbort(promptAborted, 50n)
        IO.print("M " ++ Bool.pick(String, aborted, "true", "false"))

def probe(wanted: Bool, +raw: H.Flow, authUrl: Ref.Ref<String>) -> IO(Unit):
  match wanted:
    case False{}: IO.pure(Unit, Unit{})
    case True{}:
      do IO<Unit>:
        url : String <- Ref.read(String, authUrl)
        status : Maybe<&2, U32> <- visit(raw, authParam(H.flowContext(raw), url, "callback_url"))
        IO.print("R " ++ statusText(status))

def isSome(value: Maybe<&2, U32>) -> Bool:
  match value:
    case Some{_}: True{}
    case None{}: False{}

def isSomeText(value: Maybe<&2, String>) -> Bool:
  match value:
    case Some{_}: True{}
    case None{}: False{}

def reported(interaction: Interaction) -> IO(Unit):
  match interaction:
    case Interaction{_, _, _, Browser{raw, authUrl, code, secondMs, abortOnAuthUrl, pending, watch, _, promptAborted, first, second}}:
      do IO<Unit>:
        awaited("B", isSomeText(code), first)
        awaited("B2", isSome(secondMs), second)
        pendingReport(pending || watch, promptAborted)
        probe(abortOnAuthUrl, raw, authUrl)

# The Copilot provider over a Models collection
# ---------------------------------------------

def storedAs(credential: Auth.Credential, old: Maybe<&2, Auth.Credential>) -> IO(Auth.StoreResult(Maybe<&2, Auth.Credential>)):
  IO.pure(Auth.StoreResult(Maybe<&2, Auth.Credential>), Done{Some{credential}})

def copilotModels(oauth: Auth.OAuthAuth, store: Auth.CredentialStore) -> IO(Models.Models):
  do IO<Models.Models>:
    +models : Models.Models <- Models.createModels(Models.CreateModelsOptions{Some{store}, None{}, None{}})
    provider : Models.Provider <- CopilotProvider.githubCopilotProvider(Some{oauth})
    Models.setProvider(models, provider)
    return models

def modelIds(models: List<&2, Models.Model()>) -> List<&2, V.Value>:
  match models:
    case Nil{}: Nil{}
    case model <> rest: V.Text{T.modelId(model)} <> modelIds(rest)

def availableResult(result: Models.AvailableResult()) -> IO(Unit):
  match result:
    case Done{models}: emit("V", V.ArrayValue{modelIds(models)})
    case Fail{error}: IO.print("E " ++ Text.showText(Resolve.errorMessage(error)))

# upstream: store.modify(...) the credential, createModels({credentials}),
# setProvider(githubCopilotProvider()), getAvailable("github-copilot").
def available(oauth: Auth.OAuthAuth, credential: Auth.Credential) -> IO(Unit):
  do IO<Unit>:
    +store : Auth.CredentialStore <- CredentialStore.inMemoryCredentialStore()
    +update : Auth.Modification() <- C.create(~Auth.Credential, ~Maybe<&2, Auth.Credential>, ~Auth.StoreResult(Maybe<&2, Auth.Credential>), ~storedAs, credential)
    written : Auth.StoreResult(Maybe<&2, Auth.Credential>) <- Auth.modify(store, "github-copilot", update, None{})
    C.dispose(Maybe<&2, Auth.Credential>, Auth.StoreResult(Maybe<&2, Auth.Credential>), update)
    +models : Models.Models <- copilotModels(oauth, store)
    result : Models.AvailableResult() <- Models.getAvailable(models, Some{"github-copilot"}, None{})
    availableResult(result)

def storedResult(stored: Auth.StoreResult(Maybe<&2, Auth.Credential>)) -> IO(Unit):
  match stored:
    case Done{Some{credential}}: emit("T", credentialJson(credential))
    case Done{None{}}: emit("T", V.Null{})
    case Fail{message}: IO.print("E " ++ Text.showText(message))

# upstream: createModels({credentials: store}), setProvider(
# githubCopilotProvider()), models.login("github-copilot", "oauth", ...),
# then store.read("github-copilot").
def modelsLogin(oauth: Auth.OAuthAuth, interaction: Auth.AuthInteraction) -> IO(Unit):
  do IO<Unit>:
    +store : Auth.CredentialStore <- CredentialStore.inMemoryCredentialStore()
    +models : Models.Models <- copilotModels(oauth, store)
    result : Auth.LoginOutcome() <- Models.login(models, "github-copilot", Auth.OAuthType{}, interaction)
    loginResult(result)
    stored : Auth.StoreResult(Maybe<&2, Auth.Credential>) <- Auth.read(store, "github-copilot", None{})
    storedResult(stored)

def acted(+action: String, oauth: Auth.OAuthAuth, +value: V.Value, +interaction: Interaction, signal: Abort.AbortSignal<Unit>) -> IO(Unit):
  match action oauth:
    case "describe" _: describe(oauth)
    case "refresh" Auth.OAuthAuth{_, _, _, _, refresh, _}:
      do IO<Unit>:
        result : Result<&2, &2, String, Auth.Credential> <- C.call(Auth.RefreshInput, Result<&2, &2, String, Auth.Credential>, refresh, Auth.RefreshInput{credentialOf(field(value, "credential")), signal})
        loginResult(result)
    case "available" _: available(oauth, credentialOf(field(value, "credential")))
    case "modelsLogin" _:
      do IO<Unit>:
        prompt : C.Callback<Auth.AuthPrompt, Result<&2, &2, String, String>> <- C.create(~Interaction, ~Auth.AuthPrompt, ~Result<&2, &2, String, String>, ~prompted, interaction)
        notify : C.Callback<Auth.AuthEvent, Unit> <- C.create(~Interaction, ~Auth.AuthEvent, ~Unit, ~notified, interaction)
        modelsLogin(oauth, Auth.AuthInteraction{Some{signal}, prompt, notify})
        reported(interaction)
    case "toAuth" Auth.OAuthAuth{_, _, _, _, _, toAuth}:
      do IO<Unit>:
        result : Result<&2, &2, String, Auth.ModelAuth> <- C.call(Auth.Credential, Result<&2, &2, String, Auth.ModelAuth>, toAuth, credentialOf(field(value, "credential")))
        authResult(result)
    case _ Auth.OAuthAuth{_, _, _, login, _, _}:
      do IO<Unit>:
        prompt : C.Callback<Auth.AuthPrompt, Result<&2, &2, String, String>> <- C.create(~Interaction, ~Auth.AuthPrompt, ~Result<&2, &2, String, String>, ~prompted, interaction)
        notify : C.Callback<Auth.AuthEvent, Unit> <- C.create(~Interaction, ~Auth.AuthEvent, ~Unit, ~notified, interaction)
        result : Auth.LoginOutcome() <- C.call(Auth.ProviderAuthInteraction, Auth.LoginOutcome(), login, Auth.ProviderAuthInteraction{signal, prompt, notify})
        loginResult(result)
        reported(interaction)

def numberField(value: Maybe<&2, V.Value>) -> Maybe<&2, F64>:
  match value:
    case Some{V.Number{number}}: Some{number}
    case _: None{}

def withFlow(+raw: H.Flow, oauth: Maybe<&2, Auth.OAuthAuth>, +value: V.Value) -> IO(Unit):
  match oauth:
    case None{}: IO.die(Unit, 1, "unknown flow")
    case Some{found}:
      do IO<Unit>:
        answers : Ref.Ref<List<&2, String>> <- Ref.new(List<&2, String>, textList(field(value, "prompts")))
        +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
        +now : F64 <- Date.now()
        IO.print("S " ++ U32.show(F64.to_u32(F64.floor(F.divide(now, F.fromU32(1000))))) ++ " " ++ U32.show(F64.to_u32(F64.floor(F.subtract(now, F.multiply(F64.floor(F.divide(now, F.fromU32(1000))), F.fromU32(1000)))))))
        authUrl : Ref.Ref<String> <- Ref.new(String, "")
        promptAborted : Ref.Ref<Bool> <- Ref.new(Bool, False{})
        first : Deferred.Deferred<Maybe<&2, U32>> <- Deferred.new(Maybe<&2, U32>)
        second : Deferred.Deferred<Maybe<&2, U32>> <- Deferred.new(Maybe<&2, U32>)
        +browser : Browser <- IO.pure(Browser, Browser{raw, authUrl, textOf(field(value, "callbackCode")), Maybe.map(&2, F64, U32, n => F64.to_u32(n), numberField(field(value, "secondCallbackMs"))), flagOf(field(value, "abortOnAuthUrl")), flagOf(field(value, "pendingPrompt")), flagOf(field(value, "watchPromptSignal")), textOf(field(value, "promptError")), promptAborted, first, second})
        abortIf(flagOf(field(value, "preAborted")), controller)
        acted(Maybe.default(&2, String, textOf(field(value, "action")), "login"), found, value, Interaction{answers, controller, flagOf(field(value, "abortOnDeviceCode")), browser}, Abort.signal(Unit, controller))

def runCase(+fetch: Fetch.Fetch(Unit), +base: String, parsed: Result<&2, &2, Decode.ParseError, V.Value>) -> IO(Unit):
  match parsed:
    case Fail{_}: IO.die(Unit, 1, "invalid case")
    case Done{+value}:
      do IO<Unit>:
        rewriter : Fetch.Fetch(Unit) <- C.create(~Rewrite, ~Fetch.Input<Unit>, ~Fetch.Result_(Unit), ~rewritten, Rewrite{fetch, base, TestClient.urlContext()})
        oauth : Maybe<&2, Auth.OAuthAuth> <- flowOf(Maybe.default(&2, String, textOf(field(value, "flow")), ""), rewriter, TestClient.urlContext(), numberField(field(value,"codexExpiresMs")))
        withFlow(H.Flow{fetch, TestClient.urlContext()}, oauth, value)

def caseText(result: Result<&2, &2, FS.Error, List<&2, U32>>) -> String:
  match result:
    case Done{bytes}: Utf8.decodeBytes(bytes)
    case Fail{_}: ""

def borrowed(+base: String, +path: String, pair: Fetch.Runtime & Fetch.Fetch(Unit)) -> IO(Unit):
  match pair:
    case (runtime, +fetch):
      do IO<Unit>:
        read : Result<&2, &2, FS.Error, List<&2, U32>> <- FS.readFile(path)
        runCase(fetch, base, Decode.parse(caseText(read)))
        Fetch.retire(Unit, fetch)
        Fetch.dispose(runtime)

def initialized(+base: String, +path: String, result: Result<&2, &1, Fetch.InitError, Fetch.Runtime>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "network initialization failed")
    case Done{runtime}:
      do IO<Unit>:
        pair : Fetch.Runtime & Fetch.Fetch(Unit) <- Fetch.callback(~Unit, runtime)
        borrowed(base, path, pair)

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case base <> path <> Nil{}:
      do IO<Unit>:
        runtime : Result<&2, &1, Fetch.InitError, Fetch.Runtime> <- Fetch.create(Fetch.linuxFiles(), TestClient.networkOptions())
        initialized(base, path, runtime)
    case _: IO.die(Unit, 1, "usage: oauth-flows <base> <case>")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
