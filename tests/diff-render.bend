import Base
import ../packages/coding-agent/src/modes/interactive/components/diff.bend as Diff
import ../packages/coding-agent/src/modes/interactive/theme/theme.bend as Theme
import ../packages/coding-agent/src/modes/interactive/theme/color.bend as Color
import ../packages/runtime/test/utf8-runner.bend as Wire
import ../packages/runtime/src/record.bend as R

def run(args: List<String>,+theme: Theme.Theme) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit,Unit{})
    case argument <> rest:
      do IO<Unit>:
        result : String <- Diff.renderDiff(Wire.fromScalars(Wire.parseNumbers(argument)),theme)
        IO.print(Wire.showText(result))
        run(rest,theme)
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    theme : Theme.Theme = Theme.create("diff-test",Color.Palette256{},R.Record{R.Property{"toolDiffRemoved",Color.Indexed{1n}} <> R.Property{"toolDiffAdded",Color.Indexed{2n}} <> R.Property{"toolDiffContext",Color.Indexed{8n}} <> Nil{}},R.new(Color.Color))
    run(args,theme)
