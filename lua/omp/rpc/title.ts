import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";

export default function enableRpcSessionTitles(_pi: ExtensionAPI): void {
	delete Bun.env.PI_NO_TITLE;
}
