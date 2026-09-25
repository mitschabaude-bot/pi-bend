import Base
import ../config.bend as Config

# upstream core/slash-commands.ts: the interactive built-in commands, in the
# order autocomplete lists them.
type BuiltinSlashCommand is Data:
  BuiltinSlashCommand{name: String, description: String, argumentHint: Maybe<&2, String>}

def plain(name: String, description: String) -> BuiltinSlashCommand: BuiltinSlashCommand{name, description, None{}}
def hinted(name: String, description: String, hint: String) -> BuiltinSlashCommand: BuiltinSlashCommand{name, description, Some{hint}}

def BUILTIN_SLASH_COMMANDS() -> List<&2, BuiltinSlashCommand>:
  [plain("settings", "Open settings menu"),
   hinted("model", "Select model (opens selector UI)", "<provider/model>"),
   plain("tree", "Navigate session tree (switch branches)"),
   hinted("thinking", "Set thinking level", "<level>"),
   plain("scoped-models", "Enable/disable models for Ctrl+P cycling"),
   plain("export", "Export session (HTML default, or specify path: .html/.jsonl)"),
   plain("import", "Import and resume a session from a JSONL file"),
   plain("share", "Share session as a secret GitHub gist"),
   hinted("bug", "Report a bug to the Pi developers", "<description>"),
   plain("copy", "Copy last agent message to clipboard"),
   plain("name", "Set session display name"),
   plain("session", "Show session info and stats"),
   plain("changelog", "Show changelog entries"),
   plain("hotkeys", "Show all keyboard shortcuts"),
   plain("fork", "Create a new fork from a previous user message"),
   plain("clone", "Duplicate the current session at the current position"),
   plain("trust", "Save project trust decision for future sessions"),
   hinted("login", "Configure provider authentication", "<provider>"),
   plain("logout", "Remove provider authentication"),
   plain("new", "Start a new session"),
   plain("compact", "Manually compact the session context"),
   plain("resume", "Resume a different session"),
   plain("reload", "Reload keybindings, extensions, skills, prompts, themes, and context files"),
   plain("quit", "Quit " ++ Config.appName())]
