import Base
import ./utils.bend as U
import ../../runtime/src/record.bend as R
import ../../runtime/src/regex.bend as Regex
import ../../runtime/src/text.bend as Text
import ../../runtime/src/string.bend as Strings

# pi's terminal LaTeX renderer (packages/tui/src/latex.ts): basic math as
# Unicode text, with display mode stacking fractions, operator limits,
# scripts, matrices and cases vertically. Unsupported or malformed input
# renders to None, and callers show the source.
#
# Language-driven differences:
# - pi's recursive-descent parser mutates a position, flags and a shared
#   node array. Here the parser is an explicit machine (see Parser below);
#   positions are the unparsed rest of the source, and the node array is a
#   list threaded through every nested render.
# - pi looks commands up in plain objects, so `\constructor`, `\toString`
#   and other Object.prototype names hit inherited members. The tables here
#   hold exactly pi's own entries.
# - Layout nodes are laid out bottom-up in creation order. pi lays out a
#   node's text recursively on demand; the two agree because generated
#   markers only refer to earlier nodes. Only a literal marker character
#   pair in the input naming a later node would differ.
# - Lengths count Unicode scalars, as pi's `Array.from` does; pi's UTF-16
#   `.length` is only applied to whitespace prefixes, which are single
#   units.

# Tables
# ------

def symbols() -> R.Record<String>:
  R.Record{[R.Property{"alpha","α"},R.Property{"beta","β"},R.Property{"gamma","γ"},R.Property{"delta","δ"},
    R.Property{"epsilon","ϵ"},R.Property{"varepsilon","ε"},R.Property{"zeta","ζ"},R.Property{"eta","η"},
    R.Property{"theta","θ"},R.Property{"vartheta","ϑ"},R.Property{"iota","ι"},R.Property{"kappa","κ"},
    R.Property{"varkappa","ϰ"},R.Property{"lambda","λ"},R.Property{"mu","μ"},R.Property{"nu","ν"},
    R.Property{"xi","ξ"},R.Property{"pi","π"},R.Property{"varpi","ϖ"},R.Property{"rho","ρ"},
    R.Property{"varrho","ϱ"},R.Property{"sigma","σ"},R.Property{"varsigma","ς"},R.Property{"tau","τ"},
    R.Property{"upsilon","υ"},R.Property{"phi","ϕ"},R.Property{"varphi","φ"},R.Property{"chi","χ"},
    R.Property{"psi","ψ"},R.Property{"omega","ω"},R.Property{"Gamma","Γ"},R.Property{"Delta","Δ"},
    R.Property{"Theta","Θ"},R.Property{"Lambda","Λ"},R.Property{"Xi","Ξ"},R.Property{"Pi","Π"},
    R.Property{"Sigma","Σ"},R.Property{"Upsilon","Υ"},R.Property{"Phi","Φ"},R.Property{"Psi","Ψ"},
    R.Property{"Omega","Ω"},R.Property{"pm","±"},R.Property{"mp","∓"},R.Property{"times","×"},
    R.Property{"div","÷"},R.Property{"cdot","·"},R.Property{"ast","∗"},R.Property{"star","⋆"},
    R.Property{"circ","∘"},R.Property{"bullet","•"},R.Property{"oplus","⊕"},R.Property{"ominus","⊖"},
    R.Property{"otimes","⊗"},R.Property{"oslash","⊘"},R.Property{"odot","⊙"},R.Property{"bigcirc","○"},
    R.Property{"dagger","†"},R.Property{"ddagger","‡"},R.Property{"amalg","⨿"},R.Property{"uplus","⊎"},
    R.Property{"sqcap","⊓"},R.Property{"sqcup","⊔"},R.Property{"bowtie","⋈"},R.Property{"Join","⋈"},
    R.Property{"ltimes","⋉"},R.Property{"rtimes","⋊"},R.Property{"leftouterjoin","⟕"},
    R.Property{"rightouterjoin","⟖"},R.Property{"fullouterjoin","⟗"},R.Property{"triangleleft","◁"},
    R.Property{"triangleright","▷"},R.Property{"wr","≀"},R.Property{"cap","∩"},R.Property{"cup","∪"},
    R.Property{"bigcap","⋂"},R.Property{"bigcup","⋃"},R.Property{"bigwedge","⋀"},
    R.Property{"bigvee","⋁"},R.Property{"bigsqcup","⨆"},R.Property{"biguplus","⨄"},
    R.Property{"bigoplus","⨁"},R.Property{"bigotimes","⨂"},R.Property{"bigodot","⨀"},
    R.Property{"setminus","∖"},R.Property{"in","∈"},R.Property{"notin","∉"},R.Property{"ni","∋"},
    R.Property{"subset","⊂"},R.Property{"supset","⊃"},R.Property{"subseteq","⊆"},
    R.Property{"supseteq","⊇"},R.Property{"sqsubset","⊏"},R.Property{"sqsupset","⊐"},
    R.Property{"sqsubseteq","⊑"},R.Property{"sqsupseteq","⊒"},R.Property{"prec","≺"},
    R.Property{"preceq","≼"},R.Property{"succ","≻"},R.Property{"succeq","≽"},R.Property{"ll","≪"},
    R.Property{"gg","≫"},R.Property{"le","≤"},R.Property{"leq","≤"},R.Property{"leqslant","≤"},
    R.Property{"ge","≥"},R.Property{"geq","≥"},R.Property{"geqslant","≥"},R.Property{"ne","≠"},
    R.Property{"neq","≠"},R.Property{"equiv","≡"},R.Property{"approx","≈"},R.Property{"sim","∼"},
    R.Property{"simeq","≃"},R.Property{"cong","≅"},R.Property{"asymp","≍"},R.Property{"doteq","≐"},
    R.Property{"propto","∝"},R.Property{"parallel","∥"},R.Property{"perp","⊥"},R.Property{"mid","∣"},
    R.Property{"vdash","⊢"},R.Property{"dashv","⊣"},R.Property{"models","⊨"},R.Property{"Vdash","⊩"},
    R.Property{"Vvdash","⊪"},R.Property{"nvdash","⊬"},R.Property{"nvDash","⊭"},R.Property{"forall","∀"},
    R.Property{"exists","∃"},R.Property{"nexists","∄"},R.Property{"neg","¬"},R.Property{"land","∧"},
    R.Property{"wedge","∧"},R.Property{"lor","∨"},R.Property{"vee","∨"},R.Property{"to","→"},
    R.Property{"rightarrow","→"},R.Property{"longrightarrow","→"},R.Property{"leftarrow","←"},
    R.Property{"longleftarrow","←"},R.Property{"gets","←"},R.Property{"leftrightarrow","↔"},
    R.Property{"longleftrightarrow","↔"},R.Property{"hookleftarrow","↩"},
    R.Property{"hookrightarrow","↪"},R.Property{"twoheadleftarrow","↞"},
    R.Property{"twoheadrightarrow","↠"},R.Property{"leftharpoonup","↼"},
    R.Property{"leftharpoondown","↽"},R.Property{"rightharpoonup","⇀"},
    R.Property{"rightharpoondown","⇁"},R.Property{"rightleftharpoons","⇌"},
    R.Property{"leftrightharpoons","⇋"},R.Property{"nearrow","↗"},R.Property{"searrow","↘"},
    R.Property{"swarrow","↙"},R.Property{"nwarrow","↖"},R.Property{"rightsquigarrow","⇝"},
    R.Property{"leadsto","⇝"},R.Property{"Rightarrow","⇒"},R.Property{"Longrightarrow","⇒"},
    R.Property{"Leftarrow","⇐"},R.Property{"Longleftarrow","⇐"},R.Property{"Leftrightarrow","⇔"},
    R.Property{"Longleftrightarrow","⇔"},R.Property{"implies","⇒"},R.Property{"iff","⇔"},
    R.Property{"mapsto","↦"},R.Property{"longmapsto","↦"},R.Property{"uparrow","↑"},
    R.Property{"downarrow","↓"},R.Property{"partial","∂"},R.Property{"nabla","∇"},R.Property{"int","∫"},
    R.Property{"iint","∬"},R.Property{"iiint","∭"},R.Property{"oint","∮"},R.Property{"sum","∑"},
    R.Property{"prod","∏"},R.Property{"coprod","∐"},R.Property{"infty","∞"},R.Property{"emptyset","∅"},
    R.Property{"varnothing","∅"},R.Property{"angle","∠"},R.Property{"therefore","∴"},
    R.Property{"because","∵"},R.Property{"aleph","ℵ"},R.Property{"beth","ℶ"},R.Property{"gimel","ℷ"},
    R.Property{"daleth","ℸ"},R.Property{"top","⊤"},R.Property{"bot","⊥"},R.Property{"triangle","△"},
    R.Property{"square","□"},R.Property{"lozenge","◊"},R.Property{"checkmark","✓"},
    R.Property{"complement","∁"},R.Property{"wp","℘"},R.Property{"prime","′"},R.Property{"ldots","…"},
    R.Property{"dots","…"},R.Property{"cdots","⋯"},R.Property{"vdots","⋮"},R.Property{"ddots","⋱"},
    R.Property{"ell","ℓ"},R.Property{"hbar","ℏ"},R.Property{"Im","ℑ"},R.Property{"Re","ℜ"},
    R.Property{"langle","⟨"},R.Property{"rangle","⟩"},R.Property{"vert","|"},R.Property{"lvert","|"},
    R.Property{"rvert","|"},R.Property{"Vert","‖"},R.Property{"lVert","‖"},R.Property{"rVert","‖"},
    R.Property{"lbrace","{"},R.Property{"rbrace","}"},R.Property{"backslash","\\"},
    R.Property{"lfloor","⌊"},R.Property{"rfloor","⌋"},R.Property{"lceil","⌈"},R.Property{"rceil","⌉"},
    R.Property{"colon",":"}]}
def namedOperators() -> List<&2,String>:
  ["arccos","arcsin","arctan","arg","cos","cosh","cot","coth","csc","deg","det","dim","exp","gcd","hom",
   "inf","ker","lg","lim","liminf","limsup","ln","log","max","min","Pr","sec","sin","sinh","sup","tan",
   "tanh"]
def limitOperators() -> List<&2,String>:
  ["argmax","argmin","inf","injlim","lim","liminf","limsup","max","min","projlim","sup"]
def displayLimitSymbols() -> List<&2,String>:
  ["bigcap","bigcup","bigodot","bigoplus","bigotimes","bigsqcup","biguplus","bigvee","bigwedge",
   "coprod","int","iint","iiint","oint","prod","sum"]
def relationCommands() -> List<&2,String>:
  ["Leftarrow","Leftrightarrow","Longleftarrow","Longleftrightarrow","Longrightarrow","Rightarrow",
   "Join","Vdash","Vvdash","approx","asymp","bowtie","cong","dashv","fullouterjoin","doteq","downarrow",
   "equiv","ge","geq","geqslant","gets","gg","hookleftarrow","hookrightarrow","iff","implies","in",
   "leadsto","le","leftarrow","leftharpoondown","leftharpoonup","leftrightarrow","leftrightharpoons",
   "leftouterjoin","leq","leqslant","ll","longleftarrow","longleftrightarrow","longmapsto",
   "longrightarrow","ltimes","mapsto","mid","models","ne","nearrow","neq","ni","notin","nvdash",
   "nvDash","nwarrow","parallel","perp","prec","preceq","propto","rightharpoondown","rightharpoonup",
   "rightleftharpoons","rightouterjoin","rightarrow","rightsquigarrow","rtimes","searrow","sim","simeq",
   "sqsubset","sqsubseteq","sqsupset","sqsupseteq","subset","subseteq","succ","succeq","supset",
   "supseteq","swarrow","to","triangleleft","triangleright","twoheadleftarrow","twoheadrightarrow",
   "uparrow","vdash"]
def negatedSymbols() -> R.Record<String>:
  R.Record{[R.Property{"<","≮"},R.Property{">","≯"},R.Property{"=","≠"},R.Property{"∈","∉"},R.Property{"∋","∌"},
    R.Property{"∣","∤"},R.Property{"∥","∦"},R.Property{"∼","≁"},R.Property{"≃","≄"},R.Property{"≅","≇"},
    R.Property{"≈","≉"},R.Property{"≡","≢"},R.Property{"≤","≰"},R.Property{"≥","≱"},R.Property{"≺","⊀"},
    R.Property{"≻","⊁"},R.Property{"⊂","⊄"},R.Property{"⊃","⊅"},R.Property{"⊆","⊈"},R.Property{"⊇","⊉"},
    R.Property{"⊢","⊬"},R.Property{"⊨","⊭"},R.Property{"↔","↮"},R.Property{"←","↚"},R.Property{"→","↛"},
    R.Property{"⇒","⇏"},R.Property{"⇐","⇍"},R.Property{"⇔","⇎"},R.Property{"≼","⋠"},R.Property{"≽","⋡"}]}
def blackboard() -> R.Record<String>:
  R.Record{[R.Property{"C","ℂ"},R.Property{"H","ℍ"},R.Property{"N","ℕ"},R.Property{"P","ℙ"},R.Property{"Q","ℚ"},
    R.Property{"R","ℝ"},R.Property{"Z","ℤ"}]}
def superscripts() -> R.Record<String>:
  R.Record{[R.Property{"0","⁰"},R.Property{"1","¹"},R.Property{"2","²"},R.Property{"3","³"},R.Property{"4","⁴"},
    R.Property{"5","⁵"},R.Property{"6","⁶"},R.Property{"7","⁷"},R.Property{"8","⁸"},R.Property{"9","⁹"},
    R.Property{"+","⁺"},R.Property{"-","⁻"},R.Property{"=","⁼"},R.Property{"(","⁽"},R.Property{")","⁾"},
    R.Property{"a","ᵃ"},R.Property{"b","ᵇ"},R.Property{"c","ᶜ"},R.Property{"d","ᵈ"},R.Property{"e","ᵉ"},
    R.Property{"f","ᶠ"},R.Property{"g","ᵍ"},R.Property{"h","ʰ"},R.Property{"i","ⁱ"},R.Property{"j","ʲ"},
    R.Property{"k","ᵏ"},R.Property{"l","ˡ"},R.Property{"m","ᵐ"},R.Property{"n","ⁿ"},R.Property{"o","ᵒ"},
    R.Property{"p","ᵖ"},R.Property{"r","ʳ"},R.Property{"s","ˢ"},R.Property{"t","ᵗ"},R.Property{"u","ᵘ"},
    R.Property{"v","ᵛ"},R.Property{"w","ʷ"},R.Property{"x","ˣ"},R.Property{"y","ʸ"},R.Property{"z","ᶻ"}]}
def subscripts() -> R.Record<String>:
  R.Record{[R.Property{"0","₀"},R.Property{"1","₁"},R.Property{"2","₂"},R.Property{"3","₃"},R.Property{"4","₄"},
    R.Property{"5","₅"},R.Property{"6","₆"},R.Property{"7","₇"},R.Property{"8","₈"},R.Property{"9","₉"},
    R.Property{"+","₊"},R.Property{"-","₋"},R.Property{"=","₌"},R.Property{"(","₍"},R.Property{")","₎"},
    R.Property{"a","ₐ"},R.Property{"e","ₑ"},R.Property{"h","ₕ"},R.Property{"i","ᵢ"},R.Property{"j","ⱼ"},
    R.Property{"k","ₖ"},R.Property{"l","ₗ"},R.Property{"m","ₘ"},R.Property{"n","ₙ"},R.Property{"o","ₒ"},
    R.Property{"p","ₚ"},R.Property{"r","ᵣ"},R.Property{"s","ₛ"},R.Property{"t","ₜ"},R.Property{"u","ᵤ"},
    R.Property{"v","ᵥ"},R.Property{"x","ₓ"}]}
def spacingCommands() -> List<&2,String>:
  [",",":",";"," ",">","enspace","enskip","medspace","quad","qquad","thickspace","thinspace"]
def negativeSpacingCommands() -> List<&2,String>:
  ["!","negmedspace","negthickspace","negthinspace"]
def fontSwitchCommands() -> List<&2,String>:
  ["bf","cal","it","rm","sf","sl","tt"]
def ignoredCommands() -> List<&2,String>:
  ["displaystyle","limits","nolimits","scriptstyle","scriptscriptstyle","textstyle"]
def sizeCommands() -> List<&2,String>:
  ["big","Big","bigg","Bigg","bigl","Bigl","biggl","Biggl","bigr","Bigr","biggr","Biggr"]
def plainWrappers() -> List<&2,String>:
  ["emph","mathcal","mathbf","mathfrak","mathit","mathrm","mathnormal","mathscr","mathsf","mathtt",
   "mathup","mbox","overbrace","pmb","smash","substack","text","textbf","textit","textmd","textnormal",
   "textrm","textsc","textsf","textsl","texttt","textup","underbrace","bm","boldsymbol"]
def accents() -> R.Record<String>:
  R.Record{[R.Property{"acute","\u{301}"},R.Property{"bar","\u{305}"},R.Property{"breve","\u{306}"},
    R.Property{"check","\u{30c}"},R.Property{"ddot","\u{308}"},R.Property{"dot","\u{307}"},
    R.Property{"grave","\u{300}"},R.Property{"hat","\u{302}"},R.Property{"mathring","\u{30a}"},
    R.Property{"overleftarrow","\u{20d6}"},R.Property{"overleftrightarrow","\u{20e1}"},
    R.Property{"overline","\u{305}"},R.Property{"overrightarrow","\u{20d7}"},
    R.Property{"tilde","\u{303}"},R.Property{"underline","\u{332}"},R.Property{"vec","\u{20d7}"},
    R.Property{"widehat","\u{302}"},R.Property{"widetilde","\u{303}"}]}


# Characters and strings
# ----------------------

# The private-use markers pi threads through rendered text: named-operator
# bounds, layout-node references and protected (non-collapsing) spaces.
def namedOperatorStart() -> Char: '\u{f0004}'
def namedOperatorEnd() -> Char: '\u{f0005}'
def layoutMarkerStart() -> Char: '\u{f0000}'
def layoutMarkerEnd() -> Char: '\u{f0001}'
def protectedSpace() -> Char: '\u{f0002}'
def negativeSpace() -> String: "\u{0}"

# JavaScript's `\s`.
def isSpace(char: Char) -> Bool:
  match char:
    case Chr{code}: Text.whitespace(code)
def isAsciiLetter(char: Char) -> Bool:
  match char:
    case Chr{+code}: (U32.is_ge(code,65) && U32.is_le(code,90)) || (U32.is_ge(code,97) && U32.is_le(code,122))
def isAsciiDigit(char: Char) -> Bool:
  match char:
    case Chr{+code}: U32.is_ge(code,48) && U32.is_le(code,57)
def isWordChar(+char: Char) -> Bool: isAsciiLetter(char) || isAsciiDigit(char) || Char.is_eq(char,'_')
def single(char: Char) -> String: SCon{char,SNil{}}
def member(names: List<&2,String>,+name: String) -> Bool:
  match names:
    case Nil{}: False{}
    case candidate <> rest: String.eq(candidate,name) || member(rest,name)
def lookup(table: R.Record<String>,name: String) -> Maybe<&2,String>: R.get(String,table,name)
def skipSpace(text: String) -> String:
  match text:
    case SNil{}: SNil{}
    case SCon{+char,+rest}: Bool.pick(Unit -> String,isSpace(char),_ => skipSpace(rest),_ => SCon{char,rest})(Unit{})
# `[ \t]*`
def skipBlanks(text: String) -> String:
  match text:
    case SCon{' ',rest}: skipBlanks(rest)
    case SCon{'\t',rest}: skipBlanks(rest)
    case text: text
def startsWithSpace(text: String) -> Bool:
  match text:
    case SNil{}: False{}
    case SCon{char,_}: isSpace(char)
def endsWithSpace(text: String) -> Bool: startsWithSpace(String.reverse(text))
def headIs(text: String,+char: Char) -> Bool:
  match text:
    case SNil{}: False{}
    case SCon{first,_}: Char.is_eq(first,char)
def replaceChar(text: String,+from: Char,+to: String,+reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(reversed)
    case SCon{+char,+rest}: replaceChar(rest,from,to,Bool.pick(String,Char.is_eq(char,from),String.reverse(to) ++ reversed,SCon{char,reversed}))
def withoutChar(text: String,+drop: Char,+reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(reversed)
    case SCon{+char,+rest}: withoutChar(rest,drop,Bool.pick(String,Char.is_eq(char,drop),reversed,SCon{char,reversed}))
def unprotected(text: String) -> String: replaceChar(text,protectedSpace()," ","")
def maxNat(values: List<&2,Nat>,best: Nat) -> Nat:
  match values:
    case Nil{}: best
    case value <> rest: maxNat(rest,Nat.max(best,value))
def widths(lines: List<&2,String>,reversed: List<&2,Nat>) -> List<&2,Nat>:
  match lines:
    case Nil{}: List.reverse(&2,Nat,reversed)
    case line <> rest: widths(rest,U.visibleWidth(line) <> reversed)
def maxWidth(lines: List<&2,String>) -> Nat: maxNat(widths(lines,Nil{}),0n)
type Cut is Data: Cut{before: String,after: String}
# `source.indexOf(needle)`: the text before the first occurrence and after it.
def cutAt(text: String,+needle: String,+reversed: String) -> Maybe<&2,Cut>:
  match text:
    case SNil{}: Bool.pick(Maybe<&2,Cut>,String.eq(needle,""),Some{Cut{String.reverse(reversed),""}},None{})
    case SCon{+char,+rest}:
      Bool.pick(Unit -> Maybe<&2,Cut>,String.starts_with(SCon{char,rest},needle),
        _ => Some{Cut{String.reverse(reversed),String.drop(SCon{char,rest},String.length(needle))}},
        _ => cutAt(rest,needle,SCon{char,reversed}))(Unit{})
def digitValue(char: Char) -> Nat:
  match char:
    case Chr{code}: U32.to_nat((code - 48 : U32))

# Unicode letters and numbers (`\p{L}`, `\p{N}`), decoded once per render.
type Classes is Data: Classes{letters: Regex.Class,numbers: Regex.Class}
def propertyClass(result: Result<&2,&2,Regex.Error,Regex.Class>) -> Regex.Class:
  match result:
    case Done{value}: value
    case Fail{_}: Regex.EmptyClass{}
def unicodeClasses() -> Classes: Classes{propertyClass(Regex.property("L")),propertyClass(Regex.property("N"))}
def isLetter(classes: Classes,char: Char) -> Bool:
  match classes char:
    case Classes{letters,_} Chr{code}: Regex.contains(letters,code)
def isNumber(classes: Classes,char: Char) -> Bool:
  match classes char:
    case Classes{_,numbers} Chr{code}: Regex.contains(numbers,code)
def isAlphanumeric(+classes: Classes,+char: Char) -> Bool: isLetter(classes,char) || isNumber(classes,char)
# `/^[\p{L}\p{N}.]+$/u`
def plainWord(text: String,+classes: Classes,seen: Bool) -> Bool:
  match text:
    case SNil{}: seen
    case SCon{+char,+rest}: (Char.is_eq(char,'.') || isAlphanumeric(classes,char)) && plainWord(rest,classes,True{})
# `/^[\p{N}.]+$/u`
def plainNumber(text: String,+classes: Classes,seen: Bool) -> Bool:
  match text:
    case SNil{}: seen
    case SCon{+char,+rest}: (Char.is_eq(char,'.') || isNumber(classes,char)) && plainNumber(rest,classes,True{})

# Scripts, fractions and roots
# ----------------------------

def replaceCharacters(value: String,+replacements: R.Record<String>,+reversed: String) -> Maybe<&2,String>:
  match value:
    case SNil{}: Some{String.reverse(reversed)}
    case SCon{char,rest}:
      +found = lookup(replacements,single(char))
      Bool.pick(Unit -> Maybe<&2,String>,Maybe.is_none(&2,String,found),_ => None{},
        _ => replaceCharacters(rest,replacements,String.reverse(Maybe.default(&2,String,found,"")) ++ reversed))(Unit{})
def isScriptOperator(+char: Char) -> Bool: Char.is_eq(char,'=') || Char.is_eq(char,'+') || Char.is_eq(char,'-')
# `/\s*([=+-])\s*/g` → "$1": a whitespace run next to `=`, `+` or `-` is
# dropped. `pending` holds the current run, reversed.
def tightenOperators(text: String,+pending: String,+afterOperator: Bool,+reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(Bool.pick(String,afterOperator,reversed,pending ++ reversed))
    case SCon{+char,+rest}:
      Bool.pick(Unit -> String,isSpace(char),_ => tightenOperators(rest,SCon{char,pending},afterOperator,reversed),
        _ => Bool.pick(Unit -> String,isScriptOperator(char),_ => tightenOperators(rest,"",True{},SCon{char,reversed}),
          _ => tightenOperators(rest,"",False{},SCon{char,Bool.pick(String,afterOperator,reversed,pending ++ reversed)}))(Unit{}))(Unit{})
def normalizeScriptValue(value: String) -> String: tightenOperators(Text.trim(value),"",False{},"")
def scriptTable(sub: Bool) -> R.Record<String>:
  match sub:
    case True{}: subscripts()
    case False{}: superscripts()
def formatUnicodeScript(value: String,sub: Bool) -> Maybe<&2,String>:
  replaceCharacters(normalizeScriptValue(value),scriptTable(sub),"")
def allAsciiLetters(text: String,seen: Bool) -> Bool:
  match text:
    case SNil{}: seen
    case SCon{char,rest}: isAsciiLetter(char) && allAsciiLetters(rest,True{})
def formatPlainScript(unicode: Maybe<&2,String>,+value: String,+sub: Bool) -> String:
  match unicode:
    case Some{text}: text
    case None{}:
      +prefix = Bool.pick(String,sub,"_","^")
      Bool.pick(String,Nat.is_eq(String.length(value),1n) || (sub && allAsciiLetters(value,False{})),prefix ++ value,prefix ++ "(" ++ value ++ ")")
def formatScript(value: String,+sub: Bool) -> String:
  +normalized = normalizeScriptValue(value)
  formatPlainScript(formatUnicodeScript(normalized,sub),normalized,sub)
def formatFraction(numerator: String,denominator: String,+classes: Classes) -> String:
  +top = Text.trim(numerator)
  +bottom = Text.trim(denominator)
  Bool.pick(String,plainWord(top,classes,False{}),top,"(" ++ top ++ ")") ++ "/" ++
    Bool.pick(String,plainNumber(bottom,classes,False{}) || Nat.is_eq(String.length(bottom),1n),bottom,"(" ++ bottom ++ ")")
def formatRoot(value: String,+symbol: String,+classes: Classes) -> String:
  +root = Text.trim(value)
  Bool.pick(String,plainWord(root,classes,False{}),symbol ++ root,symbol ++ "(" ++ root ++ ")")

# Output normalization
# --------------------

# `[\p{L}\p{N})\]}\u{f0001}]` before a named operator gets a space.
def spacesBeforeOperator(+classes: Classes,+char: Char) -> Bool:
  isAlphanumeric(classes,char) || Char.is_eq(char,')') || Char.is_eq(char,']') || Char.is_eq(char,'}') || Char.is_eq(char,layoutMarkerEnd())
# `[\p{L}\p{N}√\u{f0000}]` after a named operator gets a space.
def spacesAfterOperator(text: String,+classes: Classes) -> Bool:
  match text:
    case SNil{}: False{}
    case SCon{+char,_}: isAlphanumeric(classes,char) || Char.is_eq(char,'√') || Char.is_eq(char,layoutMarkerStart())
def operatorLeftSpacing(text: String,+classes: Classes,+spaced: Bool,+reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(reversed)
    case SCon{+char,+rest}:
      operatorLeftSpacing(rest,classes,spacesBeforeOperator(classes,char),
        Bool.pick(String,Char.is_eq(char,namedOperatorStart()),Bool.pick(String,spaced,SCon{' ',reversed},reversed),SCon{char,reversed}))
def operatorRightSpacing(text: String,+classes: Classes,+reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(reversed)
    case SCon{+char,+rest}:
      operatorRightSpacing(rest,classes,
        Bool.pick(String,Char.is_eq(char,namedOperatorEnd()),Bool.pick(String,spacesAfterOperator(rest,classes),SCon{' ',reversed},reversed),SCon{char,reversed}))
# `line.replace(/[ \t]+/g, " ")`
def collapseBlanks(text: String,+blank: Bool,+reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(reversed)
    case SCon{+char,+rest}:
      +isBlank = Char.is_eq(char,' ') || Char.is_eq(char,'\t')
      collapseBlanks(rest,isBlank,Bool.pick(String,isBlank,Bool.pick(String,blank,reversed,SCon{' ',reversed}),SCon{char,reversed}))
def normalizedLines(lines: List<&2,String>,reversed: List<&2,String>) -> List<&2,String>:
  match lines:
    case Nil{}: List.reverse(&2,String,reversed)
    case line <> rest: normalizedLines(rest,Text.trim(collapseBlanks(line,False{},"")) <> reversed)
# pi drops an empty first and last line before the final trim; the trim
# removes them anyway, so the lines are joined and trimmed directly.
def normalizeOutput(value: String,+classes: Classes) -> String:
  Text.trim(String.join(normalizedLines(Strings.split(operatorRightSpacing(operatorLeftSpacing(value,classes,False{},""),classes,""),'\n'),Nil{}),"\n"))

# Layout
# ------

type LayoutNode is Data:
  FractionNode{numerator: String,denominator: String}
  OperatorNode{operator: String,lower: Maybe<&2,String>,upper: Maybe<&2,String>}
  ScriptNode{lower: Maybe<&2,String>,upper: Maybe<&2,String>}
  MatrixNode{lines: List<&2,String>,baseline: Nat}
type Layout is Data: Layout{lines: List<&2,String>,width: Nat,baseline: Nat}

def marker(index: Nat) -> String: single(layoutMarkerStart()) ++ Nat.show(index) ++ single(layoutMarkerEnd())
def padLayoutLine(+line: String,+width: Nat,centered: Bool) -> String:
  +padding = width - U.visibleWidth(line)
  +left = Bool.pick(Nat,centered,padding / 2n,0n)
  U.spaces(left,"") ++ line ++ U.spaces(padding - left,"")
def padLines(lines: List<&2,String>,+width: Nat,+centered: Bool,reversed: List<&2,String>) -> List<&2,String>:
  match lines:
    case Nil{}: List.reverse(&2,String,reversed)
    case line <> rest: padLines(rest,width,centered,padLayoutLine(line,width,centered) <> reversed)
def textLayout(+text: String) -> Layout: Layout{[text],U.visibleWidth(text),0n}
def paddedOrBlank(line: Maybe<&2,String>,+width: Nat) -> String:
  match line:
    case None{}: U.spaces(width,"")
    case Some{text}: padLayoutLine(text,width,False{})
def layoutLine(lines: List<&2,String>,index: Nat,+width: Nat) -> String:
  paddedOrBlank(List.get(&2,String,lines,index),width)
def layoutRow(layouts: List<&2,Layout>,+row: Nat,+baseline: Nat,line: String) -> String:
  match layouts:
    case Nil{}: Text.trimEnd(line)
    case Layout{lines,+width,+inner} <> rest:
      +shifted = row + inner
      +piece = Bool.pick(Unit -> String,Nat.is_ge(shifted,baseline),_ => layoutLine(lines,shifted - baseline,width),_ => U.spaces(width,""))(Unit{})
      layoutRow(rest,row,baseline,line ++ piece)
def layoutRows(count: Nat,+layouts: List<&2,Layout>,+row: Nat,+baseline: Nat,reversed: List<&2,String>) -> List<&2,String>:
  match count:
    case Zero{}: List.reverse(&2,String,reversed)
    case Succ{more}: layoutRows(more,layouts,Succ{row},baseline,layoutRow(layouts,row,baseline,"") <> reversed)
def baselines(layouts: List<&2,Layout>,best: Nat) -> Nat:
  match layouts:
    case Nil{}: best
    case Layout{_,_,baseline} <> rest: baselines(rest,Nat.max(best,baseline))
def belows(layouts: List<&2,Layout>,best: Nat) -> Nat:
  match layouts:
    case Nil{}: best
    case Layout{lines,_,baseline} <> rest: belows(rest,Nat.max(best,List.length(&2,String,lines) - baseline - 1n))
def totalWidth(layouts: List<&2,Layout>,total: Nat) -> Nat:
  match layouts:
    case Nil{}: total
    case Layout{_,width,_} <> rest: totalWidth(rest,total + width)
def joinedLayouts(+layouts: List<&2,Layout>) -> Layout:
  +baseline = baselines(layouts,0n)
  Layout{layoutRows(baseline + belows(layouts,0n) + 1n,layouts,0n,baseline,Nil{}),totalWidth(layouts,0n),baseline}
# Layouts side by side, each shifted so the baselines share a row.
def joinLayouts(+layouts: List<&2,Layout>) -> Layout:
  Bool.pick(Unit -> Layout,List.is_empty(&2,Layout,layouts),_ => Layout{[""],0n,0n},_ => joinedLayouts(layouts))(Unit{})

# A laid-out node, and whether it is a matrix (whose neighbouring text
# keeps one separating space).
type Placed is Data: Placed{layout: Layout,matrix: Bool}
type Previous is Data:
  NoPrevious{}
  PreviousNode{matrix: Bool}
type Segment is Data:
  TextSegment{text: String}
  NodeSegment{placed: Placed}
def previousMatrix(previous: Previous) -> Bool:
  match previous:
    case NoPrevious{}: False{}
    case PreviousNode{matrix}: matrix
def hasPrevious(previous: Previous) -> Bool:
  match previous:
    case NoPrevious{}: False{}
    case PreviousNode{_}: True{}
def textBefore(+sliced: String,+previous: Previous,+nodeMatrix: Bool) -> Layout:
  +trimmed = Text.trimEnd(Bool.pick(String,hasPrevious(previous),Text.trimStart(sliced),sliced))
  +lead = previousMatrix(previous) && startsWithSpace(sliced)
  +trail = nodeMatrix && endsWithSpace(sliced)
  textLayout(Bool.pick(String,String.eq(trimmed,""),Bool.pick(String,lead || trail," ",""),
    Bool.pick(String,lead," ","") ++ trimmed ++ Bool.pick(String,trail," ","")))
def textAfter(+sliced: String,+previous: Previous) -> Layout:
  +trimmed = Bool.pick(String,hasPrevious(previous),Text.trimStart(sliced),sliced)
  textLayout(Bool.pick(String,previousMatrix(previous) && startsWithSpace(sliced)," " ++ trimmed,trimmed))
def placedMatrix(placed: Placed) -> Bool:
  match placed:
    case Placed{_,matrix}: matrix
def placedLayout(placed: Placed) -> Layout:
  match placed:
    case Placed{layout,_}: layout
def layoutSegments(segments: List<&2,Segment>,+pending: String,+previous: Previous,+reversed: List<&2,Layout>) -> List<&2,Layout>:
  match segments:
    case Nil{}: List.reverse(&2,Layout,Bool.pick(List<&2,Layout>,String.eq(pending,""),reversed,textAfter(pending,previous) <> reversed))
    case TextSegment{text} <> rest: layoutSegments(rest,pending ++ text,previous,reversed)
    case NodeSegment{+placed} <> rest:
      +matrix = placedMatrix(placed)
      +before = Bool.pick(List<&2,Layout>,String.eq(pending,""),reversed,textBefore(pending,previous,matrix) <> reversed)
      layoutSegments(rest,"",PreviousNode{matrix},placedLayout(placed) <> before)
type MarkerRef is Data: MarkerRef{index: Nat,rest: String}
# `(\d+)\u{f0001}` after a marker start.
def markerDigits(text: String,+value: Nat,+seen: Bool) -> Maybe<&2,MarkerRef>:
  match text:
    case SNil{}: None{}
    case SCon{+char,+rest}:
      Bool.pick(Unit -> Maybe<&2,MarkerRef>,Char.is_eq(char,layoutMarkerEnd()),
        _ => Bool.pick(Maybe<&2,MarkerRef>,seen,Some{MarkerRef{value,rest}},None{}),
        _ => Bool.pick(Unit -> Maybe<&2,MarkerRef>,isAsciiDigit(char),_ => markerDigits(rest,value * 10n + digitValue(char),True{}),_ => None{})(Unit{}))(Unit{})
def referencedSegments(reference: Maybe<&2,MarkerRef>,found: Maybe<&2,Placed>,+piece: String) -> List<&2,Segment>:
  match reference found:
    case Some{MarkerRef{_,rest}} Some{placed}: [NodeSegment{placed},TextSegment{rest}]
    case _ _: [TextSegment{single(layoutMarkerStart()) ++ piece}]
def lookupPlaced(reference: Maybe<&2,MarkerRef>,placed: List<&2,Placed>) -> Maybe<&2,Placed>:
  match reference:
    case None{}: None{}
    case Some{MarkerRef{index,_}}: List.get(&2,Placed,placed,index)
def pieceSegments(+piece: String,+placed: List<&2,Placed>) -> List<&2,Segment>:
  +reference = markerDigits(piece,0n,False{})
  referencedSegments(reference,lookupPlaced(reference,placed),piece)
def markedSegments(pieces: List<&2,String>,+placed: List<&2,Placed>,reversed: List<&2,Segment>) -> List<&2,Segment>:
  match pieces:
    case Nil{}: List.reverse(&2,Segment,reversed)
    case piece <> rest: markedSegments(rest,placed,List.append(&2,Segment,List.reverse(&2,Segment,pieceSegments(piece,placed)),reversed))
# A source line split at layout markers. A marker naming no laid-out node
# stays text, as pi skips it.
def splitSegments(pieces: List<&2,String>,+placed: List<&2,Placed>) -> List<&2,Segment>:
  match pieces:
    case Nil{}: Nil{}
    case first <> rest: TextSegment{first} <> markedSegments(rest,placed,Nil{})
def lineSegments(line: String,+placed: List<&2,Placed>) -> List<&2,Segment>:
  splitSegments(Strings.split(line,layoutMarkerStart()),placed)
def layoutLinesOf(layout: Layout) -> List<&2,String>:
  match layout:
    case Layout{lines,_,_}: lines
def layoutBaseline(layout: Layout) -> Nat:
  match layout:
    case Layout{_,_,baseline}: baseline
def layoutLines(lines: List<&2,String>,+placed: List<&2,Placed>,first: Maybe<&2,Nat>,reversed: List<&2,String>) -> Layout:
  match lines:
    case Nil{}:
      +rendered = List.reverse(&2,String,reversed)
      Layout{rendered,maxWidth(rendered),Maybe.default(&2,Nat,first,0n)}
    case line <> rest:
      +joined = joinLayouts(layoutSegments(lineSegments(line,placed),"",NoPrevious{},Nil{}))
      layoutLines(rest,placed,Maybe.or(&2,Nat,first,Some{layoutBaseline(joined)}),List.append(&2,String,List.reverse(&2,String,layoutLinesOf(joined)),reversed))
# Lays out text whose markers refer to already placed nodes.
def renderLayout(source: String,+placed: List<&2,Placed>) -> Layout:
  layoutLines(Strings.split(source,'\n'),placed,None{},Nil{})

def repeatText(+text: String,count: Nat,result: String) -> String:
  match count:
    case Zero{}: result
    case Succ{more}: repeatText(text,more,text ++ result)
def fractionLayout(numerator: Layout,denominator: Layout) -> Placed:
  match numerator denominator:
    case Layout{+top,+topWidth,_} Layout{bottom,+bottomWidth,_}:
      +content = Nat.max(Nat.max(topWidth,bottomWidth),1n)
      +width = content + 2n
      Placed{Layout{List.append(&2,String,padLines(top,width,True{},Nil{}),(" " ++ repeatText("─",content,"") ++ " ") <> padLines(bottom,width,True{},Nil{})),width,List.length(&2,String,top)},False{}}
def optionalWidth(value: Maybe<&2,String>) -> Nat:
  match value:
    case None{}: 0n
    case Some{text}: U.visibleWidth(text)
def optionalLine(value: Maybe<&2,String>,+width: Nat) -> List<&2,String>:
  match value:
    case None{}: Nil{}
    case Some{text}: [padLayoutLine(text,width,True{}) ++ " "]
def operatorLayout(+operator: String,+lower: Maybe<&2,String>,+upper: Maybe<&2,String>) -> Placed:
  +content = Nat.max(U.visibleWidth(operator),Nat.max(optionalWidth(lower),optionalWidth(upper)))
  +lines = List.append(&2,String,optionalLine(upper,content),(padLayoutLine(operator,content,True{}) ++ " ") <> optionalLine(lower,content))
  Placed{Layout{lines,content + 1n,Bool.pick(Nat,Maybe.is_none(&2,String,upper),0n,1n)},False{}}
def optionalLayout(value: Maybe<&2,String>,+placed: List<&2,Placed>) -> Maybe<&2,Layout>:
  match value:
    case None{}: None{}
    case Some{text}: Some{renderLayout(text,placed)}
def layoutWidth(value: Maybe<&2,Layout>) -> Nat:
  match value:
    case None{}: 0n
    case Some{Layout{_,width,_}}: width
def layoutPadded(value: Maybe<&2,Layout>,+width: Nat) -> List<&2,String>:
  match value:
    case None{}: Nil{}
    case Some{Layout{lines,_,_}}: padLines(lines,width,False{},Nil{})
def layoutHeight(value: Maybe<&2,Layout>) -> Nat:
  match value:
    case None{}: 0n
    case Some{Layout{lines,_,_}}: List.length(&2,String,lines)
def scriptLayout(+upper: Maybe<&2,Layout>,+lower: Maybe<&2,Layout>) -> Placed:
  +width = Nat.max(layoutWidth(upper),layoutWidth(lower))
  Placed{Layout{List.append(&2,String,layoutPadded(upper,width),U.spaces(width,"") <> layoutPadded(lower,width)),width,layoutHeight(upper)},False{}}
def matrixLayout(+lines: List<&2,String>,baseline: Nat) -> Placed:
  +width = maxWidth(lines)
  Placed{Layout{padLines(lines,width,False{},Nil{}),width,baseline},True{}}
def nodeLayout(node: LayoutNode,+placed: List<&2,Placed>) -> Placed:
  match node:
    case FractionNode{numerator,denominator}: fractionLayout(renderLayout(numerator,placed),renderLayout(denominator,placed))
    case OperatorNode{operator,lower,upper}: operatorLayout(operator,lower,upper)
    case ScriptNode{lower,upper}: scriptLayout(optionalLayout(upper,placed),optionalLayout(lower,placed))
    case MatrixNode{lines,baseline}: matrixLayout(lines,baseline)
# Nodes are laid out in creation order: a node's text only refers to nodes
# created while its arguments were parsed, which precede it.
def placeAll(nodes: List<&2,LayoutNode>,+placed: List<&2,Placed>) -> List<&2,Placed>:
  match nodes:
    case Nil{}: placed
    case node <> rest: placeAll(rest,List.append(&2,Placed,placed,[nodeLayout(node,placed)]))

# Environments
# ------------

# `body.split(/\\\\(?:\[[^\]\n]*\])?/)`: rows end at `\\`, which may carry a
# spacing argument such as `[4pt]`.
def spacingArgument(text: String,+original: String) -> String:
  match text:
    case SNil{}: original
    case SCon{']',rest}: rest
    case SCon{'\n',_}: original
    case SCon{_,rest}: spacingArgument(rest,original)
def afterRowBreak(+text: String) -> String:
  match text:
    case SCon{'[',rest}: spacingArgument(rest,text)
    case _: text
# `fuel` is the text's length: each step consumes a character.
def splitEnvironmentRows(fuel: Nat,text: String,+current: String,+reversed: List<&2,String>) -> List<&2,String>:
  match fuel text:
    case Succ{+more} SCon{+char,+rest}:
      Bool.pick(Unit -> List<&2,String>,Char.is_eq(char,'\\') && headIs(rest,'\\'),
        _ => splitEnvironmentRows(more,afterRowBreak(String.drop(rest,1n)),"",String.reverse(current) <> reversed),
        _ => splitEnvironmentRows(more,rest,SCon{char,current},reversed))(Unit{})
    case _ _: List.reverse(&2,String,String.reverse(current) <> reversed)
def rowsOf(+body: String) -> List<&2,String>: splitEnvironmentRows(String.length(body),body,"",Nil{})
# `body.replace(/^\s*\{[^}]*\}/, "")`: an array's column specification.
def columnSpecEnd(text: String) -> Maybe<&2,String>:
  match text:
    case SNil{}: None{}
    case SCon{'}',rest}: Some{rest}
    case SCon{_,rest}: columnSpecEnd(rest)
def columnSpecAfter(text: String,+body: String) -> String:
  match text:
    case SCon{'{',rest}: Maybe.default(&2,String,columnSpecEnd(rest),body)
    case _: body
def withoutColumnSpec(+body: String) -> String: columnSpecAfter(skipSpace(body),body)
def gridRows(rows: List<&2,String>,reversed: List<&2,List<&2,String>>) -> List<&2,List<&2,String>>:
  match rows:
    case Nil{}: List.reverse(&2,List<&2,String>,reversed)
    case row <> rest: gridRows(rest,Strings.split(row,'&') <> reversed)
# alignedat pairs its `&`-separated cells, joining pairs with a space.
def cellPairs(cells: List<&2,String>,reversed: List<&2,String>) -> List<&2,String>:
  match cells:
    case Nil{}: List.reverse(&2,String,reversed)
    case left <> Nil{}: List.reverse(&2,String,left <> reversed)
    case left <> right <> rest: cellPairs(rest,(left ++ right) <> reversed)
def alignedSources(rows: List<&2,String>,+alignedAt: Bool,reversed: List<&2,String>) -> List<&2,String>:
  match rows:
    case Nil{}: List.reverse(&2,String,reversed)
    case row <> rest:
      +cells = Strings.split(row,'&')
      alignedSources(rest,alignedAt,Bool.pick(String,alignedAt,String.join(cellPairs(cells,Nil{})," "),String.concat(cells)) <> reversed)

type Delimiters is Data: Delimiters{topLeft: String,topRight: String,middleLeft: String,middleRight: String,bottomLeft: String,bottomRight: String}
type MatrixStyle is Data:
  PlainMatrix{}
  DelimitedMatrix{delimiters: Delimiters}
type Grid is Data:
  CasesGrid{}
  MatrixGrid{style: MatrixStyle}
type EnvironmentKind is Data:
  EquationEnvironment{}
  AlignedEnvironment{alignedAt: Bool}
  CasesEnvironment{}
  MatrixEnvironment{array: Bool,style: MatrixStyle}
  UnknownEnvironment{}
def delimitedStyle(+name: String) -> MatrixStyle:
  Bool.pick(Unit -> MatrixStyle,String.eq(name,"pmatrix"),_ => DelimitedMatrix{Delimiters{"⎛","⎞","⎜","⎟","⎝","⎠"}},
  _ => Bool.pick(Unit -> MatrixStyle,String.eq(name,"bmatrix"),_ => DelimitedMatrix{Delimiters{"⎡","⎤","⎢","⎥","⎣","⎦"}},
  _ => Bool.pick(Unit -> MatrixStyle,String.eq(name,"Bmatrix"),_ => DelimitedMatrix{Delimiters{"⎧","⎫","⎨","⎬","⎩","⎭"}},
  _ => Bool.pick(Unit -> MatrixStyle,String.eq(name,"vmatrix"),_ => DelimitedMatrix{Delimiters{"│","│","│","│","│","│"}},
  _ => Bool.pick(Unit -> MatrixStyle,String.eq(name,"Vmatrix"),_ => DelimitedMatrix{Delimiters{"║","║","║","║","║","║"}},
  _ => PlainMatrix{})(Unit{}))(Unit{}))(Unit{}))(Unit{}))(Unit{})
def environmentKind(+name: String) -> EnvironmentKind:
  Bool.pick(Unit -> EnvironmentKind,member(["equation","equation*","displaymath"],name),_ => EquationEnvironment{},
  _ => Bool.pick(Unit -> EnvironmentKind,member(["aligned","align","align*","alignedat","alignat","alignat*","gather","gathered","multline","multline*","split"],name),
    _ => AlignedEnvironment{member(["alignedat","alignat","alignat*"],name)},
  _ => Bool.pick(Unit -> EnvironmentKind,member(["cases","cases*"],name),_ => CasesEnvironment{},
  _ => Bool.pick(Unit -> EnvironmentKind,member(["array","matrix","smallmatrix","pmatrix","bmatrix","Bmatrix","vmatrix","Vmatrix"],name),
    _ => MatrixEnvironment{String.eq(name,"array"),delimitedStyle(name)},
  _ => UnknownEnvironment{})(Unit{}))(Unit{}))(Unit{}))(Unit{})

# A rendered grid is inline text or a multi-line node.
type GridResult is Data:
  GridText{text: String}
  GridNode{node: LayoutNode}

# `value.replace(/,\s*$/, "")`
def withoutTrailingCommaFrom(reversed: String,+value: String) -> String:
  match reversed:
    case SCon{',',rest}: String.reverse(rest)
    case _: value
def withoutTrailingComma(+value: String) -> String: withoutTrailingCommaFrom(skipSpace(String.reverse(value)),value)
def firstCell(row: List<&2,String>) -> String: withoutTrailingComma(Maybe.default(&2,String,List.head(&2,String,row),""))
def secondCell(row: List<&2,String>) -> String: Maybe.default(&2,String,List.get(&2,String,row,1n),"")
def caseValueWidths(rows: List<&2,List<&2,String>>,best: Nat) -> Nat:
  match rows:
    case Nil{}: best
    case row <> rest: caseValueWidths(rest,Nat.max(best,U.visibleWidth(firstCell(row))))
# `/^(?:if|when|for|otherwise)\b/i`
def startsWithWordChar(text: String) -> Bool:
  match text:
    case SNil{}: False{}
    case SCon{char,_}: isWordChar(char)
def keywordAt(+text: String,+keyword: String) -> Bool:
  String.starts_with(text,keyword) && Bool.not(startsWithWordChar(String.drop(text,String.length(keyword))))
def conditionPrefix(condition: String) -> String:
  +lower = Text.asciiLower(condition)
  Bool.pick(String,keywordAt(lower,"if") || keywordAt(lower,"when") || keywordAt(lower,"for") || keywordAt(lower,"otherwise")," "," if ")
def caseContent(+row: List<&2,String>,+valueWidth: Nat) -> String:
  +value = firstCell(row)
  +condition = secondCell(row)
  Bool.pick(Unit -> String,String.eq(condition,""),_ => value,
    _ => value ++ repeatText(single(protectedSpace()),valueWidth - U.visibleWidth(value),"") ++ conditionPrefix(condition) ++ condition)(Unit{})
def caseContents(rows: List<&2,List<&2,String>>,+valueWidth: Nat,reversed: List<&2,String>) -> List<&2,String>:
  match rows:
    case Nil{}: List.reverse(&2,String,reversed)
    case +row <> rest: caseContents(rest,valueWidth,caseContent(row,valueWidth) <> reversed)
# The brace rows; an even count gets a bare middle piece.
def braceRows(contents: List<&2,String>,+index: Nat,+middle: Nat,+even: Bool,+reversed: List<&2,Maybe<&2,String>>) -> List<&2,Maybe<&2,String>>:
  match contents:
    case Nil{}: List.reverse(&2,Maybe<&2,String>,reversed)
    case content <> rest:
      +withGap = Bool.pick(List<&2,Maybe<&2,String>>,even && Nat.is_eq(index,middle),None{} <> reversed,reversed)
      braceRows(rest,Succ{index},middle,even,Some{content} <> withGap)
def braceLines(rows: List<&2,Maybe<&2,String>>,+index: Nat,+last: Nat,reversed: List<&2,String>) -> List<&2,String>:
  match rows:
    case Nil{}: List.reverse(&2,String,reversed)
    case row <> rest:
      +delimiter = Bool.pick(String,Nat.is_eq(index,0n),"⎧",Bool.pick(String,Nat.is_eq(index,last),"⎩","⎨"))
      braceLines(rest,Succ{index},last,Maybe.default(&2,String,Maybe.map(&2,String,String,content => delimiter ++ " " ++ content,row),delimiter) <> reversed)
def renderCases(+rows: List<&2,List<&2,String>>) -> GridResult:
  +contents = caseContents(rows,caseValueWidths(rows,0n),Nil{})
  +count = List.length(&2,String,contents)
  Bool.pick(Unit -> GridResult,Nat.is_le(count,1n),
    _ => GridText{Maybe.default(&2,String,Maybe.map(&2,String,String,content => "⎧ " ++ content,List.head(&2,String,contents)),"")},
    _ => GridNode{MatrixNode{braceLines(braceRows(contents,0n,count / 2n,Nat.is_eq(count % 2n,0n),Nil{}),0n,count - count % 2n,Nil{}),count / 2n}})(Unit{})
def cellAt(row: List<&2,String>,index: Nat) -> String: Maybe.default(&2,String,List.get(&2,String,row,index),"")
def columnWidth(rows: List<&2,List<&2,String>>,+index: Nat,best: Nat) -> Nat:
  match rows:
    case Nil{}: best
    case row <> rest: columnWidth(rest,index,Nat.max(best,U.visibleWidth(cellAt(row,index))))
def columnWidths(count: Nat,+rows: List<&2,List<&2,String>>,+index: Nat,reversed: List<&2,Nat>) -> List<&2,Nat>:
  match count:
    case Zero{}: List.reverse(&2,Nat,reversed)
    case Succ{more}: columnWidths(more,rows,Succ{index},columnWidth(rows,index,0n) <> reversed)
def rowLengths(rows: List<&2,List<&2,String>>,best: Nat) -> Nat:
  match rows:
    case Nil{}: best
    case row <> rest: rowLengths(rest,Nat.max(best,List.length(&2,String,row)))
def paddedCells(sizes: List<&2,Nat>,+row: List<&2,String>,+index: Nat,reversed: List<&2,String>) -> List<&2,String>:
  match sizes:
    case Nil{}: List.reverse(&2,String,reversed)
    case size <> rest:
      +cell = cellAt(row,index)
      paddedCells(rest,row,Succ{index},(cell ++ repeatText(single(protectedSpace()),size - U.visibleWidth(cell),"")) <> reversed)
def matrixRows(rows: List<&2,List<&2,String>>,+sizes: List<&2,Nat>,reversed: List<&2,String>) -> List<&2,String>:
  match rows:
    case Nil{}: List.reverse(&2,String,reversed)
    case row <> rest: matrixRows(rest,sizes,String.join(paddedCells(sizes,row,0n,Nil{})," │ ") <> reversed)
def delimitedRows(rows: List<&2,String>,+delimiters: Delimiters,+index: Nat,+last: Nat,reversed: List<&2,String>) -> List<&2,String>:
  match rows:
    case Nil{}: List.reverse(&2,String,reversed)
    case row <> rest:
      match delimiters:
        case Delimiters{+topLeft,+topRight,+middleLeft,+middleRight,+bottomLeft,+bottomRight}:
          +left = Bool.pick(String,Nat.is_eq(index,0n),topLeft,Bool.pick(String,Nat.is_eq(index,last),bottomLeft,middleLeft))
          +right = Bool.pick(String,Nat.is_eq(index,0n),topRight,Bool.pick(String,Nat.is_eq(index,last),bottomRight,middleRight))
          delimitedRows(rest,Delimiters{topLeft,topRight,middleLeft,middleRight,bottomLeft,bottomRight},Succ{index},last,(left ++ " " ++ row ++ " " ++ right) <> reversed)
def styledRows(style: MatrixStyle,+rows: List<&2,String>) -> List<&2,String>:
  match style:
    case PlainMatrix{}: rows
    case DelimitedMatrix{delimiters}: delimitedRows(rows,delimiters,0n,List.length(&2,String,rows) - 1n,Nil{})
def matrixResult(+lines: List<&2,String>) -> GridResult:
  Bool.pick(Unit -> GridResult,Nat.is_le(List.length(&2,String,lines),1n),
    _ => GridText{Maybe.default(&2,String,List.head(&2,String,lines),"")},_ => GridNode{MatrixNode{lines,0n}})(Unit{})
def renderMatrix(style: MatrixStyle,+rows: List<&2,List<&2,String>>) -> GridResult:
  matrixResult(styledRows(style,matrixRows(rows,columnWidths(rowLengths(rows,0n),rows,0n,Nil{}),Nil{})))
def renderGrid(grid: Grid,rows: List<&2,List<&2,String>>) -> GridResult:
  match grid:
    case CasesGrid{}: renderCases(rows)
    case MatrixGrid{style}: renderMatrix(style,rows)
def someNonEmpty(cells: List<&2,String>) -> Bool:
  match cells:
    case Nil{}: False{}
    case cell <> rest: Bool.not(String.eq(cell,"")) || someNonEmpty(rest)

# Parser
# ------
#
# pi's LatexParser is a recursive-descent parser over a mutable position.
# Here it is a machine: `input` is the unparsed rest of the current source,
# `Context` holds the parser's flags, tasks are the parser's methods and
# frames are the points where a method resumes after a nested call returns
# its string. `renderNested` runs a fresh context over another source and
# restores the caller's on return. Layout nodes are an explicit list shared
# by all nested parsers, as pi shares its node array.

type Context is Data: Context{supported: Bool,stackFractions: Bool,scriptDepth: Nat,display: Bool}
def rejected(context: Context) -> Context:
  match context:
    case Context{_,stack,depth,display}: Context{False{},stack,depth,display}
def withStack(context: Context,stack: Bool) -> Context:
  match context:
    case Context{supported,_,depth,display}: Context{supported,stack,depth,display}
def deeper(context: Context) -> Context:
  match context:
    case Context{supported,stack,depth,display}: Context{supported,stack,Succ{depth},display}
def shallower(context: Context) -> Context:
  match context:
    case Context{supported,stack,depth,display}: Context{supported,stack,depth - 1n,display}
def supportedOf(context: Context) -> Bool:
  match context:
    case Context{supported,_,_,_}: supported
def stackOf(context: Context) -> Bool:
  match context:
    case Context{_,stack,_,_}: stack
def depthOf(context: Context) -> Nat:
  match context:
    case Context{_,_,depth,_}: depth
def displayOf(context: Context) -> Bool:
  match context:
    case Context{_,_,_,display}: display

type Task is Data:
  Sequence{closing: Bool,reversed: String}
  Command{}
  Required{stackFractions: Bool}
  Scripts{sub: Bool}
  Operator{operator: String,bracket: Bool,limits: Bool,spaced: Bool}
  OperatorScripts{operator: String,bracket: Bool,limits: Bool,spaced: Bool,lower: Maybe<&2,String>,upper: Maybe<&2,String>}
  Environment{}
  Nested{source: String,stackFractions: Bool}
  Rows{sources: List<&2,String>,done: List<&2,String>}
  Cells{grid: Grid,rows: List<&2,List<&2,String>>,pending: List<&2,String>,cells: List<&2,String>,done: List<&2,List<&2,String>>}
type Frame is Data:
  AfterGroup{closing: Bool,reversed: String}
  AfterCommand{closing: Bool,reversed: String}
  AfterScript{closing: Bool,reversed: String}
  RestoreStack{previous: Bool}
  FirstScript{sub: Bool}
  SecondScript{sub: Bool,first: String}
  NotArgument{}
  Numerator{stack: Bool}
  Denominator{stack: Bool,numerator: String}
  RootDegree{}
  RootValue{degree: Maybe<&2,String>}
  BoxedArgument{}
  BinomTop{}
  BinomBottom{top: String}
  AccentArgument{command: String,accent: String}
  BlackboardArgument{}
  OperatorNameArgument{starred: Bool}
  ModArgument{pmod: Bool}
  OverTop{sub: Bool}
  OverBase{sub: Bool,script: String}
  WrapperArgument{text: Bool}
  OperatorScript{operator: String,bracket: Bool,limits: Bool,spaced: Bool,sub: Bool,lower: Maybe<&2,String>,upper: Maybe<&2,String>}
  NestedEnd{input: String,context: Context,source: String}
  Trimmed{}
  RowRendered{sources: List<&2,String>,done: List<&2,String>}
  CellRendered{grid: Grid,rows: List<&2,List<&2,String>>,pending: List<&2,String>,cells: List<&2,String>,done: List<&2,List<&2,String>>}
type Mode is Data:
  Run{task: Task}
  Give{value: String}
type Machine is Data: Machine{input: String,context: Context,nodes: List<&2,LayoutNode>,frames: List<&2,Frame>,mode: Mode}

def run(input: String,context: Context,nodes: List<&2,LayoutNode>,frames: List<&2,Frame>,task: Task) -> Machine:
  Machine{input,context,nodes,frames,Run{task}}
def give(input: String,context: Context,nodes: List<&2,LayoutNode>,frames: List<&2,Frame>,value: String) -> Machine:
  Machine{input,context,nodes,frames,Give{value}}
# Appends a layout node and returns its marker.
def giveNode(input: String,context: Context,+nodes: List<&2,LayoutNode>,frames: List<&2,Frame>,node: LayoutNode) -> Machine:
  give(input,context,List.append(&2,LayoutNode,nodes,[node]),frames,marker(List.length(&2,LayoutNode,nodes)))

# parseSequence
# -------------

# `/\u{f0000}(\d+)\u{f0001}$/` on the (reversed) result.
def reversedMarkerDigits(text: String,+value: Nat,+scale: Nat,+seen: Bool) -> Maybe<&2,Nat>:
  match text:
    case SNil{}: None{}
    case SCon{+char,+rest}:
      Bool.pick(Unit -> Maybe<&2,Nat>,Char.is_eq(char,layoutMarkerStart()),
        _ => Bool.pick(Maybe<&2,Nat>,seen,Some{value},None{}),
        _ => Bool.pick(Unit -> Maybe<&2,Nat>,isAsciiDigit(char),_ => reversedMarkerDigits(rest,value + digitValue(char) * scale,scale * 10n,True{}),_ => None{})(Unit{}))(Unit{})
def trailingMarker(reversed: String) -> Maybe<&2,Nat>:
  match reversed:
    case SCon{+char,+rest}: Bool.pick(Unit -> Maybe<&2,Nat>,Char.is_eq(char,layoutMarkerEnd()),_ => reversedMarkerDigits(rest,0n,1n,False{}),_ => None{})(Unit{})
    case _: None{}
def periodLast(reversed: List<&2,String>) -> List<&2,String>:
  match reversed:
    case Nil{}: Nil{}
    case last <> rest: List.reverse(&2,String,(last ++ ".") <> rest)
def withPeriod(lines: List<&2,String>) -> List<&2,String>: periodLast(List.reverse(&2,String,lines))
type Target is Data: Target{index: Nat,node: LayoutNode}
def matrixTarget(+index: Nat,node: Maybe<&2,LayoutNode>) -> Maybe<&2,Target>:
  match node:
    case Some{MatrixNode{lines,baseline}}: Some{Target{index,MatrixNode{withPeriod(lines),baseline}}}
    case _: None{}
def periodTarget(index: Maybe<&2,Nat>,+nodes: List<&2,LayoutNode>) -> Maybe<&2,Target>:
  match index:
    case None{}: None{}
    case Some{+position}: matrixTarget(position,List.get(&2,LayoutNode,nodes,position))
# A period right after a matrix joins the matrix's last line.
def periodStep(target: Maybe<&2,Target>,input: String,context: Context,+nodes: List<&2,LayoutNode>,frames: List<&2,Frame>,closing: Bool,reversed: String) -> Machine:
  match target:
    case None{}: run(input,context,nodes,frames,Sequence{closing,SCon{'.',reversed}})
    case Some{Target{index,node}}: run(input,context,List.set(&2,LayoutNode,nodes,index,node),frames,Sequence{closing,reversed})
def whitespaceStep(space: Bool,char: Char,input: String,context: Context,nodes: List<&2,LayoutNode>,frames: List<&2,Frame>,closing: Bool,reversed: String) -> Machine:
  match space:
    case True{}: run(skipSpace(input),context,nodes,frames,Sequence{closing,SCon{' ',reversed}})
    case False{}: run(input,context,nodes,frames,Sequence{closing,SCon{char,reversed}})
def closeStep(closing: Bool,input: String,context: Context,nodes: List<&2,LayoutNode>,frames: List<&2,Frame>,reversed: String) -> Machine:
  match closing:
    case True{}: give(input,context,nodes,frames,String.reverse(reversed))
    case False{}: give(SCon{'}',input},rejected(context),nodes,frames,String.reverse(reversed))
def endStep(closing: Bool,context: Context,nodes: List<&2,LayoutNode>,frames: List<&2,Frame>,reversed: String) -> Machine:
  match closing:
    case True{}: give("",rejected(context),nodes,frames,String.reverse(reversed))
    case False{}: give("",context,nodes,frames,String.reverse(reversed))
def plainStep(+char: Char,input: String,context: Context,nodes: List<&2,LayoutNode>,frames: List<&2,Frame>,closing: Bool,reversed: String) -> Machine:
  whitespaceStep(isSpace(char),char,input,context,nodes,frames,closing,reversed)
# One character of `parseSequence`; `closing` says a `}` ends the sequence.
# The result is accumulated reversed.
def sequenceStep(input: String,context: Context,+nodes: List<&2,LayoutNode>,frames: List<&2,Frame>,+closing: Bool,+reversed: String) -> Machine:
  match input:
    case SNil{}: endStep(closing,context,nodes,frames,reversed)
    case SCon{'}',rest}: closeStep(closing,rest,context,nodes,frames,reversed)
    case SCon{'{',rest}: run(rest,context,nodes,AfterGroup{closing,reversed} <> frames,Sequence{True{},""})
    case SCon{'\\',rest}: run(rest,context,nodes,AfterCommand{closing,reversed} <> frames,Command{})
    case SCon{'^',rest}: run(rest,context,nodes,AfterScript{closing,Text.trimStart(reversed)} <> frames,Scripts{False{}})
    case SCon{'_',rest}: run(rest,context,nodes,AfterScript{closing,Text.trimStart(reversed)} <> frames,Scripts{True{}})
    case SCon{'=',rest}: run(rest,context,nodes,frames,Sequence{closing," = " ++ Text.trimStart(reversed)})
    case SCon{'<',rest}: run(rest,context,nodes,frames,Sequence{closing," < " ++ Text.trimStart(reversed)})
    case SCon{'>',rest}: run(rest,context,nodes,frames,Sequence{closing," > " ++ Text.trimStart(reversed)})
    case SCon{'&',rest}: run(rest,context,nodes,frames,Sequence{closing,reversed})
    case SCon{'~',rest}: run(rest,context,nodes,frames,Sequence{closing,SCon{' ',reversed}})
    case SCon{'.',rest}: periodStep(periodTarget(trailingMarker(reversed),nodes),rest,context,nodes,frames,closing,reversed)
    case SCon{char,rest}: plainStep(char,rest,context,nodes,frames,closing,reversed)
# A command's result joins the sequence; negative space removes the
# whitespace (and a named operator's closing bound) before it.
def afterNegativeSpace(reversed: String) -> String:
  match reversed:
    case SCon{+char,+rest}: Bool.pick(String,Char.is_eq(char,namedOperatorEnd()),rest,SCon{char,rest})
    case _: reversed
def afterCommand(+value: String,+reversed: String) -> String:
  Bool.pick(Unit -> String,String.eq(value,negativeSpace()),_ => afterNegativeSpace(Text.trimStart(reversed)),_ => String.reverse(value) ++ reversed)(Unit{})
# A script attaches inside a preceding named operator's bounds.
def attachScript(+script: String,reversed: String) -> String:
  match reversed:
    case SCon{+char,+rest}:
      Bool.pick(String,Char.is_eq(char,namedOperatorEnd()),SCon{char,String.reverse(script) ++ rest},String.reverse(script) ++ SCon{char,rest})
    case _: String.reverse(script)

# parseCommand
# ------------

type CommandKind is Data:
  LineBreakCommand{}
  SpacingCommand{}
  NegativeSpacingCommand{}
  FontSwitchCommand{}
  IgnoredCommand{}
  EscapedCommand{}
  NormCommand{}
  NotCommand{}
  LimitCommand{}
  SymbolCommand{symbol: String}
  NamedOperatorCommand{}
  SizeCommand{}
  DelimiterCommand{}
  FractionCommand{}
  RootCommand{}
  BoxedCommand{}
  BinomCommand{}
  AccentCommand{accent: String}
  BlackboardCommand{}
  OperatorNameCommand{}
  ModCommand{}
  PmodCommand{}
  OversetCommand{}
  UndersetCommand{}
  WrapperCommand{}
  BeginCommand{}
  EndCommand{}
  UnknownCommand{}
def finalKind(+command: String) -> CommandKind:
  Bool.pick(Unit -> CommandKind,String.eq(command,"mathbb"),_ => BlackboardCommand{},
  _ => Bool.pick(Unit -> CommandKind,String.eq(command,"operatorname"),_ => OperatorNameCommand{},
  _ => Bool.pick(Unit -> CommandKind,member(["mod","bmod"],command),_ => ModCommand{},
  _ => Bool.pick(Unit -> CommandKind,member(["pmod","pod"],command),_ => PmodCommand{},
  _ => Bool.pick(Unit -> CommandKind,member(["overset","stackrel"],command),_ => OversetCommand{},
  _ => Bool.pick(Unit -> CommandKind,String.eq(command,"underset"),_ => UndersetCommand{},
  _ => Bool.pick(Unit -> CommandKind,member(plainWrappers(),command),_ => WrapperCommand{},
  _ => Bool.pick(Unit -> CommandKind,String.eq(command,"begin"),_ => BeginCommand{},
  _ => Bool.pick(CommandKind,String.eq(command,"end"),EndCommand{},UnknownCommand{}))(Unit{}))(Unit{}))(Unit{}))(Unit{}))(Unit{}))(Unit{}))(Unit{}))(Unit{})
def accentOr(found: Maybe<&2,String>,fallback: Unit -> CommandKind) -> CommandKind:
  match found:
    case Some{accent}: AccentCommand{accent}
    case None{}: fallback(Unit{})
def laterKind(+command: String) -> CommandKind:
  Bool.pick(Unit -> CommandKind,member(namedOperators(),command),_ => NamedOperatorCommand{},
  _ => Bool.pick(Unit -> CommandKind,member(sizeCommands(),command),_ => SizeCommand{},
  _ => Bool.pick(Unit -> CommandKind,member(["left","middle","right"],command),_ => DelimiterCommand{},
  _ => Bool.pick(Unit -> CommandKind,member(["frac","dfrac","tfrac"],command),_ => FractionCommand{},
  _ => Bool.pick(Unit -> CommandKind,String.eq(command,"sqrt"),_ => RootCommand{},
  _ => Bool.pick(Unit -> CommandKind,member(["boxed","fbox"],command),_ => BoxedCommand{},
  _ => Bool.pick(Unit -> CommandKind,member(["binom","dbinom","tbinom"],command),_ => BinomCommand{},
  _ => accentOr(lookup(accents(),command),_ => finalKind(command)))(Unit{}))(Unit{}))(Unit{}))(Unit{}))(Unit{}))(Unit{}))(Unit{})
def symbolOr(found: Maybe<&2,String>,fallback: Unit -> CommandKind) -> CommandKind:
  match found:
    case Some{symbol}: SymbolCommand{symbol}
    case None{}: fallback(Unit{})
def commandKind(+command: String) -> CommandKind:
  Bool.pick(Unit -> CommandKind,String.eq(command,"\\"),_ => LineBreakCommand{},
  _ => Bool.pick(Unit -> CommandKind,member(spacingCommands(),command),_ => SpacingCommand{},
  _ => Bool.pick(Unit -> CommandKind,member(negativeSpacingCommands(),command),_ => NegativeSpacingCommand{},
  _ => Bool.pick(Unit -> CommandKind,member(fontSwitchCommands(),command),_ => FontSwitchCommand{},
  _ => Bool.pick(Unit -> CommandKind,member(ignoredCommands(),command),_ => IgnoredCommand{},
  _ => Bool.pick(Unit -> CommandKind,member(["{","}","$","%","#","_","&"],command),_ => EscapedCommand{},
  _ => Bool.pick(Unit -> CommandKind,String.eq(command,"|"),_ => NormCommand{},
  _ => Bool.pick(Unit -> CommandKind,String.eq(command,"not"),_ => NotCommand{},
  _ => Bool.pick(Unit -> CommandKind,member(limitOperators(),command),_ => LimitCommand{},
  _ => symbolOr(lookup(symbols(),command),_ => laterKind(command)))(Unit{}))(Unit{}))(Unit{}))(Unit{}))(Unit{}))(Unit{}))(Unit{}))(Unit{}))(Unit{})
def symbolCommand(displayLimits: Bool,+command: String,+symbol: String,input: String,context: Context,nodes: List<&2,LayoutNode>,frames: List<&2,Frame>) -> Machine:
  match displayLimits:
    case True{}: run(input,context,nodes,frames,Operator{symbol,False{},True{},False{}})
    case False{}:
      give(input,context,nodes,frames,Bool.pick(String,String.eq(command,"cdot") || String.eq(command,"times") || member(relationCommands(),command)," " ++ symbol ++ " ",symbol))
def withoutPeriod(input: String) -> String:
  match input:
    case SCon{'.',rest}: rest
    case input: input
def withoutStar(input: String) -> String:
  match input:
    case SCon{'*',rest}: rest
    case input: input
def rootBracket(found: Maybe<&2,Cut>,input: String,context: Context,nodes: List<&2,LayoutNode>,frames: List<&2,Frame>) -> Machine:
  match found:
    case None{}: run(input,rejected(context),nodes,RootValue{None{}} <> frames,Required{True{}})
    case Some{Cut{degree,rest}}: run(rest,context,nodes,RootDegree{} <> frames,Nested{degree,True{}})
# `parseOptionalArgument` before a root's radicand.
def rootStart(input: String,context: Context,nodes: List<&2,LayoutNode>,frames: List<&2,Frame>) -> Machine:
  match input:
    case SCon{'[',+rest}: rootBracket(cutAt(rest,"]",""),SCon{'[',rest},context,nodes,frames)
    case input: run(input,context,nodes,RootValue{None{}} <> frames,Required{True{}})
def commandDispatch(kind: CommandKind,+command: String,+input: String,+context: Context,nodes: List<&2,LayoutNode>,frames: List<&2,Frame>) -> Machine:
  match kind:
    case LineBreakCommand{}: give(input,context,nodes,frames,"\n")
    case SpacingCommand{}: give(input,context,nodes,frames," ")
    case NegativeSpacingCommand{}: give(input,context,nodes,frames,negativeSpace())
    case FontSwitchCommand{}: give(skipSpace(input),context,nodes,frames,"")
    case IgnoredCommand{}: give(input,context,nodes,frames,"")
    case EscapedCommand{}: give(input,context,nodes,frames,command)
    case NormCommand{}: give(input,context,nodes,frames,"‖")
    case NotCommand{}: run(input,context,nodes,NotArgument{} <> frames,Required{False{}})
    case LimitCommand{}: run(input,context,nodes,frames,Operator{command,True{},True{},True{}})
    case SymbolCommand{symbol}: symbolCommand(member(displayLimitSymbols(),command),command,symbol,input,context,nodes,frames)
    case NamedOperatorCommand{}: give(input,context,nodes,frames,single(namedOperatorStart()) ++ command ++ single(namedOperatorEnd()))
    case SizeCommand{}: give(input,context,nodes,frames,"")
    case DelimiterCommand{}: give(withoutPeriod(input),context,nodes,frames,"")
    case FractionCommand{}:
      +stack = displayOf(context) && stackOf(context) && Bool.not(String.eq(command,"tfrac"))
      run(input,context,nodes,Numerator{stack} <> frames,Required{Bool.not(stack)})
    case RootCommand{}: rootStart(skipBlanks(input),context,nodes,frames)
    case BoxedCommand{}: run(input,context,nodes,BoxedArgument{} <> frames,Required{True{}})
    case BinomCommand{}: run(input,context,nodes,BinomTop{} <> frames,Required{True{}})
    case AccentCommand{accent}: run(input,context,nodes,AccentArgument{command,accent} <> frames,Required{True{}})
    case BlackboardCommand{}: run(input,context,nodes,BlackboardArgument{} <> frames,Required{True{}})
    case OperatorNameCommand{}: run(withoutStar(input),context,nodes,OperatorNameArgument{headIs(input,'*')} <> frames,Required{True{}})
    case ModCommand{}: give(input,context,nodes,frames," mod ")
    case PmodCommand{}: run(input,context,nodes,ModArgument{String.eq(command,"pmod")} <> frames,Required{True{}})
    case OversetCommand{}: run(input,context,nodes,OverTop{False{}} <> frames,Required{True{}})
    case UndersetCommand{}: run(input,context,nodes,OverTop{True{}} <> frames,Required{True{}})
    case WrapperCommand{}: run(input,context,nodes,WrapperArgument{String.starts_with(command,"text") || String.eq(command,"mbox")} <> frames,Required{True{}})
    case BeginCommand{}: run(input,context,nodes,frames,Environment{})
    case EndCommand{}: give(input,rejected(context),nodes,frames,"")
    case UnknownCommand{}: give(input,rejected(context),nodes,frames,"\\" ++ command)
def lettersFrom(text: String,+reversed: String) -> Cut:
  match text:
    case SNil{}: Cut{String.reverse(reversed),""}
    case SCon{+char,+rest}: Bool.pick(Unit -> Cut,isAsciiLetter(char),_ => lettersFrom(rest,SCon{char,reversed}),_ => Cut{String.reverse(reversed),SCon{char,rest}})(Unit{})
def namedCommand(name: Cut,context: Context,nodes: List<&2,LayoutNode>,frames: List<&2,Frame>) -> Machine:
  match name:
    case Cut{+command,rest}: commandDispatch(commandKind(command),command,rest,context,nodes,frames)
def withoutLineFeed(input: String) -> String:
  match input:
    case SCon{'\n',rest}: rest
    case input: input
def commandWord(letter: Bool,+char: Char,rest: String,context: Context,nodes: List<&2,LayoutNode>,frames: List<&2,Frame>) -> Machine:
  match letter:
    case True{}: namedCommand(lettersFrom(SCon{char,rest},""),context,nodes,frames)
    case False{}: commandDispatch(commandKind(single(char)),single(char),rest,context,nodes,frames)
def commandChar(+char: Char,rest: String,context: Context,nodes: List<&2,LayoutNode>,frames: List<&2,Frame>) -> Machine:
  commandWord(isAsciiLetter(char),char,rest,context,nodes,frames)
# The command after a backslash; a backslash before a line ending is a
# control space.
def commandStart(input: String,context: Context,nodes: List<&2,LayoutNode>,frames: List<&2,Frame>) -> Machine:
  match input:
    case SNil{}: give("",rejected(context),nodes,frames,"")
    case SCon{'\n',rest}: give(rest,context,nodes,frames," ")
    case SCon{'\r',rest}: give(withoutLineFeed(rest),context,nodes,frames," ")
    case SCon{char,rest}: commandChar(char,rest,context,nodes,frames)

# parseRequiredArgument
# ---------------------

def requiredValue(input: String,context: Context,nodes: List<&2,LayoutNode>,frames: List<&2,Frame>) -> Machine:
  match input:
    case SNil{}: give("",rejected(context),nodes,frames,"")
    case SCon{'{',rest}: run(rest,context,nodes,frames,Sequence{True{},""})
    case SCon{'\\',rest}: run(rest,context,nodes,frames,Command{})
    case SCon{char,rest}: give(rest,context,nodes,frames,single(char))
def requiredStart(stack: Bool,input: String,+context: Context,nodes: List<&2,LayoutNode>,frames: List<&2,Frame>) -> Machine:
  +previous = stackOf(context)
  requiredValue(skipSpace(input),withStack(context,previous && stack),nodes,RestoreStack{previous} <> frames)

# parseScripts
# ------------

def optionalScript(value: Maybe<&2,String>,+sub: Bool) -> String:
  match value:
    case None{}: ""
    case Some{text}: formatScript(text,sub)
def unicodeMissing(value: Maybe<&2,String>,sub: Bool) -> Bool:
  match value:
    case None{}: False{}
    case Some{text}: Maybe.is_none(&2,String,formatUnicodeScript(text,sub))
def hasCapitalOrStar(text: String) -> Bool:
  match text:
    case SNil{}: False{}
    case SCon{+char,+rest}: Char.is_upper(char) || Char.is_eq(char,'*') || Char.is_eq(char,'∗') || hasCapitalOrStar(rest)
def blocksLayout(value: Maybe<&2,String>) -> Bool:
  match value:
    case None{}: False{}
    case Some{+text}: String.contains(text,"/") || (Bool.not(String.contains(text,single(layoutMarkerStart()))) && Nat.is_gt(String.length(text),1n) && Bool.not(hasCapitalOrStar(text)))
def optionalNormalized(value: Maybe<&2,String>,+classes: Classes) -> Maybe<&2,String>:
  match value:
    case None{}: None{}
    case Some{text}: Some{normalizeOutput(text,classes)}
def scriptsResult(layout: Bool,+firstSub: Bool,+first: String,+second: Maybe<&2,String>,+sub: Maybe<&2,String>,+sup: Maybe<&2,String>,input: String,context: Context,+nodes: List<&2,LayoutNode>,frames: List<&2,Frame>,+classes: Classes) -> Machine:
  match layout:
    case True{}: giveNode(input,context,nodes,frames,ScriptNode{optionalNormalized(sub,classes),optionalNormalized(sup,classes)})
    case False{}: give(input,context,nodes,frames,formatScript(first,firstSub) ++ optionalScript(second,Bool.not(firstSub)))
def finishScripts(+firstSub: Bool,+first: String,+second: Maybe<&2,String>,input: String,+context: Context,nodes: List<&2,LayoutNode>,frames: List<&2,Frame>,+classes: Classes) -> Machine:
  +sub = Bool.pick(Maybe<&2,String>,firstSub,Some{first},second)
  +sup = Bool.pick(Maybe<&2,String>,firstSub,second,Some{first})
  +layout = displayOf(context) && Bool.not(blocksLayout(sub) || blocksLayout(sup)) &&
    (Nat.is_gt(depthOf(context),0n) || unicodeMissing(sub,True{}) || unicodeMissing(sup,False{}))
  scriptsResult(layout,firstSub,first,second,sub,sup,input,context,nodes,frames,classes)
def secondScript(present: Bool,+firstSub: Bool,+first: String,+input: String,+after: String,+context: Context,nodes: List<&2,LayoutNode>,frames: List<&2,Frame>,+classes: Classes) -> Machine:
  match present:
    case True{}: run(String.drop(after,1n),deeper(context),nodes,SecondScript{firstSub,first} <> frames,Required{False{}})
    case False{}: finishScripts(firstSub,first,None{},input,context,nodes,frames,classes)
def firstScriptDone(+sub: Bool,+first: String,+input: String,+context: Context,nodes: List<&2,LayoutNode>,frames: List<&2,Frame>,+classes: Classes) -> Machine:
  +after = skipSpace(input)
  +present = (headIs(after,'^') && sub) || (headIs(after,'_') && Bool.not(sub))
  secondScript(present,sub,first,input,after,context,nodes,frames,classes)

# parseOperator
# -------------

type Modifier is Data: Modifier{limits: Bool,rest: String}
def startsWithLetter(text: String) -> Bool:
  match text:
    case SNil{}: False{}
    case SCon{char,_}: isAsciiLetter(char)
def modifierNamed(+text: String,+name: String,limits: Bool) -> Maybe<&2,Modifier>:
  +rest = String.drop(text,String.length(name))
  Bool.pick(Maybe<&2,Modifier>,String.starts_with(text,name) && Bool.not(startsWithLetter(rest)),Some{Modifier{limits,rest}},None{})
def limitsModifier(+text: String) -> Maybe<&2,Modifier>:
  Maybe.or(&2,Modifier,modifierNamed(text,"\\limits",True{}),modifierNamed(text,"\\nolimits",False{}))
def operatorStart(modifier: Maybe<&2,Modifier>,operator: String,bracket: Bool,limits: Bool,spaced: Bool,input: String,context: Context,nodes: List<&2,LayoutNode>,frames: List<&2,Frame>) -> Machine:
  match modifier:
    case None{}: run(input,context,nodes,frames,OperatorScripts{operator,bracket,limits,spaced,None{},None{}})
    case Some{Modifier{explicit,rest}}: run(rest,context,nodes,frames,OperatorScripts{operator,bracket,explicit,spaced,None{},None{}})
def lowerText(value: Maybe<&2,String>,bracket: Bool) -> String:
  match value:
    case None{}: ""
    case Some{+text}: Bool.pick(String,bracket,"[" ++ text ++ "]",formatScript(text,True{}))
def operatorLayoutUsed(stacked: Bool,+operator: String,bracket: Bool,spaced: Bool,+lower: Maybe<&2,String>,+upper: Maybe<&2,String>,input: String,context: Context,+nodes: List<&2,LayoutNode>,frames: List<&2,Frame>) -> Machine:
  match stacked:
    case True{}: giveNode(input,context,nodes,frames,OperatorNode{operator,lower,upper})
    case False{}:
      +rendered = operator ++ lowerText(lower,bracket) ++ optionalScript(upper,False{})
      give(input,context,nodes,frames,Bool.pick(String,spaced," " ++ rendered ++ " ",rendered))
def operatorScriptsAt(after: String,+operator: String,+bracket: Bool,+limits: Bool,+spaced: Bool,+lower: Maybe<&2,String>,+upper: Maybe<&2,String>,+input: String,+context: Context,nodes: List<&2,LayoutNode>,frames: List<&2,Frame>) -> Machine:
  match after:
    case SCon{'_',rest}: run(rest,context,nodes,OperatorScript{operator,bracket,limits,spaced,True{},lower,upper} <> frames,Required{False{}})
    case SCon{'^',rest}: run(rest,context,nodes,OperatorScript{operator,bracket,limits,spaced,False{},lower,upper} <> frames,Required{False{}})
    case _:
      +stacked = displayOf(context) && limits && (Maybe.is_some(&2,String,lower) || Maybe.is_some(&2,String,upper))
      operatorLayoutUsed(stacked,operator,bracket,spaced,lower,upper,input,context,nodes,frames)
def operatorScriptDone(+sub: Bool,+lower: Maybe<&2,String>,+upper: Maybe<&2,String>,+context: Context) -> Context:
  Bool.pick(Context,(sub && Maybe.is_some(&2,String,lower)) || (Bool.not(sub) && Maybe.is_some(&2,String,upper)),rejected(context),context)

# Environments in the parser
# --------------------------

# The raw text up to the brace closing an open group; a backslash escapes
# the next character.
def rawGroup(text: String,+escaped: Bool,+depth: Nat,+reversed: String) -> Maybe<&2,Cut>:
  match text:
    case SNil{}: None{}
    case SCon{+char,+rest}:
      Bool.pick(Unit -> Maybe<&2,Cut>,escaped,_ => rawGroup(rest,False{},depth,SCon{char,reversed}),
        _ => Bool.pick(Unit -> Maybe<&2,Cut>,Char.is_eq(char,'\\'),_ => rawGroup(rest,True{},depth,SCon{char,reversed}),
          _ => Bool.pick(Unit -> Maybe<&2,Cut>,Char.is_eq(char,'{'),_ => rawGroup(rest,False{},Succ{depth},SCon{char,reversed}),
            _ => Bool.pick(Unit -> Maybe<&2,Cut>,Char.is_eq(char,'}') && Nat.is_eq(depth,1n),_ => Some{Cut{String.reverse(reversed),rest}},
              _ => rawGroup(rest,False{},Bool.pick(Nat,Char.is_eq(char,'}'),depth - 1n,depth),SCon{char,reversed}))(Unit{}))(Unit{}))(Unit{}))(Unit{})
def environmentBody(kind: EnvironmentKind,+body: String,input: String,context: Context,nodes: List<&2,LayoutNode>,frames: List<&2,Frame>) -> Machine:
  match kind:
    case EquationEnvironment{}: run(input,context,nodes,Trimmed{} <> frames,Nested{body,True{}})
    case AlignedEnvironment{+alignedAt}:
      run(input,context,nodes,frames,Rows{alignedSources(rowsOf(Bool.pick(String,alignedAt,withoutColumnSpec(body),body)),alignedAt,Nil{}),Nil{}})
    case CasesEnvironment{}: run(input,context,nodes,frames,Cells{CasesGrid{},gridRows(rowsOf(body),Nil{}),Nil{},Nil{},Nil{}})
    case MatrixEnvironment{array,style}:
      run(input,context,nodes,frames,Cells{MatrixGrid{style},gridRows(rowsOf(Bool.pick(String,array,withoutColumnSpec(body),body)),Nil{}),Nil{},Nil{},Nil{}})
    case UnknownEnvironment{}: give(input,rejected(context),nodes,frames,body)
def environmentEnd(found: Maybe<&2,Cut>,+name: String,+input: String,context: Context,nodes: List<&2,LayoutNode>,frames: List<&2,Frame>) -> Machine:
  match found:
    case None{}: give(input,rejected(context),nodes,frames,"")
    case Some{Cut{body,rest}}: environmentBody(environmentKind(name),body,rest,context,nodes,frames)
def environmentName(empty: Bool,+name: String,+rest: String,context: Context,nodes: List<&2,LayoutNode>,frames: List<&2,Frame>) -> Machine:
  match empty:
    case True{}: give(rest,context,nodes,frames,"")
    case False{}: environmentEnd(cutAt(rest,"\\end{" ++ name ++ "}",""),name,rest,context,nodes,frames)
def environmentNamed(found: Maybe<&2,Cut>,context: Context,nodes: List<&2,LayoutNode>,frames: List<&2,Frame>) -> Machine:
  match found:
    case None{}: give("",rejected(context),nodes,frames,"")
    case Some{Cut{+name,rest}}: environmentName(String.eq(name,""),name,rest,context,nodes,frames)
# `readRawGroup` for the environment name, then the body up to `\end{name}`.
def environmentStart(input: String,context: Context,nodes: List<&2,LayoutNode>,frames: List<&2,Frame>) -> Machine:
  match input:
    case SCon{'{',rest}: environmentNamed(rawGroup(rest,False{},1n,""),context,nodes,frames)
    case input: give(input,rejected(context),nodes,frames,"")

# Nested renders, rows and cells
# ------------------------------

# `renderNested`: a fresh parser over `source` sharing the layout nodes.
def nestedStart(+source: String,stack: Bool,input: String,+context: Context,nodes: List<&2,LayoutNode>,frames: List<&2,Frame>) -> Machine:
  run(source,Context{True{},True{},0n,displayOf(context) && stack},nodes,NestedEnd{input,context,source} <> frames,Sequence{False{},""})
# A nested render that was unsupported or stopped early makes its caller
# unsupported and yields its source.
def nestedDone(complete: Bool,input: String,context: Context,source: String,value: String,nodes: List<&2,LayoutNode>,frames: List<&2,Frame>,+classes: Classes) -> Machine:
  match complete:
    case True{}: give(input,context,nodes,frames,normalizeOutput(value,classes))
    case False{}: give(input,rejected(context),nodes,frames,source)
def rowsStep(sources: List<&2,String>,done: List<&2,String>,input: String,context: Context,nodes: List<&2,LayoutNode>,frames: List<&2,Frame>) -> Machine:
  match sources:
    case Nil{}: give(input,context,nodes,frames,String.join(List.reverse(&2,String,done),"\n"))
    case source <> rest: run(input,context,nodes,RowRendered{rest,done} <> frames,Nested{source,True{}})
def withRow(+row: String,+done: List<&2,String>) -> List<&2,String>:
  Bool.pick(List<&2,String>,String.eq(row,""),done,row <> done)
def withCells(+cells: List<&2,String>,+done: List<&2,List<&2,String>>) -> List<&2,List<&2,String>>:
  Bool.pick(List<&2,List<&2,String>>,someNonEmpty(cells),cells <> done,done)
def gridDone(result: GridResult,input: String,context: Context,nodes: List<&2,LayoutNode>,frames: List<&2,Frame>) -> Machine:
  match result:
    case GridText{text}: give(input,context,nodes,frames,text)
    case GridNode{node}: giveNode(input,context,nodes,frames,node)
def nextRow(grid: Grid,rows: List<&2,List<&2,String>>,done: List<&2,List<&2,String>>,input: String,context: Context,nodes: List<&2,LayoutNode>,frames: List<&2,Frame>) -> Machine:
  match rows:
    case Nil{}: gridDone(renderGrid(grid,List.reverse(&2,List<&2,String>,done)),input,context,nodes,frames)
    case row <> rest: run(input,context,nodes,frames,Cells{grid,rest,row,Nil{},done})
# Each cell renders nested without stacked fractions; rows whose cells are
# all empty are dropped.
def cellsStep(grid: Grid,rows: List<&2,List<&2,String>>,pending: List<&2,String>,cells: List<&2,String>,done: List<&2,List<&2,String>>,input: String,context: Context,nodes: List<&2,LayoutNode>,frames: List<&2,Frame>) -> Machine:
  match pending cells:
    case cell <> more cells: run(input,context,nodes,CellRendered{grid,rows,more,cells,done} <> frames,Nested{cell,False{}})
    case Nil{} Nil{}: nextRow(grid,rows,done,input,context,nodes,frames)
    case Nil{} cells: run(input,context,nodes,frames,Cells{grid,rows,Nil{},Nil{},withCells(List.reverse(&2,String,cells),done)})

# Driving the parser
# ------------------

def execute(task: Task,+input: String,+context: Context,+nodes: List<&2,LayoutNode>,frames: List<&2,Frame>) -> Machine:
  match task:
    case Sequence{closing,reversed}: sequenceStep(input,context,nodes,frames,closing,reversed)
    case Command{}: commandStart(input,context,nodes,frames)
    case Required{stack}: requiredStart(stack,input,context,nodes,frames)
    case Scripts{sub}: run(input,deeper(context),nodes,FirstScript{sub} <> frames,Required{False{}})
    case Operator{operator,bracket,limits,spaced}: operatorStart(limitsModifier(skipBlanks(input)),operator,bracket,limits,spaced,input,context,nodes,frames)
    case OperatorScripts{operator,bracket,limits,spaced,lower,upper}: operatorScriptsAt(skipBlanks(input),operator,bracket,limits,spaced,lower,upper,input,context,nodes,frames)
    case Environment{}: environmentStart(skipBlanks(input),context,nodes,frames)
    case Nested{source,stack}: nestedStart(source,stack,input,context,nodes,frames)
    case Rows{sources,done}: rowsStep(sources,done,input,context,nodes,frames)
    case Cells{grid,rows,pending,cells,done}: cellsStep(grid,rows,pending,cells,done,input,context,nodes,frames)
def mathbbText(text: String,reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(reversed)
    case SCon{+char,+rest}: mathbbText(rest,String.reverse(Maybe.default(&2,String,lookup(blackboard(),single(char)),single(char))) ++ reversed)
def rootText(degree: Maybe<&2,String>,+value: String,+classes: Classes) -> String:
  match degree:
    case None{}: formatRoot(value,"√",classes)
    case Some{+index}:
      Bool.pick(Unit -> String,String.eq(index,"2"),_ => formatRoot(value,"√",classes),
        _ => Bool.pick(Unit -> String,String.eq(index,"3"),_ => formatRoot(value,"∛",classes),
          _ => Bool.pick(Unit -> String,String.eq(index,"4"),_ => formatRoot(value,"∜",classes),
            _ => formatScript(index,False{}) ++ formatRoot(value,"√",classes))(Unit{}))(Unit{}))(Unit{})
def negatedText(found: Maybe<&2,String>,+value: String,input: String,context: Context,nodes: List<&2,LayoutNode>,frames: List<&2,Frame>) -> Machine:
  match found value:
    case Some{negated} _: give(input,context,nodes,frames," " ++ negated ++ " ")
    case None{} SNil{}: give(input,rejected(context),nodes,frames,"")
    case None{} SCon{first,rest}: give(input,context,nodes,frames," " ++ SCon{first,SCon{'\u{338}',rest}} ++ " ")
def fractionDone(stack: Bool,numerator: String,denominator: String,input: String,context: Context,+nodes: List<&2,LayoutNode>,frames: List<&2,Frame>,+classes: Classes) -> Machine:
  match stack:
    case True{}: giveNode(input,context,nodes,frames,FractionNode{normalizeOutput(numerator,classes),normalizeOutput(denominator,classes)})
    case False{}: give(input,context,nodes,frames,formatFraction(numerator,denominator,classes))
def resume(frame: Frame,+value: String,+input: String,+context: Context,+nodes: List<&2,LayoutNode>,frames: List<&2,Frame>,+classes: Classes) -> Machine:
  match frame:
    case AfterGroup{closing,reversed}: run(input,context,nodes,frames,Sequence{closing,String.reverse(value) ++ reversed})
    case AfterCommand{closing,reversed}: run(input,context,nodes,frames,Sequence{closing,afterCommand(value,reversed)})
    case AfterScript{closing,reversed}: run(input,context,nodes,frames,Sequence{closing,attachScript(value,reversed)})
    case RestoreStack{previous}: give(input,withStack(context,previous),nodes,frames,value)
    case FirstScript{sub}: firstScriptDone(sub,value,input,shallower(context),nodes,frames,classes)
    case SecondScript{sub,first}: finishScripts(sub,first,Some{value},input,shallower(context),nodes,frames,classes)
    case NotArgument{}:
      +trimmed = Text.trim(value)
      negatedText(lookup(negatedSymbols(),trimmed),trimmed,input,context,nodes,frames)
    case Numerator{+stack}: run(input,context,nodes,Denominator{stack,value} <> frames,Required{Bool.not(stack)})
    case Denominator{stack,numerator}: fractionDone(stack,numerator,value,input,context,nodes,frames,classes)
    case RootDegree{}: run(input,context,nodes,RootValue{Some{Text.trim(value)}} <> frames,Required{True{}})
    case RootValue{degree}: give(input,context,nodes,frames,rootText(degree,value,classes))
    case BoxedArgument{}: give(input,context,nodes,frames,"[" ++ Text.trim(value) ++ "]")
    case BinomTop{}: run(input,context,nodes,BinomBottom{value} <> frames,Required{True{}})
    case BinomBottom{top}: give(input,context,nodes,frames,"(" ++ top ++ " choose " ++ value ++ ")")
    case AccentArgument{+command,+accent}:
      give(input,context,nodes,frames,Bool.pick(String,Nat.is_eq(String.length(value),1n),value ++ accent,command ++ "(" ++ value ++ ")"))
    case BlackboardArgument{}: give(input,context,nodes,frames,mathbbText(value,""))
    case OperatorNameArgument{starred}: run(input,context,nodes,frames,Operator{Text.trim(normalizeOutput(value,classes)),True{},starred,True{}})
    case ModArgument{pmod}: give(input,context,nodes,frames,Bool.pick(String,pmod," (mod " ++ Text.trim(value) ++ ")"," (" ++ Text.trim(value) ++ ")"))
    case OverTop{sub}: run(input,context,nodes,OverBase{sub,value} <> frames,Required{True{}})
    case OverBase{sub,script}: give(input,context,nodes,frames,Text.trim(value) ++ formatScript(script,sub))
    case WrapperArgument{text}: give(input,context,nodes,frames,Bool.pick(String,text,value,Text.trim(value)))
    case OperatorScript{operator,bracket,limits,spaced,+sub,+lower,+upper}:
      +script = withoutChar(normalizeOutput(value,classes),' ',"")
      run(input,operatorScriptDone(sub,lower,upper,context),nodes,frames,
        OperatorScripts{operator,bracket,limits,spaced,Bool.pick(Maybe<&2,String>,sub,Some{script},lower),Bool.pick(Maybe<&2,String>,sub,upper,Some{script})})
    case NestedEnd{outerInput,outerContext,source}: nestedDone(supportedOf(context) && String.eq(input,""),outerInput,outerContext,source,value,nodes,frames,classes)
    case Trimmed{}: give(input,context,nodes,frames,Text.trim(value))
    case RowRendered{sources,done}: run(input,context,nodes,frames,Rows{sources,withRow(Text.trim(value),done)})
    case CellRendered{grid,rows,pending,cells,done}: run(input,context,nodes,frames,Cells{grid,rows,pending,Text.trim(value) <> cells,done})

type Final is Data: Final{input: String,context: Context,nodes: List<&2,LayoutNode>,value: String}
# Runs tasks and returns values to frames until the outermost sequence
# returns. Every task consumes input or returns to a frame pushed by a task
# that did, so the loop ends; the termination argument is not mechanized.
@unsafe def drive(machine: Machine,+classes: Classes) -> Final:
  match machine:
    case Machine{input,context,nodes,Nil{},Give{value}}: Final{input,context,nodes,value}
    case Machine{input,context,nodes,frame <> frames,Give{value}}: drive(resume(frame,value,input,context,nodes,frames,classes),classes)
    case Machine{input,context,nodes,frames,Run{task}}: drive(execute(task,input,context,nodes,frames),classes)

# renderLatex
# -----------

type RenderLatexOptions is Data: RenderLatexOptions{display: Bool}
def defaultRenderLatexOptions() -> RenderLatexOptions: RenderLatexOptions{False{}}

def leadingSpaces(text: String,+count: Nat) -> Nat:
  match text:
    case SNil{}: count
    case SCon{+char,+rest}: Bool.pick(Unit -> Nat,isSpace(char),_ => leadingSpaces(rest,Succ{count}),_ => count)(Unit{})
def indentation(lines: List<&2,String>,+best: Maybe<&2,Nat>) -> Maybe<&2,Nat>:
  match lines:
    case Nil{}: best
    case +line <> rest:
      indentation(rest,Bool.pick(Unit -> Maybe<&2,Nat>,Text.blank(line),_ => best,
        _ => Some{Maybe.default(&2,Nat,Maybe.map(&2,Nat,Nat,current => Nat.min(current,leadingSpaces(line,0n)),best),leadingSpaces(line,0n))})(Unit{}))
# Every line loses the common indentation of the non-blank lines (all of
# it when every line is blank).
def dedented(lines: List<&2,String>,+amount: Maybe<&2,Nat>,reversed: List<&2,String>) -> List<&2,String>:
  match lines:
    case Nil{}: List.reverse(&2,String,reversed)
    case line <> rest: dedented(rest,amount,Text.trimEnd(Maybe.default(&2,String,Maybe.map(&2,Nat,String,count => String.drop(line,count),amount),"")) <> reversed)
def layoutText(+lines: List<&2,String>) -> String:
  unprotected(Text.trimEnd(String.join(dedented(lines,indentation(lines,None{}),Nil{}),"\n")))
def laidOut(+nodes: List<&2,LayoutNode>,+rendered: String) -> String:
  Bool.pick(Unit -> String,List.is_empty(&2,LayoutNode,nodes),_ => unprotected(rendered),
    _ => layoutText(layoutLinesOf(renderLayout(rendered,placeAll(nodes,Nil{})))))(Unit{})
def accepted(complete: Bool,nodes: List<&2,LayoutNode>,value: String,+classes: Classes) -> Maybe<&2,String>:
  match complete:
    case True{}: Some{laidOut(nodes,normalizeOutput(value,classes))}
    case False{}: None{}
def finished(final: Final,+classes: Classes) -> Maybe<&2,String>:
  match final:
    case Final{input,context,nodes,value}: accepted(supportedOf(context) && String.eq(input,""),nodes,value,classes)

# Renders a basic LaTeX math expression as terminal-friendly Unicode text,
# or None for unsupported or malformed syntax. Display mode stacks
# fractions and operator limits vertically.
def renderLatex(source: String,options: RenderLatexOptions) -> Maybe<&2,String>:
  match options:
    case RenderLatexOptions{display}:
      +classes = unicodeClasses()
      finished(drive(run(source,Context{True{},True{},0n,display},Nil{},Nil{},Sequence{False{},""}),classes),classes)
