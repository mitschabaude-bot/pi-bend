import Base
import ../../../../../runtime/src/callback.bend as Callback
import ../../../../../runtime/src/serial-resource.bend as Serial
import ../../../../../tui/src/terminal-colors.bend as TerminalColors
import ../../../../../tui/src/terminal-query.bend as Query
import ../../../../../tui/src/tui-process.bend as Process
import ./color.bend as Color
import ./detection.bend as Detection
import ./theme.bend as Theme

# An explicit name wins over terminal hints. A light/dark pair follows scheme
# notifications; an absent setting uses OSC 11, COLORFGBG, then dark fallback.
type Selection is Data:
  Selection{setting: Maybe<&2,String>,terminalTheme: Detection.TerminalTheme,activeName: String,theme: Theme.Theme,autoSync: Bool,persistSuggested: Bool,loadError: Maybe<&2,Theme.LoadError>}
type Owner is Type:
  Owner{resource: Serial.Owner<Selection>,listenerId: Nat,listener: Callback.Callback<TerminalColors.TerminalColorScheme,Unit>,ready: Process.QueryReady}
type Handle is Data:
  Handle{resource: Serial.Handle<Selection>,ready: Process.QueryReady,env: Maybe<&2,String>,builtinDir: String,customDir: String,mode: Color.Mode}
type Notification is Data:
  Notification{resource: Serial.Handle<Selection>,requestRender: Callback.Callback<Unit,Unit>,builtinDir: String,customDir: String,mode: Color.Mode}
type Loaded is Data:
  Loaded{name: String,theme: Theme.Theme,error: Maybe<&2,Theme.LoadError>}
type Route is Data:
  Explicit{name: String}
  Automatic{pair: Detection.AutoSetting}
  Detect{}

def scheme(value: TerminalColors.TerminalColorScheme) -> Detection.TerminalTheme:
  match value:
    case TerminalColors.Dark{}: Detection.Dark{}
    case TerminalColors.Light{}: Detection.Light{}
def maybeScheme(value: Maybe<&2,TerminalColors.TerminalColorScheme>) -> Maybe<&2,Detection.TerminalTheme>:
  match value:
    case None{}: None{}
    case Some{report}: Some{scheme(report)}
def rgb(value: Maybe<&2,TerminalColors.RgbColor>) -> Maybe<&2,Color.Rgb>:
  match value:
    case None{}: None{}
    case Some{TerminalColors.RgbColor{r,g,b}}: Some{Color.Rgb{U32.to_nat(r),U32.to_nat(g),U32.to_nat(b)}}
def background(ready: Process.QueryReady,env: Maybe<&2,String>) -> IO(Detection.Detection):
  match ready:
    case Process.QueryReady{queries,_,write,_}:
      do IO<Detection.Detection>:
        response : Maybe<&2,TerminalColors.RgbColor> <- Query.colorQuery(queries,write,100)
        return Detection.detectTerminalBackgroundColor(rgb(response),env)
def autoQueries(ready: Process.QueryReady,env: Maybe<&2,String>) -> IO(Detection.TerminalTheme):
  match ready:
    case Process.QueryReady{+queries,_,+write,_}:
      do IO<Detection.TerminalTheme>:
        schemeTask : Chan(Maybe<&2,TerminalColors.TerminalColorScheme>) <- IO.fork(Maybe<&2,TerminalColors.TerminalColorScheme>,Query.schemeQuery(queries,write,100))
        colorTask : Chan(Maybe<&2,TerminalColors.RgbColor>) <- IO.fork(Maybe<&2,TerminalColors.RgbColor>,Query.colorQuery(queries,write,100))
        report : Maybe<&2,TerminalColors.TerminalColorScheme> <- IO.join(Maybe<&2,TerminalColors.TerminalColorScheme>,schemeTask)
        color : Maybe<&2,TerminalColors.RgbColor> <- IO.join(Maybe<&2,TerminalColors.RgbColor>,colorTask)
        return Detection.detectTerminalThemeForAuto(maybeScheme(report),rgb(color),env)
def confident(value: Detection.Detection) -> Bool:
  match value:
    case Detection.Detection{_,_,_,Detection.High{}}: True{}
    case _: False{}
def detectedTheme(value: Detection.Detection) -> Detection.TerminalTheme:
  match value:
    case Detection.Detection{theme,_,_,_}: theme
def themeName(value: Detection.TerminalTheme) -> String:
  match value:
    case Detection.Dark{}: "dark"
    case Detection.Light{}: "light"
def selectedName(setting: Maybe<&2,String>,+terminal: Detection.TerminalTheme) -> String:
  Maybe.default(&2,String,Detection.resolveThemeSetting(setting,terminal),themeName(terminal))
def isAuto(setting: Maybe<&2,String>) -> Bool:
  Bool.not(Maybe.is_none(&2,Detection.AutoSetting,Detection.parseAutoThemeSetting(setting)))
def explicitRoute(setting: Maybe<&2,String>) -> Route:
  match setting:
    case Some{name}: Explicit{name}
    case None{}: Detect{}
def routed(setting: Maybe<&2,String>,parsed: Maybe<&2,Detection.AutoSetting>) -> Route:
  match parsed:
    case Some{pair}: Automatic{pair}
    case None{}: explicitRoute(setting)
def route(+setting: Maybe<&2,String>) -> Route: routed(setting,Detection.parseAutoThemeSetting(setting))
def loadedDark(result: Result<&2,&2,Theme.LoadError,Theme.Theme>,error: Theme.LoadError) -> Result<&2,&2,Theme.LoadError,Loaded>:
  match result:
    case Fail{cause}: Fail{cause}
    case Done{theme}: Done{Loaded{"dark",theme,Some{error}}}
def loadFallback(result: Result<&2,&2,Theme.LoadError,Theme.Theme>,original: String,builtinDir: String,customDir: String,mode: Color.Mode) -> IO(Result<&2,&2,Theme.LoadError,Loaded>):
  match result:
    case Done{theme}: IO.pure(Result<&2,&2,Theme.LoadError,Loaded>,Done{Loaded{original,theme,None{}}})
    case Fail{error}:
      do IO<Result<&2,&2,Theme.LoadError,Loaded>>:
        fallback : Result<&2,&2,Theme.LoadError,Theme.Theme> <- Theme.loadByName("dark",builtinDir,customDir,mode)
        return loadedDark(fallback,error)
def load(+name: String,+builtinDir: String,+customDir: String,+mode: Color.Mode) -> IO(Result<&2,&2,Theme.LoadError,Loaded>):
  do IO<Result<&2,&2,Theme.LoadError,Loaded>>:
    result : Result<&2,&2,Theme.LoadError,Theme.Theme> <- Theme.loadByName(name,builtinDir,customDir,mode)
    loadFallback(result,name,builtinDir,customDir,mode)
def selection(+setting: Maybe<&2,String>,terminal: Detection.TerminalTheme,persist: Bool,loaded: Loaded) -> Selection:
  match loaded:
    case Loaded{name,theme,error}: Selection{setting,terminal,name,theme,isAuto(setting),persist,error}
def selectAuto(ready: Process.QueryReady,+setting: Maybe<&2,String>,env: Maybe<&2,String>,builtinDir: String,customDir: String,mode: Color.Mode) -> IO(Result<&2,&2,Theme.LoadError,Selection>):
  do IO<Result<&2,&2,Theme.LoadError,Selection>>:
    +terminal : Detection.TerminalTheme <- autoQueries(ready,env)
    result : Result<&2,&2,Theme.LoadError,Loaded> <- load(selectedName(setting,terminal),builtinDir,customDir,mode)
    return Result.map(&2,&2,Theme.LoadError,Loaded,Selection,value => selection(setting,terminal,False{},value),result)
def selectExplicit(+setting: Maybe<&2,String>,name: String,env: Maybe<&2,String>,builtinDir: String,customDir: String,mode: Color.Mode) -> IO(Result<&2,&2,Theme.LoadError,Selection>):
  do IO<Result<&2,&2,Theme.LoadError,Selection>>:
    result : Result<&2,&2,Theme.LoadError,Loaded> <- load(name,builtinDir,customDir,mode)
    return Result.map(&2,&2,Theme.LoadError,Loaded,Selection,value => selection(setting,detectedTheme(Detection.detectTerminalBackgroundFromEnv(env)),False{},value),result)
def selectAbsent(ready: Process.QueryReady,env: Maybe<&2,String>,builtinDir: String,customDir: String,mode: Color.Mode) -> IO(Result<&2,&2,Theme.LoadError,Selection>):
  do IO<Result<&2,&2,Theme.LoadError,Selection>>:
    +detected : Detection.Detection <- background(ready,env)
    result : Result<&2,&2,Theme.LoadError,Loaded> <- load(themeName(detectedTheme(detected)),builtinDir,customDir,mode)
    return Result.map(&2,&2,Theme.LoadError,Loaded,Selection,value => selection(None{},detectedTheme(detected),confident(detected),value),result)
def selectRoute(ready: Process.QueryReady,setting: Maybe<&2,String>,env: Maybe<&2,String>,builtinDir: String,customDir: String,mode: Color.Mode,choice: Route) -> IO(Result<&2,&2,Theme.LoadError,Selection>):
  match choice:
    case Automatic{_}: selectAuto(ready,setting,env,builtinDir,customDir,mode)
    case Explicit{name}: selectExplicit(setting,name,env,builtinDir,customDir,mode)
    case Detect{}: selectAbsent(ready,env,builtinDir,customDir,mode)
def select(+ready: Process.QueryReady,+setting: Maybe<&2,String>,+env: Maybe<&2,String>,+builtinDir: String,+customDir: String,+mode: Color.Mode) -> IO(Result<&2,&2,Theme.LoadError,Selection>):
  selectRoute(ready,setting,env,builtinDir,customDir,mode,route(setting))

def snapshot(+state: Selection) -> Selection & Selection: (state,state)
def current(handle: Handle) -> IO(Selection):
  match handle:
    case Handle{resource,_,_,_,_,_}: Serial.run(Selection,Selection,resource,value => IO.pure(Selection & Selection,snapshot(value)))

def settingOf(value: Selection) -> Maybe<&2,String>:
  match value:
    case Selection{setting,_,_,_,_,_,_}: setting
def withTerminal(value: Selection,terminal: Detection.TerminalTheme) -> Selection:
  match value:
    case Selection{setting,_,name,theme,auto,persist,error}: Selection{setting,terminal,name,theme,auto,persist,error}
def committedNotification(+state: Selection,report: Detection.TerminalTheme,result: Result<&2,&2,Theme.LoadError,Loaded>) -> Selection & Bool:
  match result:
    case Fail{_}: (state,False{})
    case Done{loaded}: (selection(settingOf(state),report,False{},loaded),True{})
def changedNotification(+state: Selection,setting: Maybe<&2,String>,+report: Detection.TerminalTheme,name: String,builtinDir: String,customDir: String,mode: Color.Mode) -> IO(Selection & Bool):
  +next = selectedName(setting,report)
  Bool.pick(Unit -> IO(Selection & Bool),String.eq(next,name),
    _ => IO.pure(Selection & Bool,(withTerminal(state,report),False{})),
    _ => do IO<Selection & Bool>:
      result : Result<&2,&2,Theme.LoadError,Loaded> <- load(next,builtinDir,customDir,mode)
      return committedNotification(state,report,result))(Unit{})
def notificationSelection(+state: Selection,report: Detection.TerminalTheme,builtinDir: String,customDir: String,mode: Color.Mode) -> IO(Selection & Bool):
  match state:
    case Selection{setting,_,name,_,auto,persist,error}:
      Bool.pick(Unit -> IO(Selection & Bool),auto,
        _ => changedNotification(state,setting,report,name,builtinDir,customDir,mode),
        _ => IO.pure(Selection & Bool,(state,False{})))(Unit{})
def notify(environment: Notification,report: TerminalColors.TerminalColorScheme) -> IO(Unit):
  match environment:
    case Notification{resource,requestRender,builtinDir,customDir,mode}:
      do IO<Unit>:
        changed : Bool <- Serial.run(Selection,Bool,resource,state => notificationSelection(state,scheme(report),builtinDir,customDir,mode))
        Bool.pick(Unit -> IO(Unit),changed,_ => Callback.call(Unit,Unit,requestRender,Unit{}),_ => IO.pure(Unit,Unit{}))(Unit{})

def stateAuto(state: Selection) -> Bool:
  match state:
    case Selection{_,_,_,_,auto,_,_}: auto
def startOwned(pair: Serial.Owner<Selection> & Serial.Handle<Selection>,+ready: Process.QueryReady,+env: Maybe<&2,String>,+builtinDir: String,+customDir: String,+mode: Color.Mode) -> IO(Result<&2,&1,Theme.LoadError,Owner & Handle>):
  match pair:
    case (owner,+resource):
      match ready:
        case Process.QueryReady{queries,_,write,requestRender}:
          do IO<Result<&2,&1,Theme.LoadError,Owner & Handle>>:
            +callback : Callback.Callback<TerminalColors.TerminalColorScheme,Unit> <- Callback.create(~Notification,~TerminalColors.TerminalColorScheme,~Unit,~notify,Notification{resource,requestRender,builtinDir,customDir,mode})
            id : Nat <- Query.onSchemeChange(queries,callback)
            state : Selection <- Serial.run(Selection,Selection,resource,value => IO.pure(Selection & Selection,snapshot(value)))
            Query.setNotifications(queries,write,stateAuto(state))
            return Done{(Owner{owner,id,callback,ready},Handle{resource,ready,env,builtinDir,customDir,mode})}
def initialized(value: Result<&2,&2,Theme.LoadError,Selection>,ready: Process.QueryReady,env: Maybe<&2,String>,builtinDir: String,customDir: String,mode: Color.Mode) -> IO(Result<&2,&1,Theme.LoadError,Owner & Handle>):
  match value:
    case Fail{error}: IO.pure(Result<&2,&1,Theme.LoadError,Owner & Handle>,Fail{error})
    case Done{state}:
      do IO<Result<&2,&1,Theme.LoadError,Owner & Handle>>:
        owner : Serial.Owner<Selection> <- Serial.create(Selection,state)
        startOwned(Serial.borrow(Selection,owner),ready,env,builtinDir,customDir,mode)
def start(+ready: Process.QueryReady,setting: Maybe<&2,String>,+env: Maybe<&2,String>,+builtinDir: String,+customDir: String,+mode: Color.Mode) -> IO(Result<&2,&1,Theme.LoadError,Owner & Handle>):
  do IO<Result<&2,&1,Theme.LoadError,Owner & Handle>>:
    value : Result<&2,&2,Theme.LoadError,Selection> <- select(ready,setting,env,builtinDir,customDir,mode)
    initialized(value,ready,env,builtinDir,customDir,mode)

def committedSetting(previous: Selection,+next: Selection) -> Selection & Selection: (next,next)
def commitReady(handle: Handle,next: Selection) -> IO(Result<&2,&2,Theme.LoadError,Selection>):
  match handle:
    case Handle{resource,Process.QueryReady{queries,_,write,requestRender},_,_,_,_}:
      do IO<Result<&2,&2,Theme.LoadError,Selection>>:
        +selected : Selection <- Serial.run(Selection,Selection,resource,previous => IO.pure(Selection & Selection,committedSetting(previous,next)))
        Query.setNotifications(queries,write,stateAuto(selected))
        Callback.call(Unit,Unit,requestRender,Unit{})
        return Done{selected}
def setReady(handle: Handle,value: Result<&2,&2,Theme.LoadError,Selection>) -> IO(Result<&2,&2,Theme.LoadError,Selection>):
  match value:
    case Fail{error}: IO.pure(Result<&2,&2,Theme.LoadError,Selection>,Fail{error})
    case Done{next}: commitReady(handle,next)
def setThemeSetting(+handle: Handle,setting: Maybe<&2,String>) -> IO(Result<&2,&2,Theme.LoadError,Selection>):
  match handle:
    case Handle{_,ready,env,builtinDir,customDir,mode}:
      do IO<Result<&2,&2,Theme.LoadError,Selection>>:
        next : Result<&2,&2,Theme.LoadError,Selection> <- select(ready,setting,env,builtinDir,customDir,mode)
        setReady(handle,next)
# Stop notifications and retire this controller while its QueryReady handles
# are still live. The caller finishes any in-flight terminal input first.
def close(owner: Owner) -> IO(Unit):
  match owner:
    case Owner{resource,id,callback,Process.QueryReady{+queries,_,+write,_}}:
      do IO<Unit>:
        Query.setNotifications(queries,write,False{})
        Query.offSchemeChange(queries,id)
        Callback.dispose(TerminalColors.TerminalColorScheme,Unit,callback)
        state : Selection <- Serial.retire(Selection,resource)
        return Unit{}
