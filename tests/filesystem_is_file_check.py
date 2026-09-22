"""Stat-only regular-file detection, including nonblocking FIFO inspection."""
import argparse,errno,os,pathlib,socket,subprocess,tempfile
p=argparse.ArgumentParser();p.add_argument('command',nargs=argparse.REMAINDER);a=p.parse_args();command=a.command
if command[:1]==['--']:command=command[1:]
with tempfile.TemporaryDirectory(prefix='bend-is-file-') as directory:
 root=pathlib.Path(directory);file=root/'regular β';file.write_bytes(b'unchanged');file.chmod(0)
 link=root/'file-link';link.symlink_to(file)
 directory_link=root/'directory-link';directory_link.symlink_to(root)
 fifo=root/'fifo';os.mkfifo(fifo)
 fifo_link=root/'fifo-link';fifo_link.symlink_to(fifo)
 missing=root/'missing';dangling=root/'dangling';dangling.symlink_to(missing)
 sock=socket.socket(socket.AF_UNIX);sock.bind(str(root/'socket'))
 try:
  paths=[file,link,root,directory_link,fifo,fifo_link,root/'socket','/dev/null',missing,dangling,file]
  result=subprocess.run(command+list(map(str,paths)),text=True,capture_output=True,timeout=5,check=True)
  assert result.stdout.splitlines()==['true','true','false','false','false','false','false','false',f'error:{errno.ENOENT}',f'error:{errno.ENOENT}','true'],result.stdout
  # Unreadable regular files remain regular, FIFOs have no peer, and no contents change.
  file.chmod(0o600);assert file.read_bytes()==b'unchanged'
 finally:sock.close()
print('PASS regular/unreadable files, symlinks, directories, FIFO without peer, socket/device, missing/dangling links and error recovery')
