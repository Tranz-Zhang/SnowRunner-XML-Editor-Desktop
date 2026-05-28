# Local macOS Development Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the SnowRunner XML Editor run locally on macOS in development mode, including selecting, unpacking, editing, and saving `initial.pak`.

**Architecture:** Keep Electron/Vue/TypeScript intact. Replace the hard Windows dependency at the archive boundary with a platform-selected archive backend: WinRAR on Windows and macOS system `zip`/`unzip` plus explicit path conversion on Darwin. Guard Windows-only menu/update/install actions while keeping the rest of the application behavior unchanged.

**Tech Stack:** Electron Forge, Vite, Vue, TypeScript, Node `child_process`, Node `fs/promises`, macOS `/usr/bin/zip`, `/usr/bin/unzip`, `/usr/bin/zipinfo`.

---

## File Structure

- Create `src/modules/archive/main/archiver/types.ts`
  - Shared archive backend interface.
- Create `src/modules/archive/main/archiver/utils.ts`
  - Archive-entry path conversion and unpack-list parsing.
- Create `src/modules/archive/main/archiver/utils.test.ts`
  - Node built-in tests for path conversion and list matching.
- Create `src/modules/archive/main/archiver/winrar.ts`
  - Move the current WinRAR implementation here with no behavior change.
- Create `src/modules/archive/main/archiver/zip-macos.ts`
  - macOS archive backend using system ZIP tools.
- Modify `src/modules/archive/main/archiver/index.ts`
  - Export the correct backend for `process.platform`.
- Modify `src/modules/archive/main/index.ts`
  - Keep public API stable; call backend through the new interface.
- Modify `src/modules/checks/main.ts`
  - Rename semantics from administrator-only to app/file permission checks.
- Modify `src/main/texts.ts` and `src/modules/checks/texts.ts`
  - Replace administrator wording with generic permission wording.
- Modify `src/renderer/components/menu/index.vue`
  - Hide Windows-only uninstall/update actions on macOS.
- Modify `src/modules/updates/main.ts`
  - Make updater a no-op warning on macOS local dev.
- Modify `src/renderer/pages/general/setup/initial-select.vue`
  - Keep manual `initial.pak` selection primary; add macOS Steam path candidates for folder selection.
- Modify `package.json`
  - Add macOS dev/test scripts without changing Windows packaging.

---

### Task 1: Add Archive Path Utilities

**Files:**
- Create: `src/modules/archive/main/archiver/types.ts`
- Create: `src/modules/archive/main/archiver/utils.ts`
- Create: `src/modules/archive/main/archiver/utils.test.ts`

- [ ] **Step 1: Add failing tests for path conversion and list matching**

Create `src/modules/archive/main/archiver/utils.test.ts`:

```ts
import assert from 'node:assert/strict'
import { describe, it } from 'node:test'
import {
  archiveEntryToLocalParts,
  localRelativePathToArchiveEntry,
  unpackListPatternMatchesEntry
} from './utils.ts'

describe('macOS archive path helpers', () => {
  it('converts Windows-style archive entries into local path parts', () => {
    assert.deepEqual(
      archiveEntryToLocalParts('[media]\\classes\\trucks\\foo.xml'),
      ['[media]', 'classes', 'trucks', 'foo.xml']
    )
  })

  it('converts local relative POSIX paths back to archive entries', () => {
    assert.equal(
      localRelativePathToArchiveEntry('[media]/classes/trucks/foo.xml'),
      '[media]\\classes\\trucks\\foo.xml'
    )
  })

  it('matches direct files from unpack lists', () => {
    assert.equal(
      unpackListPatternMatchesEntry('[strings]\\strings_english.str', '[strings]\\strings_english.str'),
      true
    )
  })

  it('matches folders from unpack lists', () => {
    assert.equal(
      unpackListPatternMatchesEntry('[media]\\classes\\trucks', '[media]\\classes\\trucks\\foo.xml'),
      true
    )
  })

  it('does not match sibling folders with the same prefix', () => {
    assert.equal(
      unpackListPatternMatchesEntry('[media]\\classes\\truck', '[media]\\classes\\trucks\\foo.xml'),
      false
    )
  })
})
```

- [ ] **Step 2: Run the test to verify it fails before implementation**

Run:

```bash
node --loader ts-node/esm --test src/modules/archive/main/archiver/utils.test.ts
```

Expected: FAIL because `src/modules/archive/main/archiver/utils.ts` does not exist yet.

- [ ] **Step 3: Create the shared archive backend type**

Create `src/modules/archive/main/archiver/types.ts`:

```ts
import type { IDir, IFile } from '../../../main'

export interface ArchiveBackend {
  update(dir: IDir, archive: IFile): Promise<void>
  unpack(archive: IFile, dir: IDir): Promise<void>
  add(file: IFile, archive: IFile): Promise<void>
}
```

- [ ] **Step 4: Implement TypeScript helpers**

Create `src/modules/archive/main/archiver/utils.ts`:

```ts
import { readFile } from 'node:fs/promises'
import { join } from 'node:path'

export function archiveEntryToLocalParts(entry: string): string[] {
  return entry.split('\\').filter(Boolean)
}

export function localRelativePathToArchiveEntry(path: string): string {
  return path.split('/').filter(Boolean).join('\\')
}

export function unpackListPatternMatchesEntry(pattern: string, entry: string): boolean {
  const normalizedPattern = pattern.replaceAll('/', '\\')

  return entry === normalizedPattern || entry.startsWith(`${normalizedPattern}\\`)
}

export async function readUnpackList(baseDir: string, name: string): Promise<string[]> {
  const raw = await readFile(join(baseDir, name), 'utf8')

  return raw
    .split(/\r?\n/)
    .map(line => line.trim())
    .filter(Boolean)
}
```

- [ ] **Step 5: Run tests and typecheck**

Run:

```bash
node --loader ts-node/esm --test src/modules/archive/main/archiver/utils.test.ts
npm run check
```

Expected: both PASS if dependencies are installed. If `node_modules` is missing, run `npm i` first.

- [ ] **Step 6: Commit**

```bash
git add src/modules/archive/main/archiver/types.ts src/modules/archive/main/archiver/utils.ts src/modules/archive/main/archiver/utils.test.ts
git commit -m "feat: add archive path helpers"
```

---

### Task 2: Preserve WinRAR Backend Behind an Interface

**Files:**
- Create: `src/modules/archive/main/archiver/winrar.ts`
- Modify: `src/modules/archive/main/archiver/index.ts`

- [ ] **Step 1: Move current implementation to `winrar.ts`**

Copy the current contents of `src/modules/archive/main/archiver/index.ts` into `src/modules/archive/main/archiver/winrar.ts`, then make these edits at the top:

```ts
import { execFile } from 'node:child_process'
import type { ArchiveBackend } from './types'
import type { IDir, IFile } from '../../../main'
import { DEBUG_ARCHIVER } from '/consts'
import Config from '/mods/data/config/main'
import { ErrorText, ProgramError } from '/mods/errors/main'
import { Dirs } from '/mods/files/main'
import Paths from '/mods/paths/main'
```

Change the class declaration:

```ts
class WinRAR implements ArchiveBackend {
```

Keep the rest of the file behavior unchanged.

- [ ] **Step 2: Replace `index.ts` with a backend export**

Replace `src/modules/archive/main/archiver/index.ts` with:

```ts
import WinRAR from './winrar'

export default WinRAR
```

- [ ] **Step 3: Run typecheck**

Run:

```bash
npm run check
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add src/modules/archive/main/archiver/index.ts src/modules/archive/main/archiver/winrar.ts
git commit -m "refactor: isolate WinRAR archive backend"
```

---

### Task 3: Add macOS ZIP Archive Backend

**Files:**
- Create: `src/modules/archive/main/archiver/zip-macos.ts`
- Modify: `src/modules/archive/main/archiver/index.ts`

- [ ] **Step 1: Implement the macOS backend**

Create `src/modules/archive/main/archiver/zip-macos.ts`:

```ts
import { execFile } from 'node:child_process'
import { mkdtemp, readdir, readFile, rm, writeFile } from 'node:fs/promises'
import { basename, join, relative } from 'node:path'
import { tmpdir } from 'node:os'
import type { ArchiveBackend } from './types'
import {
  archiveEntryToLocalParts,
  localRelativePathToArchiveEntry,
  readUnpackList,
  unpackListPatternMatchesEntry
} from './utils'
import Config from '/mods/data/config/main'
import { ErrorText, ProgramError } from '/mods/errors/main'
import type { IDir, IFile } from '/mods/files/main'
import { Dir, File } from '/mods/files/main'
import Paths from '/mods/paths/main'

type ExecResult = {
  stdout: string
  stderr: string
}

class ZipMacOS implements ArchiveBackend {
  private readonly lists = {
    main: 'unpack-list.lst',
    mods: 'unpack-mod-list.lst',
    mainOptimized: 'unpack-list-optimized.lst'
  }

  async update(dir: IDir, archive: IFile) {
    await archive.chmod(0o666)

    const archiveEntries = await this.listEntries(archive)
    const stage = new Dir(await mkdtemp(join(tmpdir(), 'sxmle-zip-update-')))

    try {
      for (const localFile of await this.findFiles(dir)) {
        const relativeLocal = relative(dir.path, localFile.path).split('/').join('/')
        const archiveEntry = localRelativePathToArchiveEntry(relativeLocal)

        if (!archiveEntries.includes(archiveEntry)) {
          continue
        }

        const stagedFile = stage.file(archiveEntry)
        await stagedFile.write(await localFile.read())
      }

      await this.run('zip', ['-0', '-f', archive.path, ...await this.stageFiles(stage)], stage.path)
    } finally {
      await stage.remove()
    }
  }

  async unpack(archive: IFile, dir: IDir) {
    const list = await this.getUnpackList(archive)
    const entries = await this.listEntries(archive)
    const selectedEntries = entries.filter(entry =>
      list.some(pattern => unpackListPatternMatchesEntry(pattern, entry))
    )

    await dir.make()

    for (const entry of selectedEntries) {
      const data = await this.readEntry(archive, entry)
      const file = dir.file(...archiveEntryToLocalParts(entry))

      await file.write(data)
    }
  }

  async add(file: IFile, archive: IFile) {
    const stage = new Dir(await mkdtemp(join(tmpdir(), 'sxmle-zip-add-')))

    try {
      const stagedFile = stage.file(file.basename())
      await stagedFile.write(await file.read())
      await this.run('zip', ['-0', '-u', archive.path, stagedFile.basename()], stage.path)
    } finally {
      await stage.remove()
    }
  }

  private async getUnpackList(archive: IFile): Promise<string[]> {
    const isMod = !!Config.initialPath && archive.path !== Config.initialPath
    const listName = isMod
      ? this.lists.mods
      : Config.optimizeUnpack
        ? this.lists.mainOptimized
        : this.lists.main

    return readUnpackList(Paths.winrar, listName)
  }

  private async listEntries(archive: IFile): Promise<string[]> {
    const { stdout } = await this.run('zipinfo', ['-1', archive.path])

    return stdout
      .split(/\r?\n/)
      .map(line => line.trim())
      .filter(Boolean)
  }

  private async readEntry(archive: IFile, entry: string): Promise<string> {
    const escaped = entry
      .replaceAll('[', '\\[')
      .replaceAll(']', '\\]')
    const { stdout } = await this.run('unzip', ['-p', archive.path, escaped])

    return stdout
  }

  private async findFiles(dir: IDir): Promise<IFile[]> {
    const result: IFile[] = []

    for (const entry of await dir.read()) {
      if (await entry.isDir()) {
        result.push(...await this.findFiles(entry.asDir()))
      } else {
        result.push(entry.asFile())
      }
    }

    return result
  }

  private async stageFiles(dir: IDir): Promise<string[]> {
    const files = await this.findFiles(dir)

    return files.map(file => relative(dir.path, file.path))
  }

  private run(command: string, args: string[], cwd?: string): Promise<ExecResult> {
    const { promise, resolve, reject } = Promise.withResolvers<ExecResult>()

    execFile(command, args, { cwd }, (error, stdout, stderr) => {
      if (error) {
        reject(new ProgramError(ErrorText.winRarCommandError, error, `${command} ${args.join(' ')}`))
        return
      }

      resolve({ stdout, stderr })
    })

    return promise
  }
}

export default new ZipMacOS()
```

- [ ] **Step 2: Select backend by platform**

Replace `src/modules/archive/main/archiver/index.ts` with:

```ts
import WinRAR from './winrar'
import ZipMacOS from './zip-macos'

export default process.platform === 'darwin'
  ? ZipMacOS
  : WinRAR
```

- [ ] **Step 3: Run typecheck**

Run:

```bash
npm run check
```

Expected: PASS. If TypeScript flags unused imports in `zip-macos.ts`, remove only the imports named in the error.

- [ ] **Step 4: Test against `test/initial.pak` manually**

Run:

```bash
cp test/initial.pak.before-zip-test test/initial.pak
npm start
```

In the app:

1. Select `test/initial.pak` manually.
2. Let it unpack.
3. Confirm lists load.
4. Open one editable XML item.
5. Save.

Then run:

```bash
unzip -tqq test/initial.pak
unzip -l test/initial.pak edited
```

Expected: `unzip -tqq` exits 0 and `edited` exists.

- [ ] **Step 5: Commit**

```bash
git add src/modules/archive/main/archiver/index.ts src/modules/archive/main/archiver/zip-macos.ts
git commit -m "feat: add macOS zip archive backend"
```

---

### Task 4: Fix Permission Check Wording and Behavior

**Files:**
- Modify: `src/modules/checks/main.ts`
- Modify: `src/main/texts.ts`
- Modify: `src/modules/checks/texts.ts`
- Modify: `src/modules/checks/renderer.ts`

- [ ] **Step 1: Rename permission method in main process**

In `src/modules/checks/main.ts`, rename:

```ts
async hasAdminPrivileges(): Promise<boolean> {
```

to:

```ts
async hasAppDataPermissions(): Promise<boolean> {
```

Keep the method body mostly unchanged because the real check is read/write access to the app JSON file.

- [ ] **Step 2: Update startup call**

In `src/main/index.ts`, replace:

```ts
await Loading.runRequiredStage(texts.checkAdminPrivileges, Checks.hasAdminPrivileges.bind(Checks))
```

with:

```ts
await Loading.runRequiredStage(texts.checkAppDataPermissions, Checks.hasAppDataPermissions.bind(Checks))
```

- [ ] **Step 3: Update renderer bridge name**

In `src/modules/checks/renderer.ts`, replace:

```ts
hasAdminPrivileges!: typeof MainChecks.hasAdminPrivileges
```

with:

```ts
hasAppDataPermissions!: typeof MainChecks.hasAppDataPermissions
```

- [ ] **Step 4: Update startup text**

In `src/main/texts.ts`, rename `checkAdminPrivileges` to `checkAppDataPermissions` and use:

```ts
checkAppDataPermissions: new BaseLocalization()
  .ru('Проверка доступа к данным программы')
  .en('Checking app data permissions')
  .de('Überprüfung der App-Datenberechtigungen')
  .ch('检查应用数据权限'),
```

- [ ] **Step 5: Update failure text**

In `src/modules/checks/texts.ts`, replace the administrator text with:

```ts
appDataPermissionError: new BaseLocalization()
  .ru('Ошибка запуска. Программа не может читать или записывать свои файлы данных.')
  .en('Startup error. The program cannot read or write its app data files.')
  .de('Startfehler. Das Programm kann seine App-Datendateien nicht lesen oder schreiben.')
  .ch('启动错误。程序无法读取或写入其应用数据文件。'),
```

Then update the caller in `src/modules/checks/main.ts` from `texts.adminRequiredMessage` to `texts.appDataPermissionError`.

- [ ] **Step 6: Run typecheck**

Run:

```bash
npm run check
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add src/main/index.ts src/main/texts.ts src/modules/checks/main.ts src/modules/checks/renderer.ts src/modules/checks/texts.ts
git commit -m "fix: use generic app data permission check"
```

---

### Task 5: Guard Windows-Only UI and Update Flows

**Files:**
- Modify: `src/renderer/components/menu/index.vue`
- Modify: `src/modules/updates/main.ts`
- Modify: `src/modules/paths/main.ts`
- Modify: `src/modules/paths/types.ts`

- [ ] **Step 1: Expose platform through Paths**

In `src/modules/paths/types.ts`, add:

```ts
platform: NodeJS.Platform
```

In `src/modules/paths/main.ts`, add to the `object`:

```ts
platform: process.platform,
```

- [ ] **Step 2: Hide uninstall menu item on macOS**

In `src/renderer/components/menu/index.vue`, add:

```ts
const isWindows = Paths.platform === 'win32'
```

Replace the uninstall item with a spread:

```ts
...isWindows
  ? [{
    key: 'uninstall_program',
    label: texts.uninstallMenuItemLabel,
    onClick: () => {
      void Files.uninstall.exec()
      Helpers.quitApp()
    }
  }]
  : []
```

- [ ] **Step 3: Make updater explicit on macOS**

In `src/modules/updates/main.ts`, add at the start of `updateApp`:

```ts
if (process.platform === 'darwin') {
  shell.openExternal(Paths.downloadPage)
  return
}
```

This keeps local macOS development from downloading Windows `.exe` or `.rar` update payloads.

- [ ] **Step 4: Run typecheck**

Run:

```bash
npm run check
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/renderer/components/menu/index.vue src/modules/updates/main.ts src/modules/paths/main.ts src/modules/paths/types.ts
git commit -m "fix: guard Windows-only actions on macOS"
```

---

### Task 6: Improve macOS `initial.pak` Discovery

**Files:**
- Modify: `src/renderer/pages/general/setup/initial-select.vue`

- [ ] **Step 1: Replace single path candidate with platform-aware candidates**

In `findInitial`, replace the current mutable `parts` loop with:

```ts
async function findInitial(dir: IDir): Promise<IFile | undefined> {
  const candidates = [
    ['steamapps', 'common', 'SnowRunner', 'en_us', 'preload', 'paks', 'client', 'initial.pak'],
    ['common', 'SnowRunner', 'en_us', 'preload', 'paks', 'client', 'initial.pak'],
    ['SnowRunner', 'en_us', 'preload', 'paks', 'client', 'initial.pak'],
    ['en_us', 'preload', 'paks', 'client', 'initial.pak'],
    ['preload', 'paks', 'client', 'initial.pak'],
    ['paks', 'client', 'initial.pak'],
    ['client', 'initial.pak'],
    ['initial.pak']
  ]

  for (const parts of candidates) {
    const file = dir.file(...parts)

    if (await file.exists()) {
      return file
    }
  }
}
```

This is not macOS-specific, but it makes folder selection more tolerant across Steam library roots.

- [ ] **Step 2: Run typecheck**

Run:

```bash
npm run check
```

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add src/renderer/pages/general/setup/initial-select.vue
git commit -m "fix: make initial pak folder discovery more tolerant"
```

---

### Task 7: Add Local macOS Scripts and Docs

**Files:**
- Modify: `package.json`
- Modify: `README.EN.md`

- [ ] **Step 1: Add scripts**

In `package.json`, update scripts:

```json
"start": "cross-env NODE_ENV=development electron-forge start",
"start:mac": "cross-env NODE_ENV=development electron-forge start",
"test:archive": "node --loader ts-node/esm --test src/modules/archive/main/archiver/utils.test.ts",
"check": "tsc --project src/tsconfig.json --noEmit && vue-tsc --project src/tsconfig.json --noEmit"
```

Do not change the existing Windows package scripts in this task.

- [ ] **Step 2: Document local macOS development**

In `README.EN.md`, under Development, add:

```md
### macOS local development

The app can run locally on macOS in development mode. macOS builds and installers are not part of this workflow.

Requirements:

- Node.js
- macOS system `zip`, `unzip`, and `zipinfo`
- A readable and writable `initial.pak`

Start:

```cmd
npm run start:mac
```

On macOS, prefer selecting `initial.pak` directly if automatic game-folder detection does not find it.
```

- [ ] **Step 3: Run tests and typecheck**

Run:

```bash
npm run test:archive
npm run check
```

Expected: both PASS.

- [ ] **Step 4: Commit**

```bash
git add package.json README.EN.md
git commit -m "docs: add macOS local development workflow"
```

---

### Task 8: End-to-End Verification on macOS

**Files:**
- No source changes expected.
- Uses: `test/initial.pak`

- [ ] **Step 1: Restore test archive**

Run:

```bash
cp test/initial.pak.before-zip-test test/initial.pak
unzip -tqq test/initial.pak
```

Expected: `unzip -tqq` exits 0.

- [ ] **Step 2: Start the app**

Run:

```bash
npm run start:mac
```

Expected: Electron launches and shows setup or main window.

- [ ] **Step 3: Select test archive**

In the app:

1. Choose manual `initial.pak`.
2. Select `test/initial.pak`.
3. Confirm app reloads.
4. Confirm the list page opens.

- [ ] **Step 4: Save one item**

In the app:

1. Open one truck or trailer.
2. Change a harmless numeric value.
3. Save.
4. Quit the app.

- [ ] **Step 5: Verify archive integrity and marker**

Run:

```bash
unzip -tqq test/initial.pak
unzip -l test/initial.pak edited
```

Expected:

- `unzip -tqq` exits 0.
- `edited` is listed.

- [ ] **Step 6: Verify updated archive still has Windows-style entries**

Run:

```bash
zipinfo -1 test/initial.pak | rg '\\[media\\]\\\\classes\\\\trucks'
```

Expected: entries are still stored with backslashes, matching SnowRunner archive style.

- [ ] **Step 7: Commit any verification fixes**

If verification required source fixes:

```bash
git add src/modules/archive/main/archiver/zip-macos.ts src/modules/archive/main/archiver/index.ts src/modules/archive/main/archiver/utils.ts src/modules/archive/main/archiver/utils.test.ts src/renderer/components/menu/index.vue src/modules/updates/main.ts src/modules/paths/main.ts src/modules/paths/types.ts src/renderer/pages/general/setup/initial-select.vue package.json README.EN.md
git commit -m "fix: complete macOS local development verification"
```

If no fixes were required, do not create an empty commit.

---

## Self-Review

- Spec coverage: The plan covers archive IO, path normalization, app startup permissions, Windows-only UI/update actions, setup discovery, dev scripts, docs, and end-to-end verification.
- Scope check: This is local macOS development only. Packaging, signing, notarization, `.dmg`, auto-update distribution, and macOS installer behavior are intentionally excluded.
- Placeholder scan: No task relies on an unspecified implementation step.
- Type consistency: `ArchiveBackend`, `ZipMacOS`, `WinRAR`, and helper names are defined before later tasks use them.
