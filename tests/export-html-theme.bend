import Base
import ../packages/coding-agent/src/core/export-html/index.bend as Export
import ../packages/coding-agent/src/modes/interactive/theme/theme.bend as Theme
import ../packages/coding-agent/src/modes/interactive/theme/color.bend as Color
import ../packages/coding-agent/src/modes/interactive/theme/theme-controller.bend as Controller
import ../packages/runtime/src/schema-value.bend as Value

def loaded(result: Result<&2,&2,Theme.LoadError,Theme.Theme>) -> IO(Theme.Theme):
  match result:
    case Done{theme}: IO.pure(Theme.Theme,theme)
    case Fail{_}: IO.die(Theme.Theme,1,"theme did not load")
def check(+name: String,condition: Bool) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit),condition,_ => IO.print("ok " ++ name),_ => IO.die(Unit,1,"FAIL " ++ name))(Unit{})
def inspected(+name: String,assets: Export.Assets) -> IO(Unit):
  +html = Export.render(assets,Value.Null{})
  do IO<Unit>:
    check(name ++ " text",String.contains(html,Bool.pick(String,String.eq(name,"light"),"--text: #1f2328;","--text: #d4d4d4;")))
    check(name ++ " background",String.contains(html,Bool.pick(String,String.eq(name,"light"),"--body-bg: #f8f8f8;","--body-bg: #18181e;")))
    check(name ++ " export palette",String.contains(html,Bool.pick(String,String.eq(name,"light"),"--exportInfoBg: #fffae6;","--exportInfoBg: #3c3728;")))
def one(+name: String,+builtinDir: String) -> IO(Unit):
  do IO<Unit>:
    result : Result<&2,&2,Theme.LoadError,Theme.Theme> <- Theme.loadByName(name,builtinDir,"/does-not-exist",Color.TrueColor{})
    theme : Theme.Theme <- loaded(result)
    assets : Export.Assets <- Export.themed(Export.Assets{"{{CSS}}","{{THEME_VARS}} --body-bg: {{BODY_BG}};","","","",""},theme,builtinDir ++ "/" ++ name ++ ".json")
    inspected(name,assets)
def fallback(result: Result<&2,&2,Theme.LoadError,Controller.Loaded>) -> IO(Theme.Theme):
  match result:
    case Done{Controller.Loaded{_,theme,_}}: IO.pure(Theme.Theme,theme)
    case Fail{_}: IO.die(Theme.Theme,1,"fallback theme did not load")
def missing() -> IO(Unit):
  do IO<Unit>:
    chosen : Result<&2,&2,Theme.LoadError,Controller.Loaded> <- Controller.load("missing-theme","packages/coding-agent/src/modes/interactive/theme","/does-not-exist",Color.TrueColor{})
    theme : Theme.Theme <- fallback(chosen)
    assets : Export.Assets <- Export.themed(Export.Assets{"{{CSS}}","{{THEME_VARS}} --body-bg: {{BODY_BG}};","","","",""},theme,"packages/coding-agent/src/modes/interactive/theme/dark.json")
    inspected("fallback",assets)
def main() -> IO(Unit):
  do IO<Unit>:
    one("light","packages/coding-agent/src/modes/interactive/theme")
    one("dark","packages/coding-agent/src/modes/interactive/theme")
    missing()
