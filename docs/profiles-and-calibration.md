# Profiles and calibration

## Profiles

Choose **Export Profile…** in Advanced Settings or the status menu's Advanced submenu to save portable settings as JSON. Optional name and notes are provided by you; do not put passwords or sensitive information there. Exports contain timing, typing/indentation mode, strict-keycode and Return settings, the confirmation master, and the size threshold. They do not include hotkeys, login registration, clipboard contents, received text, or calibration history.

**Import Profile…** validates the file and shows every setting before **Apply Profile**. Cancel is the keyboard default. Profiles can disable warnings or enable appended Return, so review the summary. Imported notes are labeled user-provided and are not proof of compatibility. Hotkeys and launch-at-login stay unchanged.

Schema version 1 accepts regular JSON files up to 16 KB. Importing a 1.3 profile without the new confirmation master defaults that master to Off; 1.4 exports include it and require a reader that supports the field. Unknown fields, missing required settings, invalid modes, out-of-range values, and symbolic-link files are rejected. Names are limited to 160 UTF-8 bytes and notes to 2000, with control/format characters restricted. Opening Advanced Settings or importing/exporting a profile ends local calibration and restores its temporary delay before the settings action.

## Calibration

Choose **Advanced > Typing Test & Calibration…**, then choose **Local received keystrokes**, copy the sample, select a trial speed, and choose **Begin Trial**. That clears the receiver and temporarily changes only the character delay. Arm Peck, send the sample once into the local receiver, then choose **Record Result**. **Compare Only** inspects text without qualifying a speed.

The default candidates are 15, 10, 5, and 2 ms. **Set Rates** accepts 1–12 distinct whole-number delays from 0 to 10000 ms. A speed requires three separate completed runs with fresh exact matches. Manual edits or ordinary paste cannot qualify a local run. A mismatch disqualifies that speed for the session; only a slower qualified speed is recommended. These are local results, not a guarantee for a browser console.

**Remote (user-supplied receipt)** lets you return text from a fresh remote scratch file after a completed Peck run. This mode cannot independently verify where the text came from, so its results are labeled user-supplied. Never execute the sample or substitute the original clipboard for the received file.

**Apply Recommended** is explicit and changes only character delay. A changed configuration invalidates its recommendation; the actual run settings are checked against the trial before it can qualify. Cancellation, Clear, **End Calibration / Restore Delay**, and closing restore the temporary delay only while Peck still recognizes it as calibration-owned. Other preferences are preserved. Test results contain aggregate match counts; the received text stays in the temporary editor and is cleared when closing. Keep actual target/editor/layout conditions consistent across trials.
