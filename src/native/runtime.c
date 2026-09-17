/* Native OS boundary for pi-bend. No provider or agent logic lives here. */
#include <curl/curl.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <sys/ioctl.h>
#include <sys/random.h>
#include <termios.h>
#include <signal.h>
#include <dirent.h>

typedef struct {
  char *data;
  size_t size, cap;
} PbBuffer;

static void pb_add(PbBuffer *b, const void *s, size_t n) {
  if (n > SIZE_MAX - b->size - 1) abort();
  if (b->size + n + 1 > b->cap) {
    b->cap = (b->size + n + 1) * 2;
    b->data = io_mem(realloc(b->data, b->cap));
  }
  memcpy(b->data + b->size, s, n);
  b->size += n;
  b->data[b->size] = 0;
}

typedef struct {
  uint32_t op, error;
  uint64_t n;
  char *a, *b, *c;
  size_t alen, blen, clen;
  PbBuffer out;
} PbCall;

typedef struct {
  int read_fd, write_fd, kind;
  pid_t pid;
  pthread_t thread;
  _Atomic int cancel;
  int finished, code;
  long status;
  uint64_t deadline;
  char *url, *headers, *body;
  size_t body_len;
  char error[CURL_ERROR_SIZE];
  unsigned char carry[4];
  size_t carry_len;
} PbStream;

#define PB_MAX_STREAMS 256
static PbStream *pb_streams[PB_MAX_STREAMS];
static pthread_mutex_t pb_stream_lock = PTHREAD_MUTEX_INITIALIZER;
static int pb_argc;
static char **pb_argv;
static struct termios pb_saved_terminal;
static int pb_terminal_active;
static volatile sig_atomic_t pb_interrupted;

static void pb_restore(void) {
  if (pb_terminal_active) tcsetattr(STDIN_FILENO, TCSAFLUSH, &pb_saved_terminal);
  pb_terminal_active = 0;
}

static void pb_signal(int sig) { (void)sig; pb_interrupted = 1; }

static void __attribute__((constructor)) pb_init(int argc, char **argv) {
  pb_argc = argc;
  pb_argv = argv;
  curl_global_init(CURL_GLOBAL_DEFAULT);
  signal(SIGPIPE, SIG_IGN);
  signal(SIGINT, pb_signal);
  atexit(pb_restore);
}

static int pb_write_all(int fd, const void *s, size_t n) {
  const char *p = s;
  while (n) {
    ssize_t k = write(fd, p, n);
    if (k < 0 && errno == EINTR) continue;
    if (k <= 0) return -1;
    p += k; n -= (size_t)k;
  }
  return 0;
}

static int pb_parents(const char *path) {
  char *copy = strdup(path);
  if (!copy) return ENOMEM;
  for (char *p = copy + 1; *p; p++) {
    if (*p != '/') continue;
    *p = 0;
    if (mkdir(copy, 0700) && errno != EEXIST) { int err = errno; free(copy); return err; }
    *p = '/';
  }
  free(copy);
  return 0;
}

static void pb_num(PbBuffer *b, long long n) {
  char s[32]; int k = snprintf(s, sizeof s, "%lld", n); pb_add(b, s, (size_t)k);
}

static PbStream *pb_handle(const char *id) {
  char *end;
  unsigned long n = strtoul(id, &end, 10);
  if (!*id || *end || n == 0 || n >= PB_MAX_STREAMS) return NULL;
  return pb_streams[n];
}

static int pb_register(PbStream *s) {
  pthread_mutex_lock(&pb_stream_lock);
  int id;
  for (id = 1; id < PB_MAX_STREAMS && pb_streams[id]; id++) {}
  if (id < PB_MAX_STREAMS) pb_streams[id] = s;
  pthread_mutex_unlock(&pb_stream_lock);
  return id < PB_MAX_STREAMS ? id : -1;
}

static size_t pb_curl_write(char *data, size_t size, size_t n, void *arg) {
  PbStream *s = arg;
  size_t total = size * n, at = 0;
  while (at < total) {
    if (atomic_load(&s->cancel)) return 0;
    struct pollfd p = { s->write_fd, POLLOUT, 0 };
    int ready = poll(&p, 1, 100);
    if (ready < 0 && errno == EINTR) continue;
    if (ready < 0 || (ready && (p.revents & (POLLERR | POLLHUP)))) return 0;
    if (!ready) continue;
    ssize_t written = write(s->write_fd, data + at, total - at);
    if (written < 0 && (errno == EINTR || errno == EAGAIN)) continue;
    if (written <= 0) return 0;
    at += (size_t)written;
  }
  return total;
}

static int pb_curl_progress(void *arg, curl_off_t a, curl_off_t b, curl_off_t c, curl_off_t d) {
  (void)a; (void)b; (void)c; (void)d;
  PbStream *s = arg;
  return atomic_load(&s->cancel);
}

static void *pb_http_worker(void *arg) {
  PbStream *s = arg;
  CURL *c = curl_easy_init();
  if (!c) { s->code = CURLE_FAILED_INIT; close(s->write_fd); return NULL; }
  struct curl_slist *headers = NULL;
  char *save = NULL;
  for (char *h = strtok_r(s->headers, "\n", &save); h; h = strtok_r(NULL, "\n", &save)) {
    if (strchr(h, '\r')) { s->code = CURLE_BAD_FUNCTION_ARGUMENT; goto done; }
    headers = curl_slist_append(headers, h);
  }
  curl_easy_setopt(c, CURLOPT_URL, s->url);
  curl_easy_setopt(c, CURLOPT_HTTPHEADER, headers);
  curl_easy_setopt(c, CURLOPT_POSTFIELDS, s->body);
  curl_easy_setopt(c, CURLOPT_POSTFIELDSIZE_LARGE, (curl_off_t)s->body_len);
  curl_easy_setopt(c, CURLOPT_WRITEFUNCTION, pb_curl_write);
  curl_easy_setopt(c, CURLOPT_WRITEDATA, s);
  curl_easy_setopt(c, CURLOPT_XFERINFOFUNCTION, pb_curl_progress);
  curl_easy_setopt(c, CURLOPT_XFERINFODATA, s);
  curl_easy_setopt(c, CURLOPT_NOPROGRESS, 0L);
  curl_easy_setopt(c, CURLOPT_CONNECTTIMEOUT_MS, 30000L);
  curl_easy_setopt(c, CURLOPT_TIMEOUT_MS, (long)s->deadline);
  curl_easy_setopt(c, CURLOPT_NOSIGNAL, 1L);
  curl_easy_setopt(c, CURLOPT_ACCEPT_ENCODING, "");
  curl_easy_setopt(c, CURLOPT_ERRORBUFFER, s->error);
  curl_easy_setopt(c, CURLOPT_PROTOCOLS_STR, "https,http");
  /* Keep TLS certificate and hostname verification enabled. No redirects
     carrying Authorization headers to another origin. */
  s->code = curl_easy_perform(c);
  curl_easy_getinfo(c, CURLINFO_RESPONSE_CODE, &s->status);
done:
  curl_slist_free_all(headers);
  curl_easy_cleanup(c);
  close(s->write_fd);
  return NULL;
}

static void pb_http(PbCall *c) {
  int p[2];
  if (pipe2(p, O_CLOEXEC) < 0) { c->error = errno; return; }
  PbStream *s = io_mem(calloc(1, sizeof *s));
  s->kind = 1; s->read_fd = p[0]; s->write_fd = p[1]; s->deadline = c->n;
  fcntl(p[1], F_SETFL, O_NONBLOCK);
  s->url = strdup(c->a); s->headers = strdup(c->b); s->body = strdup(c->c); s->body_len = c->clen;
  int id = pb_register(s);
  if (id < 0) { c->error = EMFILE; goto fail; }
  int err = pthread_create(&s->thread, NULL, pb_http_worker, s);
  if (err) { pb_streams[id] = NULL; c->error = err; goto fail; }
  pb_num(&c->out, id);
  return;
fail:
  close(p[0]); close(p[1]); free(s->url); free(s->headers); free(s->body); free(s);
}

static void pb_process(PbCall *c) {
  int p[2], errp[2];
  if (pipe2(p, O_CLOEXEC) < 0) { c->error = errno; return; }
  if (pipe2(errp, O_CLOEXEC) < 0) { c->error = errno; close(p[0]); close(p[1]); return; }
  pid_t pid = fork();
  if (pid == 0) {
    close(p[0]); close(errp[0]);
    setpgid(0, 0);
    signal(SIGINT, SIG_DFL); signal(SIGPIPE, SIG_DFL);
    if (*c->b && chdir(c->b)) { int e = errno; write(errp[1], &e, sizeof e); _exit(127); }
    int in = open("/dev/null", O_RDONLY);
    dup2(in, 0); dup2(p[1], 1); dup2(p[1], 2);
    close(in); close(p[1]);
    execl("/bin/bash", "bash", "-c", c->a, (char *)NULL);
    int e = errno; write(errp[1], &e, sizeof e); _exit(127);
  }
  close(p[1]); close(errp[1]);
  if (pid < 0) { c->error = errno; close(p[0]); close(errp[0]); return; }
  setpgid(pid, pid);
  int exec_error = 0;
  ssize_t got = read(errp[0], &exec_error, sizeof exec_error);
  close(errp[0]);
  if (got > 0) { c->error = exec_error; close(p[0]); waitpid(pid, NULL, 0); return; }
  PbStream *s = io_mem(calloc(1, sizeof *s));
  s->kind = 2; s->pid = pid; s->read_fd = p[0];
  s->deadline = c->n ? io_tick() / 1000000 + c->n : 0;
  int id = pb_register(s);
  if (id < 0) { kill(-pid, SIGKILL); waitpid(pid, NULL, 0); close(p[0]); free(s); c->error = EMFILE; return; }
  pb_num(&c->out, id);
}

/* Avoid splitting UTF-8 code points at the native/Bend string boundary. */
static size_t pb_utf8_prefix(const unsigned char *b, size_t n) {
  if (!n) return 0;
  size_t start = n - 1;
  while (start && (b[start] & 0xc0) == 0x80) start--;
  unsigned char lead = b[start];
  size_t width = lead < 0x80 ? 1 : lead < 0xe0 ? 2 : lead < 0xf0 ? 3 : 4;
  return n - start < width ? start : n;
}

static void pb_finish(PbStream *s) {
  if (s->finished) return;
  if (s->kind == 1) pthread_join(s->thread, NULL);
  else {
    int status = 0;
    while (waitpid(s->pid, &status, 0) < 0 && errno == EINTR) {}
    s->status = WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
  }
  s->finished = 1;
}

static void pb_cancel(PbStream *s) {
  atomic_store(&s->cancel, 1);
  if (s->kind == 2 && !s->finished) kill(-s->pid, SIGKILL);
}

static void pb_next(PbCall *c) {
  PbStream *s = pb_handle(c->a);
  if (!s) { c->error = EBADF; return; }
  if (s->finished) return;
  unsigned char data[8192];
  for (;;) {
    if (pb_interrupted || (s->kind == 2 && s->deadline && io_tick()/1000000 >= s->deadline)) {
      pb_cancel(s); pb_finish(s); c->error = pb_interrupted ? ECANCELED : ETIMEDOUT; return;
    }
    struct pollfd p = {s->read_fd, POLLIN, 0};
    int ready = poll(&p, 1, 100);
    if (ready < 0 && errno == EINTR) continue;
    if (ready < 0) { c->error = errno; return; }
    if (!ready) continue;
    size_t carry = s->carry_len;
    memcpy(data, s->carry, carry);
    ssize_t n = read(s->read_fd, data + carry, sizeof data - carry);
    if (n < 0 && errno == EINTR) continue;
    if (n < 0) { c->error = errno; return; }
    if (!n) {
      pb_finish(s);
      if (carry) { const char *replacement = "\xef\xbf\xbd"; pb_add(&c->out, replacement, 3); s->carry_len = 0; }
      if (s->kind == 1 && s->code) { c->error = EIO; if (!c->out.size) pb_add(&c->out, s->error, strlen(s->error)); }
      return;
    }
    size_t total = (size_t)n + carry, prefix = pb_utf8_prefix(data, total);
    s->carry_len = total - prefix;
    memcpy(s->carry, data + prefix, s->carry_len);
    if (prefix) { pb_add(&c->out, data, prefix); return; }
  }
}

static void pb_dispatch(IoWork *w) {
  PbCall *c = (PbCall *)w->data;
  switch (c->op) {
  case 1: if (c->n < (uint64_t)pb_argc) pb_add(&c->out, pb_argv[c->n], strlen(pb_argv[c->n])); break;
  case 2: pb_num(&c->out, pb_argc); break;
  case 3: { char *p = getcwd(NULL, 0); if (!p) c->error = errno; else { pb_add(&c->out, p, strlen(p)); free(p); } break; }
  case 4: {
    int fd = open(c->a, O_RDONLY | O_CLOEXEC); if (fd < 0) { c->error = errno; break; }
    struct stat st;
    if (fstat(fd, &st) || !S_ISREG(st.st_mode)) { c->error = EINVAL; close(fd); break; }
    char b[32768]; ssize_t n;
    while ((n = read(fd, b, sizeof b)) != 0) {
      if (n < 0 && errno == EINTR) continue;
      if (n < 0) { c->error = errno; break; }
      pb_add(&c->out, b, (size_t)n);
    }
    close(fd); break;
  }
  case 5: {
    c->error = pb_parents(c->a); if (c->error) break;
    int fd = open(c->a, O_WRONLY | O_CREAT | O_CLOEXEC | (c->n ? O_APPEND : O_TRUNC), 0666);
    if (fd < 0) { c->error = errno; break; }
    if (pb_write_all(fd, c->b, c->blen)) c->error = errno;
    if (close(fd) && !c->error) c->error = errno;
    break;
  }
  case 10: pb_http(c); break;
  case 11: pb_next(c); break;
  case 12: {
    PbStream *s = pb_handle(c->a); if (!s) { c->error = EBADF; break; }
    pb_cancel(s); pb_finish(s); close(s->read_fd);
    pthread_mutex_lock(&pb_stream_lock); pb_streams[strtoul(c->a, NULL, 10)] = NULL; pthread_mutex_unlock(&pb_stream_lock);
    free(s->url); free(s->headers); free(s->body); free(s); break;
  }
  case 13: { PbStream *s = pb_handle(c->a); if (!s) c->error = EBADF; else if (!s->finished) c->error = EBUSY; else pb_num(&c->out, s->status); break; }
  case 20: pb_process(c); break;
  case 30: {
    if (!isatty(0) || tcgetattr(0, &pb_saved_terminal)) { c->error = ENOTTY; break; }
    struct termios raw = pb_saved_terminal; cfmakeraw(&raw); raw.c_lflag |= ISIG;
    if (tcsetattr(0, TCSAFLUSH, &raw)) c->error = errno; else pb_terminal_active = 1;
    break;
  }
  case 31: {
    unsigned char b[256]; ssize_t n;
    do { n = read(0, b, sizeof b); } while (n < 0 && errno == EINTR && !pb_interrupted);
    if (n < 0) c->error = errno; else pb_add(&c->out, b, (size_t)n); break;
  }
  case 32: pb_restore(); break;
  case 33: { struct winsize z; if (ioctl(1, TIOCGWINSZ, &z)) { z.ws_col = 80; z.ws_row = 24; } pb_num(&c->out, z.ws_col); pb_add(&c->out, " ", 1); pb_num(&c->out, z.ws_row); break; }
  case 40: {
    unsigned char b[16]; size_t at = 0;
    while (at < sizeof b) { ssize_t n = getrandom(b + at, sizeof b - at, 0); if (n < 0 && errno == EINTR) continue; if (n <= 0) { c->error = errno; break; } at += n; }
    if (c->error) break;
    b[6] = (b[6] & 15) | 64; b[8] = (b[8] & 63) | 128;
    char s[37]; snprintf(s, sizeof s, "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x", b[0],b[1],b[2],b[3],b[4],b[5],b[6],b[7],b[8],b[9],b[10],b[11],b[12],b[13],b[14],b[15]); pb_add(&c->out, s, 36); break;
  }
  case 41: { struct timespec t; clock_gettime(CLOCK_REALTIME, &t); pb_num(&c->out, (long long)t.tv_sec * 1000 + t.tv_nsec / 1000000); break; }
  case 42: pb_num(&c->out, pb_interrupted); pb_interrupted = 0; break;
  case 43: if (chdir(c->a)) c->error = errno; break;
  case 44: {
    c->error = pb_parents(c->a); if (c->error) break;
    char *tmp = io_mem(malloc(c->alen + 16)); sprintf(tmp, "%s.XXXXXX", c->a);
    int fd = mkstemp(tmp); if (fd < 0) { c->error = errno; free(tmp); break; }
    if (fchmod(fd, c->n ? c->n : 0600) || pb_write_all(fd, c->b, c->blen) || fsync(fd)) c->error = errno;
    if (close(fd) && !c->error) c->error = errno;
    if (!c->error && rename(tmp, c->a)) c->error = errno;
    if (c->error) unlink(tmp);
    free(tmp); break;
  }
  default: c->error = ENOSYS;
  }
}

static Term pb_pack(Env e, IoWork *w) {
  PbCall *c = (PbCall *)w->data;
  Term result = c->error ? io_fail(e, c->error, NULL) : io_done(e, io_str(e, c->out.data ? c->out.data : "", c->out.size));
  free(c->a); free(c->b); free(c->c); free(c->out.data); free(c);
  return result;
}

Term native_call_run(Env e, Term *f, IoWork *w) {
  PbCall *c = io_mem(calloc(1, sizeof *c));
  c->op = (uint32_t)f[0]; c->n = (uint64_t)f[4];
  c->a = io_cstr(e, f[1], &c->alen); c->b = io_cstr(e, f[2], &c->blen); c->c = io_cstr(e, f[3], &c->clen);
  w->data = (char *)c;
  if (memchr(c->a, 0, c->alen) || (c->op == 10 && memchr(c->b, 0, c->blen))) { c->error = EINVAL; return pb_pack(e, w); }
  return io_work(w, pb_dispatch, pb_pack);
}

static void __attribute__((constructor)) native_call_use(void) {
  io_eff(CID_CALL, native_call_run, 0);
}
