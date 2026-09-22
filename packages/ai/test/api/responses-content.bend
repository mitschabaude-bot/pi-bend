import Base
import ../../src/api/openai-responses-shared.bend as C
import ../../src/api/transform-messages.bend as Transform
import ../../src/types.bend as T
import ../../src/utils/json.bend as Json
import ../../../runtime/src/utf16.bend as U
import ../../../runtime/test/schema.bend as A
import ./transform-images.bend as Fixture

def encoded(value: Maybe<&2,String>, expected: String) -> Bool:
  match value:
    case Some{actual}: U.equal(actual,expected)
    case None{}: False{}

def userJson(value: Maybe<&2,List<&2,C.ResponseInputContent>>) -> T.JsonValue:
  match value:
    case None{}: T.JsonNull{}
    case Some{user}: C.userToJson(user)

def preparedUser(vision: Bool, content: T.UserContent) -> T.UserContent:
  match vision:
    case True{}: content
    case False{}: Transform.userContent(content)

def preparedResult(vision: Bool, content: List<&2,T.TextImageContent>) -> List<&2,T.TextImageContent>:
  match vision:
    case True{}: content
    case False{}: Transform.replaceImagesWithPlaceholder(content,Transform.toolImagePlaceholder())

def check(+vision: Bool, +user: T.UserContent, +content: List<&2,T.TextImageContent>, expectedUser: String, expectedOutput: String, expectedPreparedUser: String, expectedPreparedOutput: String, label: String) -> IO(Unit):
  +model = Fixture.model(vision)
  A.assertion(encoded(Json.stringify(userJson(C.convertUserContent(user))),expectedUser) && encoded(Json.stringify(C.outputToJson(C.convertToolResultOutput(Unit,model,content))),expectedOutput) && encoded(Json.stringify(userJson(C.convertUserContent(preparedUser(vision,user)))),expectedPreparedUser) && encoded(Json.stringify(C.outputToJson(C.convertToolResultOutput(Unit,model,preparedResult(vision,content)))),expectedPreparedOutput),label)
