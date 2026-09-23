// Test-only pinned Photon 0.3.4 JPEG encoder and decoder.
const fs=require('node:fs');
const photon=require(process.argv[2]);
for(const file of process.argv.slice(3)){
 const request=JSON.parse(fs.readFileSync(file,'utf8'));
 const image=photon.PhotonImage.new_from_byteslice(Buffer.from(request.jpeg,'base64'));
 console.log(JSON.stringify({width:image.get_width(),height:image.get_height(),rgba:Array.from(image.get_raw_pixels())}));
 image.free();
}
