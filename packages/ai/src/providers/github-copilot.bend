import Base
import ../types.bend as T
import ../models.bend as Models
import ../auth/types.bend as Auth
import ../auth/helpers.bend as Helpers
import ./github-copilot.models.bend as Catalog
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/utf16.bend as U

# An array of strings, or nothing when any element is not a string.
def textIds(values: List<&2, V.Value>) -> Maybe<&2, List<&2, String>>:
  match values:
    case Nil{}: Some{Nil{}}
    case V.Text{id} <> rest: Maybe.map(&2, List<&2, String>, List<&2, String>, ids => id <> ids, textIds(rest))
    case _ <> _: None{}

def availableIds(field: Maybe<&2, V.Value>) -> Maybe<&2, List<&2, String>>:
  match field:
    case Some{V.ArrayValue{values}}: textIds(values)
    case _: None{}

def availableModelIds(credential: Maybe<&2, Auth.Credential>) -> Maybe<&2, List<&2, String>>:
  match credential:
    case Some{Auth.OAuthCredential{_, _, _, extra}}: availableIds(R.get(V.Value, extra, "availableModelIds"))
    case _: None{}

def listed(ids: List<&2, String>, +id: String) -> Bool:
  match ids:
    case Nil{}: False{}
    case first <> rest: U.equal(first, id) || listed(rest, id)

def onlyListed(models: List<&2, Models.Model()>, +ids: List<&2, String>) -> List<&2, Models.Model()>:
  match models:
    case Nil{}: Nil{}
    case +model <> rest:
      +tail = onlyListed(rest, ids)
      Bool.pick(List<&2, Models.Model()>, listed(ids, T.modelId(model)), model <> tail, tail)

def narrowed(models: List<&2, Models.Model()>, ids: Maybe<&2, List<&2, String>>) -> List<&2, Models.Model()>:
  match ids:
    case None{}: models
    case Some{ids}: onlyListed(models, ids)

# upstream filterModels: an OAuth credential whose availableModelIds is an
# array of strings (the account's picker catalog, stored at login and
# refresh) narrows the catalog to those models; anything else keeps it.
def filterAvailable(unit: Unit, input: Models.FilterModelsInput) -> IO(List<&2, Models.Model()>):
  match input:
    case Models.FilterModelsInput{models, credential}: IO.pure(List<&2, Models.Model()>, narrowed(models, availableModelIds(credential)))

# The OAuth handler (auth/oauth/github-copilot.bend, "GitHub Copilot") is
# created by the caller over its fetch, as upstream's lazyOAuth loads it.
def githubCopilotProvider(oauth: Maybe<&2, Auth.OAuthAuth>) -> IO(Models.Provider):
  do IO<Models.Provider>:
    apiKey : Auth.ApiKeyAuth <- Helpers.envApiKeyAuth("GitHub Copilot token", ["COPILOT_GITHUB_TOKEN"])
    filter : Models.FilterModels() <- C.create(~Unit, ~Models.FilterModelsInput, ~List<&2, Models.Model()>, ~filterAvailable, Unit{})
    return Models.Provider{"github-copilot", "GitHub Copilot", "https://api.individual.githubcopilot.com", Auth.ProviderAuth{Some{apiKey}, oauth}, Catalog.GITHUB_COPILOT_MODELS(), Models.ApiStreams{}, None{}, Some{filter}}
