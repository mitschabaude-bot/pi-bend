import Base
import ./punycode-core.bend as Core
import ./punycode-encode.bend as Encode
import ./punycode-decode.bend as Decode

# Unicode-scalar Punycode, without the xn-- prefix. IDNA mapping, NFC, label
# validity, case folding and DNS length policy belong to the hostname layer.
def encode(text: String) -> Result<&2, &2, Core.Error, String>: Encode.encode(text)
def decode(text: String) -> Result<&2, &2, Core.Error, String>: Decode.decode(text)
