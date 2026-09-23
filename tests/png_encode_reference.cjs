// Test-only pinned Photon PNG encoder and decoder.
const fs=require('node:fs');
const photon=require(process.argv[2]);
for(const file of process.argv.slice(3)){
 const request=JSON.parse(fs.readFileSync(file,'utf8'));
 if(request.png){
  const image=photon.PhotonImage.new_from_byteslice(Buffer.from(request.png,'base64'));
  console.log(JSON.stringify({width:image.get_width(),height:image.get_height(),rgba:Array.from(image.get_raw_pixels())}));image.free();
 }else{
  const rgba=Uint8Array.from(request.pixels.flatMap(p=>[p>>>24,(p>>>16)&255,(p>>>8)&255,p&255]));
  const image=new photon.PhotonImage(rgba,request.width,request.height);
  console.log(JSON.stringify({png:Buffer.from(image.get_bytes()).toString('base64')}));image.free();
 }
}
