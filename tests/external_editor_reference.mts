import { editInExternalEditor } from "../../pi-mono/packages/coding-agent/src/modes/interactive/external-editor.ts";

const [command, content] = process.argv.slice(2);
const result = await editInExternalEditor({ command, content });
console.log("reference:" + JSON.stringify(result));
