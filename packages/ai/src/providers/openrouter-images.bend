import Base
import ../auth/types.bend as Auth
import ../auth/helpers.bend as Helpers
import ../images-models.bend as Images
import ../image-models.generated.bend as Catalog

# upstream providers/openrouter-images.ts: OpenRouter's image models with its
# OPENROUTER_API_KEY auth and the chat provider's "OpenRouter OAuth" handler
# (auth/oauth/openrouter.bend), which the caller creates over its fetch. The
# api is passed in (api/openrouter-images.bend openrouterImagesApi).
def openrouterImagesProvider(-E: Data, oauth: Maybe<&2, Auth.OAuthAuth>, api: Images.ProviderImages(E)) -> IO(Images.ImagesProvider<E>):
  do IO<Images.ImagesProvider<E>>:
    apiKey : Auth.ApiKeyAuth <- Helpers.envApiKeyAuth("OpenRouter API key", ["OPENROUTER_API_KEY"])
    Images.createImagesProvider(E, Images.CreateImagesProviderOptions{"openrouter", Some{"OpenRouter"}, Auth.ProviderAuth{Some{apiKey}, oauth}, Catalog.OPENROUTER_IMAGE_MODELS(), None{}, api})
