# Compatibility and repeatable testing

These observations are evidence to guide testing, not a certification. A successful local editor test does not establish remote-console delivery. Initial-character loss, editor-generated formatting, and a guest keyboard-layout mismatch are different failure modes.

## User-reported successful use

The user reported that 1.2.1 worked after enabling vi/Vim paste mode and entering Insert mode. This supports that specific workflow, but no repeated exact-file qualification across versions, browsers, layouts, or 2 ms settings is implied.

## Reports after the 1.2.0 test build

| Observation | Interpretation and verification boundary |
|---|---|
| Switching to another app during typing sent text there | User-reported target spill; startup activation checking alone did not protect an ongoing paste |
| Escape in vi coincided with text deletion | Possible Escape propagation followed by queued characters in normal mode; exact event ordering unverified |
| Initial red vi error | Error text and cause not established |
| Console 40 ms delay and 10 ms hold felt slow | Slower pacing did not establish correctness and should not be presented as the fix |

The 1.2.1 regression tests must include switching away during a delay and before an event, aborting during key holds, and switching with an open bracketed-paste marker. Cleanup must not type marker characters into the new target. Local process/window checks cannot prove the active browser tab or the focused control inside a remote VM.

## Observed before 1.2.0

| Target | Evidence | Status |
|---|---|---|
| vSphere browser console in Edge, Chrome, Firefox | User reports intermittent scrambled multiline commands across all three browsers | Reported failure; exact received-file capture and repeatable reproduction pending |
| VMware Remote Console (VMRC) | No test performed | Untested |
| GLKVM with nano | Visible portion of long script appeared intact in a screenshot | Partial visual check only; no exact comparison |
| GLKVM with vi | Indentation staircase and repeated comment prefixes; `:set paste` stabilized formatting | Editor interaction observed; full character fidelity unverified |
| GLKVM with vi, short punctuation sample | Parentheses initially appeared missing but were visible after `:syntax off` | Earlier punctuation-loss interpretation withdrawn |
| GLKVM with vi, short sample | First line appeared to contain two initial `a` characters rather than three | Possible initial-character loss; unconfirmed by exact file comparison |
| Nextpad++ on macOS | Earlier visual inspection reported missing return statements and extra ending characters | Unconfirmed; repeat with unchanged input and saved-file comparison |
| Proxmox/noVNC, RDP, other hardware KVMs | No completed received-file comparison in this investigation | Untested |

## Test procedure

1. Use a scratch editor buffer. Do not type the fixture into a shell prompt or execute it. Preserve the exact original fixture as `expected.txt`.
2. Record Peck version, preset and every timing/typing/indentation setting, macOS keyboard layout, browser/version, console, guest OS/layout, editor/version, and network path.
3. Disable editor auto-indent and automatic comment/bracket insertion, or use its supported paste mode. In Vim, use `:set paste` before entering insert mode and `:set nopaste` afterward. Some vi implementations do not support this setting. Turn syntax highlighting off if screenshots obscure punctuation.
4. Send the same unchanged clipboard into a fresh buffer at least ten times. Save each result without edits. Include a short startup sample (`aaa()bbb`), shifted symbols, multiline indentation, backslashes, and a long line.
5. Compare each file with the original using `diff -u expected.txt received.txt` or an editor's file comparison. Record editor-added final newline and CRLF/LF differences separately. Do not silently normalize spaces, missing characters, or line boundaries. A screenshot alone cannot prove equality.
6. If a run fails, preserve the file and change one variable: focus delay, key hold, character delay, or post-Return delay. Repeat the full set. A slower run that succeeds once is not a verified fix.
7. Separately test Cancel during the initial delay, key hold, and a long character delay. During active typing, verify a human Escape cancels without reaching vi; while idle, verify Escape still works normally. Switch to another application during a long paste and check that no continuing text or bracketed-paste cleanup appears there. Repeat between two windows of the same browser and explicitly record whether that distinction is enforced. Browser-tab and guest-widget changes require separate testing and may be undetectable locally. Check that Shift/Option/Control/Command are released afterward. Test Send Key interrupt during typing only in a disposable session.
8. Record exact matches/attempts and time per run. Qualify a preset only after all repeats succeed for that target. Recheck after browser, console, layout, or app changes.

For disconnected VMs, store the result inside the VM and use an approved transfer route when available. If only a screen is accessible, label the evidence as visual and incomplete. Never put passwords or work scripts in bug reports.
