import Base

# This boundary exposes OS/library operations only. Agent policy, JSON,
# provider messages and tool behavior belong in Bend.
def call(op: U32, a: String, b: String, c: String, n: Nat) -> IO(Result<&1, &1, U32 & String, String>):
  import "./native/runtime.c"

def require(result: Result<&1, &1, U32 & String, String>) -> IO(String):
  IO.pass(String, result)

def run(op: U32, a: String, b: String, c: String, n: Nat) -> IO(String):
  IO.try(String, call(op, a, b, c, n))

def arg(n: Nat) -> IO(String): run(1, "", "", "", n)
def argc() -> IO(String): run(2, "", "", "", 0n)
def cwd() -> IO(String): run(3, "", "", "", 0n)
def read(path: String) -> IO(Result<&1, &1, U32 & String, String>): call(4, path, "", "", 0n)
def write(path: String, text: String) -> IO(Result<&1, &1, U32 & String, String>): call(5, path, text, "", 0n)
def append(path: String, text: String) -> IO(Result<&1, &1, U32 & String, String>): call(5, path, text, "", 1n)
def home() -> IO(String): IO.try(String, IO.get_env("HOME"))
def http(url: String, headers: String, body: String, timeout_ms: Nat) -> IO(String): run(10, url, headers, body, timeout_ms)
def next(handle: String) -> IO(Result<&1, &1, U32 & String, String>): call(11, handle, "", "", 0n)
def close(handle: String) -> IO(String): run(12, handle, "", "", 0n)
def status(handle: String) -> IO(String): run(13, handle, "", "", 0n)
def spawn(command: String, cwd: String, timeout_ms: Nat) -> IO(Result<&1, &1, U32 & String, String>): call(20, command, cwd, "", timeout_ms)
def terminal() -> IO(String): run(30, "", "", "", 0n)
def input() -> IO(String): run(31, "", "", "", 0n)
def restore() -> IO(String): run(32, "", "", "", 0n)
def dimensions() -> IO(String): run(33, "", "", "", 0n)
def uuid() -> IO(String): run(40, "", "", "", 0n)
def epoch() -> IO(String): run(41, "", "", "", 0n)
def timestamp() -> IO(String): run(46, "", "", "", 0n)
def cancelled() -> IO(String): run(42, "", "", "", 0n)
def chdir(path: String) -> IO(String): run(43, path, "", "", 0n)
def atomic_write(path: String, text: String, mode: Nat) -> IO(Result<&1, &1, U32 & String, String>): call(44, path, text, "", mode)
def segments(text: String) -> IO(String): run(50, text, "", "", 0n)
def words(text: String) -> IO(String): run(50, text, "", "", 1n)
