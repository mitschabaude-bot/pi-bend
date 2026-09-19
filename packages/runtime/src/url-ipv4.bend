import Base
import ./string-split.bend as Split
import ./uri-component.bend as Uri

# URL IPv4 addresses have one canonical numeric representation. Parsing accepts
# the URL Standard's decimal, octal, hexadecimal and abbreviated host syntax.
type Address is Data:
  Address{value: U32}

type NumberError is Data:
  InvalidNumber{}
  NumberOverflow{}

type AddressError is Data:
  InvalidPart{}
  TooManyParts{}
  OutOfRange{}

# Continue checking digits after overflow: a huge valid number must trigger
# numeric-host parsing, whereas a suffix with a non-digit can still be a domain.
def accumulated(fits: Bool, value: U32, radix: U32, digit: U32) -> Result<&2, &2, NumberError, U32>:
  match fits:
    case False{}: Fail{NumberOverflow{}}
    case True{}: Done{(value * radix + digit : U32)}

def digitValue(valid: Bool, +digit: U32, +radix: U32, state: Result<&2, &2, NumberError, U32>) -> Result<&2, &2, NumberError, U32>:
  match valid state:
    case False{} _: Fail{InvalidNumber{}}
    case True{} Fail{error}: Fail{error}
    case True{} Done{+value}: accumulated(U32.is_le(value, ((4294967295 - digit) / radix : U32)), value, radix, digit)

def addDigit(digit: Maybe<&2, U32>, +radix: U32, state: Result<&2, &2, NumberError, U32>) -> Result<&2, &2, NumberError, U32>:
  match digit:
    case None{}: Fail{InvalidNumber{}}
    case Some{+value}: digitValue(U32.is_lt(value, radix), value, radix, state)

def digits(text: String, +radix: U32, state: Result<&2, &2, NumberError, U32>) -> Result<&2, &2, NumberError, U32>:
  match text state:
    case _ Fail{InvalidNumber{}}: Fail{InvalidNumber{}}
    case SNil{} result: result
    case SCon{Chr{code}, rest} result: digits(rest, radix, addDigit(Uri.hex(code), radix, result))

def number(text: String) -> Result<&2, &2, NumberError, U32>:
  match text:
    case SNil{}: Fail{InvalidNumber{}}
    case SCon{'0', SCon{'x', rest}}: digits(rest, 16, Done{0})
    case SCon{'0', SCon{'X', rest}}: digits(rest, 16, Done{0})
    case SCon{'0', rest}: digits(rest, 8, Done{0})
    case other: digits(other, 10, Done{0})

def trimTrailing(reversed: List<&2, String>) -> List<&2, String>:
  match reversed:
    case SNil{} <> first <> rest: first <> rest
    case other: other

def reversedParts(text: String) -> List<&2, String>:
  trimTrailing(List.reverse(&2, String, Split.split(text, '.')))

def decimalTail(text: String, valid: Bool) -> Bool:
  match text valid:
    case _ False{}: False{}
    case SNil{} True{}: True{}
    case SCon{Chr{+code}, rest} True{}: decimalTail(rest, U32.is_ge(code, 48) && U32.is_le(code, 57))

def decimal(text: String) -> Bool:
  match text:
    case SNil{}: False{}
    case other: decimalTail(other, True{})

def numeric(result: Result<&2, &2, NumberError, U32>) -> Bool:
  match result:
    case Fail{InvalidNumber{}}: False{}
    case _: True{}

def lastIsNumber(parts: List<&2, String>) -> Bool:
  match parts:
    case Nil{}: False{}
    case +last <> _: decimal(last) || numeric(number(last))

# Input is the already-normalized ASCII domain, before host classification.
def endsInNumber(text: String) -> Bool: lastIsNumber(reversedParts(text))

type State is Data:
  Prefix{count: U32, value: U32}
  Complete{address: Address}

def bounded(fits: Bool, value: U32) -> Result<&2, &2, AddressError, State>:
  match fits:
    case False{}: Fail{OutOfRange{}}
    case True{}: Done{Complete{Address{value}}}

def finalPart(count: U32, prefix: U32, +last: U32) -> Result<&2, &2, AddressError, State>:
  match count:
    case 0: Done{Complete{Address{last}}}
    case 1: bounded(U32.is_le(last, 16777215), (prefix * 16777216 + last : U32))
    case 2: bounded(U32.is_le(last, 65535), (prefix * 65536 + last : U32))
    case _: bounded(U32.is_le(last, 255), (prefix * 256 + last : U32))

def prefixPart(fits: Bool, count: U32, prefix: U32, value: U32) -> Result<&2, &2, AddressError, State>:
  match fits:
    case False{}: Fail{OutOfRange{}}
    case True{}: Done{Prefix{(count + 1 : U32), (prefix * 256 + value : U32)}}

def part(last: Bool, count: U32, prefix: U32, result: Result<&2, &2, NumberError, U32>) -> Result<&2, &2, AddressError, State>:
  match last result:
    case _ Fail{InvalidNumber{}}: Fail{InvalidPart{}}
    case _ Fail{NumberOverflow{}}: Fail{OutOfRange{}}
    case True{} Done{value}: finalPart(count, prefix, value)
    case False{} Done{+value}: prefixPart(U32.is_le(value, 255), count, prefix, value)

def empty(parts: List<&2, String>) -> Bool:
  match parts:
    case Nil{}: True{}
    case _: False{}

def scan(parts: List<&2, String>, state: Result<&2, &2, AddressError, State>) -> Result<&2, &2, AddressError, Address>:
  match parts state:
    case _ Fail{error}: Fail{error}
    case Nil{} Done{Complete{address}}: Done{address}
    case Nil{} _: Fail{InvalidPart{}}
    case _ Done{Prefix{4, _}}: Fail{TooManyParts{}}
    case value <> +rest Done{Prefix{count, prefix}}: scan(rest, part(empty(rest), count, prefix, number(value)))
    case _ _: Fail{TooManyParts{}}

def parse(text: String) -> Result<&2, &2, AddressError, Address>:
  scan(List.reverse(&2, String, reversedParts(text)), Done{Prefix{0, 0}})

def serialize(address: Address) -> String:
  match address:
    case Address{+value}: U32.show((value / 16777216 : U32)) ++ "." ++ U32.show((value / 65536 % 256 : U32)) ++ "." ++ U32.show((value / 256 % 256 : U32)) ++ "." ++ U32.show((value % 256 : U32))
