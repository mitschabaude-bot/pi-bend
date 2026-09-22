import Base
import ../../src/types.bend as T
import ../../src/api/simple-options.bend as O
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/f64.bend as F
import ../../../runtime/test/schema.bend as Assert
import ./thinking-options.bend as Numbers

def optional(~A: Data, ~equal: A -> A -> Bool, left: Maybe<&2, A>, right: Maybe<&2, A>) -> Bool:
  match left right:
    case None{} None{}: True{}
    case Some{a} Some{b}: equal(a, b)
    case _ _: False{}

def record(left: R.Record<V.Value>, right: R.Record<V.Value>) -> Bool: V.equal(V.ObjectValue{left}, V.ObjectValue{right})

def strings(entries: List<&2, R.Property<String>>) -> R.Record<V.Value>:
  match entries:
    case Nil{}: R.Record{Nil{}}
    case R.Property{key, text} <> rest: R.set(V.Value, strings(rest), key, V.Text{text})

def environment(left: R.Record<String>, right: R.Record<String>) -> Bool: record(strings(R.entries(String, left)), strings(R.entries(String, right)))

def nullable(value: T.Nullable<String>) -> V.Value:
  match value:
    case T.NullValue{}: V.Null{}
    case T.PresentValue{text}: V.Text{text}

def headerValues(entries: List<&2, R.Property<T.Nullable<String>>>) -> R.Record<V.Value>:
  match entries:
    case Nil{}: R.Record{Nil{}}
    case R.Property{key, text} <> rest: R.set(V.Value, headerValues(rest), key, nullable(text))

def headers(left: T.ProviderHeaders(), right: T.ProviderHeaders()) -> Bool: record(headerValues(R.entries(T.Nullable<String>, left)), headerValues(R.entries(T.Nullable<String>, right)))

def transport(left: T.Transport, right: T.Transport) -> Bool:
  match left right:
    case T.Sse{} T.Sse{}: True{}
    case T.WebSocket{} T.WebSocket{}: True{}
    case T.WebSocketCached{} T.WebSocketCached{}: True{}
    case T.AutoTransport{} T.AutoTransport{}: True{}
    case _ _: False{}

def cache(left: T.CacheRetention, right: T.CacheRetention) -> Bool:
  match left right:
    case T.CacheNone{} T.CacheNone{}: True{}
    case T.CacheShort{} T.CacheShort{}: True{}
    case T.CacheLong{} T.CacheLong{}: True{}
    case _ _: False{}

def number(left: F64, right: F64) -> Bool: Numbers.numberEqual(left, right)

def same(left: T.StreamOptions<V.Value, String, String, String, String>, right: T.StreamOptions<V.Value, String, String, String, String>) -> Bool:
  match left right:
    case T.StreamOptions{a,b,c,d,e,None{},None{},h,i,j,k,l,m,n,o,p,q,r,s} T.StreamOptions{aa,bb,cc,dd,ee,None{},None{},hh,ii,jj,kk,ll,mm,nn,oo,pp,qq,rr,ss}:
      optional(~String, ~String.eq, a, aa) && optional(~String, ~String.eq, b, bb) && optional(~String, ~String.eq, c, cc) && optional(~String, ~String.eq, d, dd) && optional(~T.ProviderEnv(), ~environment, e, ee) && optional(~T.ProviderHeaders(), ~headers, h, hh) && optional(~F64, ~number, i, ii) && optional(~F64, ~number, j, jj) && optional(~F64, ~number, k, kk) && optional(~F64, ~number, l, ll) && optional(~R.Record<V.Value>, ~record, m, mm) && optional(~F64, ~number, n, nn) && optional(~T.Transport, ~transport, o, oo) && optional(~T.CacheRetention, ~cache, p, pp) && optional(~String, ~String.eq, q, qq) && optional(~F64, ~number, r, rr) && optional(~R.Record<V.Value>, ~record, s, ss)
    case _ _: False{}

def model(window: F64, maxTokens: F64, sampling: Maybe<&2, R.Record<V.Value>>) -> T.Model<V.Value>:
  +zero = F.fromU32(0)
  T.Model{"test", "Test", T.OpenAIResponsesApi{}, "openai", "https://example.test", False{}, None{}, T.InputText{} <> Nil{}, T.ModelCost{zero, zero, zero, zero, None{}}, window, maxTokens, sampling, None{}, None{}}

def check(model: T.Model<V.Value>, context: T.TranscriptContext<V.Value, V.Value, Unit, Unit>, options: Maybe<&2, T.SimpleStreamOptions<V.Value, String, String, String, String>>, key: Maybe<&2, String>, expected: T.StreamOptions<V.Value, String, String, String, String>, label: String) -> IO(Unit):
  Assert.assertion(same(O.buildBaseOptions(~Unit, ~Unit, ~V.Value, ~String, ~String, ~String, ~String, model, context, options, key), expected), label)
