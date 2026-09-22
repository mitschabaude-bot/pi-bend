import Base

# Incremental terminal framing. Text and paste payloads are Unicode scalars;
# bytes are decoded at the terminal boundary. Pending text is stored reversed,
# so fragmented control strings and large pastes do not copy their prefixes.
type Phase is Data:
  Plain{}
  Escape{}
  Csi{first: Bool}
  SgrMouse{fields: U32, digits: Bool, valid: Bool}
  X10{left: U32}
  Ss3{}
  Control{bell: Bool, escaped: Bool}
  Pasting{matched: U32}

type StdinBuffer is Data:
  StdinBuffer{phase: Phase, reversed: String, kitty: Maybe<&2,U32>}
type InputEvent is Data:
  DataEvent{text: String}
  PasteEvent{text: String}
type Transition is Data:
  Transition{buffer: StdinBuffer, events: List<&2,InputEvent>}
type StdinBufferOptions is Data:
  StdinBufferOptions{timeout: U32, escapeTimeout: U32}

def defaultOptions() -> StdinBufferOptions: StdinBufferOptions{50,10}
def create() -> StdinBuffer: StdinBuffer{Plain{},"",None{}}
def clear(buffer: StdinBuffer) -> StdinBuffer: create()
def destroy(buffer: StdinBuffer) -> StdinBuffer: clear(buffer)

def kittyDigits(text: String,+value: U32,+digits: Bool,+part: U32,+first: U32) -> Maybe<&2,U32>:
  match text:
    case SNil{}: None{}
    case SCon{Chr{117},SNil{}}:
      Bool.pick(Maybe<&2,U32>,(digits || U32.is_eq(part,1)) && U32.is_ge(Bool.pick(U32,U32.is_eq(part,0),value,first),32),Some{Bool.pick(U32,U32.is_eq(part,0),value,first)},None{})
    case SCon{Chr{58},rest}:
      +rest = {rest: String}
      Bool.pick(Unit -> Maybe<&2,U32>,U32.is_lt(part,2) && (digits || U32.is_eq(part,1)),_ => kittyDigits(rest,0,False{},(part + 1 : U32),Bool.pick(U32,U32.is_eq(part,0),value,first)),_ => None{})(Unit{})
    case SCon{char,rest}:
      +char = {char: Char}
      +rest = {rest: String}
      Bool.pick(Unit -> Maybe<&2,U32>,Char.is_digit(char) && U32.is_le(value,111411),_ => kittyDigits(rest,(value * 10 + Char.to_u32(char) - 48 : U32),True{},part,first),_ => None{})(Unit{})

def printable(sequence: String) -> Maybe<&2,U32>:
  match sequence:
    case SCon{Chr{27},SCon{Chr{91},rest}}: kittyDigits(rest,0,False{},0,0)
    case _: None{}

def duplicate(sequence: String,pending: Maybe<&2,U32>) -> Bool:
  match sequence pending:
    case SCon{char,SNil{}} Some{value}: U32.is_eq(Char.to_u32(char),value)
    case _ _: False{}

def emit(+sequence: String,+pending: Maybe<&2,U32>,+events: List<&2,InputEvent>) -> Transition:
  Bool.pick(Unit -> Transition,duplicate(sequence,pending),_ => Transition{create(),events},_ => Transition{StdinBuffer{Plain{},"",printable(sequence)},DataEvent{sequence} <> events})(Unit{})

def completed(reversed: String,pending: Maybe<&2,U32>,events: List<&2,InputEvent>) -> Transition:
  emit(String.reverse(reversed),pending,events)

def startsControl(text: String) -> Bool:
  match text:
    case SCon{Chr{91},_}: True{}
    case SCon{Chr{93},_}: True{}
    case SCon{Chr{79},_}: True{}
    case SCon{Chr{80},_}: True{}
    case SCon{Chr{95},_}: True{}
    case _: False{}

def pasteCharacter(index: U32) -> Char:
  match index:
    case 0: Chr{27}
    case 1: '['
    case 2: '2'
    case 3: '0'
    case 4: '1'
    case _: '~'

def pasteStep(+char: Char,+matched: U32,+reversed: String,+events: List<&2,InputEvent>) -> Transition:
  +next = Bool.pick(U32,Char.is_eq(char,pasteCharacter(matched)),(matched + 1 : U32),Bool.pick(U32,Char.is_eq(char,Chr{27}),1,0))
  +text = {SCon{char,reversed}: String}
  Bool.pick(Unit -> Transition,U32.is_eq(next,6),_ => Transition{create(),PasteEvent{String.reverse(String.drop(text,6n))} <> events},_ => Transition{StdinBuffer{Pasting{next},text,None{}},events})(Unit{})

def csiEnd(+reversed: String,+pending: Maybe<&2,U32>,+events: List<&2,InputEvent>) -> Transition:
  Bool.pick(Unit -> Transition,String.eq(reversed,"~002[\u{1b}"),_ => Transition{StdinBuffer{Pasting{0},"",None{}},events},_ => completed(reversed,pending,events))(Unit{})

def escapeStep(char: Char,+following: String,+reversed: String,+pending: Maybe<&2,U32>,+events: List<&2,InputEvent>) -> Transition:
  match char:
    case Chr{91}: Transition{StdinBuffer{Csi{True{}},SCon{'[',reversed},pending},events}
    case Chr{93}: Transition{StdinBuffer{Control{True{},False{}},SCon{']',reversed},pending},events}
    case Chr{80}: Transition{StdinBuffer{Control{False{},False{}},SCon{'P',reversed},pending},events}
    case Chr{95}: Transition{StdinBuffer{Control{False{},False{}},SCon{'_',reversed},pending},events}
    case Chr{79}: Transition{StdinBuffer{Ss3{},SCon{'O',reversed},pending},events}
    case Chr{27}: Bool.pick(Unit -> Transition,startsControl(following),_ => Transition{StdinBuffer{Escape{},"\u{1b}",None{}},DataEvent{"\u{1b}"} <> events},_ => completed(SCon{Chr{27},reversed},pending,events))(Unit{})
    case char: completed(SCon{char,reversed},pending,events)

def csiStep(+char: Char,+first: Bool,+reversed: String,+pending: Maybe<&2,U32>,+events: List<&2,InputEvent>) -> Transition:
  +text = {SCon{char,reversed}: String}
  +ordinary = Bool.pick(Unit -> Transition,U32.is_ge(Char.to_u32(char),64) && U32.is_le(Char.to_u32(char),126),_ => csiEnd(text,pending,events),_ => Transition{StdinBuffer{Csi{False{}},text,pending},events})(Unit{})
  Bool.pick(Unit -> Transition,first && Char.is_eq(char,'M'),_ => Transition{StdinBuffer{X10{3},text,pending},events},_ => Bool.pick(Unit -> Transition,first && Char.is_eq(char,'<'),_ => Transition{StdinBuffer{SgrMouse{0,False{},True{}},text,pending},events},_ => ordinary)(Unit{}))(Unit{})

def mouseStep(+char: Char,+fields: U32,+digits: Bool,+valid: Bool,+reversed: String,+pending: Maybe<&2,U32>,+events: List<&2,InputEvent>) -> Transition:
  +separator = Char.is_eq(char,';')
  +digit = Char.is_digit(char)
  +text = {SCon{char,reversed}: String}
  +next = {SgrMouse{Bool.pick(U32,separator,U32.min((fields + 1 : U32),3),fields),digit,valid && (digit || (separator && digits && U32.is_lt(fields,2)))}: Phase}
  Bool.pick(Unit -> Transition,valid && digits && U32.is_eq(fields,2) && (Char.is_eq(char,'M') || Char.is_eq(char,'m')),_ => completed(text,pending,events),_ => Transition{StdinBuffer{next,text,pending},events})(Unit{})

def step(+char: Char,following: String,state: StdinBuffer,+events: List<&2,InputEvent>) -> Transition:
  match state:
    case StdinBuffer{Plain{},_,+pending}: Bool.pick(Unit -> Transition,Char.is_eq(char,Chr{27}),_ => Transition{StdinBuffer{Escape{},"\u{1b}",pending},events},_ => emit(SCon{char,""},pending,events))(Unit{})
    case StdinBuffer{Escape{},reversed,pending}: escapeStep(char,following,reversed,pending,events)
    case StdinBuffer{Csi{first},reversed,pending}: csiStep(char,first,reversed,pending,events)
    case StdinBuffer{SgrMouse{fields,digits,valid},reversed,pending}: mouseStep(char,fields,digits,valid,reversed,pending,events)
    case StdinBuffer{X10{+left},+reversed,+pending}: Bool.pick(Unit -> Transition,U32.is_eq(left,1),_ => completed(SCon{char,reversed},pending,events),_ => Transition{StdinBuffer{X10{(left - 1 : U32)},SCon{char,reversed},pending},events})(Unit{})
    case StdinBuffer{Ss3{},reversed,pending}: completed(SCon{char,reversed},pending,events)
    case StdinBuffer{Control{+bell,escaped},+reversed,+pending}: Bool.pick(Unit -> Transition,(escaped && Char.is_eq(char,'\\')) || (bell && Char.is_eq(char,Chr{7})),_ => completed(SCon{char,reversed},pending,events),_ => Transition{StdinBuffer{Control{bell,Char.is_eq(char,Chr{27})},SCon{char,reversed},pending},events})(Unit{})
    case StdinBuffer{Pasting{matched},reversed,_}: pasteStep(char,matched,reversed,events)

def consume(text: String,transition: Transition) -> Transition:
  match text transition:
    case SNil{} Transition{buffer,events}: Transition{buffer,List.reverse(&2,InputEvent,events)}
    case SCon{char,+rest} Transition{buffer,events}: consume(rest,step(char,rest,buffer,events))

def process(text: String,buffer: StdinBuffer) -> Transition:
  match text buffer:
    case SNil{} StdinBuffer{Plain{},_,pending}: emit("",pending,Nil{})
    case text buffer: consume(text,Transition{buffer,Nil{}})

def getBuffer(buffer: StdinBuffer) -> String:
  match buffer:
    case StdinBuffer{Pasting{_},_,_}: ""
    case StdinBuffer{_,reversed,_}: String.reverse(reversed)

def flush(buffer: StdinBuffer) -> Transition:
  match buffer:
    case StdinBuffer{Pasting{matched},reversed,pending}: Transition{StdinBuffer{Pasting{matched},reversed,pending},Nil{}}
    case StdinBuffer{Plain{},_,pending}: Transition{StdinBuffer{Plain{},"",pending},Nil{}}
    case StdinBuffer{_,reversed,_}: Transition{create(),[DataEvent{String.reverse(reversed)}]}

def pendingTimeout(buffer: StdinBuffer,options: StdinBufferOptions) -> Maybe<&2,U32>:
  match buffer options:
    case StdinBuffer{Plain{},_,_} _: None{}
    case StdinBuffer{Pasting{_},_,_} _: None{}
    case StdinBuffer{Escape{},_,_} StdinBufferOptions{_,escapeTimeout}: Some{escapeTimeout}
    case _ StdinBufferOptions{timeout,_}: Some{timeout}
