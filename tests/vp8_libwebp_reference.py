import ctypes,ctypes.util,json,sys
lib=ctypes.CDLL(ctypes.util.find_library('webp'))
P=ctypes.POINTER(ctypes.c_ubyte);I=ctypes.c_int
lib.WebPDecodeYUV.argtypes=[P,ctypes.c_size_t,ctypes.POINTER(I),ctypes.POINTER(I),ctypes.POINTER(P),ctypes.POINTER(P),ctypes.POINTER(I),ctypes.POINTER(I)]
lib.WebPDecodeYUV.restype=P;lib.WebPFree.argtypes=[ctypes.c_void_p]
for path in sys.argv[1:]:
 data=open(path,'rb').read();src=(ctypes.c_ubyte*len(data)).from_buffer_copy(data);w=I();h=I();u=P();v=P();stride=I();uvstride=I()
 y=lib.WebPDecodeYUV(src,len(data),ctypes.byref(w),ctypes.byref(h),ctypes.byref(u),ctypes.byref(v),ctypes.byref(stride),ctypes.byref(uvstride));assert y
 out=[]
 for row in range(h.value):
  for col in range(w.value):
   c=y[row*stride.value+col]-16;d=u[(row//2)*uvstride.value+col//2]-128;e=v[(row//2)*uvstride.value+col//2]-128
   rgb=[(298*c+409*e+128)>>8,(298*c-100*d-208*e+128)>>8,(298*c+516*d+128)>>8]
   r,g,b=[max(0,min(255,k)) for k in rgb];out.append((r<<24)|(g<<16)|(b<<8)|255)
 print(json.dumps(dict(width=w.value,height=h.value,pixels=out)));lib.WebPFree(y)
