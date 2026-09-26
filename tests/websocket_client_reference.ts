const [url, mode, payload] = process.argv.slice(2);
await new Promise<void>((resolve, reject) => {
  const socket = new WebSocket(url, { headers: { Authorization: "Bearer fixture" }, tls: {rejectUnauthorized: false} });
  socket.binaryType = "arraybuffer";
  const wanted = mode === "reuse" ? 2 : mode === "close" ? Infinity : 1;
  let count = 0;
  socket.addEventListener("open", () => socket.send(payload));
  socket.addEventListener("error", reject);
  socket.addEventListener("message", async ({data}) => {
    console.log(typeof data === "string" ? data : `binary|${(data as ArrayBuffer).byteLength}`);
    count++;
    if (count === wanted) socket.close();
    else if (mode === "reuse") socket.send(payload);
  });
  socket.addEventListener("close", ({code, reason}) => {
    if (mode === "close") console.log(`close|${code}|${reason}`);
    resolve();
  });
});
