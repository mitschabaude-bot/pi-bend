import Base
import ../../runtime/src/child-process.bend as Child
import ../../runtime/src/callback.bend as Callback
import ../../runtime/src/ref.bend as Ref
import ../../runtime/src/text.bend as Text
import ../../runtime/src/url.bend as Url
import ../../runtime/src/posix-path.bend as Paths
import ../../runtime/src/jpeg.bend as Jpeg
import ../../runtime/src/random.bend as Random
import ../../runtime/src/base64.bend as Base64
import ../../runtime/src/utf8.bend as Utf8
import ../../runtime/src/string.bend as Strings
import ../../runtime/src/f64.bend as Number
import ../../runtime/src/record.bend as Record

# Image payloads must remain intact when overlays cover their terminal rows.
def imagePrefix(+rest: String) -> Bool: String.starts_with(rest,"_G") || String.starts_with(rest,"]1337;File=")
def imageScan(line: String,found: Bool) -> Bool:
  match line found:
    case _ True{}: True{}
    case SNil{} False{}: False{}
    case SCon{Chr{27},+rest} False{}: imageScan(rest,imagePrefix(rest))
    case SCon{_,rest} False{}: imageScan(rest,False{})
def isImageLine(line: String) -> Bool: imageScan(line,False{})

# Terminal environment and mutable JS globals are explicit caller-owned data.
type ImageProtocol is Data:
  NoImages{}
  Kitty{}
  ITerm2{}
type TerminalCapabilities is Data: TerminalCapabilities{images: ImageProtocol,trueColor: Bool,hyperlinks: Bool}
type CapabilityOverrides is Data: CapabilityOverrides{images: Maybe<&2,ImageProtocol>,trueColor: Maybe<&2,Bool>,hyperlinks: Maybe<&2,Bool>}
type CellDimensions is Data: CellDimensions{widthPx: F64,heightPx: F64}
type ImageDimensions is Data: ImageDimensions{widthPx: U32,heightPx: U32}
type ImageCellSize is Data: ImageCellSize{columns: Nat,rows: Nat}
type ImageRenderOptions is Data:
  ImageRenderOptions{maxWidthCells: Maybe<&2,F64>,maxHeightCells: Maybe<&2,F64>,preserveAspectRatio: Bool,imageId: Maybe<&2,U32>,moveCursor: Bool}
type KittyOptions is Data: KittyOptions{columns: Maybe<&2,Nat>,rows: Maybe<&2,Nat>,imageId: Maybe<&2,U32>,moveCursor: Bool}
type ImageDimension is Data:
  Auto{}
  Cells{count: Nat}
  Pixels{count: Nat}
  Percent{value: F64}
type ITerm2Options is Data: ITerm2Options{width: Maybe<&2,ImageDimension>,height: Maybe<&2,ImageDimension>,name: Maybe<&2,String>,preserveAspectRatio: Bool,inline: Bool}
type KittyImageMetadata is Data: KittyImageMetadata{imageId: U32,columns: Nat,rows: Nat,widthPx: U32,heightPx: U32}
type RegisteredMetadata is Data: RegisteredMetadata{metadata: KittyImageMetadata,transmissionGeneration: Nat}
type KittyImagePlacement is Data:
  KittyImagePlacement{imageId: U32,transmissionGeneration: Nat,transmissionBytes: Nat,estimatedDecodedBytes: Nat,sequence: String,replacementLine: String}
type State is Data:
  State{cached: Maybe<&2,TerminalCapabilities>,overrides: CapabilityOverrides,cells: CellDimensions,metadata: List<&2,RegisteredMetadata>,generation: Nat}
type Environment is Data: Environment{variables: Record.Record<String>,platform: String,home: String}
type Error is Data:
  InvalidBase64{cause: Base64.Error}
  InvalidDimensions{}
  InvalidImageId{}
  InvalidParameter{parameter: String}
  InvalidImage{format: String}
  UnsupportedFormat{mimeType: String}
  InvalidControl{}
type RenderResult is Data: RenderResult{sequence: String,columns: Nat,rows: Nat,imageId: Maybe<&2,U32>}
type Rendered is Data: Rendered{state: State,image: Maybe<&2,RenderResult>}

def noOverrides() -> CapabilityOverrides: CapabilityOverrides{None{},None{},None{}}
def defaultCellDimensions() -> CellDimensions: CellDimensions{Number.fromU32(9),Number.fromU32(18)}
def create() -> State: State{None{},noOverrides(),defaultCellDimensions(),Nil{},0n}
def defaultRenderOptions() -> ImageRenderOptions: ImageRenderOptions{None{},None{},True{},None{},True{}}
def defaultKittyOptions() -> KittyOptions: KittyOptions{None{},None{},None{},True{}}
def defaultITerm2Options() -> ITerm2Options: ITerm2Options{None{},None{},None{},True{},True{}}
def reverseInto(text: String,result: String) -> String:
  match text:
    case SNil{}: result
    case SCon{char,rest}: reverseInto(rest,SCon{char,result})
def byteCount(bytes: List<&2,U32>,count: Nat) -> Nat:
  match bytes:
    case Nil{}: count
    case _ <> rest: byteCount(rest,count + 1n)
def positive(+value: F64) -> Bool: Number.isFinite(Number.decode(value)) && F64.is_gt(value,Number.fromU32(0))
def validHeight(value: Maybe<&2,F64>) -> Bool:
  match value:
    case None{}: True{}
    case Some{value}: positive(value)
def pixelDimensions(value: ImageDimensions) -> Bool:
  match value:
    case ImageDimensions{width,height}: U32.is_gt(width,0) && U32.is_gt(height,0)
def validCells(value: CellDimensions) -> Bool:
  match value:
    case CellDimensions{width,height}: positive(width) && positive(height)
def floorCells(value: F64) -> F64: Number.maximum(Number.fromU32(1),Number.truncate(value))
def cellSize(columns: Result<&2,&2,Number.Error,Nat>,rows: Result<&2,&2,Number.Error,Nat>) -> Result<&2,&2,Error,ImageCellSize>:
  match columns rows:
    case Done{width} Done{height}: Done{ImageCellSize{width,height}}
    case _ _: Fail{InvalidDimensions{}}
def heightScale(value: Maybe<&2,F64>,cellHeight: F64,imageHeight: F64,widthScale: F64) -> F64:
  match value:
    case None{}: widthScale
    case Some{height}: Number.minimum(widthScale,Number.divide(Number.multiply(floorCells(height),cellHeight),imageHeight))
def boundRows(value: Maybe<&2,F64>,rows: F64) -> F64:
  match value:
    case None{}: rows
    case Some{height}: Number.minimum(floorCells(height),rows)
def calculateSize(dimensions: ImageDimensions,+maxWidth: F64,+maxHeight: Maybe<&2,F64>,cells: CellDimensions) -> Result<&2,&2,Error,ImageCellSize>:
  match dimensions cells:
    case ImageDimensions{width,height} CellDimensions{+cellWidth,+cellHeight}:
      +imageWidth = Number.fromU32(width)
      +imageHeight = Number.fromU32(height)
      +columnsLimit = floorCells(maxWidth)
      +widthScale = Number.divide(Number.multiply(columnsLimit,cellWidth),imageWidth)
      +scale = heightScale(maxHeight,cellHeight,imageHeight,widthScale)
      +columns = Number.maximum(Number.fromU32(1),Number.minimum(columnsLimit,Number.ceil(Number.divide(Number.multiply(imageWidth,scale),cellWidth))))
      +rows = Number.maximum(Number.fromU32(1),boundRows(maxHeight,Number.ceil(Number.divide(Number.multiply(imageHeight,scale),cellHeight))))
      cellSize(Number.convert(columns),Number.convert(rows))
def calculateImageCellSize(+dimensions: ImageDimensions,+maxWidth: F64,+maxHeight: Maybe<&2,F64>,+cells: CellDimensions) -> Result<&2,&2,Error,ImageCellSize>:
  valid = pixelDimensions(dimensions) && positive(maxWidth) && validHeight(maxHeight) && validCells(cells)
  Bool.pick(Unit -> Result<&2,&2,Error,ImageCellSize>,valid,_ => calculateSize(dimensions,maxWidth,maxHeight,cells),_ => Fail{InvalidDimensions{}})(Unit{})
def imageRows(value: Result<&2,&2,Error,ImageCellSize>) -> Result<&2,&2,Error,Nat>:
  match value:
    case Fail{error}: Fail{error}
    case Done{ImageCellSize{_,rows}}: Done{rows}
def calculateImageRows(dimensions: ImageDimensions,width: F64,cells: CellDimensions) -> Result<&2,&2,Error,Nat>:
  imageRows(calculateImageCellSize(dimensions,width,None{},cells))

def validId(value: Maybe<&2,U32>) -> Bool:
  match value:
    case None{}: True{}
    case Some{value}: U32.is_gt(value,0)
def validCount(value: Maybe<&2,Nat>) -> Bool:
  match value:
    case None{}: True{}
    case Some{value}: Nat.is_gt(value,0n)
def countParameter(name: String,value: Maybe<&2,Nat>) -> String:
  match value:
    case None{}: ""
    case Some{value}: "," ++ name ++ "=" ++ Nat.show(value)
def idParameter(value: Maybe<&2,U32>) -> String:
  match value:
    case None{}: ""
    case Some{value}: ",i=" ++ U32.show(value)
def kittyParameters(options: KittyOptions) -> Result<&2,&2,Error,String>:
  match options:
    case KittyOptions{+columns,+rows,+imageId,moveCursor}:
      valid = validCount(columns) && validCount(rows) && validId(imageId)
      params = "a=T,f=100,q=2" ++ Bool.pick(String,moveCursor,"",",C=1") ++ countParameter("c",columns) ++ countParameter("r",rows) ++ idParameter(imageId)
      Bool.pick(Result<&2,&2,Error,String>,valid,Done{params},Fail{InvalidParameter{"Kitty placement"}})
type TextChunk is Data: TextChunk{text: String,rest: String}
def takeText(count: Nat,text: String,reversed: String) -> TextChunk:
  match count text:
    case Zero{} text: TextChunk{reverseInto(reversed,""),text}
    case _ SNil{}: TextChunk{reverseInto(reversed,""),""}
    case Succ{count} SCon{char,rest}: takeText(count,rest,SCon{char,reversed})
@unsafe def kittyChunks(value: TextChunk,first: Bool,parameters: String,reversed: String) -> String:
  match value:
    case TextChunk{+text,+rest}:
      +last = Strings.equal(rest,"")
      +more = Bool.pick(String,last,",m=0",",m=1")
      controls = Bool.pick(String,first,parameters ++ Bool.pick(String,last,"",more),Bool.pick(String,last,"m=0","m=1"))
      +next = reverseInto("\u{1b}_G" ++ controls ++ ";" ++ text ++ "\u{1b}\\",reversed)
      Bool.pick(Unit -> String,last,_ => reverseInto(next,""),_ => kittyChunks(takeText(4096n,rest,""),False{},"",next))(Unit{})
def kittyValidated(data: String,parameters: Result<&2,&2,Error,String>,decoded: Result<&2,&2,Base64.Error,List<&2,U32>>) -> Result<&2,&2,Error,String>:
  match parameters decoded:
    case Fail{error} _: Fail{error}
    case _ Fail{cause}: Fail{InvalidBase64{cause}}
    case Done{parameters} Done{_}: Done{kittyChunks(takeText(4096n,data,""),True{},parameters,"")}
def encodeKitty(+data: String,options: KittyOptions) -> Result<&2,&2,Error,String>:
  kittyValidated(data,kittyParameters(options),Base64.decode(data))
def deleteKittyImage(+imageId: U32) -> Result<&2,&2,Error,String>:
  Bool.pick(Result<&2,&2,Error,String>,U32.is_gt(imageId,0),Done{"\u{1b}_Ga=d,d=I,i=" ++ U32.show(imageId) ++ ",q=2\u{1b}\\"},Fail{InvalidImageId{}})
def deleteAllKittyImages() -> String: "\u{1b}_Ga=d,d=A,q=2\u{1b}\\"
def deleteAllKittyPlacements() -> String: "\u{1b}_Ga=d,d=a,q=2\u{1b}\\"
def dimensionText(value: ImageDimension) -> Result<&2,&2,Error,String>:
  match value:
    case Auto{}: Done{"auto"}
    case Cells{+count}: Bool.pick(Result<&2,&2,Error,String>,Nat.is_gt(count,0n),Done{Nat.show(count)},Fail{InvalidDimensions{}})
    case Pixels{+count}: Bool.pick(Result<&2,&2,Error,String>,Nat.is_gt(count,0n),Done{Nat.show(count) ++ "px"},Fail{InvalidDimensions{}})
    case Percent{+value}: Bool.pick(Result<&2,&2,Error,String>,positive(value),Done{F64.show(value) ++ "%"},Fail{InvalidDimensions{}})
def dimensionParameter(name: String,value: Maybe<&2,ImageDimension>) -> Result<&2,&2,Error,String>:
  match value:
    case None{}: Done{""}
    case Some{value}: Result.map(&2,&2,Error,String,String,text => ";" ++ name ++ "=" ++ text,dimensionText(value))
def nameParameter(value: Maybe<&2,String>) -> String:
  match value:
    case None{}: ""
    case Some{SNil{}}: ""
    case Some{value}: ";name=" ++ Base64.encoded(Utf8.encode(value),"")
def itermParameters(options: ITerm2Options,size: Nat) -> Result<&2,&2,Error,String>:
  match options:
    case ITerm2Options{width,height,name,preserve,inline}:
      +prefix = "inline=" ++ Bool.pick(String,inline,"1","0") ++ ";size=" ++ Nat.show(size)
      +suffix = nameParameter(name) ++ Bool.pick(String,preserve,"",";preserveAspectRatio=0")
      Result.bind(&2,&2,Error,String,String,dimensionParameter("width",width),w =>
        Result.map(&2,&2,Error,String,String,h => prefix ++ w ++ h ++ suffix,dimensionParameter("height",height)))
def itermValidated(+data: String,options: ITerm2Options,decoded: Result<&2,&2,Base64.Error,List<&2,U32>>) -> Result<&2,&2,Error,String>:
  match decoded:
    case Fail{cause}: Fail{InvalidBase64{cause}}
    case Done{bytes}: Result.map(&2,&2,Error,String,String,parameters => "\u{1b}]1337;File=" ++ parameters ++ ":" ++ data ++ "\u{7}",itermParameters(options,byteCount(bytes,0n)))
def encodeITerm2(+data: String,options: ITerm2Options) -> Result<&2,&2,Error,String>:
  itermValidated(data,options,Base64.decode(data))

# Capability names are ASCII identifiers. Kelvin sign is the only non-ASCII
# scalar whose lowercase mapping can match an ASCII name used below.
def lowerIdentifier(text: String,reversed: String) -> String:
  match text:
    case SNil{}: reverseInto(reversed,"")
    case SCon{Chr{+point},rest}:
      asciiUpper = U32.is_ge(point,65) && U32.is_le(point,90)
      mapped = Bool.pick(U32,asciiUpper,U32.add(point,32),Bool.pick(U32,U32.is_eq(point,8490),107,point))
      lowerIdentifier(rest,SCon{Chr{mapped},reversed})
def variable(environment: Environment,name: String) -> String:
  match environment:
    case Environment{variables,_,_}: Maybe.default(&2,String,Record.get(String,variables,name),"")
def environmentPlatform(environment: Environment) -> String:
  match environment:
    case Environment{_,platform,_}: platform
def present(environment: Environment,name: String) -> Bool: Bool.not(Strings.equal(variable(environment,name),""))
def includes(text: String,+part: String) -> Bool:
  match text:
    case SNil{}: Strings.equal(part,"")
    case SCon{+char,+rest}: Bool.pick(Unit -> Bool,String.starts_with(SCon{char,rest},part),_ => True{},_ => includes(rest,part))(Unit{})
def booleanOverride(text: String) -> Maybe<&2,Bool>:
  match text:
    case "1": Some{True{}}
    case "0": Some{False{}}
    case _: None{}
def imageOverride(text: String) -> Maybe<&2,ImageProtocol>:
  match text:
    case "kitty": Some{Kitty{}}
    case "iterm2": Some{ITerm2{}}
    case "none": Some{NoImages{}}
    case "0": Some{NoImages{}}
    case _: None{}
def environmentOverrides(+environment: Environment) -> CapabilityOverrides:
  CapabilityOverrides{imageOverride(lowerIdentifier(variable(environment,"PI_IMAGE_PROTOCOL"),"")),booleanOverride(variable(environment,"PI_TRUE_COLOR")),booleanOverride(variable(environment,"PI_HYPERLINKS"))}
def applyOverrides(capabilities: TerminalCapabilities,overrides: CapabilityOverrides) -> TerminalCapabilities:
  match capabilities overrides:
    case TerminalCapabilities{images,trueColor,hyperlinks} CapabilityOverrides{image,color,links}:
      TerminalCapabilities{Maybe.default(&2,ImageProtocol,image,images),Maybe.default(&2,Bool,color,trueColor),Maybe.default(&2,Bool,links,hyperlinks)}
def terminalCapabilities(+environment: Environment,+program: String,+term: String,+trueColorHint: Bool) -> TerminalCapabilities:
  kitty = present(environment,"KITTY_WINDOW_ID") || Strings.equal(program,"kitty")
  ghostty = Strings.equal(program,"ghostty") || includes(term,"ghostty") || present(environment,"GHOSTTY_RESOURCES_DIR")
  wezterm = present(environment,"WEZTERM_PANE") || Strings.equal(program,"wezterm")
  warp = Strings.equal(program,"warpterminal") || present(environment,"WARP_SESSION_ID") || present(environment,"WARP_TERMINAL_SESSION_UUID")
  iterm = present(environment,"ITERM_SESSION_ID") || Strings.equal(program,"iterm.app")
  modern = present(environment,"WT_SESSION") || Strings.equal(program,"alacritty") || Strings.equal(program,"vscode") || Strings.equal(program,"zed")
  jetbrains = Strings.equal(lowerIdentifier(variable(environment,"TERMINAL_EMULATOR"),""),"jetbrains-jediterm")
  windows = Strings.equal(environmentPlatform(environment),"win32")
  Bool.pick(TerminalCapabilities,kitty || ghostty || wezterm || warp,TerminalCapabilities{Kitty{},True{},True{}},
    Bool.pick(TerminalCapabilities,iterm,TerminalCapabilities{ITerm2{},True{},True{}},
      Bool.pick(TerminalCapabilities,modern,TerminalCapabilities{NoImages{},True{},True{}},
        TerminalCapabilities{NoImages{},trueColorHint || jetbrains || windows,False{}})))
def detectCapabilities(+environment: Environment,tmuxForwardsHyperlinks: Bool) -> TerminalCapabilities:
  +term = lowerIdentifier(variable(environment,"TERM"),"")
  +color = lowerIdentifier(variable(environment,"COLORTERM"),"")
  +trueColor = Strings.equal(color,"truecolor") || Strings.equal(color,"24bit")
  tmux = present(environment,"TMUX") || String.starts_with(term,"tmux")
  screen = String.starts_with(term,"screen")
  detected = Bool.pick(TerminalCapabilities,tmux,TerminalCapabilities{NoImages{},trueColor,tmuxForwardsHyperlinks},
    Bool.pick(TerminalCapabilities,screen,TerminalCapabilities{NoImages{},trueColor,False{}},terminalCapabilities(environment,lowerIdentifier(variable(environment,"TERM_PROGRAM"),""),term,trueColor)))
  applyOverrides(detected,environmentOverrides(environment))
# The process variables detectCapabilities reads.
def CAPABILITY_VARIABLES() -> List<&2,String>:
  ["TERM","COLORTERM","TMUX","TERM_PROGRAM","KITTY_WINDOW_ID","GHOSTTY_RESOURCES_DIR","WEZTERM_PANE","WARP_SESSION_ID","WARP_TERMINAL_SESSION_UUID","ITERM_SESSION_ID","WT_SESSION","TERMINAL_EMULATOR","PI_IMAGE_PROTOCOL","PI_TRUE_COLOR","PI_HYPERLINKS"]
def withVariable(variables: Record.Record<String>,+name: String,value: Result<&1,&1,U32 & String,String>) -> Record.Record<String>:
  match value:
    case Done{text}: Record.set(String,variables,name,text)
    case Fail{_}: variables
def readVariables(names: List<&2,String>,variables: Record.Record<String>) -> IO(Record.Record<String>):
  match names:
    case Nil{}: IO.pure(Record.Record<String>,variables)
    case +name <> rest:
      do IO<Record.Record<String>>:
        value : Result<&1,&1,U32 & String,String> <- IO.get_env(name)
        readVariables(rest,withVariable(variables,name,value))
def processEnvironment(platform: String,home: String) -> IO(Environment):
  do IO<Environment>:
    variables : Record.Record<String> <- readVariables(CAPABILITY_VARIABLES(),Record.new(String))
    return Environment{variables,platform,home}
# upstream getCapabilities().trueColor: an explicit override (settings) wins
# over detection; the tmux hyperlink probe does not affect colour.
def capabilityTrueColor(capabilities: TerminalCapabilities) -> Bool:
  match capabilities: case TerminalCapabilities{_,value,_}: value
def trueColor(+environment: Environment,override: Maybe<&2,Bool>) -> Bool:
  match override:
    case Some{value}: value
    case None{}: capabilityTrueColor(detectCapabilities(environment,False{}))
def getCellDimensions(state: State) -> CellDimensions:
  match state:
    case State{_,_,cells,_,_}: cells
def setCellDimensions(state: State,+dimensions: CellDimensions) -> Result<&2,&2,Error,State>:
  match state:
    case State{cache,overrides,_,metadata,generation}:
      Bool.pick(Result<&2,&2,Error,State>,validCells(dimensions),Done{State{cache,overrides,dimensions,metadata,generation}},Fail{InvalidDimensions{}})
def setCapabilities(state: State,capabilities: TerminalCapabilities) -> State:
  match state:
    case State{_,overrides,cells,metadata,generation}: State{Some{capabilities},overrides,cells,metadata,generation}
def resetCapabilitiesCache(state: State) -> State:
  match state:
    case State{_,overrides,cells,metadata,generation}: State{None{},overrides,cells,metadata,generation}
def sameProtocol(left: Maybe<&2,ImageProtocol>,right: Maybe<&2,ImageProtocol>) -> Bool:
  match left right:
    case None{} None{}: True{}
    case Some{NoImages{}} Some{NoImages{}}: True{}
    case Some{Kitty{}} Some{Kitty{}}: True{}
    case Some{ITerm2{}} Some{ITerm2{}}: True{}
    case _ _: False{}
def sameBoolean(left: Maybe<&2,Bool>,right: Maybe<&2,Bool>) -> Bool:
  match left right:
    case None{} None{}: True{}
    case Some{True{}} Some{True{}}: True{}
    case Some{False{}} Some{False{}}: True{}
    case _ _: False{}
def sameOverrides(left: CapabilityOverrides,right: CapabilityOverrides) -> Bool:
  match left right:
    case CapabilityOverrides{li,lc,lh} CapabilityOverrides{ri,rc,rh}: sameProtocol(li,ri) && sameBoolean(lc,rc) && sameBoolean(lh,rh)
def setCapabilityOverrides(state: State,+overrides: CapabilityOverrides) -> State:
  match state:
    case State{cache,+old,cells,metadata,generation}:
      State{Bool.pick(Maybe<&2,TerminalCapabilities>,sameOverrides(old,overrides),cache,None{}),overrides,cells,metadata,generation}
def getCapabilities(+state: State,environment: Environment,tmuxForwardsHyperlinks: Bool) -> State & TerminalCapabilities:
  match state:
    case State{Some{+cached},_,_,_,_}: (state,cached)
    case State{None{},+overrides,_,_,_}:
      +capabilities = applyOverrides(detectCapabilities(environment,tmuxForwardsHyperlinks),overrides)
      (setCapabilities(state,capabilities),capabilities)
def overrideHasHyperlinks(overrides: CapabilityOverrides) -> Bool:
  match overrides:
    case CapabilityOverrides{_,_,value}: Bool.not(Maybe.is_none(&2,Bool,value))
def needsTmuxProbe(state: State,+environment: Environment) -> Bool:
  match state:
    case State{Some{_},_,_,_,_}: False{}
    case State{None{},overrides,_,_,_}:
      term = lowerIdentifier(variable(environment,"TERM"),"")
      (present(environment,"TMUX") || String.starts_with(term,"tmux")) && Bool.not(overrideHasHyperlinks(overrides)) && Bool.not(overrideHasHyperlinks(environmentOverrides(environment)))

def metadataId(value: KittyImageMetadata) -> U32:
  match value:
    case KittyImageMetadata{id,_,_,_,_}: id
def validMetadata(value: KittyImageMetadata) -> Bool:
  match value:
    case KittyImageMetadata{id,columns,rows,width,height}:
      U32.is_gt(id,0) && Nat.is_gt(columns,0n) && Nat.is_gt(rows,0n) && U32.is_gt(width,0) && U32.is_gt(height,0)
def retainMetadata(items: List<&2,RegisteredMetadata>,+id: U32,remaining: Nat,+reversed: List<&2,RegisteredMetadata>) -> List<&2,RegisteredMetadata>:
  match items remaining:
    case _ Zero{}: List.reverse(&2,RegisteredMetadata,reversed)
    case Nil{} _: List.reverse(&2,RegisteredMetadata,reversed)
    case RegisteredMetadata{+metadata,+generation} <> +rest Succ{+remaining}:
      Bool.pick(Unit -> List<&2,RegisteredMetadata>,U32.is_eq(metadataId(metadata),id),
        _ => retainMetadata(rest,id,Succ{remaining},reversed),
        _ => retainMetadata(rest,id,remaining,RegisteredMetadata{metadata,generation} <> reversed))(Unit{})
def registerKittyImageMetadata(state: State,+metadata: KittyImageMetadata) -> Result<&2,&2,Error,State>:
  match state:
    case State{cache,overrides,cells,items,+generation}:
      updated = {State{cache,overrides,cells,RegisteredMetadata{metadata,generation + 1n} <> retainMetadata(items,metadataId(metadata),999n,Nil{}),generation + 1n} : State}
      Bool.pick(Result<&2,&2,Error,State>,validMetadata(metadata),Done{updated},Fail{InvalidDimensions{}})
def lookupMetadata(items: List<&2,RegisteredMetadata>,+id: U32) -> Maybe<&2,RegisteredMetadata>:
  match items:
    case Nil{}: None{}
    case RegisteredMetadata{+metadata,+generation} <> rest:
      Bool.pick(Unit -> Maybe<&2,RegisteredMetadata>,U32.is_eq(metadataId(metadata),id),_ => Some{RegisteredMetadata{metadata,generation}},_ => lookupMetadata(rest,id))(Unit{})
def registered(state: State,id: U32) -> Maybe<&2,RegisteredMetadata>:
  match state:
    case State{_,_,_,items,_}: lookupMetadata(items,id)
def decimal(text: String,+value: U32,seen: Bool) -> Maybe<&2,U32>:
  match text:
    case SNil{}: Bool.pick(Maybe<&2,U32>,seen,Some{value},None{})
    case SCon{char,rest}:
      +code = Char.to_u32(char)
      +digit = U32.sub(code,48)
      valid = U32.is_ge(code,48) && U32.is_le(code,57) && U32.is_le(value,U32.div(U32.sub(4294967295,digit),10))
      Bool.pick(Unit -> Maybe<&2,U32>,valid,_ => decimal(rest,U32.add(U32.mul(value,10),digit),True{}),_ => None{})(Unit{})
def controlId(control: String) -> Maybe<&2,U32>:
  match control:
    case SCon{'i',SCon{'=',value}}: decimal(value,0,False{})
    case _: None{}
def firstId(rest: List<&2,String>,value: Maybe<&2,U32>) -> Maybe<&2,U32>:
  match rest value:
    case _ Some{id}: Some{id}
    case Nil{} None{}: None{}
    case control <> rest None{}: firstId(rest,controlId(control))
type KittyHeader is Data: KittyHeader{before: String,controls: String,payload: String}
def headerControls(text: String,before: String,reversed: String) -> Maybe<&2,KittyHeader>:
  match text:
    case SNil{}: None{}
    case SCon{';',rest}: Some{KittyHeader{before,reverseInto(reversed,""),rest}}
    case SCon{char,rest}: headerControls(rest,before,SCon{char,reversed})
def findKitty(text: String,reversed: String) -> Maybe<&2,KittyHeader>:
  match text:
    case SNil{}: None{}
    case SCon{Chr{27},SCon{'_',SCon{'G',rest}}}: headerControls(rest,reverseInto(reversed,""),"")
    case SCon{char,rest}: findKitty(rest,SCon{char,reversed})
def headerMetadata(state: State,header: Maybe<&2,KittyHeader>) -> Maybe<&2,RegisteredMetadata>:
  match header:
    case None{}: None{}
    case Some{KittyHeader{_,controls,_}}:
      Maybe.bind(&2,U32,RegisteredMetadata,firstId(Strings.split(controls,','),None{}),id => registered(state,id))
def publicMetadata(value: Maybe<&2,RegisteredMetadata>) -> Maybe<&2,KittyImageMetadata>:
  match value:
    case None{}: None{}
    case Some{RegisteredMetadata{metadata,_}}: Some{metadata}
def getKittyImageMetadata(state: State,line: String) -> Maybe<&2,KittyImageMetadata>:
  publicMetadata(headerMetadata(state,findKitty(line,"")))
def stringLength(text: String,count: Nat) -> Nat:
  match text:
    case SNil{}: count
    case SCon{_,rest}: stringLength(rest,count + 1n)
def hasMore(controls: List<&2,String>) -> Bool:
  match controls:
    case Nil{}: False{}
    case control <> rest: Bool.pick(Unit -> Bool,Strings.equal(control,"m=1"),_ => True{},_ => hasMore(rest))(Unit{})
type TransmissionEnd is Data: TransmissionEnd{suffix: String,length: Nat}
def transmissionEnd(text: String,count: Nat) -> Maybe<&2,TransmissionEnd>:
  match text:
    case SNil{}: None{}
    case SCon{Chr{27},SCon{'\\',rest}}: Some{TransmissionEnd{rest,count + 2n}}
    case SCon{_,rest}: transmissionEnd(rest,count + 1n)
# Each continuation consumes a full graphics command, including its terminator.
type Transmission is Data:
  ReadCommand{header: Maybe<&2,KittyHeader>,count: Nat}
  ReadEnd{ended: Maybe<&2,TransmissionEnd>,more: Bool}
@unsafe def transmission(state: Transmission) -> Maybe<&2,TransmissionEnd>:
  match state:
    case ReadCommand{None{},_}: None{}
    case ReadCommand{Some{KittyHeader{_,+controls,payload}},count}:
      total = count + stringLength(controls,4n)
      transmission(ReadEnd{transmissionEnd(payload,total),hasMore(Strings.split(controls,','))})
    case ReadEnd{None{},_}: None{}
    case ReadEnd{Some{value},False{}}: Some{value}
    case ReadEnd{Some{TransmissionEnd{SCon{Chr{27},SCon{'_',SCon{'G',rest}}},count}},True{}}:
      transmission(ReadCommand{headerControls(rest,"",""),count})
    case ReadEnd{_,True{}}: None{}
def placementKey(control: String) -> Bool:
  match control:
    case SCon{+char,SCon{'=',_}}:
      includes("ipxywhXYcrCUzPQHV",SCon{char,""})
    case _: False{}
def placementControls(items: List<&2,String>,+reversed: List<&2,String>) -> List<&2,String>:
  match items:
    case Nil{}: List.reverse(&2,String,reversed)
    case +control <> rest: placementControls(rest,Bool.pick(List<&2,String>,placementKey(control),control <> reversed,reversed))
def placementResult(metadata: RegisteredMetadata,before: String,controls: String,ended: Maybe<&2,TransmissionEnd>) -> Maybe<&2,KittyImagePlacement>:
  match metadata ended:
    case _ None{}: None{}
    case RegisteredMetadata{KittyImageMetadata{id,_,_,width,height},generation} Some{TransmissionEnd{suffix,length}}:
      +sequence = "\u{1b}_Ga=p,q=2," ++ String.join(placementControls(Strings.split(controls,','),Nil{}),",") ++ "\u{1b}\\"
      Some{KittyImagePlacement{id,generation,length,U32.to_nat(width) * U32.to_nat(height) * 4n,sequence,before ++ sequence ++ suffix}}
def placementMetadata(metadata: Maybe<&2,RegisteredMetadata>,header: Maybe<&2,KittyHeader>) -> Maybe<&2,KittyImagePlacement>:
  match metadata header:
    case Some{metadata} Some{KittyHeader{before,+controls,payload}}:
      placementResult(metadata,before,controls,transmission(ReadCommand{Some{KittyHeader{"",controls,payload}},0n}))
    case _ _: None{}
def getKittyImagePlacement(state: State,+line: String) -> Maybe<&2,KittyImagePlacement>:
  placementMetadata(headerMetadata(state,findKitty(line,"")),findKitty(line,""))
def cropControls(items: List<&2,String>,reversed: List<&2,String>) -> List<&2,String>:
  match items:
    case Nil{}: List.reverse(&2,String,reversed)
    case SCon{'y',SCon{'=',_}} <> rest: cropControls(rest,reversed)
    case SCon{'h',SCon{'=',_}} <> rest: cropControls(rest,reversed)
    case SCon{'r',SCon{'=',_}} <> rest: cropControls(rest,reversed)
    case control <> rest: cropControls(rest,control <> reversed)
def cropped(line: String,metadata: Maybe<&2,RegisteredMetadata>,header: Maybe<&2,KittyHeader>,+hiddenRows: Nat,+visibleRows: Nat) -> Result<&2,&2,Error,String>:
  match metadata header:
    case Some{RegisteredMetadata{KittyImageMetadata{_,_,+rows,_,height},_}} Some{KittyHeader{before,controls,payload}}:
      +croppedRows = Nat.min(visibleRows,rows - hiddenRows)
      +pixels = U32.to_nat(height)
      +sourceY = (pixels * hiddenRows) / rows
      sourceEnd = (pixels * (hiddenRows + croppedRows) + rows - 1n) / rows
      sourceHeight = Nat.max(1n,Nat.min(pixels,sourceEnd) - sourceY)
      newControls = String.join(cropControls(Strings.split(controls,','),Nil{}),",") ++ ",y=" ++ Nat.show(sourceY) ++ ",h=" ++ Nat.show(sourceHeight) ++ ",r=" ++ Nat.show(croppedRows)
      result = Bool.pick(String,Nat.is_eq(hiddenRows,0n) && Nat.is_eq(croppedRows,rows),line,before ++ "\u{1b}_G" ++ newControls ++ ";" ++ payload)
      Bool.pick(Result<&2,&2,Error,String>,Nat.is_lt(hiddenRows,rows) && Nat.is_gt(visibleRows,0n),Done{result},Fail{InvalidParameter{"crop rows"}})
    case _ _: Done{line}
def cropKittyImageLine(state: State,+line: String,hiddenRows: Nat,visibleRows: Nat) -> Result<&2,&2,Error,String>:
  cropped(line,headerMetadata(state,findKitty(line,"")),findKitty(line,""),hiddenRows,visibleRows)

# These probes inspect complete dimension-bearing headers, not pixel data. JPEG
# segment framing and component validation are shared with the native decoder.
def checkedDimensions(format: String,+width: U32,+height: U32) -> Result<&2,&2,Error,ImageDimensions>:
  Bool.pick(Result<&2,&2,Error,ImageDimensions>,U32.is_gt(width,0) && U32.is_gt(height,0),Done{ImageDimensions{width,height}},Fail{InvalidImage{format}})
def little16(a: U32,b: U32) -> U32: U32.or(a,U32.shln(b,8n))
def little24(a: U32,b: U32,c: U32) -> U32: U32.or(little16(a,b),U32.shln(c,16n))
def little32(a: U32,b: U32,c: U32,d: U32) -> U32: U32.or(little24(a,b,c),U32.shln(d,24n))
def big32(a: U32,b: U32,c: U32,d: U32) -> U32: little32(d,c,b,a)
def pngHeader(bytes: List<&2,U32>) -> Result<&2,&2,Error,ImageDimensions>:
  match bytes:
    case 137 <> 80 <> 78 <> 71 <> 13 <> 10 <> 26 <> 10 <> 0 <> 0 <> 0 <> 13 <> 73 <> 72 <> 68 <> 82 <> a <> b <> c <> d <> e <> f <> g <> h <> _ <> _ <> _ <> _ <> _ <> _ <> _ <> _ <> _ <> _:
      checkedDimensions("png",big32(a,b,c,d),big32(e,f,g,h))
    case _: Fail{InvalidImage{"png"}}
def gifHeader(bytes: List<&2,U32>) -> Result<&2,&2,Error,ImageDimensions>:
  match bytes:
    case 71 <> 73 <> 70 <> 56 <> +version <> 97 <> a <> b <> c <> d <> _:
      Bool.pick(Result<&2,&2,Error,ImageDimensions>,U32.is_eq(version,55) || U32.is_eq(version,57),checkedDimensions("gif",little16(a,b),little16(c,d)),Fail{InvalidImage{"gif"}})
    case _: Fail{InvalidImage{"gif"}}
def jpegComponentsChecked(valid: Bool,width: U32,height: U32,checked: Result<&2,&2,Jpeg.Error,List<&2,Jpeg.Component>>) -> Result<&2,&2,Error,ImageDimensions>:
  match checked:
    case Fail{_}: Fail{InvalidImage{"jpeg"}}
    case Done{_}: Bool.pick(Result<&2,&2,Error,ImageDimensions>,valid,checkedDimensions("jpeg",width,height),Fail{InvalidImage{"jpeg"}})
def jpegFrame(+marker: U32,bytes: List<&2,U32>) -> Result<&2,&2,Error,ImageDimensions>:
  match bytes:
    case +precision <> a <> b <> c <> d <> +count <> rest:
      jpegComponentsChecked((U32.is_eq(precision,8) || ((U32.is_eq(marker,193) || U32.is_eq(marker,194)) && U32.is_eq(precision,12)) || (U32.is_eq(marker,195) && U32.is_ge(precision,2) && U32.is_le(precision,16))) && U32.is_gt(count,0),Jpeg.word16(c,d),Jpeg.word16(a,b),Jpeg.frameComponents(U32.to_nat(count),rest,Nil{}))
    case _: Fail{InvalidImage{"jpeg"}}
def jpegSegment(next: List<&2,U32> -> Result<&2,&2,Error,ImageDimensions>,+marker: U32,result: Result<&2,&2,Jpeg.Error,Jpeg.Segment>) -> Result<&2,&2,Error,ImageDimensions>:
  match result:
    case Fail{_}: Fail{InvalidImage{"jpeg"}}
    case Done{Jpeg.Segment{data,rest}}:
      Bool.pick(Unit -> Result<&2,&2,Error,ImageDimensions>,U32.is_ge(marker,192) && U32.is_le(marker,195),_ => jpegFrame(marker,data),_ => next(rest))(Unit{})
# Each segment consumes its marker and length-prefixed payload; fill FF bytes
# also advance. SOS/EOI before a frame cannot provide dimensions.
@unsafe def jpegMarkers(bytes: List<&2,U32>) -> Result<&2,&2,Error,ImageDimensions>:
  match bytes:
    case 255 <> 255 <> rest: jpegMarkers(255 <> rest)
    case 255 <> 1 <> rest: jpegMarkers(rest)
    case 255 <> +marker <> rest:
      Bool.pick(Unit -> Result<&2,&2,Error,ImageDimensions>,U32.is_ge(marker,192) && U32.is_le(marker,254) && Bool.not(U32.is_ge(marker,208) && U32.is_le(marker,218)),_ =>
        jpegSegment(pending => jpegMarkers(pending),marker,Jpeg.segment(rest)),_ => Fail{InvalidImage{"jpeg"}})(Unit{})
    case _: Fail{InvalidImage{"jpeg"}}
def jpegHeader(bytes: List<&2,U32>) -> Result<&2,&2,Error,ImageDimensions>:
  match bytes:
    case 255 <> 216 <> rest: jpegMarkers(rest)
    case _: Fail{InvalidImage{"jpeg"}}
def webpPayload(kind: List<&2,U32>,bytes: List<&2,U32>) -> Result<&2,&2,Error,ImageDimensions>:
  match kind bytes:
    case [86,80,56,88] flags <> 0 <> 0 <> 0 <> a <> b <> c <> d <> e <> f <> _:
      Bool.pick(Result<&2,&2,Error,ImageDimensions>,U32.is_eq(U32.and(flags,193),0),checkedDimensions("webp",(little24(a,b,c)+1:U32),(little24(d,e,f)+1:U32)),Fail{InvalidImage{"webp"}})
    case [86,80,56,76] 47 <> a <> b <> c <> +d <> _:
      +bits = little32(a,b,c,d)
      Bool.pick(Result<&2,&2,Error,ImageDimensions>,U32.is_eq(U32.and(d,224),0),checkedDimensions("webp",(U32.and(bits,16383)+1:U32),(U32.and(U32.shrn(bits,14n),16383)+1:U32)),Fail{InvalidImage{"webp"}})
    case [86,80,56,32] +frame <> _ <> _ <> 157 <> 1 <> 42 <> a <> b <> c <> d <> _:
      Bool.pick(Result<&2,&2,Error,ImageDimensions>,U32.is_eq(U32.and(frame,1),0),checkedDimensions("webp",U32.and(little16(a,b),16383),U32.and(little16(c,d),16383)),Fail{InvalidImage{"webp"}})
    case _ _: Fail{InvalidImage{"webp"}}
def webpHeader(bytes: List<&2,U32>) -> Result<&2,&2,Error,ImageDimensions>:
  match bytes:
    case 82 <> 73 <> 70 <> 70 <> a <> b <> c <> d <> 87 <> 69 <> 66 <> 80 <> k0 <> k1 <> k2 <> k3 <> e <> f <> g <> h <> +rest:
      +size = U32.to_nat(little32(e,f,g,h))
      Bool.pick(Unit -> Result<&2,&2,Error,ImageDimensions>,Nat.is_ge(U32.to_nat(little32(a,b,c,d)),12n+size) && Nat.is_ge(byteCount(rest,0n),size),_ => webpPayload([k0,k1,k2,k3],List.take(&2,U32,rest,size)),_ => Fail{InvalidImage{"webp"}})(Unit{})
    case _: Fail{InvalidImage{"webp"}}
def decodedDimensions(result: Result<&2,&2,Base64.Error,List<&2,U32>>,mime: String) -> Result<&2,&2,Error,ImageDimensions>:
  match result mime:
    case Fail{cause} _: Fail{InvalidBase64{cause}}
    case Done{bytes} "image/png": pngHeader(bytes)
    case Done{bytes} "image/jpeg": jpegHeader(bytes)
    case Done{bytes} "image/gif": gifHeader(bytes)
    case Done{bytes} "image/webp": webpHeader(bytes)
    case Done{_} other: Fail{UnsupportedFormat{other}}
def getImageDimensions(data: String,mimeType: String) -> Result<&2,&2,Error,ImageDimensions>: decodedDimensions(Base64.decode(data),mimeType)
def getPngDimensions(data: String) -> Result<&2,&2,Error,ImageDimensions>: getImageDimensions(data,"image/png")
def getJpegDimensions(data: String) -> Result<&2,&2,Error,ImageDimensions>: getImageDimensions(data,"image/jpeg")
def getGifDimensions(data: String) -> Result<&2,&2,Error,ImageDimensions>: getImageDimensions(data,"image/gif")
def getWebpDimensions(data: String) -> Result<&2,&2,Error,ImageDimensions>: getImageDimensions(data,"image/webp")

def registerRendered(state: State,id: Maybe<&2,U32>,dimensions: ImageDimensions,size: ImageCellSize) -> Result<&2,&2,Error,State>:
  match id dimensions size:
    case None{} _ _: Done{state}
    case Some{id} ImageDimensions{width,height} ImageCellSize{columns,rows}: registerKittyImageMetadata(state,KittyImageMetadata{id,columns,rows,width,height})
def kittyEncoded(encoded: Result<&2,&2,Error,String>,+size: ImageCellSize,state: State,dimensions: ImageDimensions,+id: Maybe<&2,U32>) -> Result<&2,&2,Error,Rendered>:
  match encoded size:
    case Fail{error} _: Fail{error}
    case Done{sequence} ImageCellSize{columns,rows}: Result.map(&2,&2,Error,State,Rendered,next => Rendered{next,Some{RenderResult{sequence,columns,rows,id}}},registerRendered(state,id,dimensions,size))
def renderedKitty(state: State,data: String,dimensions: ImageDimensions,+size: ImageCellSize,+id: Maybe<&2,U32>,move: Bool) -> Result<&2,&2,Error,Rendered>:
  match size:
    case ImageCellSize{+columns,+rows}:
      kittyEncoded(encodeKitty(data,KittyOptions{Some{columns},Some{rows},id,move}),size,state,dimensions,id)
def renderSized(size: Result<&2,&2,Error,ImageCellSize>,protocol: ImageProtocol,options: ImageRenderOptions,state: State,data: String,dimensions: ImageDimensions) -> Result<&2,&2,Error,Rendered>:
  match size protocol options:
    case Fail{error} _ _: Fail{error}
    case Done{size} Kitty{} ImageRenderOptions{_,_,_,id,move}: renderedKitty(state,data,dimensions,size,id,move)
    case Done{ImageCellSize{+columns,+rows}} ITerm2{} ImageRenderOptions{_,_,aspect,_,_}:
      Result.map(&2,&2,Error,String,Rendered,sequence => Rendered{state,Some{RenderResult{sequence,columns,rows,None{}}}},encodeITerm2(data,ITerm2Options{Some{Cells{columns}},Some{Auto{}},None{},aspect,True{}}))
    case _ NoImages{} _: Done{Rendered{state,None{}}}
def widthOrDefault(width: Maybe<&2,F64>) -> F64:
  match width:
    case None{}: Number.fromU32(80)
    case Some{value}: value
def renderDetected(detected: State & TerminalCapabilities,data: String,+dimensions: ImageDimensions,+options: ImageRenderOptions) -> Result<&2,&2,Error,Rendered>:
  match detected options:
    case (state,TerminalCapabilities{NoImages{},_,_}) _: Done{Rendered{state,None{}}}
    case (+state,TerminalCapabilities{protocol,_,_}) ImageRenderOptions{width,height,_,_,_}:
      renderSized(calculateImageCellSize(dimensions,widthOrDefault(width),height,getCellDimensions(state)),protocol,options,state,data,dimensions)
def renderImage(state: State,environment: Environment,tmuxHyperlinks: Bool,data: String,dimensions: ImageDimensions,options: ImageRenderOptions) -> Result<&2,&2,Error,Rendered>:
  renderDetected(getCapabilities(state,environment,tmuxHyperlinks),data,dimensions,options)
def allocateImageId() -> IO(Result<&2,&2,Random.Error,U32>):
  do IO<Result<&2,&2,Random.Error,U32>>:
    result : Result<&2,&2,Random.Error,Nat> <- Random.randomIndex(4294967294n)
    return Result.map(&2,&2,Random.Error,Nat,U32,n => U32.from_nat(n+1n),result)

def controlFree(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{Chr{+code},rest}: Bool.pick(Unit -> Bool,U32.is_lt(code,32) || (U32.is_ge(code,127) && U32.is_le(code,159)),_ => False{},_ => controlFree(rest))(Unit{})
def hyperlink(text: String,+url: String) -> Result<&2,&2,Error,String>:
  Bool.pick(Result<&2,&2,Error,String>,controlFree(url),Done{"\u{1b}]8;;" ++ url ++ "\u{1b}\\" ++ text ++ "\u{1b}]8;;\u{1b}\\"},Fail{InvalidControl{}})
def fileUrlBytes(bytes: List<&2,U32>,reversed: String) -> String:
  match bytes:
    case Nil{}: String.reverse(reversed)
    case +byte <> rest: fileUrlBytes(rest,Url.emit(False{},Url.includes(Url.Path{},byte) || U32.is_eq(byte,37) || U32.is_eq(byte,91) || U32.is_eq(byte,92) || U32.is_eq(byte,93) || U32.is_eq(byte,124) || U32.is_eq(byte,126),byte,reversed))
def fileUrl(filename: String) -> String: "file://" ++ fileUrlBytes(Utf8.encode(Paths.normalize(filename)),"")
def stripPrefix(prefix: String,text: String) -> String:
  match prefix text:
    case SNil{} text: text
    case SCon{_,rest} SCon{_,pending}: stripPrefix(rest,pending)
    case _ SNil{}: ""
def shortenImagePath(+filename: String,+home: String) -> String:
  Bool.pick(Unit -> String,Bool.not(String.is_empty(home)) && (Strings.equal(filename,home) || String.starts_with(filename,home ++ "/") || String.starts_with(filename,home ++ "\\")),_ => "~" ++ stripPrefix(home,filename),_ => filename)(Unit{})
def fallbackFilename(filename: Maybe<&2,String>,home: String,links: Bool) -> Result<&2,&2,Error,String>:
  match filename:
    case None{}: Done{""}
    case Some{SNil{}}: Done{""}
    case Some{+filename}:
      +display = shortenImagePath(filename,home)
      Bool.pick(Unit -> Result<&2,&2,Error,String>,links && Paths.isAbsolute(filename),_ => Result.map(&2,&2,Error,String,String,text => text ++ " ",hyperlink(display,fileUrl(filename))),_ => Done{display ++ " "})(Unit{})
def fallbackDimensions(value: Maybe<&2,ImageDimensions>) -> String:
  match value:
    case None{}: ""
    case Some{ImageDimensions{width,height}}: " " ++ U32.show(width) ++ "x" ++ U32.show(height)
def imageFallback(mimeType: String,dimensions: Maybe<&2,ImageDimensions>,filename: Maybe<&2,String>,home: String,capabilities: TerminalCapabilities) -> Result<&2,&2,Error,String>:
  match capabilities:
    case TerminalCapabilities{_,_,links}: Result.map(&2,&2,Error,String,String,name => "[Image: " ++ name ++ "[" ++ mimeType ++ "]" ++ fallbackDimensions(dimensions) ++ "]",fallbackFilename(filename,home,links))

# The probe mirrors execSync's bounded stdout capture and 250ms deadline. The
# shared runner owns cancellation and drains stderr without delivering it here.
type ProbeOutput is Data: ProbeOutput{chunks: List<&2,List<&2,U32>>,length: Nat}
def captureProbe(+bytes: List<&2,U32>,state: ProbeOutput) -> ProbeOutput & Result<&2,&2,String,Unit>:
  match state:
    case ProbeOutput{+chunks,+length}:
      +size = length + byteCount(bytes,0n)
      Bool.pick(ProbeOutput & Result<&2,&2,String,Unit>,Nat.is_le(size,1048576n),(ProbeOutput{bytes <> chunks,size},Done{Unit{}}),(ProbeOutput{chunks,length},Fail{"tmux probe exceeded stdout limit"}))
def collectProbe(state: Ref.Ref<ProbeOutput>,bytes: List<&2,U32>) -> IO(Result<&2,&2,String,Unit>):
  Ref.modify(ProbeOutput,Result<&2,&2,String,Unit>,state,value => captureProbe(bytes,value))
def feature(items: List<&2,String>) -> Bool:
  match items:
    case Nil{}: False{}
    case value <> rest: Bool.pick(Unit -> Bool,Strings.equal(Text.trim(value),"hyperlinks"),_ => True{},_ => feature(rest))(Unit{})
def probeText(result: Result<&2,&2,Utf8.Error,String>) -> Bool:
  match result:
    case Fail{_}: False{}
    case Done{text}: feature(Strings.split(text,','))
def probeResult(result: Result<&2,&2,Child.ExecutionError,U32>,output: ProbeOutput) -> Bool:
  match result output:
    case Done{0} ProbeOutput{chunks,_}: probeText(Utf8.decodeStrict(List.concat(&2,U32,List.reverse(&2,List<&2,U32>,chunks))))
    case _ _: False{}
def probeTmuxHyperlinks(cwd: String,env: List<String>) -> IO(Bool):
  do IO<Bool>:
    +state : Ref.Ref<ProbeOutput> <- Ref.new(ProbeOutput,ProbeOutput{Nil{},0n})
    +callback : Callback.Callback<List<&2,U32>,Result<&2,&2,String,Unit>> <- Callback.create(~Ref.Ref<ProbeOutput>,~List<&2,U32>,~Result<&2,&2,String,Unit>,~collectProbe,state)
    result : Result<&2,&2,Child.ExecutionError,U32> <- Child.executeSelected(Child.Stdout{},"/bin/sh",["-c"],"tmux display-message -p '#{client_termfeatures}'",cwd,env,None{},Some{Number.divide(Number.fromU32(1),Number.fromU32(4))},callback)
    Callback.dispose(List<&2,U32>,Result<&2,&2,String,Unit>,callback)
    output : ProbeOutput <- Ref.dispose(ProbeOutput,state)
    return probeResult(result,output)
def getCapabilitiesWithProbe(+state: State,+environment: Environment,cwd: String,env: List<String>) -> IO(State & TerminalCapabilities):
  Bool.pick(Unit -> IO(State & TerminalCapabilities),needsTmuxProbe(state,environment),_ =>
    do IO<State & TerminalCapabilities>:
      hyperlinks : Bool <- probeTmuxHyperlinks(cwd,env)
      return getCapabilities(state,environment,hyperlinks),_ => IO.pure(State & TerminalCapabilities,getCapabilities(state,environment,False{})))(Unit{})
