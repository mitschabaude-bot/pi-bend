// Test-only oracle: upstream's pinned Photon 0.3.4 WASM decoder.
const fs = require('node:fs');
const photon = require(process.argv[2]);
for (const file of process.argv.slice(3)) {
  const image = photon.PhotonImage.new_from_byteslice(fs.readFileSync(file));
  console.log(JSON.stringify({width:image.get_width(), height:image.get_height(), rgba:Array.from(image.get_raw_pixels())}));
  image.free();
}
