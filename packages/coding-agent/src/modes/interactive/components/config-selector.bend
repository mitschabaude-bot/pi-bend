import Base
import ../../../core/package-manager.bend as PackageManager
import ../../../core/settings-manager.bend as Settings
import ../../../utils/paths.bend as Paths
import ../../../../../runtime/src/posix-path.bend as Path
import ../../../../../runtime/src/stable-sort.bend as Sort
import ../../../../../runtime/src/record.bend as Record
import ../../../../../runtime/src/schema-value.bend as Value
import ../theme/theme.bend as Theme
import ../../../../../tui/src/utils.bend as Utils
import ./keybinding-hints.bend as Hints

type ResourceType is Data:
  Extensions{}
  Skills{}
  Prompts{}
  Themes{}

type WriteScope is Data:
  Global{}
  Project{}

type Override is Data:
  Inherit{}
  Load{}
  Unload{}

type Item is Data:
  Item{path: String, enabled: Bool, metadata: PackageManager.PathMetadata, kind: ResourceType, name: String, groupKey: String, groupLabel: String}

type Group is Data:
  Group{key: String, origin: PackageManager.Source, scope: PackageManager.Scope, source: String, items: List<&2, Item>}

type Entry is Data:
  GroupHeader{label: String, inherited: Bool}
  SubgroupHeader{kind: ResourceType, inherited: Bool}
  ResourceRow{item: Item}

type State is Data:
  State{global: List<&2, Item>, project: List<&2, Item>, scope: WriteScope, projectAvailable: Bool, query: String, selected: Nat, maxVisible: Nat, inherited: List<&2, Item>}

type Changed is Data:
  Changed{state: State, manager: Settings.SettingsManager}

def kindName(kind: ResourceType) -> String:
  match kind:
    case Extensions{}: "Extensions"
    case Skills{}: "Skills"
    case Prompts{}: "Prompts"
    case Themes{}: "Themes"

def kindOrder(kind: ResourceType) -> String:
  match kind:
    case Extensions{}: "0"
    case Skills{}: "1"
    case Prompts{}: "2"
    case Themes{}: "3"

def scopeName(scope: PackageManager.Scope) -> String:
  match scope:
    case PackageManager.UserScope{}: "user"
    case PackageManager.ProjectScope{}: "project"

def scopeOrder(scope: PackageManager.Scope) -> String:
  match scope:
    case PackageManager.UserScope{}: "0"
    case PackageManager.ProjectScope{}: "1"

def sourceName(source: PackageManager.Source) -> String:
  match source:
    case PackageManager.Package{name}: name
    case PackageManager.Auto{}: "auto"
    case PackageManager.Local{}: "local"

def originOrder(source: PackageManager.Source) -> String:
  match source:
    case PackageManager.Package{_}: "0"
    case _: "1"

def homePath(+path: String, +home: String) -> String:
  Bool.pick(String, String.eq(path, home), "~", Bool.pick(String, String.starts_with(path, home ++ "/"), "~" ++ String.drop(path, String.length(home)), path))

def directoryLabel(path: String, home: String) -> String:
  homePath(path, home) ++ "/"

def groupLabel(metadata: PackageManager.PathMetadata, agentDir: String, home: String) -> String:
  match metadata:
    case PackageManager.PathMetadata{PackageManager.Package{source}, scope, _}: source ++ " (" ++ scopeName(scope) ++ ")"
    case PackageManager.PathMetadata{PackageManager.Auto{}, PackageManager.UserScope{}, Some{base}}: "User (" ++ directoryLabel(base, home) ++ ")"
    case PackageManager.PathMetadata{PackageManager.Auto{}, PackageManager.ProjectScope{}, Some{base}}: "Project (" ++ directoryLabel(base, home) ++ ")"
    case PackageManager.PathMetadata{PackageManager.Auto{}, PackageManager.UserScope{}, None{}}: "User (" ++ directoryLabel(agentDir, home) ++ ")"
    case PackageManager.PathMetadata{PackageManager.Auto{}, PackageManager.ProjectScope{}, None{}}: "Project (.pi/)"
    case PackageManager.PathMetadata{PackageManager.Local{}, PackageManager.UserScope{}, _}: "User settings"
    case PackageManager.PathMetadata{PackageManager.Local{}, PackageManager.ProjectScope{}, _}: "Project settings"

def groupKey(metadata: PackageManager.PathMetadata) -> String:
  match metadata:
    case PackageManager.PathMetadata{+source, +scope, base}:
      originOrder(source) ++ ":" ++ scopeOrder(scope) ++ ":" ++ sourceName(source) ++ ":" ++ Maybe.default(&2, String, base, "")

def displayName(+path: String, kind: ResourceType) -> String:
  match kind:
    case Extensions{}:
      +file = Path.basename(path)
      +parent = Path.basename(Path.dirname(path))
      Bool.pick(String, String.eq(parent, "extensions"), file, parent ++ "/" ++ file)
    case Skills{}:
      +file = Path.basename(path)
      Bool.pick(String, String.eq(file, "SKILL.md"), Path.basename(Path.dirname(path)), file)
    case _: Path.basename(path)

def item(resource: PackageManager.ResolvedResource, +kind: ResourceType, agentDir: String, home: String) -> Item:
  match resource:
    case PackageManager.ResolvedResource{+path, enabled, +metadata}:
      Item{path, enabled, metadata, kind, displayName(path, kind), groupKey(metadata), groupLabel(metadata, agentDir, home)}

def items(resources: List<&2, PackageManager.ResolvedResource>, +kind: ResourceType, +agentDir: String, +home: String) -> List<&2, Item>:
  match resources:
    case Nil{}: Nil{}
    case resource <> rest: item(resource, kind, agentDir, home) <> items(rest, kind, agentDir, home)

def itemKey(value: Item) -> String:
  match value:
    case Item{_, _, _, kind, name, _, _}: kindOrder(kind) ++ ":" ++ name

def itemBefore(left: Item, right: Item) -> Bool: String.is_le(itemKey(left), itemKey(right))

def singletonGroup(value: Item) -> Group:
  match value:
    case Item{path, enabled, PackageManager.PathMetadata{+origin, +scope, base}, kind, name, +key, label}:
      Group{key, origin, scope, sourceName(origin), [Item{path, enabled, PackageManager.PathMetadata{origin, scope, base}, kind, name, key, label}]}

def itemGroup(value: Item) -> String:
  match value:
    case Item{_, _, _, _, _, group, _}: group

def inserted(groups: List<&2, Group>, +value: Item) -> List<&2, Group>:
  match groups:
    case Nil{}: singletonGroup(value) <> Nil{}
    case Group{+key, +origin, +scope, +source, +items} <> +rest:
      Bool.pick(Unit -> List<&2, Group>, String.eq(key, itemGroup(value)),
        _ => Group{key, origin, scope, source, List.append(&2, Item, items, [value])} <> rest,
        _ => Group{key, origin, scope, source, items} <> inserted(rest, value))(Unit{})

def grouped(values: List<&2, Item>, groups: List<&2, Group>) -> List<&2, Group>:
  match values:
    case Nil{}: groups
    case value <> rest: grouped(rest, inserted(groups, value))

def groupSortKey(value: Group) -> String:
  match value:
    case Group{_, origin, scope, source, _}: originOrder(origin) ++ ":" ++ scopeOrder(scope) ++ ":" ++ source

def groupBefore(left: Group, right: Group) -> Bool: String.is_le(groupSortKey(left), groupSortKey(right))

def flattenGroups(groups: List<&2, Group>) -> List<&2, Item>:
  match groups:
    case Nil{}: Nil{}
    case Group{_, _, _, _, items} <> rest: List.append(&2, Item, Sort.sort(~Item, ~itemBefore, items), flattenGroups(rest))

def resolvedItems(paths: PackageManager.ResolvedPaths, +agentDir: String, +home: String) -> List<&2, Item>:
  match paths:
    case PackageManager.ResolvedPaths{extensions, skills, prompts, themes}:
      flattenGroups(Sort.sort(~Group, ~groupBefore, grouped(List.append(&2, Item, items(extensions, Extensions{}, agentDir, home), List.append(&2, Item, items(skills, Skills{}, agentDir, home), List.append(&2, Item, items(prompts, Prompts{}, agentDir, home), items(themes, Themes{}, agentDir, home)))), Nil{})))

def initial(+global: PackageManager.ResolvedPaths, project: PackageManager.ResolvedPaths, +agentDir: String, +home: String, projectAvailable: Bool, scope: WriteScope, terminalHeight: Nat) -> State:
  +inherited = resolvedItems(global, agentDir, home)
  State{inherited, resolvedItems(project, agentDir, home), scope, projectAvailable, "", 0n, Nat.max(5n, terminalHeight - 8n), inherited}

def matches(value: Item, +query: String) -> Bool:
  match value:
    case Item{path, _, _, kind, name, _, _}:
      +needle = String.to_lower(query)
      String.is_empty(String.trim(query)) || String.contains(String.to_lower(name), needle) || String.contains(String.to_lower(kindName(kind)), needle) || String.contains(String.to_lower(path), needle)

def filtered(values: List<&2, Item>, +query: String) -> List<&2, Item>:
  match values:
    case Nil{}: Nil{}
    case +value <> +rest:
      Bool.pick(Unit -> List<&2, Item>, matches(value, query), _ => value <> filtered(rest, query), _ => filtered(rest, query))(Unit{})

def inherited(scope: WriteScope, metadata: PackageManager.PathMetadata) -> Bool:
  match scope metadata:
    case Project{} PackageManager.PathMetadata{_, PackageManager.UserScope{}, _}: True{}
    case _ _: False{}

def headed(newGroup: Bool, newKind: Bool, label: String, kind: ResourceType, +inherited: Bool, rows: List<&2, Entry>) -> List<&2, Entry>:
  match newGroup newKind:
    case True{} _: GroupHeader{label, inherited} <> SubgroupHeader{kind, inherited} <> rows
    case False{} True{}: SubgroupHeader{kind, inherited} <> rows
    case False{} False{}: rows

def entries(values: List<&2, Item>, previousGroup: Maybe<&2, String>, previousKind: Maybe<&2, ResourceType>, +scope: WriteScope) -> List<&2, Entry>:
  match values:
    case Nil{}: Nil{}
    case Item{path, enabled, +metadata, +kind, name, +group, +label} <> rest:
      +changedGroup = Bool.not(Maybe.default(&2, Bool, Maybe.map(&2, String, Bool, old => String.eq(old, group), previousGroup), False{}))
      +changedKind = changedGroup || Bool.not(Maybe.default(&2, Bool, Maybe.map(&2, ResourceType, Bool, old => String.eq(kindOrder(old), kindOrder(kind)), previousKind), False{}))
      +next = entries(rest, Some{group}, Some{kind}, scope)
      +row = {ResourceRow{Item{path, enabled, metadata, kind, name, group, label}} <> next : List<&2, Entry>}
      headed(changedGroup, changedKind, label, kind, inherited(scope, metadata), row)

def visible(state: State) -> List<&2, Entry>:
  match state:
    case State{global, _, Global{}, _, query, _, _, _}: entries(filtered(global, query), None{}, None{}, Global{})
    case State{_, project, Project{}, _, query, _, _, _}: entries(filtered(project, query), None{}, None{}, Project{})

def search(state: State, query: String) -> State:
  match state:
    case State{global, project, scope, available, _, _, maxVisible, inherited}: State{global, project, scope, available, query, 0n, maxVisible, inherited}

def switchScope(state: State) -> State:
  match state:
    case State{global, project, scope, False{}, query, selected, maxVisible, inherited}: State{global, project, scope, False{}, query, selected, maxVisible, inherited}
    case State{global, project, Global{}, True{}, query, _, maxVisible, inherited}: State{global, project, Project{}, True{}, query, 0n, maxVisible, inherited}
    case State{global, project, Project{}, True{}, query, _, maxVisible, inherited}: State{global, project, Global{}, True{}, query, 0n, maxVisible, inherited}

def rowCount(values: List<&2, Entry>) -> Nat:
  match values:
    case Nil{}: 0n
    case ResourceRow{_} <> rest: 1n + rowCount(rest)
    case _ <> rest: rowCount(rest)

def selectedOf(state: State) -> Nat:
  match state:
    case State{_, _, _, _, _, selected, _, _}: selected

def pageSize(state: State) -> Nat:
  match state:
    case State{_, _, _, _, _, _, maxVisible, _}: maxVisible

def withSelected(state: State, selected: Nat) -> State:
  match state:
    case State{global, project, scope, available, query, _, maxVisible, inherited}: State{global, project, scope, available, query, selected, maxVisible, inherited}

def up(+state: State) -> State:
  withSelected(state, selectedOf(state) - 1n)

def down(+state: State) -> State:
  +count = rowCount(visible(state))
  withSelected(state, Nat.min(selectedOf(state) + 1n, count - 1n))

def fieldName(kind: ResourceType) -> String:
  match kind:
    case Extensions{}: "extensions"
    case Skills{}: "skills"
    case Prompts{}: "prompts"
    case Themes{}: "themes"

def rawSettings(manager: Settings.SettingsManager, scope: PackageManager.Scope) -> Settings.Settings:
  match scope:
    case PackageManager.UserScope{}: Settings.getGlobalSettings(manager)
    case PackageManager.ProjectScope{}: Settings.getProjectSettings(manager)

def selectedPaths(setting: Maybe<&2, Settings.Setting>, kind: ResourceType) -> Maybe<&2, List<&2, String>>:
  match kind:
    case Extensions{}: Settings.selectedExtensions(setting)
    case Skills{}: Settings.selectedSkills(setting)
    case Prompts{}: Settings.selectedPrompts(setting)
    case Themes{}: Settings.selectedThemes(setting)

def pathsOf(manager: Settings.SettingsManager, scope: PackageManager.Scope, +kind: ResourceType) -> List<&2, String>:
  Maybe.default(&2, List<&2, String>, selectedPaths(Settings.get(rawSettings(manager, scope), fieldName(kind)), kind), Nil{})

def setPaths(manager: Settings.SettingsManager, scope: PackageManager.Scope, kind: ResourceType, paths: List<&2, String>) -> Settings.Outcome(Settings.SettingsManager):
  match scope kind:
    case PackageManager.UserScope{} Extensions{}: Settings.setExtensionPaths(paths, manager)
    case PackageManager.UserScope{} Skills{}: Settings.setSkillPaths(paths, manager)
    case PackageManager.UserScope{} Prompts{}: Settings.setPromptTemplatePaths(paths, manager)
    case PackageManager.UserScope{} Themes{}: Settings.setThemePaths(paths, manager)
    case PackageManager.ProjectScope{} Extensions{}: Settings.setProjectExtensionPaths(paths, manager)
    case PackageManager.ProjectScope{} Skills{}: Settings.setProjectSkillPaths(paths, manager)
    case PackageManager.ProjectScope{} Prompts{}: Settings.setProjectPromptTemplatePaths(paths, manager)
    case PackageManager.ProjectScope{} Themes{}: Settings.setProjectThemePaths(paths, manager)

def patternTarget(entry: String) -> String:
  match entry:
    case SCon{'!', rest}: rest
    case SCon{'+', rest}: rest
    case SCon{'-', rest}: rest
    case other: other

def withoutPattern(values: List<&2, String>, +pattern: String) -> List<&2, String>:
  match values:
    case Nil{}: Nil{}
    case +value <> +rest:
      Bool.pick(Unit -> List<&2, String>, String.eq(patternTarget(value), pattern),
        _ => withoutPattern(rest, pattern),
        _ => value <> withoutPattern(rest, pattern))(Unit{})

def topLevelPattern(path: String, scope: PackageManager.Scope, base: Maybe<&2, String>, cwd: String, agentDir: String) -> String:
  match base scope:
    case Some{directory} _: Path.relative(directory, path)
    case None{} PackageManager.UserScope{}: Path.relative(agentDir, path)
    case None{} PackageManager.ProjectScope{}: Path.relative(Path.join(cwd, ".pi"), path)

def signedPattern(enabled: Bool, pattern: String) -> String:
  match enabled:
    case True{}: "+" ++ pattern
    case False{}: "-" ++ pattern

def toggleTopLevel(+manager: Settings.SettingsManager, item: Item, cwd: String, agentDir: String, enabled: Bool) -> Settings.Outcome(Settings.SettingsManager):
  match item:
    case Item{path, _, PackageManager.PathMetadata{_, +scope, base}, +kind, _, _, _}:
      +pattern = topLevelPattern(path, scope, base, cwd, agentDir)
      +existing = pathsOf(manager, scope, kind)
      setPaths(manager, scope, kind, List.append(&2, String, withoutPattern(existing, pattern), [signedPattern(enabled, pattern)]))

def packagesOf(manager: Settings.SettingsManager, scope: PackageManager.Scope) -> List<&2, Settings.PackageSource>:
  Maybe.default(&2, List<&2, Settings.PackageSource>, Settings.selectedPackages(Settings.get(rawSettings(manager, scope), "packages")), Nil{})

def filterPaths(filter: Settings.PackageFilter, kind: ResourceType) -> List<&2, String>:
  match filter kind:
    case Settings.PackageFilter{_, extensions, _, _, _} Extensions{}: Maybe.default(&2, List<&2, String>, extensions, Nil{})
    case Settings.PackageFilter{_, _, skills, _, _} Skills{}: Maybe.default(&2, List<&2, String>, skills, Nil{})
    case Settings.PackageFilter{_, _, _, prompts, _} Prompts{}: Maybe.default(&2, List<&2, String>, prompts, Nil{})
    case Settings.PackageFilter{_, _, _, _, themes} Themes{}: Maybe.default(&2, List<&2, String>, themes, Nil{})

def changedFilter(filter: Settings.PackageFilter, kind: ResourceType, paths: List<&2, String>) -> Settings.PackageFilter:
  match filter kind:
    case Settings.PackageFilter{autoload, _, skills, prompts, themes} Extensions{}: Settings.PackageFilter{autoload, Some{paths}, skills, prompts, themes}
    case Settings.PackageFilter{autoload, extensions, _, prompts, themes} Skills{}: Settings.PackageFilter{autoload, extensions, Some{paths}, prompts, themes}
    case Settings.PackageFilter{autoload, extensions, skills, _, themes} Prompts{}: Settings.PackageFilter{autoload, extensions, skills, Some{paths}, themes}
    case Settings.PackageFilter{autoload, extensions, skills, prompts, _} Themes{}: Settings.PackageFilter{autoload, extensions, skills, prompts, Some{paths}}

def defaultFilter() -> Settings.PackageFilter:
  Settings.PackageFilter{None{}, None{}, None{}, None{}, None{}}

def editedPackage(package: Settings.PackageSource, +kind: ResourceType, +pattern: String, +enabled: Bool) -> Settings.PackageSource:
  match package:
    case Settings.PackageName{source}:
      +filter = defaultFilter()
      +updated = List.append(&2, String, withoutPattern(filterPaths(filter, kind), pattern), [signedPattern(enabled, pattern)])
      Settings.FilteredPackage{source, changedFilter(filter, kind, updated), Record.new(Value.Value)}
    case Settings.FilteredPackage{source, +filter, unknown}:
      +updated = List.append(&2, String, withoutPattern(filterPaths(filter, kind), pattern), [signedPattern(enabled, pattern)])
      Settings.FilteredPackage{source, changedFilter(filter, kind, updated), unknown}

def editedPackages(packages: List<&2, Settings.PackageSource>, +source: String, +kind: ResourceType, +pattern: String, +enabled: Bool) -> List<&2, Settings.PackageSource>:
  match packages:
    case Nil{}: Nil{}
    case +package <> +rest:
      Bool.pick(Unit -> List<&2, Settings.PackageSource>, String.eq(PackageManager.sourceString(package), source),
        _ => editedPackage(package, kind, pattern, enabled) <> rest,
        _ => package <> editedPackages(rest, source, kind, pattern, enabled))(Unit{})

def storePackages(manager: Settings.SettingsManager, scope: PackageManager.Scope, packages: List<&2, Settings.PackageSource>) -> Settings.Outcome(Settings.SettingsManager):
  match scope:
    case PackageManager.UserScope{}: Settings.setPackages(packages, manager)
    case PackageManager.ProjectScope{}: Settings.setProjectPackages(packages, manager)

def togglePackage(+manager: Settings.SettingsManager, item: Item, enabled: Bool) -> Settings.Outcome(Settings.SettingsManager):
  match item:
    case Item{+path, _, PackageManager.PathMetadata{PackageManager.Package{source}, +scope, base}, kind, _, _, _}:
      +pattern = Path.relative(Maybe.default(&2, String, base, Path.dirname(path)), path)
      +packages = editedPackages(packagesOf(manager, scope), source, kind, pattern, enabled)
      storePackages(manager, scope, packages)
    case _: Done{manager}

def sameItem(left: Item, right: Item) -> Bool:
  match left right:
    case Item{leftPath, _, _, leftKind, _, _, _} Item{rightPath, _, _, rightKind, _, _, _}:
      String.eq(Path.normalize(leftPath), Path.normalize(rightPath)) && String.eq(kindOrder(leftKind), kindOrder(rightKind))

def enabledOf(item: Item) -> Bool:
  match item:
    case Item{_, enabled, _, _, _, _, _}: enabled

def inheritedEnabled(values: List<&2, Item>, +item: Item) -> Bool:
  match values:
    case Nil{}: enabledOf(item)
    case +current <> rest:
      Bool.pick(Unit -> Bool, sameItem(current, item),
        _ => enabledOf(current),
        _ => inheritedEnabled(rest, item))(Unit{})

def overrideEntry(entry: String) -> Override:
  match entry:
    case SCon{'!', _}: Unload{}
    case SCon{'-', _}: Unload{}
    case _: Load{}

def overrideFromEntries(entries: List<&2, String>, +pattern: String, current: Override) -> Override:
  match entries:
    case Nil{}: current
    case +entry <> rest: overrideFromEntries(rest, pattern, Bool.pick(Override, String.eq(patternTarget(entry), pattern), overrideEntry(entry), current))

def nextOverride(current: Override, inherited: Bool) -> Override:
  match current inherited:
    case Inherit{} True{}: Unload{}
    case Inherit{} False{}: Load{}
    case Unload{} True{}: Load{}
    case Unload{} False{}: Inherit{}
    case Load{} True{}: Inherit{}
    case Load{} False{}: Unload{}

def containsItem(values: List<&2, Item>, +item: Item) -> Bool:
  match values:
    case Nil{}: False{}
    case value <> rest: sameItem(value, item) || containsItem(rest, item)

def isInheritedItem(item: Item, global: List<&2, Item>) -> Bool:
  match item:
    case Item{_, _, PackageManager.PathMetadata{_, PackageManager.UserScope{}, _}, _, _, _, _}: True{}
    case other: containsItem(global, other)

def projectPattern(item: Item, cwd: String) -> String:
  match item:
    case Item{path, _, PackageManager.PathMetadata{_, PackageManager.UserScope{}, _}, _, _, _, _}: path
    case Item{path, _, PackageManager.PathMetadata{_, PackageManager.ProjectScope{}, Some{base}}, _, _, _, _}: Path.relative(base, path)
    case Item{path, _, _, _, _, _, _}: Path.relative(Path.join(cwd, ".pi"), path)

def projectAliases(+item: Item, +cwd: String) -> List<&2, String>:
  match item:
    case Item{+path, _, PackageManager.PathMetadata{_, _, base}, _, _, _, _}:
      +project = Path.join(cwd, ".pi")
      projectPattern(item, cwd) <> path <> Path.relative(project, path) <> Maybe.default(&2, List<&2, String>, Maybe.map(&2, String, List<&2, String>, directory => [Path.relative(directory, path)], base), Nil{})

def anyPattern(aliases: List<&2, String>, +target: String) -> Bool:
  match aliases:
    case Nil{}: False{}
    case alias <> rest: String.eq(alias, target) || anyPattern(rest, target)

def overrideAliases(entries: List<&2, String>, +aliases: List<&2, String>, current: Override) -> Override:
  match entries:
    case Nil{}: current
    case +entry <> rest:
      +next = Bool.pick(Override, anyPattern(aliases, patternTarget(entry)), overrideEntry(entry), current)
      overrideAliases(rest, aliases, next)

def signedEntry(entry: String) -> Bool:
  match entry:
    case SCon{'!', _}: True{}
    case SCon{'-', _}: True{}
    case SCon{'+', _}: True{}
    case _: False{}

def removeOverrides(entries: List<&2, String>, +aliases: List<&2, String>, +plainPattern: String, +removePlain: Bool) -> List<&2, String>:
  match entries:
    case Nil{}: Nil{}
    case +entry <> +rest:
      +remove = anyPattern(aliases, patternTarget(entry)) && (signedEntry(entry) || (removePlain && String.eq(entry, plainPattern)))
      Bool.pick(Unit -> List<&2, String>, remove,
        _ => removeOverrides(rest, aliases, plainPattern, removePlain),
        _ => entry <> removeOverrides(rest, aliases, plainPattern, removePlain))(Unit{})

def withOverride(entries: List<&2, String>, +pattern: String, inherited: Bool, choice: Override) -> List<&2, String>:
  match choice:
    case Inherit{}: entries
    case Load{}: List.append(&2, String, entries, Bool.pick(List<&2, String>, inherited, [pattern, "+" ++ pattern], ["+" ++ pattern]))
    case Unload{}: List.append(&2, String, entries, Bool.pick(List<&2, String>, inherited, [pattern, "-" ++ pattern], ["-" ++ pattern]))

def choiceIsInherit(choice: Override) -> Bool:
  match choice:
    case Inherit{}: True{}
    case _: False{}

def projectTopLevel(+manager: Settings.SettingsManager, +item: Item, global: List<&2, Item>, +cwd: String, +choice: Override) -> Settings.Outcome(Settings.SettingsManager):
  match item:
    case Item{_, _, _, +kind, _, _, _}:
      +inherited = isInheritedItem(item, global)
      +pattern = projectPattern(item, cwd)
      +current = pathsOf(manager, PackageManager.ProjectScope{}, kind)
      +filtered = removeOverrides(current, projectAliases(item, cwd), pattern, Bool.pick(Bool, choiceIsInherit(choice), inherited, False{}))
      setPaths(manager, PackageManager.ProjectScope{}, kind, withOverride(filtered, pattern, inherited, choice))

def scopeBase(scope: PackageManager.Scope, cwd: String, agentDir: String) -> String:
  match scope:
    case PackageManager.UserScope{}: agentDir
    case PackageManager.ProjectScope{}: Path.join(cwd, ".pi")

def sourcePath(+source: String, scope: PackageManager.Scope, cwd: String, agentDir: String) -> String:
  +base = scopeBase(scope, cwd, agentDir)
  +name = Bool.pick(String, String.starts_with(source, "file:"), String.drop(source, 5n), source)
  Maybe.default(&2, String, Path.resolve(base, name), source)

def sourceMatches(+left: String, leftScope: PackageManager.Scope, +right: String, rightScope: PackageManager.Scope, +cwd: String, +agentDir: String) -> Bool:
  String.eq(left, right) || (Paths.isLocalPath(left) && Paths.isLocalPath(right) && String.eq(sourcePath(left, leftScope, cwd, agentDir), sourcePath(right, rightScope, cwd, agentDir)))

def packageSource(item: Item) -> String:
  match item:
    case Item{_, _, PackageManager.PathMetadata{PackageManager.Package{source}, _, _}, _, _, _, _}: source
    case _: ""

def packageScope(item: Item) -> PackageManager.Scope:
  match item:
    case Item{_, _, PackageManager.PathMetadata{_, scope, _}, _, _, _, _}: scope

def resourceKind(item: Item) -> ResourceType:
  match item:
    case Item{_, _, _, kind, _, _, _}: kind

def matchingPackage(packages: List<&2, Settings.PackageSource>, +source: String, +scope: PackageManager.Scope, +cwd: String, +agentDir: String) -> Maybe<&2, Settings.PackageSource>:
  match packages:
    case Nil{}: None{}
    case +package <> rest:
      Bool.pick(Unit -> Maybe<&2, Settings.PackageSource>, sourceMatches(source, scope, PackageManager.sourceString(package), PackageManager.ProjectScope{}, cwd, agentDir),
        _ => Some{package},
        _ => matchingPackage(rest, source, scope, cwd, agentDir))(Unit{})

def projectPackagePattern(item: Item) -> String:
  match item:
    case Item{+path, _, PackageManager.PathMetadata{_, _, base}, _, _, _, _}:
      Path.relative(Maybe.default(&2, String, base, Path.dirname(path)), path)

def packageFilter(package: Settings.PackageSource) -> Settings.PackageFilter:
  match package:
    case Settings.PackageName{_}: defaultFilter()
    case Settings.FilteredPackage{_, filter, _}: filter

def disabledAutoload(filter: Settings.PackageFilter) -> Bool:
  match filter:
    case Settings.PackageFilter{Some{False{}}, _, _, _, _}: True{}
    case _: False{}

def packageOverride(package: Maybe<&2, Settings.PackageSource>, kind: ResourceType, pattern: String) -> Override:
  match package:
    case None{}: Inherit{}
    case Some{value}:
      +filter = packageFilter(value)
      +entries = filterPaths(filter, kind)
      +emptyIsUnload = disabledAutoload(filter) && List.is_empty(&2, String, entries)
      overrideFromEntries(entries, pattern, Bool.pick(Override, emptyIsUnload, Unload{}, Inherit{}))

def projectOverride(manager: Settings.SettingsManager, +item: Item, cwd: String, agentDir: String) -> Override:
  match item:
    case Item{_, _, PackageManager.PathMetadata{PackageManager.Package{source}, scope, _}, kind, _, _, _}:
      packageOverride(matchingPackage(packagesOf(manager, PackageManager.ProjectScope{}), source, scope, cwd, agentDir), kind, projectPackagePattern(item))
    case Item{_, _, _, kind, _, _, _}:
      overrideAliases(pathsOf(manager, PackageManager.ProjectScope{}, kind), projectAliases(item, cwd), Inherit{})

def changedFilterOption(filter: Settings.PackageFilter, kind: ResourceType, paths: Maybe<&2, List<&2, String>>) -> Settings.PackageFilter:
  match filter kind:
    case Settings.PackageFilter{autoload, _, skills, prompts, themes} Extensions{}: Settings.PackageFilter{autoload, paths, skills, prompts, themes}
    case Settings.PackageFilter{autoload, extensions, _, prompts, themes} Skills{}: Settings.PackageFilter{autoload, extensions, paths, prompts, themes}
    case Settings.PackageFilter{autoload, extensions, skills, _, themes} Prompts{}: Settings.PackageFilter{autoload, extensions, skills, paths, themes}
    case Settings.PackageFilter{autoload, extensions, skills, prompts, _} Themes{}: Settings.PackageFilter{autoload, extensions, skills, prompts, paths}

def hasResourceFilters(filter: Settings.PackageFilter) -> Bool:
  match filter:
    case Settings.PackageFilter{_, None{}, None{}, None{}, None{}}: False{}
    case _: True{}

def optionalEntries(entries: List<&2, String>) -> Maybe<&2, List<&2, String>>:
  match entries:
    case Nil{}: None{}
    case values: Some{values}

def addedOverride(entries: List<&2, String>, pattern: String, choice: Override) -> List<&2, String>:
  match choice:
    case Inherit{}: entries
    case Load{}: List.append(&2, String, entries, [signedPattern(True{}, pattern)])
    case Unload{}: List.append(&2, String, entries, [signedPattern(False{}, pattern)])

def finishedPackage(source: String, unknown: Record.Record<Value.Value>, updated: Settings.PackageFilter) -> Maybe<&2, Settings.PackageSource>:
  match updated:
    case Settings.PackageFilter{Some{False{}}, None{}, None{}, None{}, None{}}: None{}
    case Settings.PackageFilter{_, None{}, None{}, None{}, None{}}: Some{Settings.PackageName{source}}
    case other: Some{Settings.FilteredPackage{source, other, unknown}}

def modifiedProjectPackage(package: Settings.PackageSource, +kind: ResourceType, +pattern: String, +choice: Override) -> Maybe<&2, Settings.PackageSource>:
  match package:
    case Settings.PackageName{+source}:
      +filter = changedFilterOption(defaultFilter(), kind, optionalEntries(addedOverride(Nil{}, pattern, choice)))
      Bool.pick(Maybe<&2, Settings.PackageSource>, hasResourceFilters(filter), Some{Settings.FilteredPackage{source, filter, Record.new(Value.Value)}}, Some{Settings.PackageName{source}})
    case Settings.FilteredPackage{source, +filter, unknown}:
      +current = filterPaths(filter, kind)
      +paths = addedOverride(withoutPattern(current, pattern), pattern, choice)
      +updated = changedFilterOption(filter, kind, optionalEntries(paths))
      finishedPackage(source, unknown, updated)

def replacedPackage(updated: Maybe<&2, Settings.PackageSource>, rest: List<&2, Settings.PackageSource>) -> List<&2, Settings.PackageSource>:
  match updated:
    case None{}: rest
    case Some{value}: value <> rest

def newProjectPackage(item: Item, +cwd: String, agentDir: String) -> Settings.PackageSource:
  match item:
    case Item{_, _, PackageManager.PathMetadata{PackageManager.Package{+source}, scope, _}, _, _, _, _}:
      +projectBase = Path.join(cwd, ".pi")
      +normalized = Bool.pick(String, Paths.isLocalPath(source), Path.relative(projectBase, sourcePath(source, scope, cwd, agentDir)), source)
      Settings.FilteredPackage{normalized, Settings.PackageFilter{Some{False{}}, None{}, None{}, None{}, None{}}, Record.new(Value.Value)}
    case _: Settings.PackageName{""}

def createProjectPackage(+item: Item, cwd: String, agentDir: String, choice: Override) -> List<&2, Settings.PackageSource>:
  match choice:
    case Inherit{}: Nil{}
    case _:
      replacedPackage(modifiedProjectPackage(newProjectPackage(item, cwd, agentDir), resourceKind(item), projectPackagePattern(item), choice), Nil{})

def changedProjectPackages(packages: List<&2, Settings.PackageSource>, +item: Item, +cwd: String, +agentDir: String, +choice: Override) -> List<&2, Settings.PackageSource>:
  match packages:
    case Nil{}: createProjectPackage(item, cwd, agentDir, choice)
    case +package <> +rest:
      +source = packageSource(item)
      +scope = packageScope(item)
      Bool.pick(Unit -> List<&2, Settings.PackageSource>, sourceMatches(source, scope, PackageManager.sourceString(package), PackageManager.ProjectScope{}, cwd, agentDir),
        _ => replacedPackage(modifiedProjectPackage(package, resourceKind(item), projectPackagePattern(item), choice), rest),
        _ => package <> changedProjectPackages(rest, item, cwd, agentDir, choice))(Unit{})

def projectPackage(+manager: Settings.SettingsManager, item: Item, cwd: String, agentDir: String, choice: Override) -> Settings.Outcome(Settings.SettingsManager):
  Settings.setProjectPackages(changedProjectPackages(packagesOf(manager, PackageManager.ProjectScope{}), item, cwd, agentDir, choice), manager)

def projectChange(manager: Settings.SettingsManager, item: Item, global: List<&2, Item>, cwd: String, agentDir: String, choice: Override) -> Settings.Outcome(Settings.SettingsManager):
  match item:
    case Item{_, _, PackageManager.PathMetadata{PackageManager.Package{_}, _, _}, _, _, _, _}: projectPackage(manager, item, cwd, agentDir, choice)
    case _: projectTopLevel(manager, item, global, cwd, choice)

def globalChange(manager: Settings.SettingsManager, item: Item, cwd: String, agentDir: String, enabled: Bool) -> Settings.Outcome(Settings.SettingsManager):
  match item:
    case Item{_, _, PackageManager.PathMetadata{PackageManager.Package{_}, _, _}, _, _, _, _}: togglePackage(manager, item, enabled)
    case _: toggleTopLevel(manager, item, cwd, agentDir, enabled)

def selectedItem(values: List<&2, Entry>, index: Nat) -> Maybe<&2, Item>:
  match values index:
    case Nil{} _: None{}
    case ResourceRow{item} <> _ Zero{}: Some{item}
    case ResourceRow{_} <> rest Succ{previous}: selectedItem(rest, previous)
    case _ <> rest count: selectedItem(rest, count)

def enabledItem(item: Item, enabled: Bool) -> Item:
  match item:
    case Item{path, _, metadata, kind, name, key, label}: Item{path, enabled, metadata, kind, name, key, label}

def updateItems(values: List<&2, Item>, +target: Item, +enabled: Bool) -> List<&2, Item>:
  match values:
    case Nil{}: Nil{}
    case +item <> +rest:
      Bool.pick(Unit -> List<&2, Item>, sameItem(item, target),
        _ => enabledItem(item, enabled) <> rest,
        _ => item <> updateItems(rest, target, enabled))(Unit{})

def updatedState(state: State, item: Item, enabled: Bool) -> State:
  match state:
    case State{global, project, Global{}, available, query, selected, maxVisible, inherited}:
      State{updateItems(global, item, enabled), project, Global{}, available, query, selected, maxVisible, inherited}
    case State{global, project, Project{}, available, query, selected, maxVisible, inherited}:
      State{global, updateItems(project, item, enabled), Project{}, available, query, selected, maxVisible, inherited}

def changedState(state: State, item: Item, enabled: Bool, result: Settings.Outcome(Settings.SettingsManager)) -> Settings.Outcome(Changed):
  match result:
    case Fail{error}: Fail{error}
    case Done{manager}: Done{Changed{updatedState(state, item, enabled), manager}}

def choiceIsLoad(choice: Override) -> Bool:
  match choice:
    case Load{}: True{}
    case _: False{}

def globalSelected(state: State, manager: Settings.SettingsManager, +item: Item, cwd: String, agentDir: String) -> Settings.Outcome(Changed):
  match item:
    case Item{_, +enabled, PackageManager.PathMetadata{_, PackageManager.UserScope{}, _}, _, _, _, _}:
      changedState(state, item, Bool.not(enabled), globalChange(manager, item, cwd, agentDir, Bool.not(enabled)))
    case _: Done{Changed{state, manager}}

def selectedChange(+state: State, +manager: Settings.SettingsManager, +item: Item, +cwd: String, +agentDir: String) -> Settings.Outcome(Changed):
  match state:
    case State{_, _, Global{}, _, _, _, _, _}: globalSelected(state, manager, item, cwd, agentDir)
    case State{global, _, Project{}, _, _, _, _, +baseline}:
      +inherited = inheritedEnabled(baseline, item)
      +choice = nextOverride(projectOverride(manager, item, cwd, agentDir), inherited)
      +enabled = Bool.pick(Bool, choiceIsInherit(choice), inherited, choiceIsLoad(choice))
      changedState(state, item, enabled, projectChange(manager, item, baseline, cwd, agentDir, choice))

def changeSelectedResult(value: Maybe<&2, Item>, state: State, manager: Settings.SettingsManager, cwd: String, agentDir: String) -> Settings.Outcome(Changed):
  match value:
    case None{}: Done{Changed{state, manager}}
    case Some{item}: selectedChange(state, manager, item, cwd, agentDir)

def changeSelected(+state: State, manager: Settings.SettingsManager, cwd: String, agentDir: String) -> Settings.Outcome(Changed):
  changeSelectedResult(selectedItem(visible(state), selectedOf(state)), state, manager, cwd, agentDir)

def flatSelection(values: List<&2, Entry>, selected: Nat, offset: Nat) -> Nat:
  match values selected:
    case Nil{} _: 0n
    case ResourceRow{_} <> _ Zero{}: offset
    case ResourceRow{_} <> rest Succ{index}: flatSelection(rest, index, offset + 1n)
    case _ <> rest index: flatSelection(rest, index, offset + 1n)

# Page movement counts the displayed headers as well as resources, then
# chooses the first item after an upward target or the last before a downward target.
def pageTarget(values: List<&2, Entry>, +target: Nat, +offset: Nat, +itemIndex: Nat, previous: Nat, +down: Bool) -> Nat:
  match values:
    case Nil{}: previous
    case ResourceRow{_} <> rest:
      Bool.pick(Unit -> Nat, Nat.is_ge(offset, target),
        _ => Bool.pick(Nat, down && Nat.is_gt(offset, target), previous, itemIndex),
        _ => pageTarget(rest, target, offset + 1n, itemIndex + 1n, itemIndex, down))(Unit{})
    case _ <> rest: pageTarget(rest, target, offset + 1n, itemIndex, previous, down)

def page(+state: State, +down: Bool) -> State:
  +rows = visible(state)
  +position = flatSelection(rows, selectedOf(state), 0n)
  +target = Bool.pick(Nat, down, Nat.min(position + pageSize(state), List.length(&2, Entry, rows) - 1n), position - pageSize(state))
  withSelected(state, pageTarget(rows, target, 0n, 0n, selectedOf(state), down))

def windowStart(total: Nat, selected: Nat, +maxVisible: Nat) -> Nat:
  Nat.min(selected - Nat.div(maxVisible, 2n), total - maxVisible)

def scopeLabel(scope: WriteScope) -> String:
  match scope:
    case Global{}: "Global Resources"
    case Project{}: "Project Local Resources"

def scopeFile(scope: WriteScope) -> String:
  match scope:
    case Global{}: "~/.pi/agent/settings.json"
    case Project{}: ".pi/settings.json · inherited global resources are dimmed"

def actionHint(scope: WriteScope, theme: Theme.Theme) -> String:
  match scope:
    case Global{}: Hints.rawKeyHint(theme, "space", "toggle")
    case Project{}: Hints.rawKeyHint(theme, "space", "cycle inherit/+/-")

def header(state: State, +theme: Theme.Theme, +width: Nat) -> List<&2, String>:
  match state:
    case State{_, _, +scope, available, _, _, _, _}:
      +title = Theme.bold(scopeLabel(scope))
      +separator = Theme.fg(theme, "muted", " · ")
      +tab = Bool.pick(String, available, Hints.rawKeyHint(theme, "tab", "switch mode") ++ separator, "")
      +hint = tab ++ actionHint(scope, theme) ++ separator ++ Hints.rawKeyHint(theme, "esc", "close")
      +spacing = Utils.spaces(Nat.max(1n, width - Utils.visibleWidth(title) - Utils.visibleWidth(hint)), "")
      [Utils.truncateToWidth(title ++ spacing ++ hint, width, "", False{}),
       Utils.truncateToWidth(Theme.fg(theme, "muted", scopeFile(scope)), width, "", False{})]

def projectCheckbox(choice: Override, enabled: Bool, theme: Theme.Theme) -> String:
  match choice:
    case Load{}: Theme.fg(theme, "success", "[+]")
    case Unload{}: Theme.fg(theme, "warning", "[-]")
    case Inherit{}: Theme.fg(theme, "dim", Bool.pick(String, enabled, "[x]", "[ ]"))

def checkbox(+item: Item, scope: WriteScope, manager: Settings.SettingsManager, cwd: String, agentDir: String, theme: Theme.Theme) -> String:
  match scope:
    case Global{}: Theme.fg(theme, Bool.pick(String, enabledOf(item), "success", "dim"), Bool.pick(String, enabledOf(item), "[x]", "[ ]"))
    case Project{}: projectCheckbox(projectOverride(manager, item, cwd, agentDir), enabledOf(item), theme)

def projectSuffix(choice: Override, inherited: Bool, theme: Theme.Theme) -> String:
  match choice:
    case Load{}: Theme.fg(theme, "muted", "  project load")
    case Unload{}: Theme.fg(theme, "muted", "  project unload")
    case Inherit{}: Bool.pick(String, inherited, Theme.fg(theme, "dim", "  inherited global"), "")

def suffix(+item: Item, scope: WriteScope, global: List<&2, Item>, manager: Settings.SettingsManager, cwd: String, agentDir: String, theme: Theme.Theme) -> String:
  match scope:
    case Global{}: ""
    case Project{}: projectSuffix(projectOverride(manager, item, cwd, agentDir), isInheritedItem(item, global), theme)

def isProject(scope: WriteScope) -> Bool:
  match scope:
    case Project{}: True{}
    case Global{}: False{}

def itemName(item: Item) -> String:
  match item:
    case Item{_, _, _, _, name, _, _}: name

def renderedEntry(entry: Entry, +selected: Bool, +scope: WriteScope, +global: List<&2, Item>, +manager: Settings.SettingsManager, +cwd: String, +agentDir: String, +theme: Theme.Theme, width: Nat) -> String:
  match entry:
    case GroupHeader{label, +inherited}:
      Utils.truncateToWidth("  " ++ Theme.fg(theme, Bool.pick(String, inherited, "dim", "accent"), Theme.bold(label ++ Bool.pick(String, inherited, " · inherited global", ""))), width, "", False{})
    case SubgroupHeader{kind, inherited}:
      Utils.truncateToWidth("    " ++ Theme.fg(theme, Bool.pick(String, inherited, "dim", "muted"), kindName(kind)), width, "", False{})
    case ResourceRow{+item}:
      +dimmed = Bool.pick(Bool, isProject(scope), isInheritedItem(item, global) && choiceIsInherit(projectOverride(manager, item, cwd, agentDir)), False{})
      +name = itemName(item)
      +text = Bool.pick(String, selected && Bool.not(dimmed), Theme.bold(name), name)
      +colored = Bool.pick(String, dimmed, Theme.fg(theme, "dim", text), text)
      +cursor = Bool.pick(String, selected, "> ", "  ")
      Utils.truncateToWidth(cursor ++ "    " ++ checkbox(item, scope, manager, cwd, agentDir, theme) ++ " " ++ colored ++ suffix(item, scope, global, manager, cwd, agentDir, theme), width, "...", False{})

def renderWindow(values: List<&2, Entry>, +start: Nat, count: Nat, +offset: Nat, +selected: Nat, +scope: WriteScope, +global: List<&2, Item>, +manager: Settings.SettingsManager, +cwd: String, +agentDir: String, +theme: Theme.Theme, +width: Nat) -> List<&2, String>:
  match values count:
    case Nil{} _: Nil{}
    case _ Zero{}: Nil{}
    case +entry <> +rest +visible:
      Bool.pick(Unit -> List<&2, String>, Nat.is_lt(offset, start),
        _ => renderWindow(rest, start, visible, offset + 1n, selected, scope, global, manager, cwd, agentDir, theme, width),
        _ => renderedEntry(entry, Nat.is_eq(offset, selected), scope, global, manager, cwd, agentDir, theme, width) <>
          renderWindow(rest, start, visible - 1n, offset + 1n, selected, scope, global, manager, cwd, agentDir, theme, width))(Unit{})

def rule(width: Nat) -> String:
  match width:
    case Zero{}: ""
    case Succ{rest}: "─" ++ rule(rest)

def lines(+state: State, +manager: Settings.SettingsManager, +cwd: String, +agentDir: String, +theme: Theme.Theme, +width: Nat, searchLine: String) -> List<&2, String>:
  match state:
    case State{+global, _, +scope, _, _, +selected, +maxVisible, _}:
      +rows = visible(state)
      +total = List.length(&2, Entry, rows)
      +position = flatSelection(rows, selected, 0n)
      +start = windowStart(total, position, maxVisible)
      +entries = Bool.pick(List<&2, String>, Nat.is_eq(total, 0n), [Theme.fg(theme, "muted", "  No resources found")], renderWindow(rows, start, maxVisible, 0n, position, scope, global, manager, cwd, agentDir, theme, width))
      +scroll = Bool.pick(List<&2, String>, Nat.is_gt(start, 0n) || Nat.is_lt(start + maxVisible, total), [Theme.fg(theme, "dim", "  (" ++ Nat.show(selected + 1n) ++ "/" ++ Nat.show(rowCount(rows)) ++ ")")], Nil{})
      +rule = Theme.fg(theme, "border", rule(width))
      "" <> rule <> "" <> List.append(&2, String, header(state, theme, width), "" <> searchLine <> "" <> List.append(&2, String, entries, List.append(&2, String, scroll, "" <> rule <> Nil{})))

def withHeight(state: State, height: Nat) -> State:
  match state:
    case State{global, project, scope, available, query, selected, _, inherited}:
      State{global, project, scope, available, query, selected, Nat.max(5n, height - 8n), inherited}
