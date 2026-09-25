import Base
import ../../../../agent/src/types.bend as Agent
import ../../../../runtime/src/callback.bend as Callback
import ../../../../runtime/src/deferred.bend as Deferred
import ../../../../runtime/src/ref.bend as Ref
import ../../../../runtime/src/text.bend as Text
import ../../../../tui/src/tui-process.bend as Process
import ../../core/agent-runtime.bend as Runtime
import ../../core/agent-session.bend as Session
import ../../core/model-runtime.bend as Models
import ../../../../ai/src/auth/types.bend as Auth
import ../../../../ai/src/types.bend as Ai
import ../../../../ai/src/models.bend as AiModels
import ../../../../ai/src/utils/thinking-levels.bend as Levels
import ../../../../runtime/src/collation.bend as Collation
import ../../../../runtime/src/stable-sort.bend as Sort
import ../../../../tui/src/autocomplete.bend as AC
import ../../../../tui/src/fuzzy.bend as Fuzzy
import ../../core/prompt-templates.bend as Templates
import ../../core/settings-manager.bend as Settings
import ../../core/skills.bend as Skills
import ../../core/slash-commands.bend as Slash
import ./model-search.bend as Search
import ./components/model-selector.bend as ModelPicker
import ./session-controller.bend as Controller
import ./commands.bend as Commands
import ./transcript.bend as Transcript

# Model work runs in SessionController's worker. These callbacks only publish
# immutable event snapshots and ask the TUI process for another frame.
type Events is Data:
  Events{transcript: Transcript.Handle,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>}
type SubmissionFailure is Data:
  QueueFailure{cause: Controller.SubmitError}
  PromptFailure{message: String}
  CommandFailure{message: String}
  CommandNotice{message: String}
type SubmissionInput is Data:
  SubmissionInput{queue: Controller.Handle,stop: Deferred.Deferred<Unit>,failure: Ref.Ref<Maybe<&2,SubmissionFailure>>}
type CommandSink is Data:
  CommandSink{failure: Ref.Ref<Maybe<&2,SubmissionFailure>>,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,picker: Ref.Ref<Maybe<&2,ModelPicker.Host>>,session: Ref.Ref<Session.AgentSession>,models: Ref.Ref<List<&2,Models.Model()>>}
type Startup is Data:
  Startup{redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,queue: Controller.Handle,initial: List<&2,Controller.Submission>,failure: Ref.Ref<Maybe<&2,SubmissionFailure>>}

def failureText(failure: SubmissionFailure) -> String:
  match failure:
    case QueueFailure{Controller.Full{}}: "Submission queue is full"
    case QueueFailure{Controller.Closed{}}: "Session is closed"
    case PromptFailure{message}: message
    case CommandFailure{message}: message
    case CommandNotice{message}: message
def submittedResult(failure: Ref.Ref<Maybe<&2,SubmissionFailure>>,result: Result<&2,&2,Controller.SubmitError,Unit>) -> IO(Unit):
  match result:
    case Done{_}: Ref.write(Maybe<&2,SubmissionFailure>,failure,None{})
    case Fail{cause}: Ref.write(Maybe<&2,SubmissionFailure>,failure,Some{QueueFailure{cause}})

def renderRequested(callback: Maybe<&2,Callback.Callback<Unit,Unit>>) -> IO(Unit):
  match callback:
    case None{}: IO.pure(Unit,Unit{})
    case Some{value}: Callback.call(Unit,Unit,value,Unit{})
def requestRender(redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>) -> IO(Unit):
  do IO<Unit>:
    callback : Maybe<&2,Callback.Callback<Unit,Unit>> <- Ref.read(Maybe<&2,Callback.Callback<Unit,Unit>>,redraw)
    renderRequested(callback)
def observed(events: Events,event: Session.SessionEvent()) -> IO(Unit):
  match events:
    case Events{transcript,redraw}:
      do IO<Unit>:
        changed : Bool <- Transcript.accept(Unit,Runtime.Custom(),transcript,event)
        Bool.pick(Unit -> IO(Unit),changed,_ => requestRender(redraw),_ => IO.pure(Unit,Unit{}))(Unit{})
def onSessionEvent(events: Events,event: Session.AgentSessionEvent) -> IO(Unit):
  match event:
    case Session.AgentEvent{value}: observed(events,value)
    case _: IO.pure(Unit,Unit{})
def commandStatus(failure: Ref.Ref<Maybe<&2,SubmissionFailure>>,status: SubmissionFailure) -> IO(Unit):
  Ref.write(Maybe<&2,SubmissionFailure>,failure,Some{status})
def pickerCurrent(session: Session.AgentSession) -> IO(Maybe<&2,Models.Model()>):
  do IO<Maybe<&2,Models.Model()>>:
    current : Session.AgentState() <- Session.state(session)
    return Session.stateModel(current)
def openPicker(host: Maybe<&2,ModelPicker.Host>,models: List<&2,Models.Model()>,current: Maybe<&2,Models.Model()>,query: Maybe<&2,String>) -> IO(Unit):
  match host:
    case None{}: IO.pure(Unit,Unit{})
    case Some{value}: ModelPicker.open(value,ModelPicker.create(models,current,Maybe.default(&2,String,query,""),24n))
def openPickerResult(failure: Ref.Ref<Maybe<&2,SubmissionFailure>>,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,picker: Ref.Ref<Maybe<&2,ModelPicker.Host>>,session: Session.AgentSession,models: List<&2,Models.Model()>,search: Maybe<&2,String>) -> IO(Bool):
  match models:
    case Nil{}:
      do IO<Bool>:
        commandStatus(failure,CommandFailure{"No models available. Use /login to add a provider."})
        requestRender(redraw)
        return False{}
    case model <> rest:
      do IO<Bool>:
        +current : Maybe<&2,Models.Model()> <- pickerCurrent(session)
        target : Maybe<&2,ModelPicker.Host> <- Ref.read(Maybe<&2,ModelPicker.Host>,picker)
        openPicker(target,model <> rest,current,search)
        requestRender(redraw)
        return False{}
def commandResult(+sink: CommandSink,result: Commands.Action) -> IO(Bool):
  match sink result:
    case CommandSink{failure,redraw,_,_,_} Commands.Notice{message}:
      do IO<Bool>:
        commandStatus(failure,CommandNotice{message})
        requestRender(redraw)
        return False{}
    case CommandSink{failure,redraw,_,_,_} Commands.CommandError{message}:
      do IO<Bool>:
        commandStatus(failure,CommandFailure{message})
        requestRender(redraw)
        return False{}
    case CommandSink{failure,redraw,_,_,_} Commands.ModelSelected{model}:
      do IO<Bool>:
        commandStatus(failure,CommandNotice{"Model: " ++ Models.reference(model)})
        requestRender(redraw)
        return True{}
    case CommandSink{failure,redraw,picker,session,models} Commands.OpenModelPicker{search}:
      do IO<Bool>:
        live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
        available : List<&2,Models.Model()> <- Ref.read(List<&2,Models.Model()>,models)
        openPickerResult(failure,redraw,picker,live,available,search)
    case _ _: IO.pure(Bool,False{})
def act(queue: Controller.Handle,stop: Deferred.Deferred<Unit>,failure: Ref.Ref<Maybe<&2,SubmissionFailure>>,command: Commands.Command) -> IO(Unit):
  match command:
    case Commands.Stop{}:
      do IO<Unit>:
        settled : Bool <- Deferred.resolve(Unit,stop,Unit{})
        return Unit{}
    case Commands.Send{message}:
      do IO<Unit>:
        result : Result<&2,&2,Controller.SubmitError,Unit> <- Controller.submitText(queue,message)
        submittedResult(failure,result)
    case other:
      do IO<Unit>:
        result : Result<&2,&2,Controller.SubmitError,Unit> <- Controller.submitCommand(queue,other)
        submittedResult(failure,result)
def submitOwned(input: SubmissionInput,+text: String) -> IO(Unit):
  match input:
    case SubmissionInput{queue,stop,failure}:
      Bool.pick(Unit -> IO(Unit),String.is_empty(Text.trim(text)),_ => IO.pure(Unit,Unit{}),_ => do IO<Unit>:
        act(queue,stop,failure,Commands.parse(text)))(Unit{})
def submitted(input: SubmissionInput,text: String) -> IO(Unit): submitOwned(input,text)
def queueInitial(+queue: Controller.Handle,+failure: Ref.Ref<Maybe<&2,SubmissionFailure>>,initial: List<&2,Controller.Submission>) -> IO(Unit):
  match initial:
    case Nil{}: IO.pure(Unit,Unit{})
    case item <> rest:
      do IO<Unit>:
        result : Result<&2,&2,Controller.SubmitError,Unit> <- Controller.submit(queue,item)
        submittedResult(failure,result)
        queueInitial(queue,failure,rest)
def onReady(startup: Startup,ready: Process.QueryReady) -> IO(Unit):
  match startup ready:
    case Startup{redraw,queue,initial,failure} Process.QueryReady{_,_,_,request}:
      do IO<Unit>:
        Ref.write(Maybe<&2,Callback.Callback<Unit,Unit>>,redraw,Some{request})
        queueInitial(queue,failure,initial)

# upstream createBaseAutocompleteProvider/setupAutocompleteProvider. Argument
# completions read the live session, so they follow /new, /resume and model
# changes. Extension commands are absent until extensions are ported.
type AutocompleteOwner is Data:
  AutocompleteOwner{provider: AC.AutocompleteProvider,arguments: List<&2,Callback.Callback<String,AC.ResultOf(Maybe<&2,List<&2,AC.AutocompleteItem>>)>>}

# upstream createFuzzyAutocompleteItems: null when nothing matches.
type Searchable is Data: Searchable{text: String,item: AC.AutocompleteItem}
def searchableText(value: Searchable) -> String:
  match value: case Searchable{text,_}: text
def searchableItems(values: List<&2,Searchable>) -> List<&2,AC.AutocompleteItem>:
  match values:
    case Nil{}: Nil{}
    case Searchable{_,item} <> rest: item <> searchableItems(rest)
def someItems(items: List<&2,AC.AutocompleteItem>) -> AC.ResultOf(Maybe<&2,List<&2,AC.AutocompleteItem>>):
  match items:
    case Nil{}: Done{None{}}
    case _: Done{Some{items}}
def fuzzyItems(values: List<&2,Searchable>,prefix: String) -> AC.ResultOf(Maybe<&2,List<&2,AC.AutocompleteItem>>):
  someItems(searchableItems(Fuzzy.fuzzyFilter(~Searchable,~searchableText,values,prefix)))

def modelSearchable(item: Search.ModelSearchItem) -> Searchable:
  match item:
    case Search.ModelSearchItem{+id,+provider,+name}: Searchable{Search.getModelSearchText(Search.ModelSearchItem{id,provider,name}),AC.AutocompleteItem{provider ++ "/" ++ id,id,Some{provider}}}
def modelSearchables(items: List<&2,Search.ModelSearchItem>) -> List<&2,Searchable>:
  match items:
    case Nil{}: Nil{}
    case item <> rest: modelSearchable(item) <> modelSearchables(rest)
def searchItems(models: List<&2,Models.Model()>) -> List<&2,Search.ModelSearchItem>:
  match models:
    case Nil{}: Nil{}
    case model <> rest: Search.searchItem(model) <> searchItems(rest)
# upstream /model argument completions over the scoped or available models.
def modelArgumentItems(items: List<&2,Search.ModelSearchItem>,prefix: String) -> AC.ResultOf(Maybe<&2,List<&2,AC.AutocompleteItem>>):
  fuzzyItems(modelSearchables(items),prefix)
def completionModels(scoped: List<&2,Models.ScopedModel>,available: List<&2,Models.Model()>) -> List<&2,Models.Model()>:
  match scoped:
    case Nil{}: available
    case _: Session.scopedModels(scoped)
def modelCompletions(session: Ref.Ref<Session.AgentSession>,prefix: String) -> IO(AC.ResultOf(Maybe<&2,List<&2,AC.AutocompleteItem>>)):
  do IO<AC.ResultOf(Maybe<&2,List<&2,AC.AutocompleteItem>>)>:
    +live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
    scoped : List<&2,Models.ScopedModel> <- Session.getScopedModels(live)
    available : List<&2,Models.Model()> <- Models.getAvailable(Session.modelRuntime(live))
    return modelArgumentItems(searchItems(completionModels(scoped,available)),prefix)

def levelSearchables(levels: List<&2,Ai.ModelThinkingLevel>) -> List<&2,Searchable>:
  match levels:
    case Nil{}: Nil{}
    case level <> rest:
      +name = Levels.name(level)
      Searchable{name,AC.AutocompleteItem{name,name,None{}}} <> levelSearchables(rest)
def thinkingCompletions(session: Ref.Ref<Session.AgentSession>,prefix: String) -> IO(AC.ResultOf(Maybe<&2,List<&2,AC.AutocompleteItem>>)):
  do IO<AC.ResultOf(Maybe<&2,List<&2,AC.AutocompleteItem>>)>:
    live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
    levels : List<&2,Ai.ModelThinkingLevel> <- Session.getAvailableThinkingLevels(live)
    return fuzzyItems(levelSearchables(levels),prefix)

# upstream getLoginProviderOptions: an entry per provider and auth type
# (subscription before API key), ordered by name with localeCompare.
type AuthSelectorProvider is Data: AuthSelectorProvider{id: String,name: String,authType: String}
def formatAuthSelectorProviderType(+authType: String) -> String: Bool.pick(String,String.eq(authType,"oauth"),"subscription","API key")
def providerEntries(+id: String,+name: String,auth: Auth.ProviderAuth,+rest: List<&2,AuthSelectorProvider>) -> List<&2,AuthSelectorProvider>:
  match auth:
    case Auth.ProviderAuth{apiKey,oauth}:
      +keyed = Bool.pick(List<&2,AuthSelectorProvider>,Maybe.is_some(&2,Auth.ApiKeyAuth,apiKey),AuthSelectorProvider{id,name,"api_key"} <> rest,rest)
      Bool.pick(List<&2,AuthSelectorProvider>,Maybe.is_some(&2,Auth.OAuthAuth,oauth),AuthSelectorProvider{id,name,"oauth"} <> keyed,keyed)
def providerOptions(providers: List<&2,AiModels.Provider>) -> List<&2,AuthSelectorProvider>:
  match providers:
    case Nil{}: Nil{}
    case AiModels.Provider{id,name,_,auth,_} <> rest: providerEntries(id,name,auth,providerOptions(rest))
def notAfter(order: Cmp) -> Bool:
  match order:
    case GT{}: False{}
    case _: True{}
type Keyed is Data: Keyed{key: Collation.Key,index: Nat}
def keyedBefore(left: Keyed,right: Keyed) -> Bool:
  match left right:
    case Keyed{a,_} Keyed{b,_}: notAfter(Collation.compareKeys(a,b))
def keyedNames(+collator: Collation.Collator,names: List<&2,String>,+index: Nat) -> List<&2,Keyed>:
  match names:
    case Nil{}: Nil{}
    case name <> rest: Keyed{Collation.key(collator,name),index} <> keyedNames(collator,rest,index + 1n)
def indices(values: List<&2,Keyed>) -> List<&2,Nat>:
  match values:
    case Nil{}: Nil{}
    case Keyed{_,index} <> rest: index <> indices(rest)
# The stable order of `names` by localeCompare, as positions; the input order
# without collation data.
def nameOrder(collator: Maybe<&2,Collation.Collator>,+names: List<&2,String>) -> List<&2,Nat>:
  match collator:
    case Some{value}: indices(Sort.sort(~Keyed,~keyedBefore,keyedNames(value,names,0n)))
    case None{}: List.range(List.length(&2,String,names))
def optionName(option: AuthSelectorProvider) -> String:
  match option: case AuthSelectorProvider{_,name,_}: name
def selectorNames(options: List<&2,AuthSelectorProvider>) -> List<&2,String>:
  match options:
    case Nil{}: Nil{}
    case option <> rest: optionName(option) <> selectorNames(rest)
def picked(-A: Data,found: Maybe<&2,A>,rest: List<&2,A>) -> List<&2,A>:
  match found:
    case None{}: rest
    case Some{value}: value <> rest
def pickAll(-A: Data,positions: List<&2,Nat>,+values: List<&2,A>) -> List<&2,A>:
  match positions:
    case Nil{}: Nil{}
    case index <> rest: picked(A,List.get(&2,A,values,index),pickAll(A,rest,values))
def getLoginProviderOptions(collator: Maybe<&2,Collation.Collator>,providers: List<&2,AiModels.Provider>) -> List<&2,AuthSelectorProvider>:
  +options = providerOptions(providers)
  pickAll(AuthSelectorProvider,nameOrder(collator,selectorNames(options)),options)

# upstream getLoginProviderCompletionOptions: entries grouped by provider id
# (first appearance), auth types in subscription/API key order, then ordered
# by name.
type LoginProviderCompletionOption is Data: LoginProviderCompletionOption{id: String,name: String,authTypes: List<&2,String>}
def hasType(types: List<&2,String>,+wanted: String) -> Bool:
  match types:
    case Nil{}: False{}
    case kind <> rest: String.eq(kind,wanted) || hasType(rest,wanted)
def withAuthType(+types: List<&2,String>,+authType: String) -> List<&2,String>:
  Bool.pick(List<&2,String>,hasType(types,authType),types,
    Bool.pick(List<&2,String>,String.eq(authType,"oauth"),authType <> types,List.append(&2,String,types,[authType])))
def mergedEntry(same: Bool,entry: LoginProviderCompletionOption,+authType: String) -> LoginProviderCompletionOption:
  match same entry:
    case True{} LoginProviderCompletionOption{id,name,types}: LoginProviderCompletionOption{id,name,withAuthType(types,authType)}
    case False{} entry: entry
def mergedAll(entries: List<&2,LoginProviderCompletionOption>,+id: String,+authType: String) -> List<&2,LoginProviderCompletionOption>:
  match entries:
    case Nil{}: Nil{}
    case LoginProviderCompletionOption{+other,name,types} <> rest: mergedEntry(String.eq(other,id),LoginProviderCompletionOption{other,name,types},authType) <> mergedAll(rest,id,authType)
def hasId(entries: List<&2,LoginProviderCompletionOption>,+id: String) -> Bool:
  match entries:
    case Nil{}: False{}
    case LoginProviderCompletionOption{other,_,_} <> rest: String.eq(other,id) || hasId(rest,id)
def groupedWith(found: Bool,entries: List<&2,LoginProviderCompletionOption>,option: AuthSelectorProvider) -> List<&2,LoginProviderCompletionOption>:
  match found option:
    case True{} AuthSelectorProvider{id,_,authType}: mergedAll(entries,id,authType)
    case False{} AuthSelectorProvider{id,name,authType}: List.append(&2,LoginProviderCompletionOption,entries,[LoginProviderCompletionOption{id,name,[authType]}])
def optionId(option: AuthSelectorProvider) -> String:
  match option: case AuthSelectorProvider{id,_,_}: id
def grouped(+entries: List<&2,LoginProviderCompletionOption>,+option: AuthSelectorProvider) -> List<&2,LoginProviderCompletionOption>:
  groupedWith(hasId(entries,optionId(option)),entries,option)
def groupedAll(options: List<&2,AuthSelectorProvider>,entries: List<&2,LoginProviderCompletionOption>) -> List<&2,LoginProviderCompletionOption>:
  match options:
    case Nil{}: entries
    case option <> rest: groupedAll(rest,grouped(entries,option))
def completionName(option: LoginProviderCompletionOption) -> String:
  match option: case LoginProviderCompletionOption{_,name,_}: name
def completionNames(options: List<&2,LoginProviderCompletionOption>) -> List<&2,String>:
  match options:
    case Nil{}: Nil{}
    case option <> rest: completionName(option) <> completionNames(rest)
def getLoginProviderCompletionOptions(collator: Maybe<&2,Collation.Collator>,options: List<&2,AuthSelectorProvider>) -> List<&2,LoginProviderCompletionOption>:
  +entries = groupedAll(options,Nil{})
  pickAll(LoginProviderCompletionOption,nameOrder(collator,completionNames(entries)),entries)
def typeSearchText(types: List<&2,String>) -> List<&2,String>:
  match types:
    case Nil{}: Nil{}
    case +kind <> rest: (kind ++ " " ++ formatAuthSelectorProviderType(kind)) <> typeSearchText(rest)
def typeNames(types: List<&2,String>) -> List<&2,String>:
  match types:
    case Nil{}: Nil{}
    case kind <> rest: formatAuthSelectorProviderType(kind) <> typeNames(rest)
# getLoginProviderSearchText and formatLoginProviderCompletionDescription.
def loginSearchable(option: LoginProviderCompletionOption) -> Searchable:
  match option:
    case LoginProviderCompletionOption{+id,+name,+types}:
      +described = String.join(typeNames(types),"/")
      Searchable{id ++ " " ++ name ++ " " ++ String.join(typeSearchText(types)," "),AC.AutocompleteItem{id,id,Some{Bool.pick(String,String.eq(name,id),described,name ++ " · " ++ described)}}}
def loginSearchables(options: List<&2,LoginProviderCompletionOption>) -> List<&2,Searchable>:
  match options:
    case Nil{}: Nil{}
    case option <> rest: loginSearchable(option) <> loginSearchables(rest)
# upstream /login argument completions.
def loginArgumentItems(+collator: Maybe<&2,Collation.Collator>,options: List<&2,AuthSelectorProvider>,prefix: String) -> AC.ResultOf(Maybe<&2,List<&2,AC.AutocompleteItem>>):
  fuzzyItems(loginSearchables(getLoginProviderCompletionOptions(collator,options)),prefix)
def loadedCollator(loaded: Result<&2,&2,Collation.LoadError,Collation.Collator>) -> Maybe<&2,Collation.Collator>:
  match loaded:
    case Done{collator}: Some{collator}
    case Fail{_}: None{}
type LoginCompletion is Data: LoginCompletion{session: Ref.Ref<Session.AgentSession>,collator: Maybe<&2,Collation.Collator>}
def loginCompletions(state: LoginCompletion,prefix: String) -> IO(AC.ResultOf(Maybe<&2,List<&2,AC.AutocompleteItem>>)):
  match state:
    case LoginCompletion{session,+collator}:
      do IO<AC.ResultOf(Maybe<&2,List<&2,AC.AutocompleteItem>>)>:
        live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
        return loginArgumentItems(collator,getLoginProviderOptions(collator,Models.getProviders(Session.modelRuntime(live))),prefix)

# upstream getAutocompleteSourceTag and prefixAutocompleteDescription. Package
# sources (npm and git installs) are not ported, so resources carry auto,
# local or cli sources and the tag is the scope.
def scopePrefix(scope: Skills.SourceScope) -> String:
  match scope:
    case Skills.User{}: "u"
    case Skills.Project{}: "p"
    case Skills.Temporary{}: "t"
def sourceTag(info: Skills.SourceInfo) -> String:
  match info:
    case Skills.SourceInfo{_,source,scope,_,_}:
      +prefix = scopePrefix(scope)
      +trimmed = Text.trim(source)
      Bool.pick(String,String.starts_with(trimmed,"npm:"),prefix ++ ":" ++ trimmed,prefix)
def prefixAutocompleteDescription(+description: String,info: Skills.SourceInfo) -> Maybe<&2,String>:
  +tag = sourceTag(info)
  Some{Bool.pick(String,String.is_empty(description),"[" ++ tag ++ "]","[" ++ tag ++ "] " ++ description)}

type Arguments is Data: Arguments{model: Callback.Callback<String,AC.ResultOf(Maybe<&2,List<&2,AC.AutocompleteItem>>)>,thinking: Callback.Callback<String,AC.ResultOf(Maybe<&2,List<&2,AC.AutocompleteItem>>)>,login: Callback.Callback<String,AC.ResultOf(Maybe<&2,List<&2,AC.AutocompleteItem>>)>}
def argumentsFor(+name: String,arguments: Arguments) -> Maybe<&2,Callback.Callback<String,AC.ResultOf(Maybe<&2,List<&2,AC.AutocompleteItem>>)>>:
  match arguments:
    case Arguments{model,thinking,login}:
      Bool.pick(Maybe<&2,Callback.Callback<String,AC.ResultOf(Maybe<&2,List<&2,AC.AutocompleteItem>>)>>,String.eq(name,"model"),Some{model},
        Bool.pick(Maybe<&2,Callback.Callback<String,AC.ResultOf(Maybe<&2,List<&2,AC.AutocompleteItem>>)>>,String.eq(name,"thinking"),Some{thinking},
          Bool.pick(Maybe<&2,Callback.Callback<String,AC.ResultOf(Maybe<&2,List<&2,AC.AutocompleteItem>>)>>,String.eq(name,"login"),Some{login},None{})))
def builtinCommands(commands: List<&2,Slash.BuiltinSlashCommand>,+arguments: Arguments) -> List<&2,AC.Command>:
  match commands:
    case Nil{}: Nil{}
    case Slash.BuiltinSlashCommand{+name,description,hint} <> rest:
      AC.Slash{AC.SlashCommand{name,Some{description},hint,argumentsFor(name,arguments)}} <> builtinCommands(rest,arguments)
def templateCommands(templates: List<&2,Templates.PromptTemplate>) -> List<&2,AC.Command>:
  match templates:
    case Nil{}: Nil{}
    case Templates.PromptTemplate{name,description,hint,_,info,_} <> rest:
      AC.Slash{AC.SlashCommand{name,prefixAutocompleteDescription(description,info),hint,None{}}} <> templateCommands(rest)
def skillCommands(skills: List<&2,Skills.Skill>) -> List<&2,AC.Command>:
  match skills:
    case Nil{}: Nil{}
    case Skills.Skill{name,description,_,_,info,_} <> rest:
      AC.Slash{AC.SlashCommand{"skill:" ++ name,prefixAutocompleteDescription(description,info),None{},None{}}} <> skillCommands(rest)
def enabledSkills(enabled: Bool,skills: List<&2,Skills.Skill>) -> List<&2,AC.Command>:
  match enabled:
    case True{}: skillCommands(skills)
    case False{}: Nil{}
def sessionCwd(session: Session.AgentSession) -> String:
  match session: case Session.AgentSession{_,_,_,_,cwd,_,_,_}: cwd
def argumentList(arguments: Arguments) -> List<&2,Callback.Callback<String,AC.ResultOf(Maybe<&2,List<&2,AC.AutocompleteItem>>)>>:
  match arguments: case Arguments{model,thinking,login}: [model,thinking,login]
def disposeArguments(values: List<&2,Callback.Callback<String,AC.ResultOf(Maybe<&2,List<&2,AC.AutocompleteItem>>)>>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case value <> rest:
      do IO<Unit>:
        Callback.dispose(String,AC.ResultOf(Maybe<&2,List<&2,AC.AutocompleteItem>>),value)
        disposeArguments(rest)
# Without collation data, folded scalar order approximates localeCompare.
def sortPolicy(collator: Maybe<&2,Collation.Collator>) -> AC.SortPolicy:
  match collator:
    case Some{value}: AC.LocaleOrder{value}
    case None{}: AC.FoldedScalarOrder{}
def combinedOwner(+arguments: Arguments,created: AC.ResultOf(AC.CombinedAutocompleteProvider)) -> IO(Maybe<&2,AutocompleteOwner>):
  match created:
    case Fail{_}:
      do IO<Maybe<&2,AutocompleteOwner>>:
        disposeArguments(argumentList(arguments))
        return None{}
    case Done{combined}:
      do IO<Maybe<&2,AutocompleteOwner>>:
        provider : AC.AutocompleteProvider <- AC.asProvider(combined)
        return Some{AutocompleteOwner{provider,argumentList(arguments)}}
# `recursiveFiles` is upstream's fdPath: @ file search runs only when fd is
# available, although the port searches natively. `home` and the session
# cwd must be absolute; otherwise there is no provider.
def createAutocompleteProvider(+session: Ref.Ref<Session.AgentSession>,home: String,data: String,recursiveFiles: Bool) -> IO(Maybe<&2,AutocompleteOwner>):
  do IO<Maybe<&2,AutocompleteOwner>>:
    +live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
    settings : Settings.SettingsManager <- Session.getSettings(live)
    templates : List<&2,Templates.PromptTemplate> <- Session.promptTemplates(live)
    skills : List<&2,Skills.Skill> <- Session.getSkills(live)
    model : Callback.Callback<String,AC.ResultOf(Maybe<&2,List<&2,AC.AutocompleteItem>>)> <- Callback.create(~Ref.Ref<Session.AgentSession>,~String,~AC.ResultOf(Maybe<&2,List<&2,AC.AutocompleteItem>>),~modelCompletions,session)
    thinking : Callback.Callback<String,AC.ResultOf(Maybe<&2,List<&2,AC.AutocompleteItem>>)> <- Callback.create(~Ref.Ref<Session.AgentSession>,~String,~AC.ResultOf(Maybe<&2,List<&2,AC.AutocompleteItem>>),~thinkingCompletions,session)
    loaded : Result<&2,&2,Collation.LoadError,Collation.Collator> <- Collation.load(data)
    +collator : Maybe<&2,Collation.Collator> <- IO.pure(Maybe<&2,Collation.Collator>,loadedCollator(loaded))
    login : Callback.Callback<String,AC.ResultOf(Maybe<&2,List<&2,AC.AutocompleteItem>>)> <- Callback.create(~LoginCompletion,~String,~AC.ResultOf(Maybe<&2,List<&2,AC.AutocompleteItem>>),~loginCompletions,LoginCompletion{session,collator})
    +arguments : Arguments <- IO.pure(Arguments,Arguments{model,thinking,login})
    +commands : List<&2,AC.Command> <- IO.pure(List<&2,AC.Command>,List.append(&2,AC.Command,builtinCommands(Slash.BUILTIN_SLASH_COMMANDS(),arguments),List.append(&2,AC.Command,templateCommands(templates),enabledSkills(Settings.getEnableSkillCommands(settings),skills))))
    combinedOwner(arguments,AC.create(commands,sessionCwd(live),home,sortPolicy(collator),recursiveFiles))
def disposeAutocompleteProvider(owner: AutocompleteOwner) -> IO(Unit):
  match owner:
    case AutocompleteOwner{provider,arguments}:
      do IO<Unit>:
        AC.disposeProvider(provider)
        disposeArguments(arguments)
