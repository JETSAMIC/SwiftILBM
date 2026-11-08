# The IFF ILBM and PBM Image Formats

A byte-level reference for implementers of readers (and writers) of Amiga
bitmap images: the EA IFF 85 container, the `FORM ILBM` and `FORM PBM `
image forms, the Commodore-Amiga display-mode chunk `CAMG`, the
Hold-And-Modify and Extra-Half-Brite display modes, and — at least at the
layout level — the related image forms (`ACBM`, `RGBN`, `RGB8`, `DEEP`) and
the `ANIM` animation deltas that are built on the same container.

This document is the single authoritative format reference for SwiftILBM.
Section 9 records which parts the package implements.

Contents

1. Overview
2. Conventions
3. Byte-level layouts
4. Enumerations and flags
5. Algorithms
6. Semantics and de-facto behaviour
7. Robustness guidance for readers
8. Errata
9. Implementation status (SwiftILBM)
10. References and provenance

---

## 1. Overview

### 1.1 What the format is

**EA IFF 85** ("Interchange File Format", full name "EA IFF 1985") is a
generic tagged container published by Jerry Morrison of Electronic Arts on
14 January 1985, designed together with Commodore-Amiga as the interchange
standard for the then-new Amiga. An IFF file is a tree of *chunks*: each
chunk is a four-character identifier, a 32-bit big-endian length and that many
payload bytes. Three *group* chunk kinds (`FORM`, `LIST`, `CAT `) nest other
chunks, and `PROP` supplies shared properties inside a `LIST`.

**ILBM** ("InterLeaved BitMap") was the first IFF `FORM` type and became the
native raster image format of the Amiga. Its specification, also by Jerry
Morrison, is dated 17 January 1986; the colour-cycling section was updated by
Morrison in October 1988, and in the same month Commodore-Amiga added the
`CAMG` reader rules and an appendix of additional information. The format
mirrors the Amiga's planar display hardware: pixels are stored as separate
bitplanes, interleaved one plane-row at a time.

Deluxe Paint (Dan Silva, Electronic Arts, 1985) made ILBM ubiquitous; nearly
every Amiga paint, digitiser, ray-tracer and presentation program reads and
writes it. **PBM** is a chunky (one byte per pixel) sibling introduced by
Deluxe Paint II Enhanced for MS-DOS around 1989–1990: same chunks, same
header, but a byte-per-pixel `BODY` suited to VGA mode 13h.

### 1.2 Related forms and how to tell them apart

All of these are `FORM`s inside the same EA IFF 85 container. The *FORM type*
(the four bytes at file offset 8 for a top-level `FORM`) identifies the
variant; the `BMHD` fields then refine it.

| FORM type | Origin | Pixel storage | Distinguishing data |
|---|---|---|---|
| `ILBM` | EA / Commodore, 1985–86 | Interleaved bitplanes in `BODY` | `BMHD.nPlanes` 1–8 indexed; 24 or 32 true colour; `CAMG` HAM / EHB bits select display modes |
| `PBM ` | EA, Deluxe Paint II Enhanced (PC) | One byte per pixel in `BODY` | FORM type only; `nPlanes` normally 8 |
| `ACBM` | Commodore (Carolyn Scheppner), 1986 | Contiguous planes in `ABIT` | `ABIT` chunk instead of `BODY` |
| `RGBN` | Impulse (Turbo Silver / Imagine) | 16-bit run-coded pixels | `nPlanes` 13, `compression` 4 |
| `RGB8` | Impulse (Turbo Silver / Imagine) | 32-bit run-coded pixels | `nPlanes` 25, `compression` 4 |
| `DEEP` | Amiga Centre Scotland, 1991 (used by TV Paint) | Chunky multi-component pixels in `DBOD` | `DGBL` / `DPEL` chunks; no `BMHD` |
| `ANIM` | Aegis / SPARTA, 1988 | First frame is an ILBM; later frames are deltas | `FORM ANIM` wrapping `FORM ILBM`s with `ANHD` / `DLTA` |

Within `FORM ILBM` the sub-variants are told apart as follows (precise rules
in Sections 5.6 and 6.2):

| Variant | Recognised by |
|---|---|
| Indexed (2–256 colours) | `nPlanes` 1–8, no HAM/EHB in `CAMG` |
| HAM6 | `CAMG` HAM bit, `nPlanes` 6 |
| HAM8 (AGA) | `CAMG` HAM bit, `nPlanes` 8 |
| Extra-Half-Brite | `CAMG` EHB bit, `nPlanes` 6 |
| Dynamic-palette (SHAM, PCHG, CTBL) | presence of those chunks; base mode as above |
| 24-bit / 32-bit true colour ("deep ILBM") | `nPlanes` 24 or 32, normally no `CMAP` |
| 21-bit NewTek | `nPlanes` 21 (different plane order, Section 3.13) |
| Palette only | `nPlanes` 0 and no `BODY` |

### 1.3 File names, MIME types and UTIs

| Item | Values |
|---|---|
| Extensions | `.iff` (generic), `.ilbm`, `.lbm` (Deluxe Paint on the PC, either ILBM or PBM), `.bbm` (Deluxe Paint PC brush), `.anim` (ANIM) |
| Amiga convention | No extension; type detected from content |
| MIME | `image/x-ilbm` (most common), `image/x-iff`; neither is IANA-registered |
| Magic | `FORM` at offset 0 and `ILBM` / `PBM ` at offset 8; for `LIST` / `CAT ` containers the type at offset 8 is only a hint and the inner `FORM` must be found |
| UTI | No system-declared Apple UTI exists for ILBM. Applications should export their own identifier conforming to `public.image` and `public.data`, matched by the extensions above |

---

## 2. Conventions

* **Byte order.** Every multi-byte integer in IFF and every form described
  here is **big-endian** (Motorola 68000 order). There are no little-endian
  fields, even in `PBM ` files written on the PC.
* **Integer types** (EA IFF 85 names): `UBYTE` 8-bit unsigned, `BYTE` 8-bit
  signed, `UWORD` 16-bit unsigned, `WORD` 16-bit signed, `ULONG` 32-bit
  unsigned, `LONG` 32-bit signed. Signed values are two's complement. No
  floating-point or fixed-point fields occur in ILBM.
* **Alignment.** Structures inside a chunk are byte-packed (no implicit
  padding between fields). Chunks themselves start on even offsets relative
  to the start of the file (Section 3.1.3).
* **IDs.** Four bytes compared as a 32-bit value; written here in double
  quotes or code font, with trailing spaces shown (`"CAT "`, `PBM `).
* **Text.** Text chunks (`ANNO`, `AUTH`, `NAME`, `(c) `) hold 8-bit
  characters, conventionally ISO 8859-1 (Amiga) or the writer's code page;
  they are not NUL-terminated unless stated.
* **Bit numbering.** Bit 0 is the least significant bit. Within a bitplane
  byte, bit 7 is the leftmost pixel.
* **Pixel origin.** (0, 0) is the top-left pixel; rows run top to bottom.
* **Terminology.** *Plane row*: one row of one bitplane, `RowBytes` bytes.
  *Scan line*: all plane rows (and the mask row) for one image row. *Colour
  register*: a palette entry. *Jiffy*: 1/60 s.
* Hexadecimal is written `0x…`; `x >> n`, `x << n`, `&`, `|` are C operators.

---

## 3. Byte-level layouts

### 3.1 EA IFF 85 container

#### 3.1.1 Chunk

| Offset | Size | Type | Name | Meaning / valid range | Notes |
|---:|---:|---|---|---|---|
| 0 | 4 | ID | `ckID` | Chunk identifier (Section 3.1.2) | |
| 4 | 4 | LONG | `ckSize` | Number of payload bytes, 0 … 2³¹−1 | Excludes the 8-byte header and the pad byte |
| 8 | `ckSize` | — | `ckData` | Payload | |
| 8 + `ckSize` | 0 or 1 | UBYTE | pad | Present iff `ckSize` is odd | Written as 0; never counted in any size |

`ckSize` is declared as a signed `LONG`; values with bit 31 set are not legal.
For a group chunk (`FORM`, `LIST`, `CAT `, `PROP`) `ckSize` counts the 4-byte
type field plus every nested chunk *including their pad bytes*.

#### 3.1.2 Identifier rules

* An ID is four ASCII characters in the range 0x20 (space) through 0x7E
  (`~`). Control characters and bytes ≥ 0x7F are forbidden.
* Leading spaces are not allowed (a space may not precede a printing
  character); trailing spaces pad shorter names (`"CAT "`, `"PBM "`).
* Comparison is a case-sensitive 32-bit equality test.
* **FORM types** (the type ID following `FORM`, `LIST`, `CAT ` or `PROP`) are
  further restricted: no lower-case letters and no punctuation, so that they
  can double as file-name extensions on case-insensitive systems. Local chunk
  IDs inside a FORM may use lower case and punctuation (e.g. `(c) `).
* **Universally reserved IDs**: `FORM`, `LIST`, `PROP`, `CAT `, and `"    "`
  (four spaces), plus `FOR1`–`FOR9`, `LIS1`–`LIS9`, `CAT1`–`CAT9` for future
  versioned group types. None of these may be used as a local chunk ID or a
  FORM type.
* `"    "` (four spaces) is the **filler** chunk ID: its payload is to be
  ignored. It may appear wherever a chunk may. It is also the "no hint" value
  for the contents type of a `CAT ` or `LIST`.

(Circulating text copies of the 1985 standard render the four-space ID as
`"JJJJ"`; see Errata E1.)

#### 3.1.3 Padding and alignment

If `ckSize` is odd, one pad byte follows the payload so that the next chunk
starts at an even offset. The pad byte is never counted in `ckSize`, but it
*is* counted in the enclosing group's `ckSize`. Writers write 0; readers must
not assume it is 0. Because every chunk header is 8 bytes and every payload is
padded to even length, all chunks start at even offsets relative to the start
of the file.

#### 3.1.4 Group chunks

| ID | Payload layout | Meaning |
|---|---|---|
| `FORM` | `ID formType`, then local chunks and nested `FORM`/`LIST`/`CAT ` | One self-contained data object of type `formType` |
| `LIST` | `ID contentsType`, then zero or more `PROP`, then `FORM`/`LIST`/`CAT ` | A collection whose members may share properties |
| `CAT ` | `ID contentsType`, then `FORM`/`LIST`/`CAT ` | A plain concatenation; no shared properties |
| `PROP` | `ID formType`, then property chunks | Shared property chunks for every `FORM formType` in the enclosing `LIST` |

Rules:

* A `FORM` may contain nested `FORM`, `LIST` and `CAT ` chunks; a nested FORM
  is a complete, independent data object (e.g. `FORM ANIM` contains
  `FORM ILBM`s).
* `PROP` is legal **only** directly inside a `LIST` — not inside a `FORM` or
  `CAT `. A `LIST` may contain at most one `PROP` per FORM type, and all its
  `PROP`s must precede its first `FORM`, `LIST` or `CAT `.
* The `contentsType` of a `CAT ` or `LIST` is a **hint** describing the kind
  of FORMs inside; `"    "` means "mixed / no hint". Readers must not rely on
  it.
* A file is a single `FORM`, `LIST` or `CAT ` chunk. Anything after the end
  of that chunk is outside the IFF data (commonly junk or a second
  concatenated file).

#### 3.1.5 Property scoping

Property chunks found in a `PROP formType` act as defaults for every
`FORM formType` lexically inside the same `LIST`, including FORMs inside
nested `LIST`s and `CAT `s. The scope rules are:

1. A chunk inside the FORM itself overrides any `PROP` default with the same
   ID.
2. A `PROP` in an inner `LIST` overrides one in an outer `LIST`.
3. `PROP` defaults override the reader's built-in defaults.
4. Scope ends with the `LIST`; sibling `LIST`s and enclosing `CAT `s do not
   see the properties.

#### 3.1.6 Generic data chunks

The EA IFF 85 standard and later Commodore registry define chunks that may
appear in any FORM:

| ID | Payload | Notes |
|---|---|---|
| `"    "` | anything | Filler; skip |
| `ANNO` | text | Annotation / comment |
| `AUTH` | text | Author |
| `(c) ` | text | Copyright notice; rewriters should preserve it |
| `NAME` | text | Name of the object |
| `FVER` | text | AmigaOS version string (`$VER: …`) |
| `JUNK` | anything | Registry chunk for ignorable data |
| `TEXT` | text | Unformatted text |

### 3.2 FORM ILBM: chunk catalogue and ordering

Grammar (adapted from the ILBM specification's Appendix A; `*` = zero or
more, `[ ]` = optional):

```
ILBM ::= "FORM" #{ "ILBM" BMHD [CMAP] [GRAB] [DEST] [SPRT] [CAMG]
                         CRNG* CCRT* [other properties] [BODY] }
```

* The property chunks may appear in any order, but **all must precede
  `BODY`**. Deluxe Paint writes `BMHD` first, and most readers expect it, but
  the specification does not require it.
* If a property chunk is repeated, **the last occurrence before `BODY`
  counts**.
* A property missing from the FORM is taken from an enclosing `PROP ILBM`
  (Section 3.1.5), else the reader's default.
* `BODY` is optional: a FORM with `CMAP`, a `BMHD` whose `nPlanes` is 0 and
  no `BODY` is the recommended way to store a palette alone.

| ID | Size (bytes) | Status | Section |
|---|---:|---|---|
| `BMHD` | 20 | Required | 3.3 |
| `CMAP` | 3 × n | Optional, encouraged; needed for indexed images | 3.4 |
| `CAMG` | 4 | Optional; Amiga display mode | 3.5 |
| `BODY` | varies | Image data | 3.6 |
| `GRAB` | 4 | Optional; hotspot | 3.7 |
| `DEST` | 8 | Optional; plane merge | 3.8 |
| `SPRT` | 2 | Optional; sprite flag | 3.9 |
| `CRNG` | 8 | Optional, repeatable; colour cycling (DPaint) | 3.10 |
| `CCRT` | 14 | Optional, repeatable; colour cycling (Graphicraft) | 3.10 |
| `DRNG` | 8 + 4·ntrue + 2·nregs | Optional, repeatable; DPaint IV cycling | 3.10 |
| `SHAM` | 2 + 32·lines | Optional; sliced HAM palettes | 3.11 |
| `CTBL`, `DYCP` | varies | Optional; NewTek dynamic HAM / hires palettes | 3.11 |
| `PCHG` | varies | Optional; line-by-line palette changes | 3.12 |
| `DPI ` | 4 | `UWORD dpiX, dpiY` | — |
| `CLUT`, `CMYK`, `CNAM`, `XBMI`, `EPSF`, `DPPV`, `DPPS`, `TINY`, `PRVW`, `XSSL` | varies | Application chunks; ignorable for decoding | 3.14 |

### 3.3 BMHD — bitmap header (20 bytes)

| Offset | Size | Type | Name | Meaning / valid range | Notes |
|---:|---:|---|---|---|---|
| 0 | 2 | UWORD | `w` | Raster width in pixels, 1 … 65535 | 0 only for palette-only FORMs |
| 2 | 2 | UWORD | `h` | Raster height in pixels, 1 … 65535 | |
| 4 | 2 | WORD | `x` | Suggested X position in the destination | Many readers ignore it; default 0 |
| 6 | 2 | WORD | `y` | Suggested Y position | |
| 8 | 1 | UBYTE | `nPlanes` | Bitplanes excluding the mask: 0 (palette only), 1–8 indexed, 24 / 32 true colour; 13 / 25 in RGBN / RGB8 | OCS/ECS display up to 6, AGA up to 8 |
| 9 | 1 | UBYTE | `masking` | 0–3, Section 4.1 | |
| 10 | 1 | UBYTE | `compression` | 0–1 for ILBM/PBM, Section 4.2 | 4 in RGBN / RGB8 |
| 11 | 1 | UBYTE | `pad1` / `flags` | Reserved in the 1986 spec ("write 0, ignore on read"); later Commodore headers name bit 7 `BMHDF_CMAPOK` | Section 4.3 |
| 12 | 2 | UWORD | `transparentColor` | Colour number treated as transparent for `masking` 2 and the lasso fill for 3 | Matched against *source* pixel values |
| 14 | 1 | UBYTE | `xAspect` | Pixel width : height ratio, `xAspect : yAspect` | 0 = unknown |
| 15 | 1 | UBYTE | `yAspect` | | |
| 16 | 2 | WORD | `pageWidth` | Width of the source page / screen in pixels | The image may be larger than the page |
| 18 | 2 | WORD | `pageHeight` | Height of the source page in pixels | |

**Aspect ratio.** The ratio describes one pixel. Two ratios are equal when
`xAspect × yDesired == yAspect × xDesired`. Typical values written by Amiga
software:

| Screen | xAspect : yAspect |
|---|---|
| 320 × 200 NTSC (lo-res) | 10 : 11 |
| 640 × 200 NTSC (hi-res) | 5 : 11 |
| 320 × 400 NTSC (lo-res laced) | 20 : 11 |
| 640 × 400 NTSC (hi-res laced) | 10 : 11 |
| Macintosh (the ILBM spec's example), VGA 640 × 480 | 1 : 1 |
| VGA 320 × 200 on a 4:3 display (physical value) | 5 : 6 |

PAL screens have squarer pixels than NTSC, but much software writes the NTSC
values regardless; treat the ratio as a hint.

**Page size.** `pageWidth`/`pageHeight` give the screen the image was made
for (e.g. 320 × 200). Readers may use it to pick a display mode (Section
5.5) or to scale; it does not bound the raster.

### 3.4 CMAP — colour map

| Offset | Size | Type | Name | Meaning |
|---:|---:|---|---|---|
| 3·i | 1 | UBYTE | `red` | Colour register *i*, 0–255 |
| 3·i + 1 | 1 | UBYTE | `green` | |
| 3·i + 2 | 1 | UBYTE | `blue` | |

* Number of registers `n = ⌊ckSize / 3⌋`, normally `2^nPlanes`. Fewer is legal
  (missing registers take reader defaults); extra registers are ignored.
* Components are in 256ths: 0x00 black … 0xFF full intensity.
* An odd `ckSize` (e.g. 3 × 5 = 15) is followed by the usual IFF pad byte. A
  `ckSize` that is not a multiple of 3 has a partial trailing entry; readers
  ignore it.
* Mode-specific counts: HAM6 uses 16 registers, HAM8 64, EHB 32 (the upper
  32 are derived, Section 5.8), PBM normally 256.
* **4-bit values.** OCS/ECS hardware has 4 bits per gun. The specification
  asks writers to store *scaled* 8-bit values (`n × 17`, i.e. the nibble
  duplicated: `0xF` → `0xFF`). Early software instead stored the nibble
  *shifted* into the high half (`0xF` → `0xF0`). Readers detect the latter
  by the low nibble of every component of every register being zero and
  then scale (Section 5.4), unless `BMHDF_CMAPOK` says the values are already
  full 8-bit (Section 4.3).

### 3.5 CAMG — Commodore Amiga viewport mode (4 bytes)

| Offset | Size | Type | Name | Meaning |
|---:|---:|---|---|---|
| 0 | 4 | ULONG | `viewModes` | Pre-2.0 files: a 16-bit `ViewPort.Modes` value in the low word, high word 0. AmigaOS 2.0+ writers: the 32-bit display-database mode ID from `GetVPModeID()` (monitor ID in the upper bits) |

Bits are listed in Section 4.4 and the reader clean-up rules in Section 5.5.
Only HAM and EHB change how pixels are decoded; the rest describe the
original display (resolution, interlace, playfields).

### 3.6 BODY — interleaved bitplanes

Uncompressed layout:

```
RowBytes = ((w + 15) / 16) × 2               // width rounded up to 16-bit words

scan line y (y = 0 … h−1):
    plane 0 row   (RowBytes bytes)
    plane 1 row
    …
    plane nPlanes−1 row
    mask row      (RowBytes bytes, only if masking == 1)
```

* Within a plane row, byte *k* bit 7 is pixel 8k, bit 0 is pixel 8k + 7.
  Bits beyond `w` (up to the word boundary) are padding; readers ignore them,
  writers should write 0.
* Plane 0 holds the least significant bit of the pixel value (Section 5.2).
* Uncompressed `BODY` size: `h × (nPlanes + (masking == 1 ? 1 : 0)) ×
  RowBytes` bytes. A longer `BODY` has trailing bytes to ignore.
* With `compression == 1`, **each plane row (and the mask row) is compressed
  separately** with ByteRun1 (Section 5.1). Compressed rows have varying
  lengths and are simply concatenated; there is no row index.
* If the `BODY` length is odd, the IFF pad byte follows.

### 3.7 GRAB — hotspot (4 bytes)

| Offset | Size | Type | Name | Meaning |
|---:|---:|---|---|---|
| 0 | 2 | WORD | `x` | Hotspot X relative to the image's top-left corner |
| 2 | 2 | WORD | `y` | Hotspot Y |

Used for brushes and pointer images (the "handle").

### 3.8 DEST — destination plane merge (8 bytes)

| Offset | Size | Type | Name | Meaning |
|---:|---:|---|---|---|
| 0 | 1 | UBYTE | `depth` | Number of planes in the original source |
| 1 | 1 | UBYTE | `pad1` | 0 |
| 2 | 2 | UWORD | `planePick` | Bit *d* = 1: the next source plane goes into destination plane *d*; the number of 1 bits should equal `nPlanes` |
| 4 | 2 | UWORD | `planeOnOff` | For destination planes whose `planePick` bit is 0: the constant bit to fill |
| 6 | 2 | UWORD | `planeMask` | Bit *d* = 1: write destination plane *d*; 0: leave it unchanged |

Only the low `depth` bits of each mask are used. Without `DEST` the default
is `planePick = planeMask = 2^nPlanes − 1`, `planeOnOff = 0`. Algorithm in
Section 5.13.

### 3.9 SPRT — sprite precedence (2 bytes)

| Offset | Size | Type | Name | Meaning |
|---:|---:|---|---|---|
| 0 | 2 | UWORD | `spritePrecedence` | 0 = foremost; larger = further back |

Presence marks the image as intended for a hardware sprite. A 2-plane Amiga
sprite uses `transparentColor = 0`; `CMAP` registers 1–3 map to the sprite's
colour registers and register 0 is ignored.

### 3.10 Colour cycling: CRNG, CCRT, DRNG

**CRNG** (Deluxe Paint; 8 bytes, repeatable; Deluxe Paint normally writes
four):

| Offset | Size | Type | Name | Meaning |
|---:|---:|---|---|---|
| 0 | 2 | WORD | `pad1` | 0 |
| 2 | 2 | WORD | `rate` | Steps per second × 16384 / 60: 16384 = 60 steps/s, 8192 = 30, ≈273 = 1 |
| 4 | 2 | WORD | `flags` | Section 4.5 |
| 6 | 1 | UBYTE | `low` | First register of the range |
| 7 | 1 | UBYTE | `high` | Last register (inclusive) |

**CCRT** (Commodore Graphicraft; 14 bytes, repeatable):

| Offset | Size | Type | Name | Meaning |
|---:|---:|---|---|---|
| 0 | 2 | WORD | `direction` | 0 = do not cycle, 1 = forward, −1 = backward |
| 2 | 1 | UBYTE | `start` | First register |
| 3 | 1 | UBYTE | `end` | Last register |
| 4 | 4 | LONG | `seconds` | Delay between steps, seconds part |
| 8 | 4 | LONG | `microseconds` | Delay, microseconds part |
| 12 | 2 | WORD | `pad` | 0 |

New programs should write `CRNG` (optionally also `CCRT` for old readers).

**DRNG** (Deluxe Paint IV "enhanced range", Lee Taran, EA; repeatable):

| Offset | Size | Type | Name | Meaning |
|---:|---:|---|---|---|
| 0 | 1 | UBYTE | `min` | First cell of the range |
| 1 | 1 | UBYTE | `max` | Last cell |
| 2 | 2 | WORD | `rate` | As `CRNG.rate` (16384 = 60 steps/s) |
| 4 | 2 | WORD | `flags` | Section 4.5 |
| 6 | 1 | UBYTE | `ntrue` | Number of `DColor` records |
| 7 | 1 | UBYTE | `nregs` | Number of `DIndex` records |
| 8 | 4·ntrue | DColor[] | | `UBYTE cell, r, g, b` — a cell holding a fixed true colour |
| 8 + 4·ntrue | 2·nregs | DIndex[] | | `UBYTE cell, index` — a cell taking the colour of register `index` |

A `DRNG` range may be non-contiguous and may mix fixed RGB values with
register references. Cells not listed are not part of the cycle.

### 3.11 Per-line palettes: SHAM, CTBL / DYCP

These describe a different palette for each display line, used to show more
colours than the base mode allows ("sliced HAM", "dynamic HAM", "dynamic
hires"). Neither has a specification in the EA/Commodore document set; the
layouts below are those that files in the wild use.

**SHAM** (sliced HAM):

| Offset | Size | Type | Name | Meaning |
|---:|---:|---|---|---|
| 0 | 2 | UWORD | `version` | 0 |
| 2 | 32 per line | UWORD[16] per line | `colors` | 16 colour registers per line, each `0x0RGB` (4 bits per gun) |

Number of palette lines `L = (ckSize − 2) / 32`. If `L ≥ h`, line *y* uses
palette *y*. If the image is interlaced and `L == h / 2`, palette *k*
applies to lines 2k and 2k + 1. Original SHAM pictures are 6-plane HAM,
320 × 200 (the PCHG document calls SHAM "hardwired to 200 lines").

**CTBL** (NewTek Digiview IV dynamic HAM / dynamic hires): an array of
`UWORD 0x0RGB` colour registers, one block per display line; 16 registers
per line for HAM pictures, 32 for non-HAM ("dynamic hires") pictures, so the
number of lines is `ckSize / 32` or `ckSize / 64`. **DYCP** holds three
`ULONG`s of NewTek setup data whose meaning is not published; readers ignore
it.

### 3.12 PCHG — line-by-line palette changes

Proposed by Sebastiano Vigna (draft 0.6, 28 November 1991) as a cleaner
replacement for SHAM and CTBL. Two header revisions circulate (Errata E8).
The **draft 0.6** layout published on the Amiga Developer CD is:

| Offset | Size | Type | Name | Meaning |
|---:|---:|---|---|---|
| 0 | 2 | UWORD | `Compression` | `PCHG_COMP_NONE` or `PCHG_COMP_HUFFMANN` (Section 4.6) |
| 2 | 2 | UWORD | `Flags` | `PCHGF_4BIT` (12-bit changes), `PCHGF_32BIT`, `PCHGF_USE_ALPHA` |
| 4 | 2 | WORD | `StartLine` | First line covered; may be negative (above the screen top) |
| 6 | 2 | UWORD | `LineCount` | Number of lines the line mask covers |
| 8 | 2 | UWORD | `MinReg` | Lowest register changed anywhere (optimisation hint) |
| 10 | 2 | UWORD | `MaxReg` | Highest register changed |
| 12 | 2 | UWORD | `TreeSize` | Bytes of Huffman tree (compressed only) |
| 14 | 2 | UWORD | `Reserved` | 0 |
| 16 | 4 | ULONG | `OriginalSize` | Size of the decompressed line data; equals `ckSize − 20` when uncompressed |

The later revision distributed with Vigna's `pchg.library` (1992) keeps a
20-byte header with `Compression, Flags, StartLine, LineCount, ChangedLines,
MinReg, MaxReg, MaxChanges` (all `UWORD`/`WORD`) and `ULONG TotalChanges`,
and moves the tree size and original size into a separate compression
header that precedes the tree when `Compression` is Huffman. A reader must
validate counts against the chunk length whichever layout it assumes.

Line data (after decompression, if any):

```
LineMask:   ((LineCount + 31) / 32) ULONGs; bit i set ⇔ line StartLine + i
            has a change record
then, for every set bit in order, one change record:

  PCHGF_4BIT (small changes):
    UBYTE ChangeCount16          changes to registers 0–15
    UBYTE ChangeCount32          changes to registers 16–31
    UWORD Change[ChangeCount16 + ChangeCount32]
          bits 15–12 register (plus 16 for the second group),
          bits 11–0 colour as 0x0RGB-style 4-bit guns

  PCHGF_32BIT (big changes):
    UWORD ChangeCount
    { UWORD Register; UBYTE Alpha, Red, Blue, Green } [ChangeCount]
          (note the documented Blue-before-Green order; Alpha meaningful
           only with PCHGF_USE_ALPHA)
```

`CMAP` gives the palette at the top of the picture; changes take effect from
display line 1 (line 2 for interlaced pictures) onward. Writers are asked to
change at most 7 registers per line and, for interlaced pictures, only on
even lines. Huffman decoding is described in Section 5.12.

### 3.13 Deep (true-colour) ILBM

Same chunks as ILBM, `CMAP` normally absent, `BODY` interleaved exactly as in
Section 3.6 with `nPlanes` planes per scan line:

| `nPlanes` | Plane order (first stored → last) | Origin |
|---|---|---|
| 24 | R0 … R7, G0 … G7, B0 … B7 (bit 0 of each gun first) | ILBM "IFF Hints" appendix |
| 32 | as 24, then A0 … A7 | de facto (several 1990s Amiga and PC programs) |
| 21 | R7 G7 B7 R6 G6 B6 … R0 G0 B0 (NewTek) | ILBM "IFF Hints" appendix |

Other depths (12, 18) occur only in a few experimental files. Deep ILBMs may
carry a `CLUT` chunk (Section 3.14).

### 3.14 Other ILBM chunks (ignorable for decoding)

| ID | Layout | Origin |
|---|---|---|
| `CLUT` | `ULONG type, reserved; UBYTE lut[256]`; type 0 mono, 1 red, 2 green, 3 blue, 4 hue, 5 saturation, 6–7 unused, > 7 reserved | Justin V. McCormick, 1989 |
| `CMYK` | 4 bytes per register (C, M, Y, K), `n = ckSize / 4`, alongside `CMAP` | Soft-Logik, 1991 |
| `CNAM` | `UWORD start, end`, then NUL-terminated colour names | Soft-Logik, 1991 |
| `XBMI` | `WORD type, dpiX, dpiY`; type 0 palette, 1 grey, 2 RGB, 3 RGBA, 4 CMYK, 5 CMYKA, 6 b&w | Soft-Logik, 1991 |
| `DPI ` | `UWORD dpiX, dpiY` | Spencer Shanson, 1990 |
| `EPSF` | `WORD` bounding box ×4, then PostScript text | Pixelations |
| `DPPV` / `DPPS` | Deluxe Paint perspective state | EA (Dan Silva) |
| `TINY` | Thumbnail written by later Deluxe Paint versions; layout not published in the EA/Commodore set | Electronic Arts |
| `PRVW` | Nested miniature ILBM preview | Oxxi (Gary Bonham), 1991 |
| `XSSL` | 4 reserved bytes; identifies Haitex X-Specs 3D images | Haitex |

### 3.15 FORM PBM (Deluxe Paint II Enhanced)

Same chunk set and grammar as ILBM (`BMHD`, `CMAP`, `CRNG`, `DPPS`, `TINY`,
`BODY`, …), with these differences:

| Item | PBM rule |
|---|---|
| `BODY` | Chunky: one byte per pixel (the colour number), rows top to bottom |
| Row length | `(w + 1) & ~1` bytes — padded to an **even** byte count, not to a 16-bit *pixel* boundary |
| `nPlanes` | Normally 8; values < 8 still use one byte per pixel |
| `compression` 1 | ByteRun1 applied per row |
| `masking` | 0 or 2; a mask plane (`masking` 1) is not defined |
| `CAMG` | Not written; no HAM / EHB |
| `CMAP` | 256 entries in practice |

### 3.16 FORM ACBM / ABIT (Amiga Contiguous BitMap)

Submitted by Carolyn Scheppner (Commodore), May 1986, to let AmigaBASIC
load and save screens with one read/write per bitplane. Identical to ILBM
except that `BODY` is replaced by `ABIT`:

```
ABIT = plane 0 (h rows × RowBytes) | plane 1 (h rows × RowBytes) | … | plane nPlanes−1
```

`RowBytes` is `((w + 15) / 16) × 2` and data is uncompressed in all known
files; the ACBM document itself does not state either (Errata E11). There is
no mask plane.

### 3.17 FORM RGBN and RGB8 (Impulse)

"Almost identical" to ILBM (BMHD, CAMG, BODY) with these differences:

| Item | RGBN | RGB8 |
|---|---|---|
| `BMHD.nPlanes` | 13 | 25 |
| `BMHD.compression` | 4 | 4 |
| Pixel unit | `UWORD` | `ULONG` |
| Colour bits | bits 15–12 R, 11–8 G, 7–4 B (4 bits per gun) | bits 31–24 R, 23–16 G, 15–8 B |
| Genlock bit | bit 3 | bit 7 |
| Repeat count | bits 2–0 | bits 6–0 |

`CAMG` is required. Pixels are scanned left to right, top to bottom; each
unit gives a colour, a genlock flag and a repeat count (Section 5.10). The
genlock bit marks "colour zero" (video shows through) in Turbo Silver and,
in Diamond / Light24 brushes, pixels outside the brush.

### 3.18 FORM DEEP (TV Paint chunky)

Submitted by Amiga Centre Scotland, 10 September 1991; the TV Paint addendum
adds compression 5 and the `TVDC` chunk. No `BMHD` / `CMAP`.

| Chunk | Layout | Meaning |
|---|---|---|
| `DGBL` (first, required) | `UWORD DisplayWidth, DisplayHeight, Compression; UBYTE xAspect, yAspect` (8 bytes) | Global info; compression per Section 4.8 |
| `DPEL` | `ULONG nElements; { UWORD cType, cBitDepth } [nElements]` | Pixel elements in storage order, MSB first; types in Section 4.8 |
| `DLOC` | `UWORD w, h; WORD x, y` (8 bytes) | Size/position of the following `DBOD`; default is the display size at (0, 0) |
| `DBOD` | compressed pixel data | Pixels stored chunky and pixel-interleaved: each pixel's elements in `DPEL` order, each pixel padded to a byte boundary |
| `DCHG` | `LONG FrameRate` | Milliseconds between frames; 0 = as fast as possible; −1 = frame separator for non-animated multi-frame files |
| `TVDC` | `WORD table[16]` | Delta table for compression 5 (Section 5.11) |

### 3.19 FORM ANIM (cel animation)

Designed by SPARTA Inc. (Gary Bonham) with Aegis Development, revision of
4 May 1988; later operations added by others (op 6 William J. Coldwell,
1991; op 7 Wolfgang Hofer; op 8 Joe Porkka, 1992).

```
FORM ANIM
    FORM ILBM   BMHD [ANHD] CMAP BODY        first frame, complete image
    FORM ILBM   ANHD [CMAP] DLTA             frame 2 (delta)
    FORM ILBM   ANHD [CMAP] DLTA             frame 3 …
```

An XOR-mode frame (operation 1) carries a `BODY` instead of `DLTA`. For op 8
the first frame may itself be a `DLTA` against an all-zero bitmap, in which
case its `ANHD` must be present.

**ANHD** (40 bytes):

| Offset | Size | Type | Name | Meaning |
|---:|---:|---|---|---|
| 0 | 1 | UBYTE | `operation` | Section 4.7 |
| 1 | 1 | UBYTE | `mask` | XOR mode: bit *p* set ⇔ plane *p* has data |
| 2 | 2 | UWORD | `w` | XOR mode: width of the changed area |
| 4 | 2 | UWORD | `h` | XOR mode: height |
| 6 | 2 | WORD | `x` | XOR mode: position of the area |
| 8 | 2 | WORD | `y` | |
| 10 | 4 | ULONG | `abstime` | Time since the first frame in jiffies (unused by players) |
| 14 | 4 | ULONG | `reltime` | Time since the previous frame in jiffies |
| 18 | 1 | UBYTE | `interleave` | Frames back that the delta modifies; 0 = two (double buffering); op 6 uses 4 |
| 19 | 1 | UBYTE | `pad0` | 0 |
| 20 | 4 | ULONG | `bits` | Option bits for ops 4, 5, 7, 8 (Section 4.7) |
| 24 | 16 | UBYTE[16] | `pad` | 0 |

**DLTA** layouts (all offsets are from the start of the `DLTA` payload):

| Op | Header | Body |
|---|---|---|
| 1 (XOR) | — (uses `BODY`) | ByteRun1 ILBM body of the `w × h` area; XORed into the frame two back |
| 2 (long delta) | `ULONG planeOffset[8]` (0 = plane unchanged) | Per plane: offset/data groups, `WORD` offsets and counts, `LONG` data, terminated by offset 0xFFFF |
| 3 (short delta) | `ULONG planeOffset[8]` | As op 2 with `WORD` data |
| 4 (generalised) | `ULONG dataOffset[8]; ULONG listOffset[8]` | Per plane: offset/count list (terminated by 0xFFFF) plus a data list; `bits` select word/long, set/XOR, shared list, vertical/horizontal |
| 5 (byte vertical) | `ULONG planeOffset[8]; ULONG unused[8]` | Per plane, per byte column: op lists (Section 5.14) |
| 6 (stereo op 5) | as op 5 | as op 5; quad-buffered, `interleave` = 4 |
| 7 (vertical, split lists) | `ULONG opcodeList[8]; ULONG dataList[8]` | Byte opcodes as op 5; data items are `UWORD` or `ULONG` (`bits` bit 0) taken from the separate data list |
| 8 (word/long vertical) | `ULONG planeOffset[8]; ULONG unused[8]` | As op 5 with word or long opcodes, counts and data (`bits` bit 0); an odd final column is word-coded |
| 74 (`'J'`) | — | Reserved for Eric Graham's method (Sculpt-Animate); layout not published in the EA/Commodore set |

---

## 4. Enumerations and flags

### 4.1 BMHD.masking

| Value | Name | Meaning | Extra BODY data |
|---:|---|---|---|
| 0 | `mskNone` | Opaque rectangle | none |
| 1 | `mskHasMask` | A mask plane follows the image planes of every scan line. Mask bit 1 = copy the pixel (opaque), 0 = transparent (leave the destination alone) | 1 plane row per scan line |
| 2 | `mskHasTransparentColor` | Source pixels equal to `transparentColor` are transparent | none |
| 3 | `mskLasso` | The reader builds a mask by lasso fill (Section 5.3) | none |
| 4–255 | — | Undefined | Readers reject the file or treat it as 0 and warn; never guess a layout |

### 4.2 BMHD.compression

| Value | Name | Meaning |
|---:|---|---|
| 0 | `cmpNone` | Uncompressed rows |
| 1 | `cmpByteRun1` | ByteRun1 per plane row (Section 5.1) |
| 2 | — | Not defined by the ILBM spec. Files from Atari ST software use this value with a `BODY` holding one `VDAT` sub-chunk of vertical word RLE per plane; not portable, layout outside this document's scope |
| 4 | — | RGBN / RGB8 run-length pixels (Section 5.10); only in those FORMs |
| other | — | Undefined; reject |

### 4.3 BMHD.pad1 (flags)

| Bit | Name | Meaning |
|---:|---|---|
| 7 | `BMHDF_CMAPOK` | The `CMAP` holds genuine 8-bit values; readers must **not** apply the 4-bit scaling heuristic (Section 5.4) |
| 0–6 | — | Reserved: write 0, ignore on read |

The 1986 specification only says "write 0, ignore on read"; the flag was
added by Commodore's later (AmigaOS 3.x era) ILBM headers. Old readers that
ignore it are unaffected.

### 4.4 CAMG view mode bits

16-bit `ViewPort.Modes` bits (low word):

| Mask | Name | Effect |
|---:|---|---|
| 0x0001 | — | Undefined in ViewModes |
| 0x0002 | `GENLOCK_VIDEO` | Genlock; no pixel effect. Stripped by the clean-up rule |
| 0x0004 | `LACE` | Interlace (doubles vertical resolution); aspect only |
| 0x0008 | `DOUBLESCAN` | AGA (V39) line doubling; aspect only |
| 0x0010 | — | Undefined in ViewModes |
| 0x0020 | `SUPERHIRES` | ECS 1280-pixel mode (V36); aspect only |
| 0x0040 | `PFBA` | Playfield 2 has priority over playfield 1 (dual playfield only) |
| 0x0080 | `EXTRA_HALFBRITE` | EHB (Section 5.8) |
| 0x0100 | `GENLOCK_AUDIO` | No pixel effect. Stripped by the clean-up rule |
| 0x0200 | — | Undefined in ViewModes |
| 0x0400 | `DUALPF` | Dual playfield: odd planes (0, 2, 4) form playfield 1, even planes (1, 3, 5) playfield 2 |
| 0x0800 | `HAM` | Hold-And-Modify (Section 5.7) |
| 0x1000 | `EXTENDED_MODE` | In 16-bit files: no pixel effect, stripped. In 32-bit mode IDs: part of every monitor ID |
| 0x2000 | `VP_HIDE` | No pixel effect. Stripped by the clean-up rule |
| 0x4000 | `SPRITES` | No pixel effect. Stripped by the clean-up rule |
| 0x8000 | `HIRES` | 640-pixel mode; aspect only |

The five "stripped" bits together are `0x7102`; the clean-up mask is
`0x8EFD` (Section 5.5).

AmigaOS 2.0+ mode IDs: the monitor ID occupies the bits selected by
`MONITOR_ID_MASK = 0xFFFF1000`; the HAM (0x0800) and EHB (0x0080) keys keep
their ViewModes positions, while the meaning of the resolution bits depends on
the monitor (e.g. VGA "productivity" and A2024 modes reuse them).

| Monitor ID | Value |
|---|---:|
| default | 0x00000000 |
| NTSC | 0x00011000 |
| PAL | 0x00021000 |
| VGA (Multiscan) | 0x00031000 |
| A2024 | 0x00041000 |
| Proto | 0x00051000 |
| Euro72 | 0x00061000 |
| Euro36 | 0x00071000 |
| Super72 | 0x00081000 |
| DblNTSC | 0x00091000 |
| DblPAL | 0x000A1000 |

Every non-default monitor ID has bit 0x1000 set; that is what the bogus-CAMG
test (Section 5.5) relies on.

### 4.5 Colour-cycling flags (CRNG, DRNG)

| Bit | Name | Meaning |
|---:|---|---|
| 0 (0x1) | `RNG_ACTIVE` | Cycling enabled |
| 1 (0x2) | `RNG_REVERSE` | Cycle downward (CRNG only) |
| 2 (0x4) | `RNG_DP_RESERVED` | DRNG: reserved, must be 0 |
| others | — | Reserved, 0 |

`rate == 0` means "do not cycle" regardless of the flags. One early package
always set `RNG_ACTIVE` and used `rate == 36` to mean inactive (noted in the
ILBM spec); readers may treat 36 with suspicion but should not special-case it
by default.

### 4.6 PCHG constants

| Name | Value |
|---|---:|
| `PCHG_COMP_NONE` | 0 |
| `PCHG_COMP_HUFFMANN` | 1 |
| `PCHGF_4BIT` (later called `PCHGF_12BIT`) | 0x0001 |
| `PCHGF_32BIT` | 0x0002 |
| `PCHGF_USE_ALPHA` | 0x0004 |

The draft names these constants without giving values; the values above are
the ones used in files and in the `pchg.library` distribution (Open question
in Errata E8). Exactly one of `PCHGF_4BIT` / `PCHGF_32BIT` should be set.

### 4.7 ANIM operations and option bits

| `operation` | Name |
|---:|---|
| 0 | Set directly (normal ILBM `BODY`) |
| 1 | XOR ILBM |
| 2 | Long delta |
| 3 | Short delta |
| 4 | Generalised short/long delta |
| 5 | Byte vertical delta (the common "ANIM5") |
| 6 | Stereo byte vertical delta (quad-buffered op 5) |
| 7 | Short/long vertical delta with separate opcode and data lists ("ANIM7") |
| 8 | Short/long vertical delta, inline data ("ANIM8") |
| 74 (`'J'`) | Eric Graham's method |
| others | Undefined |

`ANHD.bits` (ops 4 and 5; op 5 writers should leave all zero; ops 7 and 8
use only bit 0):

| Bit | 0 | 1 |
|---:|---|---|
| 0 | short (16-bit) data | long (32-bit) data |
| 1 | set | XOR |
| 2 | separate info list per plane | one info list for all planes |
| 3 | not run-length coded | run-length coded |
| 4 | horizontal | vertical |
| 5 | short info offsets | long info offsets |
| 6–31 | reserved, 0 | |

### 4.8 DEEP enumerations

`DGBL.Compression`:

| Value | Name |
|---:|---|
| 0 | `NOCOMPRESSION` |
| 1 | `RUNLENGTH` |
| 2 | `HUFFMAN` |
| 3 | `DYNAMICHUFF` |
| 4 | `JPEG` |
| 5 | `TVDC` (TV Paint addendum) |

`DPEL.cType`:

| Value | Element | Value | Element |
|---:|---|---:|---|
| 1 | red | 8 | black |
| 2 | green | 9 | mask |
| 3 | blue | 10 | Z buffer |
| 4 | alpha | 11 | opacity |
| 5 | yellow | 12 | linear key |
| 6 | cyan | 13 | binary key |
| 7 | magenta | | |

---

## 5. Algorithms

### 5.1 ByteRun1

ByteRun1 is the byte-oriented run-length code of the ILBM specification's
Appendix D (the same scheme as Apple's PackBits). The stream is a sequence
of packets, each starting with a control byte *n* read as signed 8-bit:

| *n* | Action |
|---|---|
| 0 … 127 | Copy the next *n* + 1 bytes literally |
| −1 … −127 | Repeat the next byte −*n* + 1 times (2 … 128 copies) |
| −128 | No operation; continue with the next control byte |

Decoder (one plane row; a whole BODY is the same loop run until
`h × planesPerLine × RowBytes` bytes have been produced):

```
function unpackRow(src, dst, rowBytes):
    produced = 0
    while produced < rowBytes:
        if src exhausted: error "truncated"
        n = signed(src.next())
        if n >= 0:
            count = n + 1
            require src has count bytes, else error
            copy count bytes from src to dst
        else if n != -128:
            count = -n + 1
            require src has 1 byte, else error
            b = src.next(); write b count times to dst
        else:
            continue                       // -128: no-op
        produced += count
    if produced > rowBytes: discard the excess (non-conforming writer)
```

Encoder (per plane row; never let a packet cross a row boundary):

```
function packRow(row):
    i = 0
    while i < len(row):
        run = length of the run of bytes equal to row[i] starting at i, capped at 128
        if run >= 3 or (run == 2 and the previous packet was not a literal
                        and the next bytes do not start a literal):
            emit byte(-(run - 1)), row[i]; i += run
        else:
            start literal at i; extend while fewer than 128 bytes and no run
            of 3 or more equal bytes begins; emit byte(len - 1), bytes
```

The specification's guidance: always encode runs of three or more as
replicate packets; a run of exactly two should be a replicate packet unless
it sits between two literal packets, in which case merge it into the
literal. Never emit −128.

**Expansion bound.** Every two input bytes produce at most 128 output bytes,
so `L` compressed bytes decode to at most `⌊L / 2⌋ × 128` bytes. A reader can
reject a BODY that cannot possibly fill the declared raster before
allocating anything.

### 5.2 Planar to chunky

```
RowBytes = ((w + 15) / 16) * 2
P        = nPlanes + (masking == 1 ? 1 : 0)        // plane rows per scan line
for y in 0 ..< h:
    line = body[y * P * RowBytes ..< (y + 1) * P * RowBytes]
    for x in 0 ..< w:
        value = 0
        for p in 0 ..< nPlanes:
            byte  = line[p * RowBytes + x / 8]
            bit   = (byte >> (7 - x % 8)) & 1
            value |= bit << p                     // plane 0 = least significant
        pixel[y][x] = value
        if masking == 1:
            byte = line[nPlanes * RowBytes + x / 8]
            opaque[y][x] = ((byte >> (7 - x % 8)) & 1) == 1
```

### 5.3 Transparency

* `masking == 1`: opaque where the mask bit is 1 (Section 5.2).
* `masking == 2`: transparent where `pixel == transparentColor` (the raw
  source value, before any HAM/EHB translation).
* `masking == 3` (lasso, as described by the ILBM specification):

```
surround the w × h image with a 1-pixel border of transparentColor
flood-fill (4-connected) from the border through pixels equal to
    transparentColor
every filled pixel inside the image is transparent; all others are opaque
```

  So background-coloured pixels enclosed by the drawing stay opaque.

### 5.4 CMAP 4-bit scaling

```
if BMHD.flags bit 7 (BMHDF_CMAPOK) is set:        // values are genuine 8-bit
    use CMAP as stored
else if every component c of every register has (c & 0x0F) == 0
        and at least one component is non-zero:
    for each component: c = c | (c >> 4)          // = (c >> 4) * 17; 0xF0 → 0xFF
```

An all-black palette is left as is (scaling would not change it).
Converting to 4-bit hardware is `c >> 4`; the scaled form round-trips.

### 5.5 CAMG clean-up and display-mode selection

The October 1988 Commodore notes in the ILBM specification require readers to
sanitise `CAMG` before use:

```
m = CAMG value
// 1. Old-style 16-bit ViewModes: drop bits that are not display modes.
if (m & 0xFFFF0000) == 0:                    // no monitor ID in the upper word
    m &= ~0x7102                             // EXTENDED_MODE|SPRITES|VP_HIDE|
                                             //  GENLOCK_AUDIO|GENLOCK_VIDEO
// 2. Bogus values written by some brush programs: junk upper word without
//    EXTENDED_MODE. Ignore the stored mode and derive one from the page size.
else if (m & 0x00001000) == 0:
    m = 0
    if BMHD.pageWidth  >= 640: m |= HIRES
    if BMHD.pageHeight >= 400: m |= LACE
```

(The specification states step 1 as "no `MONITOR_ID_MASK` bits, or
`EXTENDED_MODE` with a zero upper word"; both cases reduce to "upper word
zero".) Under AmigaOS 2.0+ a viewer then asks the display database whether
`m` is available and, if not, falls back to `m & (HIRES|LACE|HAM|EHB)` or
asks the user.

Colour interpretation (SwiftILBM's policy, which follows the specification
plus the de-facto refinements of Section 6.2):

```
if FORM is PBM:                       indexed
else if nPlanes > 8:                  true colour (Section 5.9)
else if CAMG present (after clean-up):
    if m & HAM:                       HAM (nPlanes 6 → HAM6, 8 → HAM8)
    else if m & EHB and nPlanes == 6: EHB
    else:                             indexed
else if nPlanes == 6 and CMAP has exactly 32 registers: EHB
else if nPlanes == 6 and CMAP has ≤ 16 registers:        HAM6
else:                                 indexed
```

### 5.6 Indexed colour

`rgb = CMAP[value]` (after Section 5.4). Values with no `CMAP` entry use the
reader's default; black is the usual choice.

### 5.7 Hold-And-Modify

With `D = nPlanes − 2` data bits, the pixel value splits into a 2-bit
control `c = value >> D` (the two highest planes) and data
`d = value & (2^D − 1)`. Each row starts from the background colour,
register 0 — the hardware holds the border colour at the left edge.

```
for each row:
    (r, g, b) = CMAP[0]
    for x in 0 ..< w:
        c = value[x] >> D;  d = value[x] & ((1 << D) - 1)
        switch c:
            0b00: (r, g, b) = CMAP[d]            // load register d
            0b01: b = modify(b, d)               // hold R, G
            0b10: r = modify(r, d)               // hold G, B
            0b11: g = modify(g, d)               // hold R, B
        out[x] = (r, g, b)

HAM6 (D = 4, OCS/ECS):  modify(old, d) = d * 17           // whole 4-bit gun
HAM8 (D = 6, AGA):      modify(old, d) = (d << 2) | (old & 0x03)
                                                // upper 6 bits replaced,
                                                // low 2 bits held
```

The control bits come from planes `nPlanes − 1` (most significant) and
`nPlanes − 2`. HAM6 can show all 4096 OCS colours; HAM8 about 262 144 of the
16.7 million AGA colours at once.

### 5.8 Extra-Half-Brite

With 6 planes and EHB, bit 5 (plane 5) is a half-brightness flag:

```
if value < 32: rgb = CMAP[value]
else:          rgb = CMAP[value - 32] with each component halved
```

OCS/ECS halve the 4-bit gun (`n >> 1`); AGA halves the 8-bit component
(`c >> 1`). Readers working in 8 bits use `c >> 1`. Stored `CMAP` entries
32–63 are ignored by the hardware.

### 5.9 Deep ILBM

```
for each pixel:
    value = planar value assembled over all nPlanes planes (Section 5.2,
            but into a 32-bit integer)
    24 planes: r = value & 0xFF; g = (value >> 8) & 0xFF; b = (value >> 16) & 0xFF
    32 planes: as 24, alpha = (value >> 24) & 0xFF
    21 planes (NewTek): de-interleave planes 0,3,6,… as R bits 7..0,
               1,4,7,… as G, 2,5,8,… as B (Section 3.13), each gun 7 bits
```

### 5.10 RGBN / RGB8 decoding

```
pixels = 0; total = w * h
while pixels < total:
    RGBN: u = UWORD; rgb = (u >> 4) & 0xFFF (scale 4-bit guns); genlock = (u >> 3) & 1; n = u & 7
    RGB8: u = ULONG; rgb = u >> 8;              genlock = (u >> 7) & 1;  n = u & 0x7F
    if n == 0:                                 // extended count (RGBN only in practice)
        n = UBYTE
        if n == 0: n = UWORD
    write rgb (with genlock) n times
```

The run is the number of pixels, not "repeat n more times". The
specification does not say whether a run may cross a row boundary; treat the
BODY as one continuous pixel stream (runs that cross rows simply continue on
the next row). Impulse software never wrote extended counts in RGB8 and only
reads 7-bit counts there.

### 5.11 DEEP TVDC decompression

For each line and each `DPEL` element in turn (for RGBA: a red line, a green
line, a blue line, an alpha line):

```
v = 0                                          // running value per line
pos = 0                                        // nibble index into the source
for i in 0 ..< lineLength:
    d = nibble(pos++)                          // high nibble of each byte first
    v = (v + table[d]) & 0xFF
    out[i] = v
    if table[d] == 0:                          // zero delta introduces a run
        count = nibble(pos++)
        repeat count: out[++i] = v
consumed bytes = (pos + 1) / 2
```

### 5.12 PCHG Huffman decoding

The tree is an array of `TreeSize / 2` big-endian `WORD`s (at most 511),
decoded starting from its **last** word. Bits are read MSB-first from
big-endian 32-bit longwords; the compressed stream is padded to a multiple of
32 bits.

```
p = index of last tree word                    // the root
loop:
    if nextBit() == 0:                          // left branch
        p = p - 1                               // left subtree starts at the preceding word
        w = tree[p]
        if w >= 0 and (w & 0x100) != 0:         // left child is a leaf
            emit(w & 0xFF); p = last; continue
        // otherwise tree[p] is the left child's own right-branch slot
    else:                                       // right branch
        w = tree[p]
        if w >= 0:                              // right child is a leaf stored in place
            emit(w & 0xFF); p = last; continue
        p = p + w / 2                           // negative byte offset (-t-1)*2 to the
                                                // right subtree
until OriginalSize bytes have been emitted
```

The draft describes the tree as left subtree stored first, then a negative
byte offset to the right subtree; leaves have bit 8 set. Because the draft's
description is terse, an implementation should be checked against sample
files before relying on it.

### 5.13 DEST plane merge

```
src = 0
for d in 0 ..< DEST.depth:
    if planeMask bit d == 0: continue                 // leave plane d alone
    if planePick bit d == 1: dstPlane[d] = srcPlane[src]; src += 1
    else:                    dstPlane[d] = all bits = planeOnOff bit d
```

### 5.14 ANIM op 5 (byte vertical delta)

Applied to the bitmap of `interleave` frames back (two for double
buffering). `RowBytes` is the bitmap's bytes per plane row.

```
for p in 0 ..< nPlanes:
    off = ULONG at DLTA[4 * p];  if off == 0: continue         // plane unchanged
    s = off
    for col in 0 ..< RowBytes:                                // one byte column
        row = 0
        ops = DLTA[s++]
        repeat ops times:
            op = DLTA[s++]
            if op == 0:                                         // SAME
                count = DLTA[s++]; v = DLTA[s++]
                repeat count: plane[p][row][col] = v; row += 1
            else if op & 0x80:                                  // UNIQ
                repeat (op & 0x7F): plane[p][row][col] = DLTA[s++]; row += 1
            else:                                               // SKIP
                row += op
```

Every write must be bounds-checked against `h`. Op 8 is the same algorithm
with 16-bit (or 32-bit, `bits` bit 0) opcodes, counts and data over word (or
long) columns; with long data, a width that is an odd number of words ends in
one word-coded column. Op 7 uses byte opcodes as above but takes each data
item (word or long) from the plane's separate data list.

Ops 2 and 3: each plane's list is a sequence of `WORD offset` groups ending
with 0xFFFF (checked before the sign). A non-negative offset is followed by
one data item; a negative offset introduces a run whose `WORD` count follows,
then that many data items stored at consecutive positions. Whether offsets
are relative to the previous position or to the plane start, and the exact
conversion of a negative offset, are not settled by the 1988 document
(Errata E10).

---

## 6. Semantics and de-facto behaviour

### 6.1 Container

* **Group sizes.** Some writers get the outer `FORM` size wrong: off by the
  final pad byte, still holding a placeholder, or larger than the file. Lenient
  readers clamp the outer group to the file length and accept the data. A *chunk* whose size
  exceeds its parent is a different matter: the chunk walk cannot continue
  reliably.
* **Trailing data** after the outer group (e.g. a second FORM appended by
  `cat`, or XMODEM padding) is ignored.
* **Unknown chunks** are skipped by length plus pad. Writers freely add
  application chunks; rewriters should preserve `AUTH` and `(c) `.
* **Search order.** Viewers display the first `FORM ILBM` / `FORM PBM ` found
  in a depth-first walk; for `FORM ANIM` that is the first frame.

### 6.2 ILBM

* **Missing CAMG.** The specification says only "if the image is 6 planes
  deep, assume HAM". Six-plane EHB pictures without `CAMG` also exist (from
  PC and early Amiga software), so common readers refine the rule: exactly 32
  `CMAP` registers → EHB; 16 or fewer → HAM6; otherwise indexed (a 64-colour
  palette means a plain 6-bit indexed image, e.g. from Deluxe Paint on the
  PC, which never writes `CAMG`).
* **HAM with other depths.** OCS HAM requires 6 planes (5-plane HAM is
  possible on hardware but practically unused); AGA HAM8 requires 8. A `CAMG`
  HAM bit with any other depth is an error in practice.
* **Palette-only ILBM.** `nPlanes == 0` with no `BODY` (Deluxe Paint
  "Save palette"). There is no image to decode.
* **Repeated chunks.** Some writers emit a second `CMAP` or `CAMG` (e.g. after
  editing). Per the specification the last one before `BODY` wins.
* **Properties after BODY.** Not allowed by the specification, but a few
  writers place `CAMG` or `CRNG` after the `BODY`. Lenient readers use such a
  chunk only if no occurrence precedes `BODY`.
* **ByteRun1 across rows.** Some encoders compress the whole BODY as one stream, so packets cross row boundaries.
  Decoding the BODY as a single continuous stream accepts these files and
  gives identical results for conforming ones. Some encoders also emit a final
  packet that overshoots the last row; the excess is discarded.
* **Uncompressed narrow images.** Small brushes are often stored with
  `compression == 0` because ByteRun1 would make them longer (ILBM "IFF Hints").
* **HAM palettes.** HAM6 uses `CMAP` registers 0–15 and HAM8 registers 0–63;
  any further registers are ignored.
* **EHB `CMAP` of 64 entries.** Some writers store 64 registers with the
  halved colours spelled out. The hardware ignores registers 32–63; readers
  derive them.
* **Dual playfield.** Rarely used for stills. Playfield 1 = planes 0, 2, 4
  (colour registers 0–7), playfield 2 = planes 1, 3, 5 (registers 8–15),
  colour 0 of each playfield transparent; `PFBA` puts playfield 2 in front.
* **Aspect.** Treat `xAspect/yAspect` as a hint (Section 3.3).

### 6.3 PBM

* Deluxe Paint II Enhanced writes `nPlanes = 8`, a 256-entry `CMAP`,
  `compression` 1, and pads each row to even length. The `.LBM` extension is used for both PBM and ILBM; detection must
  look at the FORM type.

### 6.4 ANIM

* Players decode the first frame into buffer A, copy it to buffer B, show A,
  then apply each delta to the hidden buffer (two frames back) and swap. Later
  `CMAP` chunks update both buffers' palettes. Timing uses `reltime` jiffies.
* Op 5 is by far the most common (Deluxe Paint III and IV write it, as do
  most conversion tools). Looping animations end with two extra frames that bring
  both buffers back to frames 1 and 2.

---

## 7. Robustness guidance for readers

Every field is untrusted. A conforming reader:

* **Walks chunks defensively.** Requires at least 12 bytes for a group header;
  checks each `ckSize` against the bytes remaining in its parent (in 64-bit or
  checked arithmetic — a `ULONG` size does not fit a 32-bit signed integer);
  never trusts the pad byte's value; bounds nesting depth (8 levels is ample
  for real files) to defeat recursion bombs; makes forward progress on every
  step (an 8-byte header always advances the cursor).
* **Validates the header.** `BMHD` at least 20 bytes; `w > 0` and `h > 0`;
  `nPlanes` within the supported set; `masking` and `compression` defined.
* **Caps allocation before decoding.** `w × h` can be 65535² ≈ 4.3 G pixels
  from a 20-byte header. Enforce a pixel-count limit, use overflow-checked
  multiplication for `h × planes × RowBytes`, and reject a ByteRun1 BODY whose
  length cannot reach the required size (Section 5.1).
* **Bounds every copy.** Literal packets that run past the end of `BODY`,
  replicate packets with no data byte, and a stream that ends early are errors,
  not silent zero fill.
* **Never indexes memory with pixel values.** Pixel values beyond the `CMAP`
  are rendered with a default colour (black); `transparentColor` beyond the
  palette is harmless.
* **Treats contradictions consistently.** A `CAMG` that names HAM for a depth
  other than 6 or 8 is rejected; a mask plane in PBM is rejected; an undefined
  masking or compression value is rejected rather than guessed.
* **Bounds dynamic-palette and animation data.** `SHAM`/`CTBL` line counts,
  `PCHG` mask and change counts, ANIM column ops and `DLTA` offsets must all be
  checked against their chunk lengths and the bitmap height; a SKIP/UNIQ/SAME
  that runs past the bottom of a column is an error.
* **Handles truncation.** A file cut anywhere must produce a clean error.

---

## 8. Errata

Errors and ambiguities in the original documents and in previously
circulating descriptions (including the earlier edition of this reference).

| # | Source | Problem | Correction / evidence |
|---|---|---|---|
| E1 | EA IFF 85 text copies | The filler / blank ID appears as `"JJJJ"` (and quote marks as `R S`), e.g. "A CAT could just have blank contents ID ("JJJJ")" | Typesetting artefact of the original Macintosh document: a visible-space glyph became `J`. The ID is four spaces (0x20202020); the same document lists `"    "` in the universally reserved set |
| E2 | ILBM spec, Appendix "additional information" (HAM) | Lists control codes as "10 = modify blue, 01 = modify red" | The pair is written plane 4 then plane 5 (LSB first). In conventional MSB-first notation (plane 5 is the high bit) it is 01 = blue, 10 = red, 11 = green, matching the *Amiga Hardware Reference Manual* |
| E3 | ILBM spec, CRNG | Text refers to an "active" field; the structure has `flags` | `flags` bit 0 is `RNG_ACTIVE` |
| E4 | ILBM spec, CAMG | "No CAMG and 6 planes → assume HAM" misreads 6-plane EHB and PC 64-colour images | De-facto refinement in Section 6.2 |
| E5 | ILBM spec, appendix numbering | Body text cites "Appendix C/D" for IFF Hints and ByteRun1 while the table of contents numbers them differently | Cosmetic; ByteRun1 is the packer appendix, IFF Hints the October 1988 appendix |
| E6 | ILBM spec, IFF Hints | Recommends expanding 4-bit hardware colour with `R8 := R4 << 4` | That rule produced the dark "left-justified" palettes; the same appendix notes that scaling (`R4 × 255 / 15`, i.e. `× 17`) is better. Readers detect and scale (Section 5.4) |
| E7 | Earlier edition of this reference | Said `BMHD` "must come first" | The spec allows property chunks in any order before `BODY`; BMHD first is only convention |
| E8 | PCHG draft 0.6 vs later | Header layout differs between the draft (`TreeSize`, `Reserved`, `OriginalSize`) and the `pchg.library` revision (`ChangedLines`, `MaxChanges`, `TotalChanges` + separate compression header); constants given without values; line-mask bit order within each longword and the nibble order of small changes not stated; the `BigPaletteChange` field order Alpha, Red, **Blue, Green** is unusual | Section 3.12 documents both layouts; values in Section 4.6 are those used by files and the library; small changes use the Amiga `0RGB` register order; verify against sample files |
| E9 | ANIM spec | The byte-vertical method is headed "2.2.2" but is the third format described; op 7 is absent from the Commodore document set; `interleave` 0 means *two* frames back, not "none" | Section 3.19 / 4.7 |
| E10 | ANIM spec, ops 2/3 | The prose says the offset is added to a running pointer while the sample routine treats it as relative to the plane start; "the absolute value is the offset+2" for negative offsets is ambiguous | Undecided; recorded in Section 5.14. Verify against sample files |
| E11 | ACBM spec | Does not state `ABIT` row width, padding or whether compression is allowed | All known writers use word-aligned rows (`RowBytes`), uncompressed, plane after plane |
| E12 | DEEP spec | `DBOD` layout pseudocode is garbled in circulating copies; `RUNLENGTH` (1) is not defined; `TVDC` (5) is missing from the main compression list | Section 3.18; compression 1 should be treated as unsupported until confirmed against TV Paint files |
| E13 | RGBN/RGB8 spec | The extended repeat count rule is described for both forms, but Impulse software never wrote or read extended counts for RGB8 | Section 5.10 |
| E14 | Earlier edition of this reference | Did not give the CAMG clean-up / bogus-value rule, the "last property before BODY wins" rule, or `BMHDF_CMAPOK` | Sections 3.2, 4.3, 5.4, 5.5 |
| E15 | Secondary sources | Expand "PBM" as "Planar BitMap" | Unattested in EA documentation and contradicts the content (PBM is chunky); treat the ID as opaque |

---

## 9. Implementation status (SwiftILBM)

| Section | Feature | Status |
|---|---|---|
| 3.1.1, 3.1.3 | Chunk header, big-endian sizes, odd-size pad byte | Supported |
| 3.1.2 | ID validation | Partial — IDs are compared, not validated; non-printable bytes are shown as `?` |
| 3.1.4 | `FORM ILBM`, `FORM PBM ` at top level | Supported |
| 3.1.4 | Nested `LIST` / `CAT ` / `FORM ANIM` (first ILBM/PBM, depth-first) | Supported (depth ≤ 8) |
| 3.1.5 | `PROP` defaults with inner-over-outer and FORM-over-PROP scoping | Supported |
| 3.1.6 | Generic / filler / unknown chunks | Skipped |
| 3.2 | Last property before `BODY` wins; property after `BODY` used only if none precedes it | Supported |
| 3.3 | `BMHD` all fields, aspect ratio, page size | Supported (`pixelAspectRatio`; pixels not aspect-corrected) |
| 3.3 / 6.2 | Palette-only ILBM (`nPlanes` 0, no `BODY`) | Unsupported — rejected (`unsupportedDepth(0)`); no image |
| 3.4, 5.4 | `CMAP`, partial entries, 4-bit scaling | Supported (scaling on by default, switchable) |
| 4.3 | `BMHDF_CMAPOK` (BMHD flags bit 7) suppresses scaling | Unsupported — flag ignored (deviation) |
| 3.5, 5.5 | `CAMG` clean-up (strip 0x7102 in 16-bit values; bogus-value replacement from page size) | Unsupported — raw value used (deviation) |
| 4.4 | `CAMG` HIRES / LACE / SUPERHIRES / DOUBLESCAN | Exposed; no effect on pixels |
| 4.4, 6.2 | Dual playfield | Unsupported — decoded as plain indexed |
| 3.6, 5.2 | Interleaved BODY, 1–8 planes | Supported |
| 4.1, 5.3 | Masking 0, 1 (mask plane → alpha), 2 (transparent colour → alpha) | Supported (masking 2 applies to indexed, EHB and PBM; not to HAM or true colour) |
| 4.1, 5.3 | Masking 3 (lasso) | Partial — parsed, rendered opaque |
| 4.2, 5.1 | Compression 0, 1 (incl. −128 no-op, cross-row runs, overshoot) | Supported |
| 4.2 | Compression 2 (Atari VDAT) and others | Unsupported — `unsupportedCompression` |
| 5.5, 6.2 | 6-plane files without `CAMG` (EHB / HAM6 heuristics) | Supported |
| 5.7 | HAM6, HAM8 | Supported |
| 5.7, 6.2 | HAM with depths other than 6 or 8 | Unsupported — `unsupportedDepth` |
| 5.8 | Extra-Half-Brite | Supported (8-bit halving) |
| 3.13, 5.9 | 24- and 32-plane true colour | Supported |
| 3.13 | 21-plane NewTek and other deep depths | Unsupported — `unsupportedDepth` |
| 3.7–3.9 | `GRAB`, `DEST`, `SPRT` | Ignored |
| 3.10 | `CRNG` | Parsed and exposed (`colorRanges`) |
| 3.10 | `CCRT`, `DRNG` | Ignored |
| 3.11, 3.12 | `SHAM`, `CTBL`/`DYCP`, `PCHG` dynamic palettes | Unsupported — ignored; image decodes with the static `CMAP` |
| 3.14 | Application chunks (`CLUT`, `CMYK`, `DPI `, `TINY`, …) | Ignored |
| 3.15 | `FORM PBM ` (1–8 planes, masking 0/2) | Supported |
| 3.16 | `FORM ACBM` | Unsupported |
| 3.17, 5.10 | `FORM RGBN`, `FORM RGB8` | Unsupported |
| 3.18, 5.11 | `FORM DEEP` | Unsupported |
| 3.19, 5.14 | `FORM ANIM` deltas | Unsupported — first frame only |
| — | Encoding / writing | Unsupported |

---

## 10. References and provenance

1. Jerry Morrison, Electronic Arts. *"EA IFF 85" Standard for Interchange
   Format Files*, 14 January 1985. Standards committee: Bob "Kodiak" Burns,
   R. J. Mical, Jerry Morrison, Greg Riker, Steve Shaw, Barry Walsh.
2. Jerry Morrison, Electronic Arts. *"ILBM" IFF Interleaved Bitmap*,
   17 January 1986; CRNG section updated October 1988 (Morrison); CAMG notes
   and additional-information appendix October 1988 (Commodore-Amiga, Inc.).
   Committee adds Dan Silva (EA). Published in the *Amiga ROM Kernel Reference
   Manual: Devices* (3rd ed., Addison-Wesley, 1991) and on the AmigaOS
   documentation wiki.
3. Commodore-Amiga, Inc. *Amiga Hardware Reference Manual*, 3rd ed., 1991 —
   HAM, Extra-Half-Brite and dual-playfield display modes; AGA HAM8.
4. Commodore-Amiga, Inc. *Amiga Developer CD v2.1*, `Extras/IFF/IFF_Forms`
   (1993): ACBM (Carolyn Scheppner, 1986), ANIM (Gary Bonham, SPARTA Inc., and
   Aegis Development, 1988), ANIM op 6 (William J. Coldwell, Cryogenic
   Software, 1991), ANIM op 8 (Joe Porkka, 1992), DEEP (Amiga Centre Scotland,
   1991, with TV Paint addendum), RGBN/RGB8 (Impulse), ILBM.PCHG (Sebastiano
   Vigna, draft 0.6, 1991), ILBM.CTBL.DYCP (NewTek), ILBM.DRNG (Lee Taran,
   EA), ILBM.CLUT (Justin V. McCormick), ILBM.CMYK / CNAM / XBMI (Soft-Logik),
   ILBM.DPI (Spencer Shanson), and the IFF registry.
5. Sebastiano Vigna. *pchg.library* documentation (public domain), 1992.
6. Electronic Arts. *Deluxe Paint II Enhanced* (MS-DOS) — origin of
   `FORM PBM `; behaviour observed from files it writes.
7. Netpbm `ilbmtoppm` user manual; AmigaOS `iffparse.library` and ILBM
   datatype documentation — de-facto reader behaviour.

**Provenance.** This document was written from the public specification
documents listed above, the Amiga hardware manuals, and black-box observation
of files written by the named programs. Facts, field layouts and numeric
tables are reproduced; prose is original. No third-party source code was
consulted or copied.
