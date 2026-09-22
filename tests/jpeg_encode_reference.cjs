// Test-only pinned Photon 0.3.4 JPEG encoder and decoder.
const fs=require('node:fs');
const photon=require(process.argv[2]);
for(const file of process.argv.slice(3)){
 const request=JSON.parse(fs.readFileSync(file,'utf8'));
 if(request.jpeg){
  const image=photon.PhotonImage.new_from_byteslice(Buffer.from(request.jpeg,'base64'));
  console.log(JSON.stringify({width:image.get_width(),height:image.get_height(),rgba:Array.from(image.get_raw_pixels())}));
  image.free();
 }else{
  const rgba=Uint8Array.from(request.pixels.flatMap(p=>[p>>>24,(p>>>16)&255,(p>>>8)&255,p&255]));
  const image=new photon.PhotonImage(rgba,request.width,request.height);
  const jpeg=image.get_bytes_jpeg(request.quality);
  const decoded=photon.PhotonImage.new_from_byteslice(jpeg);
  console.log(JSON.stringify({jpeg:Buffer.from(jpeg).toString('base64'),width:decoded.get_width(),height:decoded.get_height(),rgba:Array.from(decoded.get_raw_pixels())}));
  decoded.free();image.free();
 }
}
