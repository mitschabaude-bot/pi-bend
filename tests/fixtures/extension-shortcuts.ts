import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
  pi.registerShortcut("ctrl+v", { handler: async (ctx) => { ctx.ui.setEditorText("SHORTCUT-OK"); } });
  pi.registerShortcut("ctrl+o", { handler: async (ctx) => {
    await new Promise((resolve) => setTimeout(resolve, 1000));
    ctx.ui.setEditorText("ASYNC-OK");
  } });
  pi.registerShortcut("ctrl+g", { handler: async () => { throw "shortcut fixture failure"; } });
}
