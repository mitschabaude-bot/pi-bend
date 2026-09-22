// Pinned Photon 0.3.4 is a test-only decoded-pixel reference.
const fs=require('node:fs'),photon=require(process.argv[2]);
for(const file of process.argv.slice(3)){
 const image=photon.PhotonImage.new_from_byteslice(fs.readFileSync(file));
 const bytes=image.get_raw_pixels(),pixels=[];
 for(let i=0;i<bytes.length;i+=4) pixels.push(((bytes[i]*16777216)+(bytes[i+1]<<16)+(bytes[i+2]<<8)+bytes[i+3])>>>0);
 console.log(JSON.stringify({width:image.get_width(),height:image.get_height(),pixels}));image.free();
}
