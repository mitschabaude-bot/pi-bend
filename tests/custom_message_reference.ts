import { UPSTREAM } from "./upstream_pin.mjs";
const { CustomMessageComponent } = await import(UPSTREAM + "/packages/coding-agent/src/modes/interactive/components/custom-message.ts");
const { initTheme } = await import(UPSTREAM + "/packages/coding-agent/src/modes/interactive/theme/theme.ts");
const { Text } = await import(UPSTREAM + "/packages/tui/src/components/text.ts");
initTheme("dark");
const message: any = { role: "custom", customType: "notice", content: "fallback body", display: true, details: undefined, timestamp: 0 };
const snapshot = (label: string, component: any) => process.stdout.write(label + "\x1e" + component.render(80).join("\x1f") + "\n");
const custom = new CustomMessageComponent(message, (message: any, options: any) => ({
  render: () => [`${message.customType}:${options.expanded ? "True" : "False"}:${options.outputPad}`],
  invalidate: () => {},
}));
snapshot("initial", custom);
custom.setExpanded(false);
custom.setOutputPad(1);
custom.setExpanded(true);
custom.setOutputPad(3);
snapshot("options", custom);
custom.invalidate();
snapshot("fallback", new CustomMessageComponent(message, () => { throw new Error("renderer failed"); }));
snapshot("fallback", new CustomMessageComponent(message, () => undefined));
snapshot("fallback", new CustomMessageComponent(message));
snapshot("fallback", new CustomMessageComponent({ ...message, customType: "skill" }));
const padded = new CustomMessageComponent(message, (_: any, options: any) => new Text("custom", options.outputPad, 0));
process.stdout.write("padding1\x1e" + padded.render(40).join("\x1f") + "\n");
padded.setOutputPad(0);
process.stdout.write("padding0\x1e" + padded.render(40).join("\x1f") + "\n");
