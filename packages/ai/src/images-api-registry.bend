import Base
import ./types.bend as T
import ./images-models.bend as Images
import ../../runtime/src/callback.bend as C
import ../../runtime/src/record.bend as R

# upstream images-api-registry.ts. The registry is a value: registering
# returns the next registry (upstream mutates a module-level Map; a repeated
# api replaces its entry in place, as Map.set does).

type ImagesApiProvider<-E: Data> is Data:
  ImagesApiProvider{api: String, generateImages: Images.ProviderImages(E)}

type RegisteredImagesApiProvider<-E: Data> is Data:
  RegisteredImagesApiProvider{provider: ImagesApiProvider<E>, sourceId: Maybe<&2, String>}

type ImagesApiRegistry<-E: Data> is Data:
  ImagesApiRegistry{entries: R.Record<RegisteredImagesApiProvider<E>>}

def emptyImagesApiRegistry(-E: Data) -> ImagesApiRegistry<E>: ImagesApiRegistry{R.new(RegisteredImagesApiProvider<E>)}

def registerImagesApiProvider(-E: Data, registry: ImagesApiRegistry<E>, provider: ImagesApiProvider<E>, sourceId: Maybe<&2, String>) -> ImagesApiRegistry<E>:
  match registry provider:
    case ImagesApiRegistry{entries} ImagesApiProvider{+api, generate}: ImagesApiRegistry{R.set(RegisteredImagesApiProvider<E>, entries, api, RegisteredImagesApiProvider{ImagesApiProvider{api, generate}, sourceId})}

def registeredProvider(-E: Data, value: Maybe<&2, RegisteredImagesApiProvider<E>>) -> Maybe<&2, ImagesApiProvider<E>>:
  match value:
    case Some{RegisteredImagesApiProvider{provider, _}}: Some{provider}
    case None{}: None{}

def getImagesApiProvider(-E: Data, registry: ImagesApiRegistry<E>, api: String) -> Maybe<&2, ImagesApiProvider<E>>:
  match registry:
    case ImagesApiRegistry{entries}: registeredProvider(E, R.get(RegisteredImagesApiProvider<E>, entries, api))

def modelApi(model: T.ImagesModel<T.JsonValue>) -> String:
  match model:
    case T.ImagesModel{_, _, api, _, _, _, _, _, _, _, _, _, _}: api

def generated(-E: Data, generate: Images.ProviderImages(E), request: Images.ImagesRequest<E>) -> IO(Result<&2, &2, String, T.AssistantImages>):
  do IO<Result<&2, &2, String, T.AssistantImages>>:
    result : T.AssistantImages <- C.call(Images.ImagesRequest<E>, T.AssistantImages, generate, request)
    return Done{result}

# The registered function (upstream wrapGenerateImages) rejects a model of
# another api.
def generateWith(-E: Data, provider: ImagesApiProvider<E>, request: Images.ImagesRequest<E>) -> IO(Result<&2, &2, String, T.AssistantImages>):
  match provider request:
    case ImagesApiProvider{+api, generate} Images.ImagesRequest{+model, context, options}:
      Bool.pick(Unit -> IO(Result<&2, &2, String, T.AssistantImages>), String.eq(modelApi(model), api), _ => generated(E, generate, Images.ImagesRequest{model, context, options}), _ => IO.pure(Result<&2, &2, String, T.AssistantImages>, Fail{"Mismatched api: " ++ modelApi(model) ++ " expected " ++ api}))(Unit{})
