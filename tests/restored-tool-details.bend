import Base
import ../packages/coding-agent/src/core/tools/index.bend as Tools
import ../packages/coding-agent/src/core/tools/edit.bend as Edit
import ../packages/coding-agent/src/core/tools/ls.bend as Ls
import ../packages/coding-agent/src/core/tools/grep.bend as Grep
import ../packages/coding-agent/src/core/tools/truncate.bend as Truncate
import ../packages/coding-agent/src/modes/interactive/transcript.bend as Transcript
import ../packages/ai/src/types.bend as Ai

def check(ok: Bool,message: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit,Unit{})
    case False{}: IO.die(Unit,1,message)
def restored(name: String,details: Tools.ToolDetails) -> Tools.ToolDetails:
  Tools.restoreDetails(name,Tools.RawDetails{Tools.detailsValue(details)})
def editTyped(details: Tools.ToolDetails) -> Bool:
  match details:
    case Tools.EditDetails{Edit.EditToolDetails{" 1 alpha\n-2 beta\n+2 gamma","patch",Some{2n}}}: True{}
    case _: False{}
def lsTyped(details: Tools.ToolDetails) -> Bool:
  match details:
    case Tools.LsDetails{Ls.LsToolDetails{Some{Truncate.TruncationResult{_,True{},_,_,_,_,_,_,_,_,maxBytes}},Some{3n}}}: Nat.is_eq(maxBytes,51200n)
    case _: False{}
def grepTyped(details: Tools.ToolDetails) -> Bool:
  match details:
    case Tools.GrepDetails{Grep.GrepToolDetails{None{},Some{5n},Some{True{}}}}: True{}
    case _: False{}
def transcriptEdit(details: Maybe<&2,Tools.ToolDetails>) -> Bool:
  match details:
    case Some{Tools.EditDetails{_}}: True{}
    case _: False{}
def main() -> IO(Unit):
  do IO<Unit>:
    check(editTyped(restored("edit",Tools.EditDetails{Edit.EditToolDetails{" 1 alpha\n-2 beta\n+2 gamma","patch",Some{2n}}})),"edit details were not restored")
    +cut : Truncate.TruncationResult <- IO.pure(Truncate.TruncationResult,Truncate.TruncationResult{"a",True{},Some{Truncate.Bytes{}},12n,42n,3n,8n,False{},False{},2000n,51200n})
    check(lsTyped(restored("ls",Tools.LsDetails{Ls.LsToolDetails{Some{cut},Some{3n}}})),"ls details were not restored")
    check(grepTyped(restored("grep",Tools.GrepDetails{Grep.GrepToolDetails{None{},Some{5n},Some{True{}}}})),"grep details were not restored")
    +saved : Ai.ToolResultMessage<Tools.ToolDetails> <- IO.pure(Ai.ToolResultMessage<Tools.ToolDetails>,Ai.ToolResultMessage{"tool-1","edit",Nil{},Some{Tools.RawDetails{Tools.detailsValue(Tools.EditDetails{Edit.EditToolDetails{"-1 before\n+1 after","patch",Some{1n}}})}},None{},False{},F64{0,0}})
    check(transcriptEdit(Transcript.historicalDetails(saved)),"saved edit details did not reach the transcript as typed data")
    IO.print("saved tool details restore to native types")
