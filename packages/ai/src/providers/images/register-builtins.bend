import Base
import ../../images-models.bend as Images
import ../../images-api-registry.bend as Registry

# upstream providers/images/register-builtins.ts: the built-in image api
# providers. Upstream registers a lazy loader into the module-level registry
# on import; here the registry value is built from the api the caller
# created (api/openrouter-images.bend openrouterImagesApi).
def registerBuiltInImagesApiProviders(-E: Data, registry: Registry.ImagesApiRegistry<E>, openrouter: Images.ProviderImages(E)) -> Registry.ImagesApiRegistry<E>:
  Registry.registerImagesApiProvider(E, registry, Registry.ImagesApiProvider{"openrouter-images", openrouter}, None{})

def builtinImagesApiRegistry(-E: Data, openrouter: Images.ProviderImages(E)) -> Registry.ImagesApiRegistry<E>:
  registerBuiltInImagesApiProviders(E, Registry.emptyImagesApiRegistry(E), openrouter)
