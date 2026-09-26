import Base
import ../../src/core/extensions/types.bend as Ext
import ../../src/core/extensions/context.bend as Ctx
import ../../src/core/extensions/loader.bend as Loader
import ../../../ai/src/types.bend as Ai
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/filesystem.bend as FS
import ../../../runtime/src/posix-path.bend as Path
import ../../../runtime/src/text.bend as Text
import ../../../runtime/src/utf8.bend as Utf8

# pi v0.87.1 examples/extensions/git-merge-and-resolve.ts: after each agent
# run, fetch and merge the upstream tracking ref. Clean merges complete
# silently; conflicts (or those of an unfinished merge) are sent to the agent
# as a follow-up listing each conflict block's file, lines and sides.

type ConflictBlock is Data:
  ConflictBlock{file: String, startLine: Nat, separatorLine: Nat, endLine: Nat}

# Lines as node:readline yields them from a UTF-8 stream: "\n", "\r\n" and a
# lone "\r" end a line; a final line terminator adds no empty line.
def crSplit(segments: List<&2, String>) -> List<&2, String>:
  match segments:
    case Nil{}: Nil{}
    case +segment <> rest:
      +line = Bool.pick(String, String.ends_with(segment, "\r"), String.take(segment, Nat.sub(String.length(segment), 1n)), segment)
      List.append(&2, String, String.split(line, '\r'), crSplit(rest))

def withoutFinal(lines: List<&2, String>) -> List<&2, String>:
  match lines:
    case Nil{}: Nil{}
    case "" <> Nil{}: Nil{}
    case line <> rest: line <> withoutFinal(rest)

def readlineLines(text: String) -> List<&2, String>: withoutFinal(crSplit(String.split(text, '\n')))

type Scan is Data:
  Scan{lineNo: Nat, blockStart: Maybe<&2, Nat>, separatorLine: Maybe<&2, Nat>, blocks: List<&2, ConflictBlock>}

type Marker is Data:
  Opening{}
  Separator{}
  Closing{}
  Content{}

def markerOf(+line: String) -> Marker:
  Bool.pick(Marker, String.starts_with(line, "<<<<<<<"), Opening{}, Bool.pick(Marker, String.starts_with(line, "======="), Separator{}, Bool.pick(Marker, String.starts_with(line, ">>>>>>>"), Closing{}, Content{})))

def advanced(+file: String, marker: Marker, +lineNo: Nat, start: Maybe<&2, Nat>, separator: Maybe<&2, Nat>, blocks: List<&2, ConflictBlock>) -> Scan:
  match marker start separator:
    case Opening{} _ _: Scan{lineNo, Some{lineNo}, None{}, blocks}
    case Separator{} Some{opened} _: Scan{lineNo, Some{opened}, Some{lineNo}, blocks}
    case Closing{} Some{opened} Some{middle}: Scan{lineNo, None{}, None{}, ConflictBlock{file, opened, middle, lineNo} <> blocks}
    case _ kept middle: Scan{lineNo, kept, middle, blocks}

def scanned(+file: String, line: String, scan: Scan) -> Scan:
  match scan:
    case Scan{previous, start, separator, blocks}: advanced(file, markerOf(line), Nat.add(previous, 1n), start, separator, blocks)

def scanLines(lines: List<&2, String>, +file: String, scan: Scan) -> Scan:
  match lines:
    case Nil{}: scan
    case line <> rest: scanLines(rest, file, scanned(file, line, scan))

def blocksOf(scan: Scan) -> List<&2, ConflictBlock>:
  match scan:
    case Scan{_, _, _, blocks}: blocks

# A file that cannot be read contributes no blocks.
def fileBlocks(+file: String, read: Result<&2, &2, FS.Error, List<&2, U32>>) -> List<&2, ConflictBlock>:
  match read:
    case Fail{_}: Nil{}
    case Done{bytes}: List.reverse(&2, ConflictBlock, blocksOf(scanLines(readlineLines(Utf8.decodeBuffer(bytes)), file, Scan{0n, None{}, None{}, Nil{}})))

def fileConflicts(files: List<&2, String>, +cwd: String) -> IO(List<&2, ConflictBlock>):
  match files:
    case Nil{}: IO.pure(List<&2, ConflictBlock>, Nil{})
    case +file <> rest:
      do IO<List<&2, ConflictBlock>>:
        read : Result<&2, &2, FS.Error, List<&2, U32>> <- FS.readFile(Path.join(cwd, file))
        others : List<&2, ConflictBlock> <- fileConflicts(rest, cwd)
        return List.append(&2, ConflictBlock, fileBlocks(file, read), others)

def conflictFiles(+cwd: String, result: Loader.ExecResult) -> IO(List<&2, ConflictBlock>):
  match result:
    case Loader.ExecResult{stdout, _, code, _}:
      +names = Text.trim(stdout)
      Bool.pick(Unit -> IO(List<&2, ConflictBlock>), U32.is_eq(code, 0) && Bool.not(String.is_empty(names)),
        _ => fileConflicts(String.split(names, '\n'), cwd),
        _ => IO.pure(List<&2, ConflictBlock>, Nil{}))(Unit{})

# Parse conflict markers from working tree files with unmerged paths.
def findConflicts(+api: Ext.ExtensionAPI, +cwd: String) -> IO(List<&2, ConflictBlock>):
  do IO<List<&2, ConflictBlock>>:
    result : Loader.ExecResult <- Loader.exec(api, "git", ["diff", "--name-only", "--diff-filter=U"], Loader.noExecOptions())
    conflictFiles(cwd, result)

def formatRange(+start: Nat, +end: Nat) -> String:
  Bool.pick(String, Nat.is_gt(start, end), "empty", Bool.pick(String, Nat.is_eq(start, end), Nat.show(start), Nat.show(start) ++ "-" ++ Nat.show(end)))

def blockLine(block: ConflictBlock) -> String:
  match block:
    case ConflictBlock{file, +startLine, +separatorLine, +endLine}:
      +ours = formatRange(Nat.add(startLine, 1n), Nat.sub(separatorLine, 1n))
      +theirs = formatRange(Nat.add(separatorLine, 1n), Nat.sub(endLine, 1n))
      "  " ++ file ++ ":" ++ Nat.show(startLine) ++ "-" ++ Nat.show(endLine) ++ " (ours " ++ ours ++ ", theirs " ++ theirs ++ ")"

def blockLines(blocks: List<&2, ConflictBlock>) -> List<&2, String>:
  match blocks:
    case Nil{}: Nil{}
    case block <> rest: blockLine(block) <> blockLines(rest)

def formatConflicts(+ref: String, blocks: List<&2, ConflictBlock>) -> String:
  String.join(List.append(&2, String, ["Merged " ++ ref ++ " with conflicts:", ""], List.append(&2, String, blockLines(blocks), ["", "Resolve these conflicts."])), "\n")

def Reply() -> Data: Result<&2, &2, String, Maybe<&2, Unit>>

def skip() -> IO(Reply()): IO.pure(Reply(), Done{None{}})

def reported(+api: Ext.ExtensionAPI, +ref: String, blocks: List<&2, ConflictBlock>) -> IO(Reply()):
  match blocks:
    case Nil{}: skip()
    case +found:
      do IO<Reply()>:
        sent : Result<&2, &2, String, Unit> <- Loader.sendUserMessage(api, Ai.UserText{formatConflicts(ref, found)}, Ext.SendUserMessageOptions{Some{Ext.UserFollowUp{}}, None{}})
        return Result.map(&2, &2, String, Unit, Maybe<&2, Unit>, done => None{}, sent)

# Either a merge just left conflicts, or an earlier merge is unfinished.
def resolveConflicts(+api: Ext.ExtensionAPI, +ctx: Ctx.ExtensionContext, +ref: String) -> IO(Reply()):
  do IO<Reply()>:
    conflicts : List<&2, ConflictBlock> <- findConflicts(api, Ctx.cwd(ctx))
    reported(api, ref, conflicts)

def merged(+api: Ext.ExtensionAPI, +ctx: Ctx.ExtensionContext, +ref: String, result: Loader.ExecResult) -> IO(Reply()):
  match result:
    case Loader.ExecResult{_, _, 0, _}: skip()
    case _: resolveConflicts(api, ctx, ref)

def fetched(+api: Ext.ExtensionAPI, +ctx: Ctx.ExtensionContext, +ref: String, result: Loader.ExecResult) -> IO(Reply()):
  match result:
    case Loader.ExecResult{_, _, 0, _}:
      do IO<Reply()>:
        merge : Loader.ExecResult <- Loader.exec(api, "git", ["merge", "--no-ff", ref], Loader.noExecOptions())
        merged(api, ctx, ref, merge)
    case Loader.ExecResult{_, stderr, _, _}:
      do IO<Reply()>:
        Ctx.notify(ctx, "git-merge-and-resolve: fetch failed: " ++ Text.trim(stderr), Ctx.WarningNotice{})
        skip()

def remoteOf(parts: List<&2, String>) -> String:
  match parts:
    case Nil{}: ""
    case first <> _: first

def tracked(+api: Ext.ExtensionAPI, +ctx: Ctx.ExtensionContext, result: Loader.ExecResult) -> IO(Reply()):
  match result:
    case Loader.ExecResult{stdout, _, 0, _}:
      +ref = Text.trim(stdout)
      +remote = remoteOf(String.split(ref, '/'))
      do IO<Reply()>:
        Ctx.notify(ctx, "git-merge-and-resolve: fetching " ++ remote ++ ", merging " ++ ref, Ctx.InfoNotice{})
        fetch : Loader.ExecResult <- Loader.exec(api, "git", ["fetch", remote], Loader.noExecOptions())
        fetched(api, ctx, ref, fetch)
    case _: skip()

# Only attempt a new merge if the working tree is clean.
def statusChecked(+api: Ext.ExtensionAPI, +ctx: Ctx.ExtensionContext, result: Loader.ExecResult) -> IO(Reply()):
  match result:
    case Loader.ExecResult{status, _, _, _}:
      Bool.pick(Unit -> IO(Reply()), String.is_empty(Text.trim(status)),
        _ =>
          do IO<Reply()>:
            upstream : Loader.ExecResult <- Loader.exec(api, "git", ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"], Loader.noExecOptions())
            tracked(api, ctx, upstream),
        _ => skip())(Unit{})

def mergeHeadChecked(+api: Ext.ExtensionAPI, +ctx: Ctx.ExtensionContext, result: Loader.ExecResult) -> IO(Reply()):
  match result:
    case Loader.ExecResult{_, _, 0, _}: resolveConflicts(api, ctx, "MERGE_HEAD")
    case _:
      do IO<Reply()>:
        status : Loader.ExecResult <- Loader.exec(api, "git", ["status", "--porcelain"], Loader.noExecOptions())
        statusChecked(api, ctx, status)

def repositoryChecked(+api: Ext.ExtensionAPI, +ctx: Ctx.ExtensionContext, result: Loader.ExecResult) -> IO(Reply()):
  match result:
    case Loader.ExecResult{_, _, 0, _}:
      do IO<Reply()>:
        mergeHead : Loader.ExecResult <- Loader.exec(api, "git", ["rev-parse", "MERGE_HEAD"], Loader.noExecOptions())
        mergeHeadChecked(api, ctx, mergeHead)
    case _: skip()

def checked(+api: Ext.ExtensionAPI, ctx: Ctx.ExtensionContext) -> IO(Reply()):
  do IO<Reply()>:
    repository : Loader.ExecResult <- Loader.exec(api, "git", ["rev-parse", "--git-dir"], Loader.noExecOptions())
    repositoryChecked(api, ctx, repository)

def onAgentEnd(api: Ext.ExtensionAPI, call: Ext.HandlerCall<Ext.AgentEndEvent>) -> IO(Reply()):
  match call:
    case Ext.HandlerCall{_, ctx}: checked(api, ctx)

def subscribe(+api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    handler : Ext.ExtensionHandler(Ext.AgentEndEvent, Unit) <- C.create(~Ext.ExtensionAPI, ~Ext.HandlerCall<Ext.AgentEndEvent>, ~Reply(), ~onAgentEnd, api)
    subscribed : Result<&2, &2, String, Loader.Unsubscribe> <- Loader.on(api, Ext.OnAgentEnd{handler})
    return Result.map(&2, &2, String, Loader.Unsubscribe, Unit, done => Unit{}, subscribed)

def gitMergeAndResolve(api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>): subscribe(api)
