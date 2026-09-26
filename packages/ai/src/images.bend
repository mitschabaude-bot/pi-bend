import Base
import ./types.bend as T
import ./images-models.bend as Images
import ./images-api-registry.bend as Registry

# upstream images.ts: generation through the api provider registered for the
# model's api. Upstream imports providers/images/register-builtins.ts for
# its side effect; here the caller passes the registry
# (providers/images/register-builtins.bend builds the built-in one). A
# missing api provider or a mismatched model is a failure (upstream rejects);
# provider failures are AssistantImages with stopReason "error".
def dispatched(-E: Data, provider: Maybe<&2, Registry.ImagesApiProvider<E>>, +model: T.ImagesModel<T.JsonValue>, context: T.ImagesContext, options: Maybe<&2, Images.Options(E)>) -> IO(Result<&2, &2, String, T.AssistantImages>):
  match provider:
    case None{}: IO.pure(Result<&2, &2, String, T.AssistantImages>, Fail{"No API provider registered for api: " ++ Registry.modelApi(model)})
    case Some{value}: Registry.generateWith(E, value, Images.ImagesRequest{model, context, options})

def generateImages(-E: Data, registry: Registry.ImagesApiRegistry<E>, +model: T.ImagesModel<T.JsonValue>, context: T.ImagesContext, options: Maybe<&2, Images.Options(E)>) -> IO(Result<&2, &2, String, T.AssistantImages>):
  dispatched(E, Registry.getImagesApiProvider(E, registry, Registry.modelApi(model)), model, context, options)
