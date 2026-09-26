import Base
import ../src/modes/interactive/clipboard-paste.bend as Paste
import ../src/utils/clipboard-image.bend as Clip
import ../../runtime/src/callback.bend as Callback
import ../../runtime/src/ref.bend as Ref
import ../../runtime/src/filesystem.bend as FS

# pi-mono packages/coding-agent/test/clipboard-image-native-errors.test.ts,
# on upstream's handleClipboardPaste (clipboard-paste.bend), plus two native
# supplements for the paths upstream exercises only interactively: an image
# is inserted by the path of its temp file, and without one the clipboard's
# text is inserted.

def report(+name: String,passed: Bool) -> IO(Unit):
  Bool.pick(IO(Unit),passed,IO.print("PASS " ++ name),IO.print("FAIL " ++ name))
def png() -> List<&2,U32>: [137,80,78,71,13,10,26,10,0,0,0,13,73,72,68,82]

type Seen is Data: Seen{inserted: Ref.Ref<List<&2,String>>,renders: Ref.Ref<Nat>,textReads: Ref.Ref<Nat>,text: Maybe<&2,String>}
def insertCall(seen: Seen,value: String) -> IO(Unit):
  match seen: case Seen{inserted,_,_,_}: Ref.modify(List<&2,String>,Unit,inserted,list => (value <> list,Unit{}))
def renderCall(seen: Seen,_: Unit) -> IO(Unit):
  match seen: case Seen{_,renders,_,_}: Ref.modify(Nat,Unit,renders,n => (n + 1n,Unit{}))
def textCall(seen: Seen,_: Unit) -> IO(Maybe<&2,String>):
  match seen:
    case Seen{_,_,reads,text}:
      do IO<Maybe<&2,String>>:
        Ref.modify(Nat,Unit,reads,n => (n + 1n,Unit{}))
        return text
def noEnv(_: Unit,name: String) -> IO(Maybe<&2,String>): IO.pure(Maybe<&2,String>,None{})
def refuse(_: Unit,command: Clip.ClipboardCommand) -> IO(Maybe<&2,List<&2,U32>>): IO.pure(Maybe<&2,List<&2,U32>>,None{})
def nativeAnswer(answer: Clip.NativeImage,_: Unit) -> IO(Clip.NativeImage): IO.pure(Clip.NativeImage,answer)

type Result3 is Data: Result3{inserted: List<&2,String>,renders: Nat,textReads: Nat}
def pasted(answer: Clip.NativeImage,text: Maybe<&2,String>) -> IO(Result3):
  do IO<Result3>:
    +inserted : Ref.Ref<List<&2,String>> <- Ref.new(List<&2,String>,Nil{})
    +renders : Ref.Ref<Nat> <- Ref.new(Nat,0n)
    +reads : Ref.Ref<Nat> <- Ref.new(Nat,0n)
    +seen : Seen <- IO.pure(Seen,Seen{inserted,renders,reads,text})
    insert : Callback.Callback<String,Unit> <- Callback.create(~Seen,~String,~Unit,~insertCall,seen)
    render : Callback.Callback<Unit,Unit> <- Callback.create(~Seen,~Unit,~Unit,~renderCall,seen)
    readText : Callback.Callback<Unit,Maybe<&2,String>> <- Callback.create(~Seen,~Unit,~Maybe<&2,String>,~textCall,seen)
    env : Callback.Callback<String,Maybe<&2,String>> <- Callback.create(~Unit,~String,~Maybe<&2,String>,~noEnv,Unit{})
    run : Callback.Callback<Clip.ClipboardCommand,Maybe<&2,List<&2,U32>>> <- Callback.create(~Unit,~Clip.ClipboardCommand,~Maybe<&2,List<&2,U32>>,~refuse,Unit{})
    getImage : Callback.Callback<Unit,Clip.NativeImage> <- Callback.create(~Clip.NativeImage,~Unit,~Clip.NativeImage,~nativeAnswer,answer)
    Paste.handleClipboardPaste(Paste.PasteTarget{insert,render,readText},Clip.Dependencies{env,run,Some{Clip.NativeClipboard{getImage}}},"win32")
    list : List<&2,String> <- Ref.read(List<&2,String>,inserted)
    count : Nat <- Ref.read(Nat,renders)
    textCount : Nat <- Ref.read(Nat,reads)
    return Result3{list,count,textCount}

def nothing(result: Result3) -> Bool:
  match result:
    case Result3{Nil{},0n,0n}: True{}
    case _: False{}
def nativeErrors(_: Unit) -> IO(Unit):
  do IO<Unit>:
    result : Result3 <- pasted(Clip.NativeFailed{"Native clipboard operation failed"},Some{"text"})
    report("native image errors abort paste without reading text or changing the editor",nothing(result))
def sameBytes(a: List<&2,U32>,b: List<&2,U32>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case x <> xs y <> ys: U32.is_eq(x,y) && sameBytes(xs,ys)
    case _ _: False{}
def fileHolds(read: Result<&2,&2,FS.Error,List<&2,U32>>) -> Bool:
  match read:
    case Done{bytes}: sameBytes(bytes,png())
    case Fail{_}: False{}
def pathChecked(+path: String,renders: Nat,textReads: Nat) -> IO(Bool):
  do IO<Bool>:
    read : Result<&2,&2,FS.Error,List<&2,U32>> <- FS.readFile(path)
    removed : Result<&1,&1,U32 & String,Unit> <- File.unlink(path)
    return fileHolds(read) && String.contains(path,"/pi-clipboard-") && String.ends_with(path,".png") && Nat.is_eq(renders,1n) && Nat.is_eq(textReads,0n)
def imageInserted(result: Result3) -> IO(Bool):
  match result:
    case Result3{path <> Nil{},renders,textReads}: pathChecked(path,renders,textReads)
    case _: IO.pure(Bool,False{})
def imagePaste(_: Unit) -> IO(Unit):
  do IO<Unit>:
    result : Result3 <- pasted(Clip.NativeBytes{png()},Some{"text"})
    ok : Bool <- imageInserted(result)
    report("native supplement > an image is written to the temp directory and inserted by its path",ok)
def textInserted(result: Result3) -> Bool:
  match result:
    case Result3{text <> Nil{},1n,1n}: String.eq(text,"clipboard text")
    case _: False{}
def textPaste(_: Unit) -> IO(Unit):
  do IO<Unit>:
    result : Result3 <- pasted(Clip.NativeNone{},Some{"clipboard text"})
    report("native supplement > without an image the clipboard's text is inserted",textInserted(result))

def main() -> IO(Unit):
  do IO<Unit>:
    nativeErrors(Unit{})
    imagePaste(Unit{})
    textPaste(Unit{})
