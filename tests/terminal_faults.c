#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <termios.h>
#include <sys/stat.h>
#include <unistd.h>
static int raw,changed,close_failed,write_count;
static struct sigaction installed;
static int mode(const char* wanted){const char* value=getenv("BEND_TERMINAL_FAULT");return value&&!strcmp(value,wanted);}
static void previous(int signal){(void)signal;write(2,"prior\n",6);}
static void replacement(int signal){(void)signal;write(2,"replacement\n",12);}
static void final_signal(void){if(getenv("BEND_TERMINAL_PRIOR"))raise(SIGWINCH);}
__attribute__((constructor)) static void install_previous(void){
 if(getenv("BEND_TERMINAL_PRIOR")){struct sigaction action={.sa_handler=previous};sigemptyset(&action.sa_mask);sigaction(SIGWINCH,&action,NULL);atexit(final_signal);}
}
int tcsetattr(int fd,int action,const struct termios* settings){
 static int(*real)(int,int,const struct termios*);if(!real)real=dlsym(RTLD_NEXT,"tcsetattr");
 int result=real(fd,action,settings);if(!result){raw=!(settings->c_lflag&ICANON);if(raw&&!changed&&mode("raw")){changed=1;errno=EIO;return -1;}}
 return result;
}
int pipe2(int fds[2],int flags){static int(*real)(int*,int);if(!real)real=dlsym(RTLD_NEXT,"pipe2");if(raw&&!changed&&mode("pipe")){changed=1;errno=EMFILE;return -1;}return real(fds,flags);}
int sigaction(int signal,const struct sigaction* action,struct sigaction* old){
 static int(*real)(int,const struct sigaction*,struct sigaction*);if(!real)real=dlsym(RTLD_NEXT,"sigaction");
 if(signal==SIGWINCH&&raw&&action&&(action->sa_flags&SA_SIGINFO)){
  if(!changed&&mode("signal")){changed=1;errno=EIO;return -1;}
  installed=*action;
 }
 if(signal==SIGWINCH&&action&&installed.sa_sigaction&&!(action->sa_flags&SA_SIGINFO)&&!changed&&mode("signal-restore")){
  changed=1;errno=EIO;return -1;
 }
 if(signal==SIGWINCH&&raw&&!action&&installed.sa_sigaction&&!changed&&mode("replaced")){
  struct sigaction next={.sa_handler=replacement};sigemptyset(&next.sa_mask);real(SIGWINCH,&next,NULL);changed=1;
 }
 return real(signal,action,old);
}
int close(int fd){static int(*real)(int);if(!real)real=dlsym(RTLD_NEXT,"close");int result=real(fd);if(raw&&fd>2&&!close_failed&&mode("close")){close_failed=1;errno=EIO;return -1;}return result;}
ssize_t write(int fd,const void* bytes,size_t count){
 static ssize_t(*real)(int,const void*,size_t);if(!real)real=dlsym(RTLD_NEXT,"write");
 if(mode("slow-regular")&&count==22&&!memcmp(bytes,"BLOCKING_REGULAR_WRITE",22)){
  struct stat st;if(!fstat(fd,&st)&&S_ISREG(st.st_mode)){real(2,"slow-enter\n",11);usleep(300000);real(2,"slow-exit\n",10);}
 }
 if(raw&&fd!=2&&isatty(fd)&&!changed&&mode("reuse-output")){
  changed=1;int replacement_fd=atoi(getenv("BEND_TERMINAL_REPLACEMENT"));
  if(close(1)<0||dup2(replacement_fd,1)!=1)_exit(91);
 }
 if(raw&&fd!=2&&isatty(fd)){write_count++;if((mode("write-first")&&write_count==1)||(mode("write-stop")&&write_count==2)){errno=EIO;return -1;}}
 return real(fd,bytes,count);
}
