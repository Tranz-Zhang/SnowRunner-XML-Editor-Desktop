# `initial.pak` — ZIP Format Analysis

File: `/Users/bytedance/Development/SnowRunner-XML-Editor-Desktop/test/initial.pak`

## 1. Overall identification

- Magic bytes at offset 0: `50 4B 03 04` → standard ZIP local file header (`PK\x03\x04`)
- `file(1)` output: `Zip archive data, at least v2.0 to extract, compression method=store`
- File size on disk: **26,728,935 bytes (≈26.7 MB)**
- Total uncompressed payload: **≈102.5 MB** across **10,308 entries**
- It is a renamed, plain ZIP container. SnowRunner's `.pak` is just a ZIP.

## 2. End-of-central-directory (EOCD)

```
EOCD signature : PK\x05\x06   at offset 0x0197D9D1 (26,728,913)
Central dir    : offset 0x0185C96A (25,545,066), length 0x00121067 (1,183,847) bytes
Total entries  : 10,308 (this disk == total)
Disks          : 1 (single-part archive)
Archive comment: (none)
ZIP64 locator  : NOT present
```

EOCD raw bytes:

```
0197d9d1: 50 4B 05 06 00 00 00 00 44 28 44 28 67 10 12 00
0197d9e1: 6A C9 85 01 00 00
```

## 3. Per-entry encoder fingerprint

From `zipinfo -v`:

- `file system or operating system of origin`: **Unix**
- `version of encoding software`: **2.0**
- `minimum software version required to extract`: **2.0**
- `minimum file system compatibility required`: **MS-DOS, OS/2 or NT FAT**
- `extended local header`: **no** (sizes/CRCs written up-front in the local file header, not in a trailing data descriptor)
- `length of extra field`: **0 bytes** for every entry
  - No Unicode path extra field (0x7075)
  - No NTFS times extra field (0x000A)
  - No Unix UID/GID / extended timestamp extra fields
- `length of file comment`: **0** for every entry
- `file security status`: **not encrypted**
- `apparent file type`: **binary**
- `Unix file attributes`: `100666 octal` (`-rw-rw-rw-`)
- `MS-DOS file attributes`: `00 hex` (none)

Conclusion: produced by a **minimal, deterministic ZIP writer running on Unix/Linux build infrastructure**, not WinRar/7-Zip on Windows.

## 4. Mixed compression per entry

The archive is not uniformly "stored". Only the manifest is uncompressed; everything else is deflated.

| Entry                                  | Method        | Ratio | Notes                                  |
|----------------------------------------|---------------|-------|----------------------------------------|
| `pak.load_list`                        | **Stored**    | 0%    | Kept uncompressed for direct seeking   |
| `[ssl_cache]\initial_debug.sslbundle`  | Deflated (N)  | ~73%  | Normal deflate level                   |
| `[ssl_cache]\initial_profile.sslbundle`| Deflated (N)  | ~73%  |                                        |
| `[ssl_cache]\initial_release.sslbundle`| Deflated (N)  | ~73%  |                                        |
| `[media]\_templates\*.xml`             | Deflated (N)  | ~82–85% | Standard text deflate                |
| `[media]\_dlc\...\classes\...\*.xml`   | Deflated (N)  | high  |                                        |
| `[strings]\strings_*.str`              | Deflated (N)  | high  |                                        |

Distinct methods present in the archive: only `Stored` and `Defl:N` (deflate, normal sub-type). No Deflate64, no BZIP2, no LZMA, no Zstd.

> Why `file initial.pak` reported "store": `file(1)` only inspects the **first local file header**, which happens to be `pak.load_list` (stored). Subsequent entries are deflated.

## 5. Path / naming conventions

- Path separator: **backslash `\`** (Windows-style), e.g.
  - `[media]\_templates\trucks.xml`
  - `[ssl_cache]\initial_debug.sslbundle`
- The ZIP APPNOTE/PKWARE specification mandates **forward slashes**. Many strict ZIP tools and libraries treat backslashed names as a single flat filename rather than a directory tree.
- Top-level names begin with bracketed tokens that act as **logical VFS namespaces**, not real directories on disk:
  - `[media]`     — game data (XML classes, templates, DLC content)
  - `[strings]`   — localized string tables (`*.str`)
  - `[ssl_cache]` — shader / SSL caches (`*.sslbundle`)
  - `[meta]`, etc.
- No directory ("folder") entries — only file entries; the tree is implicit in the filename strings.

## 6. Frozen DOS timestamps

Every entry is timestamped:

```
1980-01-01 03:00:00  (DOS date/time)
```

This is the DOS epoch base, deliberately fixed so the archive is **byte-reproducible and hash-stable** across rebuilds (no per-file mtime drift between CI runs).

## 7. Integrity

- Each entry carries a real **CRC-32** value, e.g.
  - `pak.load_list`                         → `e635b186`
  - `[ssl_cache]\initial_debug.sslbundle`   → `582f29b5`
  - `[ssl_cache]\initial_profile.sslbundle` → `10e14113`
  - `[ssl_cache]\initial_release.sslbundle` → `b07ae2cc`
- CRCs are correct and can be used by the game to verify on load.

## 8. What this archive does NOT use

- **No ZIP64** (sizes < 4 GB; entry count < 65,535 → fits in classic EOCD)
- **No encryption** (neither traditional ZipCrypto nor AES)
- **No archive comment**
- **No spanning / multi-disk**
- **No data descriptors** after entries (sizes/CRCs are known at write time)
- **No extra fields** (no Unicode path, no Unix/NTFS timestamps, no UID/GID)
- **No directory entries**
- **No exotic compression** (only Stored + Deflate-normal)

## 9. Inferred writer behavior

The producing tool sets, per entry:
- `version made by` low byte = 20 (PKZIP 2.0), high byte = 3 (Unix)
- `version needed to extract` = 20
- `general purpose bit flag` = 0 (no data descriptor, no UTF-8 name flag (bit 11) set, no encryption)
- `compression method` = 0 (stored) for the manifest, 8 (deflate) elsewhere
- `last mod time/date` = DOS 1980-01-01 03:00
- `extra field length` = 0
- External attributes encode `-rw-rw-rw-` (0o100666) shifted into the upper 16 bits per the ZIP spec for Unix.

## 10. Practical implications for the editor

Per [README.EN.md](file:///Users/bytedance/Development/SnowRunner-XML-Editor-Desktop/README.EN.md#L4-L5), the project bundles a portable WinRar to unpack/repack `initial.pak`. The reasons fall out of the format details above:

1. **Backslash paths.** Some `unzip` implementations / libraries refuse or mishandle `\` separators. WinRar tolerates them and round-trips them unchanged.
2. **Per-entry compression must be preserved.** In particular `pak.load_list` must remain **Stored**; if a repack accidentally deflates it, the game's manifest reader (which seeks/maps the entry directly) breaks.
3. **No extra fields should be injected.** Generic re-archivers tend to add Unicode path / Unix timestamp extras, changing local-header sizes and offsets — best avoided for compatibility.
4. **Timestamps should stay at 1980-01-01 03:00:00** to keep the archive byte-stable.
5. **Stay non-ZIP64, non-encrypted, no archive comment.** Don't enable features the game's loader doesn't expect.
6. **Path separator on write must be `\`**, not `/`, to match existing entries.

## 11. Quick reference: header dump (first 32 bytes)

```
00000000: 50 4B 03 04 14 00 00 00 00 00 00 18 21 00 86 B1   PK..........!...
00000010: 35 E6 5A AE 21 00 5A AE 21 00 0D 00 00 00 70 61   5.Z.!.Z.!.....pa
```

Decoded:

| Field                    | Value (LE)         | Meaning                        |
|--------------------------|--------------------|--------------------------------|
| Signature                | `50 4B 03 04`      | Local file header              |
| Version needed           | `14 00` = 20       | PKZIP 2.0                      |
| GP bit flag              | `00 00`            | none                           |
| Compression method       | `00 00`            | **Stored**                     |
| Last mod time            | `00 00`            | 00:00 (DOS)                    |
| Last mod date            | `21 00`            | 1980-01-01                     |
| CRC-32                   | `86 B1 35 E6`      | `0xE635B186`                   |
| Compressed size          | `5A AE 21 00`      | `0x0021AE5A` = 2,207,322       |
| Uncompressed size        | `5A AE 21 00`      | `0x0021AE5A` = 2,207,322       |
| Filename length          | `0D 00`            | 13 (= len("pak.load_list"))    |
| Extra field length       | `00 00`            | 0                              |
| Filename                 | `pa…`              | `pak.load_list`                |

This matches the central-directory entry exactly.

## 12. `pak.load_list` — boot-time resource manifest

`pak.load_list` is the very first entry in the archive (entry #1), stored uncompressed, 2,207,322 bytes. It is **not** a ZIP container itself — it is a custom binary manifest that the game reads at startup to discover, in order, every resource it needs to load and *which* `.pak` to load it from.

This is also why it must remain **Stored** inside `initial.pak`: the loader maps/seeks it directly without going through a deflate stream.

### 12.1 What it contains

A binary, length-prefixed table of records, grouped into named **load phases**. Each record is roughly:

```
{
  path          : string   // VFS path, e.g. <media>\_templates\trucks.xml
  loader_type   : string   // cls_loader / tpl_loader / sslbundle / mesh_loader / sound_loader / ...
  source_pak    : string   // initial.pak | shared.pak | shared_debug.pak | shared_sound.pak
  flags         : byte(s)  // load priority / category
}
```

`strings(1)` extracts ~53,716 strings — that is roughly 3 strings per record × ~17,900 records, plus the phase headers and small flag/index tables. Note this is significantly **more than the 10,308 ZIP entries** in `initial.pak` because the manifest also indexes content stored in the *other* paks.

### 12.2 Load phases observed (in order)

```
RES3_INIT load
SSL_SOURCES_PARSE load
SSL_INITIAL load
TEMPLATES load
RES3_PROJECT load
PROJECT load
DEFAULT load
DESC_BLOCK load
```

Each phase header is a short ASCII tag followed by the literal token `load`, then the array of records belonging to that phase.

### 12.3 Loader types and counts

| loader_type    | Count   | Purpose                                       |
|----------------|---------|-----------------------------------------------|
| `cls_loader`   | 10,284  | XML "class" files (trucks, trailers, engines, suspensions, tuning parts, …) — the bulk of the manifest |
| `tpl_loader`   | 5       | Template XMLs (`environment`, `models`, `plants`, `trailers`, `trucks`) |
| `sslbundle`    | 3       | Shader/SSL caches (debug / profile / release) |
| `mesh_loader`  | (refd)  | Geometry meshes                               |
| `sound_loader` | (refd)  | Audio                                         |

### 12.4 Source `.pak` files referenced

The manifest cross-references **four** archives:

```
initial.pak
shared.pak
shared_debug.pak
shared_sound.pak
```

So `pak.load_list` is the master VFS index for the **initial boot phase across all base game paks**, not just the archive it lives in.

### 12.5 Path namespace convention inside the manifest

Note the path prefixes use **angle brackets**, e.g. `<media>\...`, `<ssl_cache>\...`, while the ZIP entries themselves use **square brackets** (`[media]\...`, `[ssl_cache]\...`). The game's loader resolves `<name>` to the matching `[name]` namespace inside the target `.pak`. This is a deliberate two-form convention: `<…>` in the manifest, `[…]` on disk.

### 12.6 Header / structure (inferred from the byte layout)

First bytes:

```
00000000: 01 00 00 00 01 FD 45 00 00 03 00 00 00 01 05 01
00000010: 01 02 02 02 02 02 02 02 01 02 02 02 02 02 01 02
...
```

- `01 00 00 00` — version / format tag
- `01 FD 45 00 00` — reads as a 5-byte field; the 32-bit value `0x000045FD` = **17,917**, which roughly matches the total number of indexed records (≈10,284 cls + 5 tpl + 3 sslbundle + thousands more from `shared*.pak`).
- `03 00 00 00` — likely the count of source-pak strings (`initial.pak`, `shared.pak`, `shared_debug.pak`, `shared_sound.pak` — note the loader may dedup `shared_debug.pak`).
- The long run of bytes `01 02 02 02 02 02 …` (and a similar block at the tail) is a **per-record flag/category table** — one byte per record. That's why the file is ~2 MB despite "only" containing ~18k records: it has both the byte-flag table and a long array of length-prefixed string triples.

Tail bytes:

```
0021ade0: ... 01 01 01 11 00 00 00 52 45 53 33 5F 50 52 4F 4A   ...........RES3_PROJ
0021adf0:     45 43 54 20 6C 6F 61 64 01 00 00 00 02 00 00 00   ECT load........
0021ae00:     01 01 01 0C 00 00 00 50 52 4F 4A 45 43 54 20 6C   .......PROJECT l
0021ae10:     6F 61 64 01 00 00 00 02 00 00 00 01 01 01 0C 00   oad.............
0021ae20:     00 00 44 45 46 41 55 4C 54 20 6C 6F 61 64 01 00   ..DEFAULT load..
0021ae30:     00 00 02 00 00 00 01 01 01 0F 00 00 00 44 45 53   .............DES
0021ae40:     43 5F 42 4C 4F 43 4B 20 6C 6F 61 64 00 00 00 00   C_BLOCK load....
0021ae50:     02 00 00 00 01 01                                 ......
```

Pattern: each phase tag is written as `<u32 length><ASCII bytes>`, followed by a small fixed footer (`01 00 00 00 02 00 00 00 01 01 01`) that likely encodes (record-count, phase-flags). The final phase `DESC_BLOCK load` ends with `00 00 00 00 02 00 00 00 01 01` — the manifest's terminator.

### 12.7 Do you have to update `pak.load_list` when modifying the pak?

**Depends on the operation:**

| Operation                                                              | Update `pak.load_list`? |
|------------------------------------------------------------------------|-------------------------|
| Edit an existing XML in place (typical use of this editor)             | **No** — path/loader/source unchanged. Only the ZIP entry's bytes & CRC change. |
| Add a brand-new class XML (e.g. a new truck under `[media]\...\trucks\my_truck.xml`) | **Yes** — must append a `cls_loader` record in the `DESC_BLOCK load` phase, increment the header counts, and re-store the manifest. |
| Add a new template XML under `[media]\_templates\...`                  | **Yes** — `tpl_loader` record in `TEMPLATES load`. |
| Replace an existing file with a *different* filename                   | **Yes** — manifest still references the old name. Either keep the original filename or update the manifest. |
| Add new mesh / sound / shader / texture                                | **Yes** — record with the matching `mesh_loader` / `sound_loader` / `sslbundle` / etc. |
| Ship the changes as a separate mod `.pak` (DLC-style, see `[media]\_dlc\DLC_*\`) | **No** — separate paks have their own manifest; `initial.pak`'s `pak.load_list` is untouched. |

### 12.8 Why this matters for the editor

The XML editor in this project is by design a **read-modify-write of existing `<media>\...\*.xml` entries only**. That is exactly the case where `pak.load_list` does **not** need to change — which is convenient, because parsing/regenerating the binary manifest correctly (counts, flag bytes, phase footers, terminator) is non-trivial and error-prone. Any feature that *adds* or *renames* files would have to reverse-engineer and rewrite this manifest, or fall back to the separate-mod-pak approach.

## 13. Tooling — SnowPakTool

If you ever **do** need to add/rename files (i.e. write a new `pak.load_list`), don't reinvent the binary writer — use the community tool that already encodes the format correctly.

### 13.1 What it is

**SnowPakTool** (part of the [SnowRunnerTools](https://gitmemories.com/index.php/chase-000/SnowRunnerTools) repository by `chase-000`, source on GitHub at `github.com/chase-000/SnowRunnerTools`) is a small command-line utility purpose-built for SnowRunner's pak quirks. From its README:

> SnowRunner Tools is a set of utilities to handle SnowRunner data files. Its PAK files are really ZIP files with a particular layout and can be extracted with any common tools like 7-Zip, but **require a bit of special handling to create**.

Capabilities:

- Compress files into a single PAK file (preserves the **stored vs. deflated** split per entry).
- **Create `initial.pak\pak.load_list`** — generates the binary manifest with the correct header, per-record flag bytes, phase footers, and terminator. This is the part you cannot trivially do with a generic ZIP tool.
- Create `shared_sound.pak\sound.sound_list` (the analogous manifest for the audio pak).
- Pack/unpack `initial.pak\initial.cache_block` (UI layout, settings, translations, etc.).

### 13.2 Why it matters for §12

§12 documented the **structure** of `pak.load_list` (load phases, loader types, source-pak strings, header counts, per-record flag table, phase footers). SnowPakTool is currently the **only public, working implementation** of a `pak.load_list` writer. Reading its source is the most reliable way to learn the precise byte layout if you want to port the logic into this Electron editor or another tool.

### 13.3 Typical command-line usage

Unpack `initial.pak`, edit content, repack — from the SnowPakTool README:

```bat
set client=D:\Games\SnowRunner\en_us\preload\paks\client

REM unpack
7z x -o"initial-pak" "%client%\initial.pak"
snowpaktool cb unpack --allow-mixing "initial-pak\initial.cache_block" "initial-pak"
del "initial-pak\initial.cache_block"

REM ... edit XML / drop in new files ...

REM repack (regenerates pak.load_list, restores stored/deflate split, fixed timestamps)
del "%client%\initial.pak"
snowpaktool pak pack --mixed-cache-block "initial-pak" "%client%\initial.pak"
```

Key behaviors:

- The `pak pack` subcommand keeps `pak.load_list` **stored** (uncompressed) as required by the game's loader.
- It uses backslash paths and avoids extra fields, matching the conventions documented in §3, §5, §8.
- `cb unpack --allow-mixing` separates the contents of `initial.cache_block` into a per-namespace tree alongside `[media]\...`, `[strings]\...`, etc., which is necessary if you want to edit anything that lives inside the cache block (UI, localization, default settings).

### 13.4 Where SnowPakTool fits the workflows from §10 / Option B

| Workflow                                       | Use of SnowPakTool                                                                 |
|------------------------------------------------|------------------------------------------------------------------------------------|
| Edit existing XML only (this Electron editor)  | Not strictly required — WinRar can round-trip an unchanged file list. Still useful for guaranteeing the stored/deflate split. |
| Re-pack a modified `initial.pak` (Option D)    | **Recommended.** Preserves `pak.load_list`, cache_block, timestamps, and per-entry method. |
| Build an Option-B sideload mod pak with **new** files | **Required** — generate your mod's own `pak.load_list` with the new `cls_loader` / `tpl_loader` / etc. records, then pack into `<your_mod>.pak`. |
| Edit `initial.cache_block` (UI/strings/settings) | **Required** — only SnowPakTool unpacks/repacks the cache_block format.            |

### 13.5 Companion tool

The same repo also ships **SnowTruckConfig**, which operates one level above the manifest:

- Add top-center crane sockets to lift vehicles.
- Change customization-camera FOV.
- Rename game objects to embed detailed info into their names.

It works on already-unpacked XML (e.g. `initial-pak\[media]\classes\trucks\hummer_h2.xml`) and pairs naturally with SnowPakTool for the unpack/repack steps.

### 13.6 Caveats

- **Windows-first.** SnowPakTool is a .NET CLI; on macOS/Linux you'll typically run it via Wine or .NET on Linux. Functionality is identical because the pak format is platform-neutral, but paths in the examples are Windows-style.
- **No published binary spec** of `pak.load_list` exists from Saber. SnowPakTool's source is the de-facto reference for the manifest's exact bytes — pin a known-good version if you embed its logic into another project.
- **Always back up `initial.pak`** before letting any tool repack it; a corrupted `pak.load_list` makes the game fail to boot rather than fail gracefully.
- The README does **not** describe a separate `loadlist build` mode for arbitrary mod paks; that's typically handled by `pak pack` over a directory tree that includes a hand-laid-out (or copied-from-base) `pak.load_list`. Inspect the source / `--help` of the version you install for current subcommands.

### 13.7 Quick reference

- Repo (mirror): https://gitmemories.com/index.php/chase-000/SnowRunnerTools
- Source: https://github.com/chase-000/SnowRunnerTools
- Subcommands relevant to this doc:
  - `snowpaktool pak pack <src_dir> <out.pak>` — pack a directory back into a `.pak` (regenerates manifest).
  - `snowpaktool pak unpack <in.pak> <dst_dir>` — counterpart to `7z x` but format-aware.
  - `snowpaktool cb unpack <initial.cache_block> <dst_dir>` — split `initial.cache_block` into source files.
  - `snowpaktool cb pack` — recombine a cache_block.
- Companion: `snowtruckconfig` (vehicle XML batch operations).
