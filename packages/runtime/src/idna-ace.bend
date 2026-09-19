import Base
import ./punycode.bend as Punycode
import ./punycode-core.bend as Core

type Error is Data:
  NonASCIIEncoding{}
  InvalidPunycode{reason: Core.Error}
  ASCIIOnlyDecodedLabel{}

type Label is Data:
  Label{text: String, encoded: Bool}

def asciiScan(text: String, ascii: Bool) -> Bool:
  match text:
    case SNil{}: ascii
    case SCon{Chr{code}, rest}: asciiScan(rest, ascii && U32.is_le(code, 127))

def isASCII(text: String) -> Bool:
  asciiScan(text, True{})

def decodedText(ascii: Bool, value: String) -> Result<&2, &2, Error, Label>:
  match ascii:
    case True{}: Fail{ASCIIOnlyDecodedLabel{}}
    case False{}: Done{Label{value, True{}}}

def decoded(value: Result<&2, &2, Core.Error, String>) -> Result<&2, &2, Error, Label>:
  match value:
    case Fail{error}: Fail{InvalidPunycode{error}}
    case Done{+text}: decodedText(isASCII(text), text)

def decodeBody(ascii: Bool, text: String) -> Result<&2, &2, Error, Label>:
  match ascii:
    case False{}: Fail{NonASCIIEncoding{}}
    case True{}: decoded(Punycode.decode(text))

# Input has already undergone domain-wide mapping/NFC. ACE output must later be
# validated WITHOUT mapping and always using nontransitional status rules.
# This strict decoder is the IgnoreInvalidPunycode=false path used by URL hosts.
def decode(label: String) -> Result<&2, &2, Error, Label>:
  match label:
    case SCon{'x', SCon{'n', SCon{'-', SCon{'-', +rest}}}}: decodeBody(isASCII(rest), rest)
    case text: Done{Label{text, False{}}}
