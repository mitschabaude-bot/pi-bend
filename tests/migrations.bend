import Base
import ../packages/coding-agent/src/migrations.bend as Migrations
import ../packages/coding-agent/src/core/keybindings.bend as Keybindings

# Runs upstream runMigrations(cwd) for <agentDir> <cwd> and prints its result
# (tests/migrations_check.py compares the resulting trees and output with the
# pinned upstream function run on a copy of the same fixture).

def printed(result: Migrations.MigrationResult) -> IO(Unit):
  match result:
    case Migrations.MigrationResult{providers, warnings}:
      do IO<Unit>:
        IO.print("migratedAuthProviders: " ++ String.join(providers, ","))
        IO.print("deprecationWarnings: " ++ String.join(warnings, " | "))

def started(args: List<String>) -> IO(Unit):
  match args:
    case agentDir <> cwd <> Nil{}:
      do IO<Unit>:
        result : Migrations.MigrationResult <- Migrations.runMigrations(Migrations.Stdout{}, agentDir, cwd, Keybindings.Environment{"linux", None{}, None{}})
        printed(result)
    case _: IO.die(Unit, 2, "usage: migrations <agentDir> <cwd>")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    started(args)
