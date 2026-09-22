"""Independent JPEG fixture writers: constant DCT blocks and predictive lossless samples."""
import struct
def marker(code,data):return bytes([255,code])+struct.pack('>H',len(data)+2)+data
def lossless(w,h,components,precision,predictor,low,interval,pixels):
 sof=bytes([precision])+struct.pack('>HHB',h,w,components)+b''.join(bytes([i+1,17,0]) for i in range(components))
 dht=bytes([0])+bytes([0,0,0,0,17]+[0]*11)+bytes(range(17))
 sos=bytes([components])+b''.join(bytes([i+1,0]) for i in range(components))+bytes([predictor,0,low])
 data=b'\xff\xd8'+marker(195,sof)+marker(196,dht)
 if interval:data+=marker(221,struct.pack('>H',interval))
 data+=marker(218,sos)
 bits='';rst=0
 def packed(bits):
  bits+='1'*((-len(bits))%8)
  return bytes(int(bits[i:i+8],2) for i in range(0,len(bits),8)).replace(b'\xff',b'\xff\x00')
 mask=(1<<(precision-low))-1
 for pos in range(w*h):
  if interval and pos and pos%interval==0:data+=packed(bits)+bytes([255,208+rst]);bits='';rst=(rst+1)%8
  for c in range(components):
   at=lambda p:pixels[p*components+c]>>low
   a=at(pos-1) if pos%w else 0;b=at(pos-w) if pos>=w else 0;d=at(pos-w-1) if pos>=w and pos%w else 0
   pred=(1<<(precision-low-1)) if pos==0 or interval and pos%interval==0 else a if (pos%interval if interval else pos)<w else b if pos%w==0 else [0,a,b,d,a+b-d,a+((b-d)>>1),b+((a-d)>>1),(a+b)//2][predictor]
   diff=(at(pos)-pred)&65535
   if diff>=32768:diff-=65536
   size=abs(diff).bit_length();bits+=f'{size:05b}'
   if size and size<16:bits+=format(diff if diff>=0 else diff+(1<<size)-1,f'0{size}b')
 data+=packed(bits)+b'\xff\xd9';return data

def packed(bits):
 bits+='1'*((-len(bits))%8)
 return bytes(int(bits[i:i+8],2) for i in range(0,len(bits),8)).replace(b'\xff',b'\xff\x00')

def baseline(w,h,factors,ids=None,adobe=None,separate=False,interval=0,wide=False,mode=192):
 ids=ids or list(range(1,len(factors)+1));hm=max(v[0] for v in factors);vm=max(v[1] for v in factors)
 columns=(w+8*hm-1)//(8*hm);rows=(h+8*vm-1)//(8*vm)
 sof=bytes([8])+struct.pack('>HHB',h,w,len(factors))+b''.join(bytes([id,hf*16+vf,0]) for id,(hf,vf) in zip(ids,factors))
 q=bytes([16 if wide else 0])+(b'\0\1' if wide else b'\1')*64
 dc=bytes([0])+bytes([0,0,0,12]+[0]*12)+bytes(range(12));ac=bytes([16])+bytes([1]+[0]*15)+bytes([0])
 data=b'\xff\xd8'+marker(mode,sof)+marker(219,q)+marker(196,dc+ac)
 if adobe is not None:data+=marker(238,b'Adobe'+b'\0d\0\0\0\0'+bytes([adobe]))
 if interval:data+=marker(221,struct.pack('>H',interval))
 groups=[[i] for i in range(len(ids))] if separate else [list(range(len(ids)))]
 for group in groups:
  data+=marker(218,bytes([len(group)])+b''.join(bytes([ids[i],0]) for i in group)+bytes([0,63,0]))
  multi=len(group)>1;ci=group[0];hf,vf=factors[ci]
  cols=columns if multi else ((w*hf+hm-1)//hm+7)//8
  rs=rows if multi else ((h*vf+vm-1)//vm+7)//8
  previous=[0]*len(ids);bits='';rst=0
  for my in range(rs):
   for mx in range(cols):
    pos=my*cols+mx
    if interval and pos and pos%interval==0:data+=packed(bits)+bytes([255,208+rst]);bits='';rst=(rst+1)%8;previous=[0]*len(ids)
    for i in group:
     hf,vf=factors[i];hf=hf if multi else 1;vf=vf if multi else 1
     for dy in range(vf):
      for dx in range(hf):
       bx=mx*hf+dx;by=my*vf+dy;value=32+(i*61+bx*19+by*27)%192
       coefficient=(value-128)*8;diff=coefficient-previous[i];previous[i]=coefficient;size=abs(diff).bit_length()
       bits+=format(size,'04b')
       if size:bits+=format(diff if diff>=0 else diff+(1<<size)-1,f'0{size}b')
       bits+='0'
  data+=packed(bits)
 return data+b'\xff\xd9'

def mjpeg(data):
 output=b'\xff\xd8'+marker(224,b'AVI1\0');offset=2
 while offset<len(data):
  assert data[offset]==255;code=data[offset+1]
  if code==218:return output+data[offset:]
  length=int.from_bytes(data[offset+2:offset+4],'big');chunk=data[offset:offset+2+length];offset+=2+length
  if code not in [196,224]:output+=chunk
 raise AssertionError('no scan')

def segments(data):
 """Return marker offsets, payload extents and complete scan extents."""
 result=[];offset=2
 while offset<len(data):
  assert data[offset]==255
  code=data[offset+1]
  if code==217:result.append((code,offset,offset+2,offset+2));break
  size=int.from_bytes(data[offset+2:offset+4],'big');end=offset+2+size;scan_end=end
  if code==218:
   while scan_end<len(data):
    if data[scan_end]!=255:scan_end+=1;continue
    following=data[scan_end+1]
    if following==0 or 208<=following<=215:scan_end+=2;continue
    if following==255:scan_end+=1;continue
    break
  result.append((code,offset,end,scan_end));offset=scan_end
 return result
