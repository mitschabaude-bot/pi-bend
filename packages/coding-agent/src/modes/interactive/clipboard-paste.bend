import Base
import ../../utils/clipboard-image.bend as ClipboardImage
import ../../core/tools/output-accumulator.bend as TempFiles
import ../../../../ai/src/utils/uuid.bend as Uuid
import ../../../../runtime/src/filesystem.bend as Filesystem
import ../../../../runtime/src/callback.bend as Callback

# upstream InteractiveMode.handleClipboardPaste (the pasteImage key, Ctrl+V):
# an image on the clipboard is written to the temp directory as
# pi-clipboard-<uuid>.<ext> and inserted by its path; without one, the
# clipboard's text is inserted. Clipboard errors are ignored as upstream's
# catch does; a native transfer error therefore pastes nothing. The target
# is the editor's insert, the UI's render request and the text reader
# (upstream readClipboardText).
type PasteTarget is Data:
  PasteTarget{insert: Callback.Callback<String,Unit>,requestRender: Callback.Callback<Unit,Unit>,readText: Callback.Callback<Unit,Maybe<&2,String>>}

def closedAfter(pair: File & Result<&1,&1,U32 & String,Unit>) -> IO(Bool):
  match pair:
    case (file,written):
      do IO<Bool>:
        closed : Result<&1,&1,U32 & String,Unit> <- File.close_checked(file)
        return Result.is_done(&1,&1,U32 & String,Unit,written) && Result.is_done(&1,&1,U32 & String,Unit,closed)
def writtenTo(opened: Result<&1,&1,U32 & String,File>,bytes: List<&2,U32>) -> IO(Bool):
  match opened:
    case Fail{_}: IO.pure(Bool,False{})
    case Done{file}:
      do IO<Bool>:
        pair : File & Result<&1,&1,U32 & String,Unit> <- File.write_bytes(file,bytes)
        closedAfter(pair)
def writeBytes(path: String,bytes: List<&2,U32>) -> IO(Bool):
  do IO<Bool>:
    opened : Result<&1,&1,U32 & String,File> <- File.open(path,"w")
    writtenTo(opened,bytes)
def inserted(+target: PasteTarget,text: String) -> IO(Unit):
  match target:
    case PasteTarget{insert,requestRender,_}:
      do IO<Unit>:
        Callback.call(String,Unit,insert,text)
        Callback.call(Unit,Unit,requestRender,Unit{})
def insertIf(+target: PasteTarget,+written: Bool,text: String) -> IO(Unit):
  match written:
    case True{}: inserted(target,text)
    case False{}: IO.pure(Unit,Unit{})
def pastedImageNamed(+target: PasteTarget,image: ClipboardImage.ClipboardImage,name: Result<&2,&2,Uuid.Error,String>) -> IO(Unit):
  match image name:
    case _ Fail{_}: IO.pure(Unit,Unit{})
    case ClipboardImage.ClipboardImage{bytes,mimeType} Done{id}:
      do IO<Unit>:
        directory : String <- TempFiles.tempDirectory(["TMPDIR","TMP","TEMP"],None{})
        +path : String <- IO.pure(String,Filesystem.child(directory,"pi-clipboard-" ++ id ++ "." ++ Maybe.default(&2,String,ClipboardImage.extensionForImageMimeType(mimeType),"png")))
        written : Bool <- writeBytes(path,bytes)
        insertIf(target,written,path)
def pastedText(+target: PasteTarget,text: Maybe<&2,String>) -> IO(Unit):
  match text:
    case Some{SCon{c,rest}}: inserted(target,SCon{c,rest})
    case _: IO.pure(Unit,Unit{})
def readTextOf(target: PasteTarget) -> Callback.Callback<Unit,Maybe<&2,String>>:
  match target: case PasteTarget{_,_,readText}: readText
def pastedFrom(+target: PasteTarget,image: Result<&2,&2,String,Maybe<&2,ClipboardImage.ClipboardImage>>) -> IO(Unit):
  match image:
    case Fail{_}: IO.pure(Unit,Unit{})
    case Done{Some{found}}:
      do IO<Unit>:
        name : Result<&2,&2,Uuid.Error,String> <- Uuid.randomUUID()
        pastedImageNamed(target,found,name)
    case Done{None{}}:
      do IO<Unit>:
        text : Maybe<&2,String> <- Callback.call(Unit,Maybe<&2,String>,readTextOf(target),Unit{})
        pastedText(target,text)
def handleClipboardPaste(+target: PasteTarget,deps: ClipboardImage.Dependencies,+platform: String) -> IO(Unit):
  do IO<Unit>:
    image : Result<&2,&2,String,Maybe<&2,ClipboardImage.ClipboardImage>> <- ClipboardImage.readClipboardImageWith(deps,platform)
    pastedFrom(target,image)
