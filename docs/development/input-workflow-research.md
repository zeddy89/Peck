# Easier console input: research notes

Research-only, 2026-09-05. No application changes or remote tests performed. The user reports that Peck 1.2.1 worked after `:set paste` and `i`; that is useful case evidence, not general compatibility qualification.

## Recommended product direction

Make **copy, focus the destination, press a dedicated Peck hotkey** the primary fast path. Keep crosshair targeting available separately. Offer an explicit profile selector: ordinary text/password, prepared vi/Vim, and an experimental verified-Vim workflow. Preserve Escape cancellation, target checks, strict keycodes, and Return confirmation. Do not override ordinary Command-V. This is a product recommendation, not an implemented change.

## What Vim can automate

Vim's `paste` option disables automatic indentation and several formatting behaviors; it is a setting, not an instruction to enter Insert mode. `pastetoggle` works in Normal and Insert modes, but not Command-line mode. Thus a toggle cannot safely normalize an unknown starting state. [Official Vim options documentation](https://github.com/vim/vim/blob/master/runtime/doc/options.txt#L6174)

Modern Vim recognizes bracketed-paste start/end sequences when terminal capabilities are configured. Vim sends enable/disable sequences to the terminal, which surrounds pasted content with markers. Missing marker capabilities or disabled `esckeys` can disable this behavior; the manual also describes contexts that expose raw text or discard input. This is capability-dependent signaling, not something a keyboard-only sender can assume the guest negotiated. [Official terminal documentation](https://github.com/vim/vim/blob/master/runtime/doc/term.txt#L87)

Vim source confirms recognized bracketed paste works from Normal mode, entering insertion handling, and from Insert mode. Normal-mode placement follows append semantics except at column zero; Visual mode can replace the selection. This is not equivalent to generic vi support or a promise about the user's installed build. [Normal-mode implementation](https://github.com/vim/vim/blob/master/src/normal.c#L6649), [Insert-mode implementation](https://github.com/vim/vim/blob/master/src/edit.c#L1061)

**Recommendation:** test Peck's existing bracketed-paste option against the actual Vim and console in both Normal and Insert mode. If reliable, it could remove manual preparation for an explicitly qualified Vim profile. Do not infer support merely because the executable is named `vi`.

An explicit “Prepare Vim and type” macro could send Escape, `:set paste`, Return, `i`, then text. Treat this as an opt-in experiment restricted to a known Vim buffer: in a shell, login field, command prompt, or unsupported editor those are unintended commands/text. It also cannot know whether paste was originally enabled, and aborting before cleanup could leave it enabled. Automatic cleanup must never defeat cancellation or send into another target. These are design inferences from modal behavior, not tested outcomes.

## vSphere boundaries

Broadcom's VMC-on-AWS article states that HTML5 WebMKS clipboard sharing was removed and distinguishes VMRC as the supported clipboard path for that environment. Its VMRC instructions require VMware Tools and per-VM configuration, cover text rather than files/folders, and do not establish browser-console support. Do not present VMRC settings as a fix for the user's Edge/Chrome/Firefox console. [WebMKS boundary](https://knowledge.broadcom.com/external/article/313685), [VMRC configuration](https://knowledge.broadcom.com/external/article/319537/enable-content-copypaste-between-vmrc-cl.html)

Peck's generic keystroke path therefore remains useful. Guest-supported file transfer is an alternative only when the disconnected VM and workplace policy actually permit it; this research has not established a universal vSphere browser file-transfer route.

## Optional adapters for long scripts

GL.iNet documents Virtual Media upload followed by Mount To Remote and File Sharing, exposing an emulated USB drive to the controlled computer. This can avoid slow typing into the physically attached host. Reaching a VM guest additionally requires suitable USB/storage assignment, not demonstrated here. [GL.iNet file sharing](https://docs.gl-inet.com/kvm/en/tutorials/how_to_share_files_between_controlling_device_and_controlled_device/)

GL.iNet also documents a built-in Toolbox Clipboard action. Benchmark it as a baseline; its presence does not prove faster transport, exact receipt, or automatic vi preparation. [GL-RM1 console guide](https://docs.gl-inet.com/kvm/en/user_guide/gl-rm1/console_guide/#clipboard)

noVNC's `clipboardPasteFrom` API sends clipboard data to its remote server. That is a possible target-specific integration, not proof the guest accepts paste and not evidence that vSphere uses noVNC. [Official noVNC API](https://github.com/novnc/noVNC/blob/master/docs/API.md#rfbclipboardpastefrom)

## Speed and team adoption

For 10,000 characters, delay alone is approximately 150 seconds at 15 ms, 50 seconds at 5 ms, or 20 seconds at 2 ms. Key holds, Return delays, target checks, and console overhead add time. These are arithmetic estimates, not benchmarks. Test identical fixtures repeatedly before recommending faster team defaults. Share named, qualified profiles with console/editor/layout versions and exact-match results; retain generic typing as the fallback.
