import Base
import ./clipboard-command.bend as Cmd
import ./image-convert.bend as Convert
import ../core/tools/output-accumulator.bend as Temp
import ../../../ai/src/utils/uuid.bend as Uuid
import ../../../runtime/src/filesystem.bend as FS
import ../../../runtime/src/utf8.bend as Utf8
import ../../../runtime/src/text.bend as Text
import ../../../runtime/src/callback.bend as Callback

# pi-mono packages/coding-agent/src/utils/clipboard-image.ts: the image on the
# system clipboard, read with wl-paste (Wayland, WSL), xclip (X11), on WSL
# PowerShell for Windows screenshots, and last the native clipboard helper
# (upstream @earendil-works/pi-tui getNativeClipboard). The helper is a Node
# addon upstream; the native binary has none (upstream's "no native helper"
# case), so `nativeClipboard` is None in `processDependencies` and tests
# supply one. Upstream's environment option, clipboard command module and
# native helper are the injectable Dependencies here.
type ClipboardImage is Data: ClipboardImage{bytes: List<&2,U32>,mimeType: String}
# Upstream's undefined (the backend failed), null (no image), an image, and
# a native transfer error (which upstream throws).
type Probe is Data: Failed{} Empty{} Found{image: ClipboardImage} Broken{message: String}
# NativeClipboard.getImage: bytes, null, undefined, or a thrown error.
type NativeImage is Data: NativeBytes{bytes: List<&2,U32>} NativeNone{} NativeUnavailable{} NativeFailed{message: String}
type NativeClipboard is Data: NativeClipboard{getImage: Callback.Callback<Unit,NativeImage>}
type ClipboardCommand is Type: ClipboardCommand{name: String,args: List<String>,options: Cmd.Options}
type Dependencies is Data:
  Dependencies{env: Callback.Callback<String,Maybe<&2,String>>,run: Callback.Callback<ClipboardCommand,Maybe<&2,List<&2,U32>>>,nativeClipboard: Maybe<&2,NativeClipboard>}

def SUPPORTED_IMAGE_MIME_TYPES() -> List<&2,String>: ["image/png","image/jpeg","image/webp","image/gif"]
def DEFAULT_LIST_TIMEOUT_MS() -> U32: 1000
def DEFAULT_POWERSHELL_TIMEOUT_MS() -> U32: 5000

def envOf(+deps: Dependencies,name: String) -> IO(Maybe<&2,String>):
  match deps: case Dependencies{env,_,_}: Callback.call(String,Maybe<&2,String>,env,name)
def runOf(+deps: Dependencies,+name: String,args: List<String>,options: Cmd.Options) -> IO(Maybe<&2,List<&2,U32>>):
  match deps: case Dependencies{_,run,_}: Callback.call(ClipboardCommand,Maybe<&2,List<&2,U32>>,run,ClipboardCommand{name,args,options})
def present(value: Maybe<&2,String>) -> Bool:
  match value:
    case Some{text}: Bool.not(String.is_empty(text))
    case None{}: False{}

# upstream isWaylandSession(env)
def isWaylandSession(+deps: Dependencies) -> IO(Bool):
  do IO<Bool>:
    display : Maybe<&2,String> <- envOf(deps,"WAYLAND_DISPLAY")
    session : Maybe<&2,String> <- envOf(deps,"XDG_SESSION_TYPE")
    return present(display) || String.eq(Maybe.default(&2,String,session,""),"wayland")

def firstPart(parts: List<&2,String>,fallback: String) -> String:
  match parts:
    case first <> _: first
    case Nil{}: fallback
def baseMimeType(+mimeType: String) -> String:
  String.to_lower(Text.trim(firstPart(String.split(mimeType,';'),mimeType)))

def extensionOfBase(base: String) -> Maybe<&2,String>:
  match base:
    case "image/png": Some{"png"}
    case "image/jpeg": Some{"jpg"}
    case "image/webp": Some{"webp"}
    case "image/gif": Some{"gif"}
    case _: None{}
def extensionForImageMimeType(mimeType: String) -> Maybe<&2,String>: extensionOfBase(baseMimeType(mimeType))

def withBase(+types: List<&2,String>,+base: String) -> Maybe<&2,String>:
  match types:
    case Nil{}: None{}
    case +raw <> rest: Bool.pick(Maybe<&2,String>,String.eq(baseMimeType(raw),base),Some{raw},withBase(rest,base))
def preferredOf(+types: List<&2,String>,preferred: List<&2,String>) -> Maybe<&2,String>:
  match preferred:
    case Nil{}: None{}
    case +base <> rest: Maybe.or(&2,String,withBase(types,base),preferredOf(types,rest))
def anyImage(types: List<&2,String>) -> Maybe<&2,String>:
  match types:
    case Nil{}: None{}
    case +raw <> rest: Bool.pick(Maybe<&2,String>,String.starts_with(baseMimeType(raw),"image/"),Some{raw},anyImage(rest))
def keptIf(empty: Bool,t: String,rest: List<&2,String>) -> List<&2,String>:
  match empty:
    case True{}: rest
    case False{}: t <> rest
def kept(+t: String,rest: List<&2,String>) -> List<&2,String>: keptIf(String.is_empty(t),t,rest)
def cleaned(types: List<&2,String>) -> List<&2,String>:
  match types:
    case Nil{}: Nil{}
    case t <> rest: kept(Text.trim(t),cleaned(rest))
def selectPreferredImageMimeType(+types: List<&2,String>) -> Maybe<&2,String>:
  +normalized = cleaned(types)
  Maybe.or(&2,String,preferredOf(normalized,SUPPORTED_IMAGE_MIME_TYPES()),anyImage(normalized))
def isSupportedImageMimeType(mimeType: String) -> Bool:
  Maybe.is_some(&2,String,withBase(SUPPORTED_IMAGE_MIME_TYPES(),baseMimeType(mimeType)))

# Lines of a command's output (upstream split(/\r?\n/), trimmed, nonempty).
def outputLines(bytes: List<&2,U32>) -> List<&2,String>:
  cleaned(String.split(Utf8.decodeBuffer(bytes),'\n'))

def fetched(+mimeType: String,data: Maybe<&2,List<&2,U32>>) -> Probe:
  match data:
    case None{}: Failed{}
    case Some{Nil{}}: Empty{}
    case Some{bytes}: Found{ClipboardImage{bytes,baseMimeType(mimeType)}}
def wlPasteSelected(+deps: Dependencies,selected: Maybe<&2,String>) -> IO(Probe):
  match selected:
    case None{}: IO.pure(Probe,Empty{})
    case Some{+mimeType}:
      do IO<Probe>:
        data : Maybe<&2,List<&2,U32>> <- runOf(deps,"wl-paste",["--type",mimeType,"--no-newline"],Cmd.options())
        return fetched(mimeType,data)
def wlPasteListed(+deps: Dependencies,list: Maybe<&2,List<&2,U32>>) -> IO(Probe):
  match list:
    case None{}: IO.pure(Probe,Failed{})
    case Some{bytes}: wlPasteSelected(deps,selectPreferredImageMimeType(outputLines(bytes)))
# An empty Wayland clipboard must not fall through to stale X11 contents.
def readClipboardImageViaWlPaste(+deps: Dependencies) -> IO(Probe):
  do IO<Probe>:
    list : Maybe<&2,List<&2,U32>> <- runOf(deps,"wl-paste",["--list-types"],Cmd.withTimeout(DEFAULT_LIST_TIMEOUT_MS()))
    wlPasteListed(deps,list)

def imageOf(+mimeType: String,data: Maybe<&2,List<&2,U32>>) -> Maybe<&2,ClipboardImage>:
  match data:
    case Some{b <> bs}: Some{ClipboardImage{b <> bs,baseMimeType(mimeType)}}
    case _: None{}
def foundOr(hit: Maybe<&2,ClipboardImage>,fallback: Probe) -> Probe:
  match hit:
    case Some{image}: Found{image}
    case None{}: fallback
def xclipTried(+deps: Dependencies,types: List<&2,String>) -> IO(Probe):
  match types:
    case Nil{}: IO.pure(Probe,Failed{})
    case +mimeType <> rest:
      do IO<Probe>:
        data : Maybe<&2,List<&2,U32>> <- runOf(deps,"xclip",["-selection","clipboard","-t",mimeType,"-o"],Cmd.options())
        +hit : Maybe<&2,ClipboardImage> <- IO.pure(Maybe<&2,ClipboardImage>,imageOf(mimeType,data))
        Bool.pick(Unit -> IO(Probe),Maybe.is_some(&2,ClipboardImage,hit),_ => IO.pure(Probe,foundOr(hit,Failed{})),_ => xclipTried(deps,rest))(Unit{})
def listed(+t: String,seen: List<&2,String>) -> Bool:
  match seen:
    case Nil{}: False{}
    case s <> rest: String.eq(s,t) || listed(t,rest)
def addIfNew(known: Bool,t: String,seen: List<&2,String>) -> List<&2,String>:
  match known:
    case True{}: seen
    case False{}: t <> seen
def uniqueTypes(types: List<&2,String>,+seen: List<&2,String>) -> List<&2,String>:
  match types:
    case Nil{}: List.reverse(&2,String,seen)
    case +t <> rest: uniqueTypes(rest,addIfNew(listed(t,seen),t,seen))
def xclipCandidates(+deps: Dependencies,+listing: Bool,preferred: Maybe<&2,String>) -> IO(Probe):
  match preferred:
    case None{}: Bool.pick(Unit -> IO(Probe),listing,_ => IO.pure(Probe,Empty{}),_ => xclipTried(deps,SUPPORTED_IMAGE_MIME_TYPES()))(Unit{})
    case Some{choice}: xclipTried(deps,uniqueTypes(choice <> SUPPORTED_IMAGE_MIME_TYPES(),Nil{}))
def xclipListed(+deps: Dependencies,targets: Maybe<&2,List<&2,U32>>) -> IO(Probe):
  match targets:
    case None{}: xclipCandidates(deps,False{},None{})
    case Some{bytes}: xclipCandidates(deps,True{},selectPreferredImageMimeType(outputLines(bytes)))
def readClipboardImageViaXclip(+deps: Dependencies) -> IO(Probe):
  do IO<Probe>:
    targets : Maybe<&2,List<&2,U32>> <- runOf(deps,"xclip",["-selection","clipboard","-t","TARGETS","-o"],Cmd.withTimeout(DEFAULT_LIST_TIMEOUT_MS()))
    xclipListed(deps,targets)

# WSL: the Linux clipboard does not receive Windows screenshots
# (Win+Shift+S); PowerShell saves the Windows clipboard image to a file.
def powerShellScript(winPath: String) -> String:
  String.join(["Add-Type -AssemblyName System.Windows.Forms","Add-Type -AssemblyName System.Drawing","$path = '" ++ String.join(String.split(winPath,Char.from_u32(39)),"''") ++ "'","$img = [System.Windows.Forms.Clipboard]::GetImage()","if ($img) { $img.Save($path, [System.Drawing.Imaging.ImageFormat]::Png); Write-Output 'ok' } else { Write-Output 'empty' }"],"; ")
def savedImage(read: Result<&2,&2,FS.Error,List<&2,U32>>) -> Maybe<&2,ClipboardImage>:
  match read:
    case Done{b <> bs}: Some{ClipboardImage{b <> bs,"image/png"}}
    case _: None{}
def powerShellSaved(ok: Bool,+tmpFile: String) -> IO(Maybe<&2,ClipboardImage>):
  match ok:
    case True{}:
      do IO<Maybe<&2,ClipboardImage>>:
        read : Result<&2,&2,FS.Error,List<&2,U32>> <- FS.readFile(tmpFile)
        return savedImage(read)
    case False{}: IO.pure(Maybe<&2,ClipboardImage>,None{})
def saidOk(result: Maybe<&2,List<&2,U32>>) -> Bool:
  match result:
    case Some{bytes}: String.eq(Text.trim(Utf8.decodeBuffer(bytes)),"ok")
    case None{}: False{}
def windowsPath(result: Maybe<&2,List<&2,U32>>) -> String:
  match result:
    case Some{bytes}: Text.trim(Utf8.decodeBuffer(bytes))
    case None{}: ""
def powerShellAt(+deps: Dependencies,+winPath: String,+tmpFile: String) -> IO(Maybe<&2,ClipboardImage>):
  Bool.pick(Unit -> IO(Maybe<&2,ClipboardImage>),String.is_empty(winPath),_ => IO.pure(Maybe<&2,ClipboardImage>,None{}),
    _ => do IO<Maybe<&2,ClipboardImage>>:
      result : Maybe<&2,List<&2,U32>> <- runOf(deps,"powershell.exe",["-NoProfile","-Command",powerShellScript(winPath)],Cmd.withTimeout(DEFAULT_POWERSHELL_TIMEOUT_MS()))
      powerShellSaved(saidOk(result),tmpFile))(Unit{})
def powerShellNamed(+deps: Dependencies,name: Result<&2,&2,Uuid.Error,String>) -> IO(Maybe<&2,ClipboardImage>):
  match name:
    case Fail{_}: IO.pure(Maybe<&2,ClipboardImage>,None{})
    case Done{id}:
      do IO<Maybe<&2,ClipboardImage>>:
        directory : String <- Temp.tempDirectory(["TMPDIR","TMP","TEMP"],None{})
        +tmpFile : String <- IO.pure(String,FS.child(directory,"pi-wsl-clip-" ++ id ++ ".png"))
        converted : Maybe<&2,List<&2,U32>> <- runOf(deps,"wslpath",["-w",tmpFile],Cmd.withTimeout(DEFAULT_LIST_TIMEOUT_MS()))
        image : Maybe<&2,ClipboardImage> <- powerShellAt(deps,windowsPath(converted),tmpFile)
        removed : Result<&1,&1,U32 & String,Unit> <- File.unlink(tmpFile)
        return image
def readClipboardImageViaPowerShell(+deps: Dependencies) -> IO(Maybe<&2,ClipboardImage>):
  do IO<Maybe<&2,ClipboardImage>>:
    name : Result<&2,&2,Uuid.Error,String> <- Uuid.randomUUID()
    powerShellNamed(deps,name)

# upstream isWSL(env): interop variables, or /proc/version naming Microsoft
# or WSL.
def mentionsWsl(read: Result<&2,&2,FS.Error,List<&2,U32>>) -> Bool:
  match read:
    case Done{bytes}:
      +release = String.to_lower(Utf8.decodeBuffer(bytes))
      String.contains(release,"microsoft") || String.contains(release,"wsl")
    case Fail{_}: False{}
def isWSL(+deps: Dependencies) -> IO(Bool):
  do IO<Bool>:
    distro : Maybe<&2,String> <- envOf(deps,"WSL_DISTRO_NAME")
    interop : Maybe<&2,String> <- envOf(deps,"WSLENV")
    Bool.pick(Unit -> IO(Bool),present(distro) || present(interop),_ => IO.pure(Bool,True{}),
      _ => do IO<Bool>:
        read : Result<&2,&2,FS.Error,List<&2,U32>> <- FS.readFile("/proc/version")
        return mentionsWsl(read))(Unit{})

# upstream readClipboardImageViaNativeClipboard: the helper's bytes are
# labelled by their content (detectSupportedImageMimeType).
def detectedMime(+bytes: List<&2,U32>) -> String:
  match bytes:
    case 137 <> 80 <> 78 <> 71 <> _: "image/png"
    case 255 <> 216 <> 255 <> _: "image/jpeg"
    case 71 <> 73 <> 70 <> 56 <> _: "image/gif"
    case 82 <> 73 <> 70 <> 70 <> _ <> _ <> _ <> _ <> 87 <> 69 <> 66 <> 80 <> _: "image/webp"
    case _: "application/octet-stream"
def nativeProbe(value: NativeImage) -> Probe:
  match value:
    case NativeBytes{Nil{}}: Empty{}
    case NativeBytes{+bytes}: Found{ClipboardImage{bytes,detectedMime(bytes)}}
    case NativeNone{}: Empty{}
    case NativeUnavailable{}: Failed{}
    case NativeFailed{message}: Broken{message}
def readClipboardImageViaNativeClipboard(+deps: Dependencies) -> IO(Probe):
  match deps:
    case Dependencies{_,_,None{}}: IO.pure(Probe,Failed{})
    case Dependencies{_,_,Some{NativeClipboard{getImage}}}:
      do IO<Probe>:
        value : NativeImage <- Callback.call(Unit,NativeImage,getImage,Unit{})
        return nativeProbe(value)

def asPng(converted: Maybe<&2,List<&2,U32>>) -> Maybe<&2,ClipboardImage>:
  match converted:
    case Some{png}: Some{ClipboardImage{png,"image/png"}}
    case None{}: None{}
def keptImage(ok: Bool,bytes: List<&2,U32>,mimeType: String) -> Maybe<&2,ClipboardImage>:
  match ok:
    case True{}: Some{ClipboardImage{bytes,mimeType}}
    case False{}: asPng(Convert.convertImageBytesToPng(bytes))
# Unsupported formats (e.g. Windows DIB data wrapped as BMP) become PNG.
def supported(probe: Probe) -> Result<&2,&2,String,Maybe<&2,ClipboardImage>>:
  match probe:
    case Found{ClipboardImage{bytes,+mimeType}}: Done{keptImage(isSupportedImageMimeType(mimeType),bytes,mimeType)}
    case Broken{message}: Fail{message}
    case _: Done{None{}}
def present2(probe: Probe) -> Bool:
  match probe:
    case Found{_}: True{}
    case _: False{}
def undecided(probe: Probe) -> Bool:
  match probe:
    case Failed{}: True{}
    case _: False{}
def afterPowerShell(image: Maybe<&2,ClipboardImage>,probe: Probe) -> Probe:
  match image:
    case Some{found}: Found{found}
    case None{}: probe
def orNative(+deps: Dependencies,+probe: Probe) -> IO(Probe):
  Bool.pick(Unit -> IO(Probe),undecided(probe),_ => readClipboardImageViaNativeClipboard(deps),_ => IO.pure(Probe,probe))(Unit{})
# Preserve Linux's empty/unavailable distinction if Windows has no image.
def onWsl(+deps: Dependencies,+wsl: Bool,+probe: Probe) -> IO(Probe):
  Bool.pick(Unit -> IO(Probe),wsl && Bool.not(present2(probe)),
    _ => do IO<Probe>:
      image : Maybe<&2,ClipboardImage> <- readClipboardImageViaPowerShell(deps)
      orNative(deps,afterPowerShell(image,probe)),
    _ => orNative(deps,probe))(Unit{})
def afterWayland(+deps: Dependencies,+wsl: Bool,+probe: Probe) -> IO(Probe):
  do IO<Probe>:
    +linux : Probe <- Bool.pick(Unit -> IO(Probe),undecided(probe),_ => readClipboardImageViaXclip(deps),_ => IO.pure(Probe,probe))(Unit{})
    onWsl(deps,wsl,linux)
def onLinux(+deps: Dependencies,+wayland: Bool,+wsl: Bool) -> IO(Probe):
  do IO<Probe>:
    first : Probe <- Bool.pick(Unit -> IO(Probe),wayland || wsl,_ => readClipboardImageViaWlPaste(deps),_ => IO.pure(Probe,Failed{}))(Unit{})
    afterWayland(deps,wsl,first)
def onPlatform(+deps: Dependencies,+platform: String) -> IO(Probe):
  Bool.pick(Unit -> IO(Probe),String.eq(platform,"linux"),
    _ => do IO<Probe>:
      wayland : Bool <- isWaylandSession(deps)
      wsl : Bool <- isWSL(deps)
      onLinux(deps,wayland,wsl),
    _ => readClipboardImageViaNativeClipboard(deps))(Unit{})
def readClipboardImageWith(+deps: Dependencies,+platform: String) -> IO(Result<&2,&2,String,Maybe<&2,ClipboardImage>>):
  do IO<Result<&2,&2,String,Maybe<&2,ClipboardImage>>>:
    termux : Maybe<&2,String> <- envOf(deps,"TERMUX_VERSION")
    probe : Probe <- Bool.pick(Unit -> IO(Probe),present(termux),_ => IO.pure(Probe,Empty{}),_ => onPlatform(deps,platform))(Unit{})
    return supported(probe)

# The process's dependencies: its environment, clipboard commands run in
# `cwd`, and no native helper.
def envValue(value: Result<&1,&1,U32 & String,String>) -> Maybe<&2,String>:
  match value:
    case Done{text}: Some{text}
    case Fail{_}: None{}
def processEnv(_: Unit,name: String) -> IO(Maybe<&2,String>):
  do IO<Maybe<&2,String>>:
    value : Result<&1,&1,U32 & String,String> <- IO.get_env(name)
    return envValue(value)
def processRun(cwd: String,command: ClipboardCommand) -> IO(Maybe<&2,List<&2,U32>>):
  match command:
    case ClipboardCommand{name,args,options}: Cmd.runClipboardCommand(name,args,options,cwd)
def processDependencies(cwd: String) -> IO(Dependencies):
  do IO<Dependencies>:
    env : Callback.Callback<String,Maybe<&2,String>> <- Callback.create(~Unit,~String,~Maybe<&2,String>,~processEnv,Unit{})
    run : Callback.Callback<ClipboardCommand,Maybe<&2,List<&2,U32>>> <- Callback.create(~String,~ClipboardCommand,~Maybe<&2,List<&2,U32>>,~processRun,cwd)
    return Dependencies{env,run,None{}}
def disposeDependencies(+deps: Dependencies) -> IO(Unit):
  match deps:
    case Dependencies{env,run,_}:
      do IO<Unit>:
        Callback.dispose(String,Maybe<&2,String>,env)
        Callback.dispose(ClipboardCommand,Maybe<&2,List<&2,U32>>,run)
def readClipboardImage(+platform: String,cwd: String) -> IO(Result<&2,&2,String,Maybe<&2,ClipboardImage>>):
  do IO<Result<&2,&2,String,Maybe<&2,ClipboardImage>>>:
    +deps : Dependencies <- processDependencies(cwd)
    result : Result<&2,&2,String,Maybe<&2,ClipboardImage>> <- readClipboardImageWith(deps,platform)
    disposeDependencies(deps)
    return result
