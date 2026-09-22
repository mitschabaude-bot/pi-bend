import Base
import ../utils/paths.bend as Paths
import ../utils/mime.bend as Mime
import ../utils/image-process.bend as Images
import ../../../ai/src/types.bend as Ai
import ../../../runtime/src/filesystem.bend as FS
import ../../../runtime/src/utf8.bend as Utf8
import ../../../runtime/src/u64.bend as Word

type ProcessedFiles is Data:
  ProcessedFiles{text: String,images: List<&2,Ai.ImageContent>}

type ProcessFileOptions is Data:
  ProcessFileOptions{autoResizeImages: Maybe<&2,Bool>}

def defaults() -> ProcessFileOptions: ProcessFileOptions{None{}}

type Error is Data:
  InvalidPath{input: String,cause: Paths.Error}
  NotFound{path: String,cause: FS.Error}
  Stat{path: String,cause: FS.Error}
  Read{path: String,cause: FS.Error}
  InvalidEncoding{path: String,cause: Utf8.Error}

def ResultOf(-A: Data) -> Data: Result<&2,&2,Error,A>
def Processing(-A: Data) -> Type: IO(ResultOf(A))

def Processing.pure(-A: Data,value: A) -> Processing(A): IO.pure(ResultOf(A),Done{value})

def continueWith(-A: Data,-B: Data,next: A -> Processing(B),result: ResultOf(A)) -> Processing(B):
  match result:
    case Fail{cause}: IO.pure(ResultOf(B),Fail{cause})
    case Done{value}: next(value)

def Processing.bind(-A: Data,-B: Data,operation: Processing(A),next: A -> Processing(B)) -> Processing(B):
  do IO<ResultOf(B)>:
    result : ResultOf(A) <- operation
    continueWith(A,B,next,result)

def lift(-A: Data,operation: IO(A)) -> Processing(A):
  do IO<ResultOf(A)>:
    value : A <- operation
    Processing.pure(A,value)

def failure(-A: Data,cause: Error) -> Processing(A): IO.pure(ResultOf(A),Fail{cause})

def pathResult(input: String,result: Result<&2,&2,Paths.Error,String>) -> Processing(String):
  match result:
    case Fail{cause}: failure(String,InvalidPath{input,cause})
    case Done{path}: Processing.pure(String,path)

def resolved(+environment: Paths.Environment,+input: String) -> Processing(String):
  match environment:
    case Paths.Environment{cwd,_,_}:
      do Processing<String>:
        path : String <- pathResult(input,Paths.resolveToCwd(environment,input,cwd))
        lift(String,Paths.resolvedReadPath(environment,path))

def accessible(path: String,result: Result<&1,&1,U32 & String,Unit>) -> ResultOf(Unit):
  match result:
    case Done{Unit{}}: Done{Unit{}}
    case Fail{(code,message)}: Fail{NotFound{path,FS.System{code,message}}}

def access(+path: String) -> Processing(Unit):
  do IO<ResultOf(Unit)>:
    result : Result<&1,&1,U32 & String,Unit> <- File.access(path,0)
    return accessible(path,result)

def statResult(path: String,result: Result<&2,&2,FS.Error,Word.U64>) -> ResultOf(Bool):
  match result:
    case Fail{cause}: Fail{Stat{path,cause}}
    case Done{size}: Done{Word.equal(size,Word.zero())}

def empty(+path: String) -> Processing(Bool):
  do IO<ResultOf(Bool)>:
    result : Result<&2,&2,FS.Error,Word.U64> <- FS.size(path)
    return statResult(path,result)

def readResult(-A: Data,path: String,result: Result<&2,&2,FS.Error,A>) -> ResultOf(A):
  match result:
    case Fail{cause}: Fail{Read{path,cause}}
    case Done{value}: Done{value}

def readFile(+path: String) -> Processing(List<&2,U32>):
  do IO<ResultOf(List<&2,U32>)>:
    result : Result<&2,&2,FS.Error,List<&2,U32>> <- FS.readFile(path)
    return readResult(List<&2,U32>,path,result)

def detect(+path: String) -> Processing(Maybe<&2,String>):
  do IO<ResultOf(Maybe<&2,String>)>:
    result : Result<&2,&2,FS.Error,Maybe<&2,String>> <- Mime.detectSupportedImageMimeTypeFromFile(path)
    return readResult(Maybe<&2,String>,path,result)

type Attachment is Data:
  Attachment{text: String,image: Maybe<&2,Ai.ImageContent>}

def reference(path: String,content: String) -> String: "<file name=\"" ++ path ++ "\">" ++ content ++ "</file>\n"

def imageAttachment(path: String,processed: Images.ProcessImageResult) -> Attachment:
  match processed:
    case Images.Unsupported{message}: Attachment{reference(path,message),None{}}
    case Images.Processed{data,mime,hints}: Attachment{reference(path,String.join(hints,"\n")),Some{Ai.ImageContent{data,mime}}}

def textAttachment(+path: String,result: Result<&2,&2,Utf8.Error,String>) -> Processing(Attachment):
  match result:
    case Fail{cause}: failure(Attachment,InvalidEncoding{path,cause})
    case Done{content}: Processing.pure(Attachment,Attachment{reference(path,"\n" ++ content ++ "\n"),None{}})

def attachment(path: String,bytes: List<&2,U32>,mime: Maybe<&2,String>,options: ProcessFileOptions) -> Processing(Attachment):
  match mime options:
    case None{} _: textAttachment(path,Utf8.decodeWith(Utf8.StripLeading{},bytes))
    case Some{mime} ProcessFileOptions{resize}:
      Processing.pure(Attachment,imageAttachment(path,Images.processImage(bytes,mime,Images.ProcessImageOptions{resize,None{}})))

def processFile(+environment: Paths.Environment,+input: String,options: ProcessFileOptions) -> Processing(Maybe<&2,Attachment>):
  do Processing<Maybe<&2,Attachment>>:
    +absolute : String <- resolved(environment,input)
    access(absolute)
    isEmpty : Bool <- empty(absolute)
    Bool.pick(Unit -> Processing(Maybe<&2,Attachment>),isEmpty,_ => Processing.pure(Maybe<&2,Attachment>,None{}),
      _ => do Processing<Maybe<&2,Attachment>>:
        mime : Maybe<&2,String> <- detect(absolute)
        bytes : List<&2,U32> <- readFile(absolute)
        value : Attachment <- attachment(absolute,bytes,mime,options)
        Processing.pure(Maybe<&2,Attachment>,Some{value}))(Unit{})

type Accumulated is Data:
  Accumulated{text: List<&2,String>,images: List<&2,Ai.ImageContent>}

def accumulated(state: Accumulated,part: Maybe<&2,Attachment>) -> Accumulated:
  match state part:
    case value None{}: value
    case Accumulated{text,images} Some{Attachment{content,None{}}}: Accumulated{content <> text,images}
    case Accumulated{text,images} Some{Attachment{content,Some{image}}}: Accumulated{content <> text,image <> images}

def finished(state: Accumulated) -> ProcessedFiles:
  match state:
    case Accumulated{text,images}: ProcessedFiles{String.join(List.reverse(&2,String,text),""),List.reverse(&2,Ai.ImageContent,images)}

def files(arguments: List<&2,String>,+environment: Paths.Environment,+options: ProcessFileOptions,state: Accumulated) -> Processing(ProcessedFiles):
  match arguments:
    case Nil{}: Processing.pure(ProcessedFiles,finished(state))
    case input <> rest:
      do Processing<ProcessedFiles>:
        part : Maybe<&2,Attachment> <- processFile(environment,input,options)
        files(rest,environment,options,accumulated(state,part))

# Environment lookup is explicit; the CLI owns diagnostics and exit policy.
# Files are processed serially, preserving text references and image order.
def processFileArguments(environment: Paths.Environment,fileArgs: List<&2,String>,options: ProcessFileOptions) -> IO(ResultOf(ProcessedFiles)):
  files(fileArgs,environment,options,Accumulated{Nil{},Nil{}})
