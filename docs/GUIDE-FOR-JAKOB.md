# How to build Gallra with Claude (beginner guide)

## The 5 ideas that matter
1. **Claude reads `CLAUDE.md` at the start of every chat.** It is the project's memory. That is why you never need to re-explain the app. Keep it short.
2. **Cost comes from context.** Every message re-sends the whole conversation. Long chats get expensive and Claude gets sloppier. So: one small task per chat, then start a new one.
3. **Plan first, code second.** Ask for a short plan, approve it, then let it build. Fixing a wrong plan is cheap; fixing wrong code is not.
4. **Git is your undo button.** Commit after every working step. If Claude breaks something, you go back.
5. **Never test on original photos.** Always copies.

## Which model
| Use | Model | Why |
|---|---|---|
| Almost everything (building screens, features, fixes) | **Sonnet** | Best value |
| Hard one-off problems: the RAW rating writer, the compare zoom sync, a bug Sonnet failed twice on | **Opus**, briefly, then switch back | Smarter, but uses your allowance much faster |
| Tiny edits, renames, "explain this file" | **Haiku** | Cheapest |

Switch with the model picker in the app. Start each stage in Sonnet.

## Working routine (every session)
1. New chat in the `Gallra` folder.
2. Say: *"Read docs/ROADMAP.md. We're doing Stage N, task X. Give me a short plan first."*
3. Approve or adjust the plan. Let it build.
4. Run the app in Xcode (press the Play button) and try it yourself. Tell Claude what you see, in plain words, or paste a screenshot.
5. When it works: *"Commit this with a clear message and tick the roadmap box."*
6. Start a **new chat**. Don't continue forever in one.

## Do / don't
- Do keep requests small: "add the star filter bar", not "build the whole app".
- Do paste exact error messages instead of describing them.
- Do ask "explain that in plain language" any time. It is free learning.
- Don't ask for several stages in one go.
- Don't let it add features not in the spec (the rules in CLAUDE.md say it shouldn't).
- Don't paste huge files or logs; point to the file name.

## Agents, chats, skills: what you need
- **Multiple agents:** not now. They multiply token use. One chat at a time.
- **Multiple chats:** yes, sequentially: one per task (that is how you keep it cheap).
- **Skills:** none needed yet. Possible later: a "release" skill once the Sparkle update steps are working, so shipping a version is one command.
- **Claude Design:** use in Stage 1 for the look. Bring screenshots of Photoculler and Aperture you like; save the result into `docs/DESIGN.md` so later chats can read it.

## Realistic expectations
- The two risky parts are (a) fast previews of big RAW files and (b) safely writing ratings into RAW files. That's why Stage 0 tests them first, before any UI work.
- Without a paid Apple account, the app can't be notarized: on each new Mac, the first launch needs right-click > Open. Updates after that are smooth.
- You need Xcode installed (free). Claude can write code and run builds, but you press Play and judge how it feels.
