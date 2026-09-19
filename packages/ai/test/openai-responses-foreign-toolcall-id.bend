import Base
import ../src/api/openai-responses-shared.bend as C
import ../src/api/openai-responses-assistant.bend as Assistant
import ../src/types.bend as T
import ../src/utils/hash.bend as Hash
import ./api/responses-named.bend as Fixture
import ../../runtime/test/schema.bend as Assert

def rawId() -> String: "call_4VnzVawQXPB9MgYib7CiQFEY|I9b95oN1wD/cHXKTw3PpRkL6KkCtzTJhUxMouMWYwHeTo2j3htzfSk7YPx2vifiIM4g3A8XXyOj8q4Bt6SLUG7gqY1E3ELkrkVQNHglRfUmWj84lqxJY+Puieb3VKyX0FB+83TUzn91cDMF/4gzt990IzqVrc+nIb9RRscRD070Du16q1glydVjWR0SBJsE6TbY/esOjFpqplogQqrajm1eI++f3eLi73R6q7hVusY0QbeFySVxABCjhN0lXB04caBe1rzHjYzul6MAXj7uq+0r17VLq+yrtyYhN12wkmFqHeqTyEei6EFPbMy24Nc+IbJlkP0OCg02W+gOnyBFcbi2ctvJFSOhSjt1CqBdqCnnhwUqXjbWiT0wh3DmLScRgTHmGkaI+oAcQQjfic65nxj+TnEkReA=="

def alphanumeric(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{Chr{+code},rest}: ((U32.is_ge(code,48) && U32.is_le(code,57)) || (U32.is_ge(code,65) && U32.is_le(code,90)) || (U32.is_ge(code,97) && U32.is_le(code,122))) && alphanumeric(rest)

def shape(text: String) -> Bool:
  match text:
    case SCon{'f',SCon{'c',SCon{'_',SCon{char,rest}}}}: alphanumeric(SCon{char,rest})
    case _: False{}

def matches(call: Maybe<&2,Assistant.Call>) -> Bool:
  match call:
    case Some{Assistant.Call{Some{+id},_,_,_}}: String.eq(id,"fc_" ++ Hash.shortHash("I9b95oN1wD/cHXKTw3PpRkL6KkCtzTJhUxMouMWYwHeTo2j3htzfSk7YPx2vifiIM4g3A8XXyOj8q4Bt6SLUG7gqY1E3ELkrkVQNHglRfUmWj84lqxJY+Puieb3VKyX0FB+83TUzn91cDMF/4gzt990IzqVrc+nIb9RRscRD070Du16q1glydVjWR0SBJsE6TbY/esOjFpqplogQqrajm1eI++f3eLi73R6q7hVusY0QbeFySVxABCjhN0lXB04caBe1rzHjYzul6MAXj7uq+0r17VLq+yrtyYhN12wkmFqHeqTyEei6EFPbMy24Nc+IbJlkP0OCg02W+gOnyBFcbi2ctvJFSOhSjt1CqBdqCnnhwUqXjbWiT0wh3DmLScRgTHmGkaI+oAcQQjfic65nxj+TnEkReA==")) && Nat.is_le(String.length(id),64n) && shape(id)
    case _: False{}

def run() -> IO(Unit):
  message = Fixture.assistant(Fixture.toolCall(rawId(),"edit","path","src/styles/app.css",None{}) <> Nil{},"openai-responses","github-copilot","gpt-5.5",T.ToolUse{})
  do IO<Unit>:
    items : List<&2,C.ResponseInputItem> <- Fixture.convert(Fixture.model(T.OpenAICodexResponsesApi{},"openai-codex","gpt-5.5"),Some{"You are concise."},Fixture.user("Use the tool.") <> message <> Fixture.result(rawId(),"edit","ok") <> Nil{},"openai" <> "openai-codex" <> "opencode" <> Nil{},None{})
    Assert.assertion(matches(Fixture.findCall(items,False{})),"foreign item ID equals its bounded alphanumeric fc hash")
    IO.print("PASS hashes foreign Copilot tool item IDs into a bounded Codex-safe fc_<hash> shape")
