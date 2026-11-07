# The IFF ILBM and PBM Image Formats

A byte-level reference for decoder implementers, covering the EA IFF 85
container and the ILBM (InterLeaved BitMap) and PBM (Planar BitMap, actually
chunky) image FORMs, plus the Commodore-Amiga-specific chunks that change how
pixels are decoded.

---

## 1. History and Scope

**EA IFF 85** ("Interchange File Format") was published by Jerry Morrison of
Electronic Arts in January 1985, in cooperation with Commodore-Amiga, as a
general tagged container for interchange between programs. **ILBM** — "IFF
Interleaved Bitmap" — was the first and most widely used IFF FORM. It was the
native image format of Deluxe Paint and, by extension, of practically every
Amiga paint, digitizer and presentation program. Deluxe Paint II Enhanced for
the PC (1989) introduced the **PBM** FORM, which keeps the ILBM chunk structure
but stores one byte per pixel instead of interleaved bitplanes.

Commodore later documented additional chunks (notably `CAMG`, which carries
Amiga display modes such as Hold-And-Modify) in the *Amiga ROM Kernel Reference
Manual: Devices* (3rd edition, 1991) and the IFF documentation on the Amiga
Developer CDs. Those documents are the authoritative sources; this summary
follows them and notes de-facto reader behaviour where files in the wild
deviate.

---

## 2. EA IFF 85 Container

### 2.1 Chunks

Every IFF structure is a **chunk**:

| Offset | Size | Field | Notes |
|---:|---:|---|---|
| 0 | 4 | `ckID` | Four ASCII characters in the range `0x20`–`0x7E`. Case-sensitive. Shorter names are padded with trailing spaces (`"CAT "`, `"PBM "`). |
| 4 | 4 | `ckSize` | **Big-endian** count of data bytes that follow. Excludes the 8-byte header and any pad byte. Defined as a signed `LONG`, so legal values are 0 ... 2³¹−1. |
| 8 | `ckSize` | `ckData` | Payload. |
| 8 + `ckSize` | 0 or 1 | pad | If `ckSize` is odd, one pad byte (should be 0) follows so the next chunk starts on an even offset. **Not** counted in `ckSize`. |

All multi-byte integers in IFF and ILBM are **big-endian** (Motorola 68000
order). `UBYTE`/`UWORD`/`ULONG` are unsigned 8/16/32-bit; `WORD`/`LONG` are
signed.

### 2.2 Group chunks

Four chunk IDs introduce nested structure. Their payload begins with a
4-character **type** followed by further chunks:

| ID | Payload | Meaning |
|---|---|---|
| `FORM` | type, then local chunks (and nested groups) | One self-contained object of the given type (`ILBM`, `PBM `, `8SVX`, `ANIM`, …). |
| `LIST` | contents type, then `PROP`s, then `FORM`/`LIST`/`CAT ` | A group of objects that may share properties. |
| `CAT ` | hint type (`"    "` = no hint), then `FORM`/`LIST`/`CAT ` | A simple concatenation of objects. |
| `PROP` | type, then property chunks | Only legal inside a `LIST`, before its `FORM`s. Supplies default property chunks (for example a shared `BMHD` and `CMAP`) for every `FORM` of that type in the `LIST`. Chunks inside a `FORM` override `PROP` defaults. |

IDs `FOR1`–`FOR9`, `LIS1`–`LIS9` and `CAT1`–`CAT9` are reserved for future
group types. A file normally starts with `FORM`, `LIST` or `CAT `.

An `ANIM` file is `FORM ANIM` containing a sequence of `FORM ILBM` frames; the
first frame is a complete ILBM.

### 2.3 Reader rules

* **Skip unknown chunks.** A reader must ignore any chunk ID it does not
  understand, using `ckSize` (plus pad) to step over it. Writers add
  application chunks (`ANNO`, `AUTH`, `(c) `, `NAME`, `DPI `, `DPPS`, `TINY`,
  …) freely.
* **Chunk order** within a FORM is significant only where a FORM's
  specification says so. ILBM requires property chunks (`BMHD`, `CMAP`,
  `CAMG`, …) to precede `BODY`.
* **Sizes are untrusted.** A chunk whose `ckSize` exceeds the bytes remaining
  in its parent is malformed. The outer group's size is frequently wrong in
  files written by buggy software (off by the pad byte, or larger than the
  file); readers commonly clamp it to the file length.

---

## 3. FORM ILBM

### 3.1 Chunks

| ID | Required | Purpose |
|---|---|---|
| `BMHD` | Yes | Bitmap header (Section 3.2). Must come first. |
| `CMAP` | Usually | Colour map (Section 3.3). Required in practice for indexed images. |
| `CAMG` | No | Amiga display mode (Section 4). |
| `GRAB` | No | Hotspot: `WORD x, y`. |
| `DEST` | No | Destination plane merge: `UBYTE depth, pad1; UWORD planePick, planeOnOff, planeMask`. |
| `SPRT` | No | Sprite precedence: `UWORD`. Marks the image as a sprite. |
| `CRNG` | No | Colour-cycling range (Section 6). Repeatable. |
| `CCRT` | No | Graphicraft colour-cycling range (Section 6). |
| `DRNG` | No | Deluxe Paint IV enhanced range (Section 6). |
| `SHAM`, `PCHG`, `CTBL` | No | Per-line palette changes ("sliced HAM", dynamic HAM / HiRes). |
| `BODY` | Yes* | Pixel data (Section 3.4). *A FORM may omit it when used purely as a palette. |

### 3.2 BMHD — BitMapHeader (20 bytes)

| Offset | Type | Field | Notes |
|---:|---|---|---|
| 0 | UWORD | `w` | Raster width in pixels. |
| 2 | UWORD | `h` | Raster height in pixels. |
| 4 | WORD | `x` | Suggested position on the destination page. |
| 6 | WORD | `y` | |
| 8 | UBYTE | `nPlanes` | Number of bitplanes, excluding any mask plane. 1–8 for indexed images (OCS/ECS hardware: up to 6; AGA: 8); 24 (or 32) for "deep" true-colour ILBM. |
| 9 | UBYTE | `masking` | 0 `mskNone`; 1 `mskHasMask`; 2 `mskHasTransparentColor`; 3 `mskLasso`. Other values are undefined. |
| 10 | UBYTE | `compression` | 0 `cmpNone`; 1 `cmpByteRun1`. Other values are undefined. |
| 11 | UBYTE | `pad1` | Unused; write 0, ignore on read. |
| 12 | UWORD | `transparentColor` | Palette index treated as transparent ("background") when `masking == 2`. |
| 14 | UBYTE | `xAspect` | Pixel aspect ratio `xAspect : yAspect`, e.g. 10:11 for a 320×200 NTSC low-res screen, 5:11 for 640×200, 20:11 for 320×400. 0 means unknown. |
| 15 | UBYTE | `yAspect` | |
| 16 | WORD | `pageWidth` | Size of the source page / screen in pixels. |
| 18 | WORD | `pageHeight` | |

**Masking semantics.**

* `mskNone` (0): opaque rectangle.
* `mskHasMask` (1): a mask bitplane is stored in `BODY` after the image
  planes of every row (Section 3.4). A 1 bit means the pixel is part of the
  image (opaque); 0 means transparent.
* `mskHasTransparentColor` (2): pixels whose colour index equals
  `transparentColor` are transparent. No extra data in `BODY`.
* `mskLasso` (3): the reader should "lasso" the image (flood-fill from the
  edges with `transparentColor` to find the outline). No extra data in
  `BODY`. Rarely used; most readers treat it as opaque.

### 3.3 CMAP — Colour map

`n × 3` bytes: `UBYTE red, green, blue` per entry, in index order. Normally
`n = 2^nPlanes` (fewer entries are legal; missing entries are typically
treated as black). For HAM6 `n` is 16, for HAM8 64, and for EHB 32 (the
upper 32 half-brite colours are implied).

**4-bit palettes.** The original Amiga chipsets (OCS/ECS) have 4 bits per
gun, and much software of that era stored colours left-justified: a 4-bit
value *n* is written as `n << 4`, peaking at `0xF0`. Displayed on an 8-bit system
such a palette is slightly dark (white is `0xF0F0F0`). Readers therefore
commonly test whether **every component's low nibble is zero** and, if so,
scale each component as `c | (c >> 4)` (equivalently `n × 17`), mapping
`0xF0` to `0xFF`. Writers of 8-bit data should store full 8-bit values.

An odd trailing 1–2 bytes in `CMAP` (a partial entry) is ignored by common
readers.

### 3.4 BODY — Interleaved bitplanes

The image is stored row by row, top to bottom. Each row consists of one
**plane row** per bitplane, plane 0 first, followed by the mask plane row if
`masking == 1`:

```
row 0:  plane 0 | plane 1 | … | plane nPlanes−1 | [mask]
row 1:  plane 0 | plane 1 | … | plane nPlanes−1 | [mask]
…
```

Each plane row is

```
RowBytes = ((w + 15) / 16) × 2        // width rounded up to a 16-bit word
```

bytes long. Within a byte, bit 7 is the leftmost pixel. The value of the
pixel at column *x* is assembled from bit *x* of each plane row, **plane 0
being the least significant bit**:

```
value(x) = Σ  bit(plane p, x) << p        for p in 0 ..< nPlanes
```

Padding bits beyond `w` are ignored.

Uncompressed size of `BODY`:
`h × (nPlanes + (masking == 1 ? 1 : 0)) × RowBytes`.

### 3.5 ByteRun1 compression

`compression == 1` packs each row with **ByteRun1**, a byte-oriented RLE
identical to Apple's PackBits. Read a control byte *n* as a signed 8-bit
value:

| *n* | Action |
|---|---|
| 0 … 127 | Copy the next *n* + 1 bytes literally. |
| −1 … −127 | Repeat the next byte −*n* + 1 times (2 … 128 copies). |
| −128 | No operation; read the next control byte. |

The specification has encoders compress **each plane row separately**, so a
packet never spans two plane rows. Readers that decode the BODY as one
continuous stream accept both conforming files and the occasional
non-conforming file whose runs cross a row boundary, and produce identical
output for conforming files. Some encoders emit a final packet that
overshoots the last row; readers discard the excess.

Two input bytes expand to at most 128 output bytes, so a BODY of *L* bytes
can never decode to more than `⌊L / 2⌋ × 128` bytes — a cheap check that
rejects decompression bombs before allocating.

---

## 4. CAMG — Amiga display modes

`CAMG` holds one `ULONG`: the Amiga `ViewPort` mode bits the image was
created in (under AmigaOS 2.0+ the upper 16 bits may hold a monitor ID).

| Bit | Name | Effect on decoding |
|---:|---|---|
| `0x0002` | `GENLOCK_VIDEO` | None. |
| `0x0004` | `LACE` | Interlaced: doubles vertical resolution (affects aspect only). |
| `0x0020` | `SUPERHIRES` | ECS 1280-pixel mode (aspect only). |
| `0x0040` | `PFBA` | Playfield 2 priority (dual playfield only). |
| `0x0080` | `EXTRA_HALFBRITE` | EHB, see 4.2. |
| `0x0100` | `GENLOCK_AUDIO` | None. |
| `0x0400` | `DUALPF` | Dual playfield: odd planes and even planes form two separate images. |
| `0x0800` | `HAM` | Hold-And-Modify, see 4.1. |
| `0x1000` | `EXTENDED_MODE` | None. |
| `0x2000` | `VP_HIDE` | None. |
| `0x4000` | `SPRITES` | None. |
| `0x8000` | `HIRES` | 640-pixel mode (aspect only). |

Readers should ignore bits they do not understand; some writers stored
garbage in `VP_HIDE`, `SPRITES` and the genlock bits.

**Files without `CAMG`.** Early files omit the chunk. The de-facto
heuristics for a 6-plane image without `CAMG` are: a 32-entry `CMAP` means
EHB; a 16-entry (or smaller) `CMAP` means HAM6.

### 4.1 Hold-And-Modify (HAM6, HAM8)

With `HAM` set, the top two bits of each pixel value are a control code and
the remaining `nPlanes − 2` bits are data:

| Control | Meaning |
|---|---|
| `00` | Set the pixel to palette entry *data*. |
| `01` | Hold red and green from the pixel to the left; modify **blue**. |
| `10` | Hold green and blue; modify **red**. |
| `11` | Hold red and blue; modify **green**. |

* **HAM6** (`nPlanes == 6`, OCS/ECS): 4 data bits, 16-entry palette. A
  modify sets the 4-bit component to *data*; in 8-bit terms `data × 17`.
* **HAM8** (`nPlanes == 8`, AGA): 6 data bits, 64-entry palette. A modify
  replaces the **upper 6 bits** of the 8-bit component with *data* and keeps
  the lower 2 bits from the previous pixel.
* The "previous pixel" at the start of every row is the **background colour**
  (palette entry 0), as on the hardware.

### 4.2 Extra-Half-Brite (EHB)

With `EXTRA_HALFBRITE` and `nPlanes == 6`, indices 0–31 select palette
entries 0–31 and indices 32–63 select entries 0–31 with each component
halved (`c >> 1`). The `CMAP` normally holds 32 entries; hardware ignores
any stored entries 32–63.

---

## 5. Deep (true-colour) ILBM

`nPlanes == 24` stores direct RGB: planes 0–7 are red (plane 0 = least
significant bit), 8–15 green, 16–23 blue. Some writers also produce
`nPlanes == 32`, with planes 24–31 as alpha. No
`CMAP` is needed. Other depths above 8 (12, 18, 21) appear only in a few
experimental files.

Related but distinct true-colour FORMs — `RGBN`, `RGB8` (Impulse), `ACBM`
(contiguous bitmap, `ABIT` chunk) and `DEEP` (TV Paint) — are separate FORM
types, not ILBM.

---

## 6. Colour cycling

### CRNG (Deluxe Paint)

| Offset | Type | Field |
|---:|---|---|
| 0 | WORD | `pad1` (0) |
| 2 | WORD | `rate` — 16384 = 60 steps per second; 0 = inactive |
| 4 | WORD | `flags` — bit 0 `RNG_ACTIVE`, bit 1 `RNG_REVERSE` |
| 6 | UBYTE | `low` — first colour register |
| 7 | UBYTE | `high` — last colour register |

### CCRT (Graphicraft)

`WORD direction` (0 none, 1 forward, −1 backward); `UBYTE start, end`;
`LONG seconds, microseconds` (delay per step); `WORD pad`.

### DRNG (Deluxe Paint IV)

`UBYTE min, max; WORD rate, flags; UBYTE ntrue, nregs;` followed by `ntrue`
`DColor { UBYTE cell, r, g, b }` and `nregs` `DIndex { UBYTE cell, index }`
records describing a range that mixes true colours and registers.

Colour cycling animates the palette; it does not change the pixel data, so a
static decoder may ignore these chunks.

---

## 7. FORM PBM (Deluxe Paint II Enhanced)

`FORM PBM ` uses the same `BMHD`, `CMAP` (and optional `CRNG`, `DPPS`,
`TINY`, …) chunks as ILBM, but `BODY` is **chunky**: one byte per pixel
(the palette index), rows stored top to bottom, each row padded to an
**even** number of bytes (`(w + 1) & ~1`). `nPlanes` is normally 8.
`compression == 1` applies ByteRun1 to each row. `CAMG` is not used, and a
mask plane (`masking == 1`) is not defined for PBM.

---

## 8. Implementation checklist and hostile input

* Validate the outer group ID; locate the first `FORM ILBM` / `FORM PBM `
  (possibly nested in `LIST`, `CAT ` or `FORM ANIM`); bound nesting depth.
* Step over unknown and zero-length chunks; honour the pad byte; reject a
  chunk whose size exceeds its parent. Do arithmetic in 64 bits (or checked):
  a `ULONG` size does not fit a 32-bit signed integer.
* Require `BMHD` (≥ 20 bytes) and `BODY`; require `w > 0` and `h > 0`.
* Cap `w × h` before allocating (a 20-byte header can declare 65535 × 65535
  pixels), and check that an uncompressed `BODY` is long enough, or that a
  compressed one *could* be (Section 3.5).
* Reject undefined `masking` and `compression` values rather than guessing.
* Palette indices beyond the `CMAP` must not be used to index memory; render
  them as black.

---

## 9. References

1. Jerry Morrison, Electronic Arts. *"EA IFF 85" Standard for Interchange
   Format Files*, 14 January 1985.
2. Jerry Morrison, Electronic Arts. *"ILBM" IFF Interleaved Bitmap*, 1986
   revision.
3. Commodore-Amiga, Inc. *Amiga ROM Kernel Reference Manual: Devices*,
   3rd ed., Addison-Wesley, 1991 — appendices on IFF, ILBM, `CAMG` and the
   colour-cycling chunks.
4. Commodore-Amiga, Inc. *Amiga Hardware Reference Manual*, 3rd ed., 1991
   — HAM and Extra-Half-Brite display modes; AGA HAM8 behaviour.
5. Netpbm `ilbmtoppm` and the AmigaOS `iffparse.library` /
   `datatypes` ILBM implementation — de-facto reader behaviour (consulted for
   comparison only; no code copied).

---

## 10. SwiftILBM coverage

| Feature | Status |
|---|---|
| IFF chunks, big-endian sizes, odd-size padding | Supported |
| Unknown / zero-length chunk skipping | Supported |
| `FORM ILBM` at top level | Supported |
| `FORM PBM ` (Deluxe Paint II Enhanced) | Supported (1–8 planes, no mask plane) |
| Nested `LIST` / `CAT ` / `FORM ANIM` (first ILBM/PBM found) | Supported (depth ≤ 8) |
| `PROP` defaults inside `LIST` | Supported |
| `BMHD` all fields | Supported; `xAspect`/`yAspect` exposed as `pixelAspectRatio` |
| `masking` 0 / 1 / 2 | Supported (mask plane and transparent colour become alpha) |
| `masking` 3 (lasso) | Partial — parsed, rendered opaque |
| `compression` 0 / 1 (ByteRun1, incl. −128 no-op) | Supported |
| `CMAP`, incl. 4-bit left-justified scaling | Supported (scaling on by default) |
| 1–8 plane indexed | Supported |
| `CAMG` HAM6 / HAM8 | Supported |
| `CAMG` EHB | Supported |
| `CAMG` HIRES / LACE / SUPERHIRES | Exposed (no effect on pixels) |
| `CAMG` dual playfield | Unsupported — decoded as plain indexed |
| 24- and 32-plane deep ILBM | Supported |
| `CRNG` | Parsed and exposed |
| `CCRT`, `DRNG` | Unsupported (ignored) |
| `GRAB`, `DEST`, `SPRT` | Unsupported (ignored) |
| `SHAM`, `PCHG`, `CTBL` dynamic palettes | Unsupported (ignored; image decodes with the static `CMAP`) |
| ANIM deltas (`DLTA`) | Unsupported (first frame only) |
| `ACBM`, `RGBN`, `RGB8`, `DEEP` FORMs | Unsupported |
| Encoding / writing | Unsupported |
