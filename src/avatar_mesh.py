#!/usr/bin/env python3
"""Decode avatar models out of AvatarAssetPack.toc into OBJ.

This is the missing link for the 3D view: the pack stores each asset as a
Y TGR/STRB container whose Model block (id 3) is a chain of LZX-compressed
blocks holding a bit-packed mesh. Nothing here could be guessed — it follows the
format implemented by Avatar Aura (crates/avatar-formats, itself a port of
xenia's kernel/xam/avatars), with the LZX decoder in lzx.py.

    python3 avatar_mesh.py --pack <AvatarAssetPack.toc> --asset MaleBody --obj male.obj

Confirmed against the shipped pack: LZX decodes, the STRB Model block parses, and
MaleBody yields 1137 vertices / 2264 triangles (FemaleBody 1232 / 2454).

Positions come out in BIND space, not as a standing figure: MaleBody measures
1.79 along x (up), 1.51 along y, 0.37 along z, and baking it gives one bent limb
rather than a body. The block carries per-vertex blend indices and weights, so
the vertices are posed by the skeleton (STRB block 5) at draw time. Assembling a
standing avatar therefore needs skeleton + skinning, which is not implemented
here; for a posed model today, export from Avatar Aura and bake that.

Written values are positions and triangle indices only. Normals are lattice
packed and UVs are half floats per UV layer; flat shading needs neither.
"""

import argparse
import json
import math
import os
import struct
import sys

import lzx

SIGNATURE_SIZE = 0x140
BLOCK_HEADER_SIZE = 12
WINDOW_SIZE = 0x8000

BLOCK_NAMES = {
    0: "Invalid",
    1: "Animation",
    2: "Texture",
    3: "Model",
    4: "ShapeOverrides",
    5: "Skeleton",
    6: "AssetMetadataUnversioned",
    7: "CustomColorTable",
    8: "AssetMetadataVersioned",
}


class Malformed(Exception):
    pass


# ---------------------------------------------------------------- bit stream

class BitStream:
    """LSB-first bit reader over bytes, as the avatar formats define it."""

    def __init__(self, data):
        self.data = data
        self.offset = 0
        self.size_bits = len(data) * 8

    def check(self, num_bits):
        if self.offset + num_bits > self.size_bits:
            raise Malformed("bit overrun at %d (+%d of %d)" % (self.offset, num_bits, self.size_bits))

    def read(self, num_bits):
        if num_bits > 64:
            raise Malformed("read wider than 64 bits")
        self.check(num_bits)
        result = 0
        shift = 0
        offset = self.offset
        left = num_bits
        while left > 0:
            bit_in_byte = offset % 8
            take = min(8 - bit_in_byte, left)
            mask = (1 << take) - 1
            value = self.data[offset >> 3] >> bit_in_byte
            result |= (mask & value) << shift
            shift += take
            left -= take
            offset += take
        self.offset += num_bits
        return result

    def read_u8_bits(self, n):
        if n > 8:
            raise Malformed("u8 read wider than 8 bits")
        return self.read(n)

    def read_u16(self):
        return self.read(16)

    def read_u32(self):
        return self.read(32)

    def read_bytes(self, count):
        """Whole bytes as they sit, for data the stream does not bit-pack.

        Textures are byte-aligned and can be tens of kilobytes, so they cannot
        go through read(), which is a 64-bit field reader.
        """
        if self.offset % 8:
            raise Malformed("read_bytes at a bit offset")
        at = self.offset // 8
        if at + count > len(self.data):
            raise Malformed("read past the end of the block")
        self.offset += 8 * count
        return self.data[at:at + count]

    def read_i32(self):
        v = self.read(32)
        return v - (1 << 32) if v & (1 << 31) else v

    def read_i64_bits(self, n):
        v = self.read(n)
        if n and v & (1 << (n - 1)):
            v -= 1 << n
        return v

    def read_f32(self):
        return struct.unpack("<f", struct.pack("<I", self.read(32)))[0]

    def advance(self, n):
        self.check(n)
        self.offset += n

    def align_to_next_byte(self):
        self.offset = (self.offset + 7) & ~7
        self.check(0)


# ---------------------------------------------------------------- serializers

class VectorSerializer:
    """Lattice-quantized Vec3: base point, hexagonal step, per-axis bit widths."""

    def __init__(self, stream):
        self.quant_radius = stream.read_f32()
        self.base_x = stream.read_f32()
        self.base_y = stream.read_f32()
        self.base_z = stream.read_f32()
        self.bit_count_x = stream.read_u8_bits(6)
        self.bit_count_y = stream.read_u8_bits(6)
        self.bit_count_z = stream.read_u8_bits(6)
        self.delta_x = self.quant_radius * 2.0
        self.delta_y = self.quant_radius * (2.0 / 3.0) * (6.0 ** 0.5)
        self.delta_z = self.quant_radius * (3.0 ** 0.5)

    def read(self, stream):
        # The lattice counts are unsigned: position = min + q * step * k with
        # q in 0..2^width-1. Sign-extending q shears every mesh (MaleBody came
        # out 1.79 wide and asymmetric instead of +-0.711); open-avatar-lib's
        # docs/FORMATS.md 3.3 states the formula and its MaleBody bounds, and
        # decoding these as unsigned reproduces them exactly.
        x = stream.read(self.bit_count_x) if self.bit_count_x else 0
        y = stream.read(self.bit_count_y) if self.bit_count_y else 0
        z = stream.read(self.bit_count_z) if self.bit_count_z else 0
        out_y = self.base_y + self.delta_y * y
        out_z = self.base_z + self.delta_z * z
        if y & 1:
            out_z += (1.0 / 3.0) * self.delta_z
        out_x = self.base_x + self.delta_x * x
        if (y & 1) != (z & 1):
            out_x += 0.5 * self.delta_x
        return (out_x, out_y, out_z)


class ValueSerializer:
    """Base value plus a fixed-width unsigned delta."""

    def __init__(self, stream, bits, signed=False):
        self.mask = (1 << bits) - 1
        self.signed = signed
        self.base = stream.read(bits)
        self.width = stream.read(bits)
        if self.width > 64:
            raise Malformed("value serializer width above 64")

    def read(self, stream):
        delta = stream.read(self.width) if self.width else 0
        v = (self.base + delta) & self.mask
        if self.signed and v & (1 << (self.mask.bit_length() - 1)):
            v -= self.mask + 1
        return v


# ---------------------------------------------------------------- compression

# No block in an item decompresses to more than a few megabytes. The limit is
# what stops a block that is not a chain at all - a colour table, a texture -
# from having its own bytes read as a header that claims a four-gigabyte window.
MAX_DECOMPRESSED = 64 * 1024 * 1024


def decompress(data):
    """Chain of 12-byte-headered LZX blocks: (compressed, out_off, out_size).

    A retail closet model stops its chain and leaves a few trailing bytes that
    read as an oversized header; that tail is skipped so the model still decodes.
    """
    chunks = []
    size = 0
    offset = 0
    while offset + BLOCK_HEADER_SIZE <= len(data):
        comp, out_off, out_size = struct.unpack_from("<III", data, offset)
        offset += BLOCK_HEADER_SIZE
        if comp > len(data) - offset:
            if not chunks:
                raise Malformed("compressed block past end")
            break
        # Not a chain: whatever bytes these are, the header is invented, and
        # allocating what it asks for is how a real item dies with MemoryError.
        if (not out_size or out_off > MAX_DECOMPRESSED
                or out_size > MAX_DECOMPRESSED
                or out_off + out_size > MAX_DECOMPRESSED):
            if not chunks:
                raise Malformed("decompressed size out of range")
            break
        chunks.append((comp, out_off, out_size))
        size = max(size, out_off + out_size)
        offset += comp
    out = bytearray(size)
    offset = 0
    for comp, out_off, out_size in chunks:
        offset += BLOCK_HEADER_SIZE
        chunk = lzx.decompress(data[offset:offset + comp], out_size, WINDOW_SIZE)
        out[out_off:out_off + out_size] = chunk
        offset += comp
    return bytes(out)


# ---------------------------------------------------------------- STRB

def strb_blocks(buffer):
    """Every block: a table of (id, entry_count, entry_size) then the payloads."""
    strb = buffer
    if strb[:4] == b"YTGR":
        if len(strb) < SIGNATURE_SIZE:
            raise Malformed("short YTGR")
        strb = strb[SIGNATURE_SIZE:]
    if len(strb) < 24 or strb[:4] != b"STRB":
        raise Malformed("not a STRB container")

    has_alignment = strb[4] != 0
    little_endian = strb[5] != 0
    id_size = strb[22]
    size_size = strb[23]
    alignment = strb[26] if has_alignment else 1
    if alignment == 0:
        raise Malformed("block alignment of zero")

    def align(value):
        return (value + alignment - 1) & ~(alignment - 1)

    header_size = align(id_size + size_size + size_size)
    offset = align(30 if has_alignment else 26)
    order = "little" if little_endian else "big"
    if header_size == 0:
        raise Malformed("block header size of zero")

    out = []
    while offset + header_size <= len(strb):
        id_raw = int.from_bytes(strb[offset:offset + id_size], order)
        data_size = int.from_bytes(strb[offset + id_size:offset + id_size + size_size], order)
        entry_size = int.from_bytes(
            strb[offset + id_size + size_size:offset + id_size + 2 * size_size], order
        )
        # Everything past the last real block is zero padding. Reading it as
        # headers invented a run of empty "id 0" blocks - 144 of them on a
        # 36 KB container - which swamped the report's evidence list with
        # nothing at all.
        if data_size == 0 and entry_size == 0:
            break
        offset += header_size
        total = data_size * entry_size
        payload = strb[offset:offset + total]
        if len(payload) != total:
            raise Malformed("block extends past container")
        out.append((id_raw, data_size, entry_size, payload))
        # The payload is data_size * entry_size bytes, so that is what the next
        # block starts after. Advancing by data_size alone desyncs every block
        # that follows as soon as an entry is wider than one byte - which is
        # exactly how a texture and colour table end up "not there".
        offset += align(total)
    return out


# ---------------------------------------------------------------- model

def half_to_float(bits):
    """IEEE 754 binary16 -> float, for the 16-bit UV halves."""
    sign = -1.0 if bits & 0x8000 else 1.0
    exponent = (bits >> 10) & 0x1F
    mantissa = bits & 0x3FF
    if exponent == 0:
        return sign * mantissa * 2.0 ** -24
    if exponent == 0x1F:
        return sign * float("inf") if mantissa == 0 else float("nan")
    return sign * (1.0 + mantissa / 1024.0) * 2.0 ** (exponent - 15)


def texture_header_ok(header):
    """A 33-byte texture header, recognised by the 0x1A20 that follows the format.

    A magic found by chance in vertex data is not a header, so the walk stops on
    the first 33 bytes that do not carry it rather than reading garbage as a
    size.
    """
    return len(header) == 33 and header[2:4] == b"\x20\x1A"


def texture_size(fmt, width, height):
    """The bytes a texture's pixels take: DXT1 half a byte a texel, DXT5 one.

    This is the size stored in the table - 16,384 for a 256x128 DXT1, 1,024 for
    a 32x32 DXT5 - and it is not the `bytes a frame` in the header, which is the
    padded GPU size (4,096 for that 32x32 mask). Reading the padded size walks
    off the end of the table and loses every slot after the first.
    """
    blocks = max(1, width // 4) * max(1, height // 4)
    if fmt == 0x12:
        return blocks * 8
    if fmt == 0x14:
        return blocks * 16
    return 0


def read_texture_header(header, stream):
    """One texture entry: 33-byte header (xenos fetch constant style) and pixels.

    byte 0: low 6 bits the data format (0x12 DXT1, 0x14 DXT5), high 2 bits the
    endian mode (1 = 8-in-16, swap the bytes of every 16-bit word). Then a u16
    0x1A20, u32 width, u32 height, u32 allocated bytes, u32 bytes a frame, u32
    frame count, u32 flags (bit 0: empty slot), u32 height, u8 zero.
    """
    fmt = header[0] & 0x3F
    endian = header[0] >> 6
    width, height = struct.unpack_from("<II", header, 4)
    _, per_frame, frames, flags, _ = struct.unpack_from("<IIIII", header, 12)
    empty = bool(flags & 1)
    data = b""
    size = texture_size(fmt, width, height)
    if not empty and size:
        data = stream.read_bytes(size)
    return {"format": fmt, "width": width, "height": height, "frames": frames,
            "per_frame": per_frame, "size": size, "empty": empty,
            "endian": endian, "data": data}


def read_texture_table(stream, count):
    """A model's texture table: offset, allocated size, header, then the pixels.

    This is where an item's colours actually live - the base map, the tint mask
    that says which parts take a custom colour, and a decal - so a table that is
    not read is an item reported as having no texture at all. The walk stops on
    the first header that is not one, so a truncated table loses only what is
    missing.
    """
    textures = []
    for _ in range(count or 0):
        stream.align_to_next_byte()
        try:
            stream.read_u32()      # offset into the model's texture memory
            stream.read_u32()      # allocated size
            header = stream.read_bytes(33)
            if not texture_header_ok(header):
                break
            textures.append(read_texture_header(header, stream))
        except Malformed:
            break
    return textures


def _rgb565(v):
    r = (v >> 11) & 0x1F
    g = (v >> 5) & 0x3F
    b = v & 0x1F
    return ((r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2))


def decode_dxt(data, width, height, dxt5, swap=True):
    """DXT1 (BC1) or DXT5 (BC3) to an (h, w, 4) uint8 array, linear, not tiled."""
    import numpy as np
    if not data:
        return np.zeros((max(1, height), max(1, width), 4), np.uint8)
    raw = np.frombuffer(data, dtype=np.uint8)
    if swap:
        raw = raw.reshape(-1, 2)[:, ::-1].reshape(-1)
    block = 16 if dxt5 else 8
    bw, bh = (width + 3) // 4, (height + 3) // 4
    out = np.zeros((bh * 4, bw * 4, 4), np.uint8)
    need = bw * bh * block
    if len(raw) < need:
        raw = np.concatenate([raw, np.zeros(need - len(raw), np.uint8)])
    for by in range(bh):
        for bx in range(bw):
            off = (by * bw + bx) * block
            blk = raw[off:off + block]
            if dxt5:
                a0, a1 = int(blk[0]), int(blk[1])
                bits = int.from_bytes(bytes(blk[2:8]), "little")
                alpha = [a0, a1]
                if a0 > a1:
                    alpha += [((7 - i) * a0 + i * a1) // 7 for i in range(1, 7)]
                else:
                    alpha += [((5 - i) * a0 + i * a1) // 5 for i in range(1, 5)] + [0, 255]
                col = blk[8:16]
            else:
                alpha = None
                bits = 0
                col = blk[0:8]
            c0 = int(col[0]) | (int(col[1]) << 8)
            c1 = int(col[2]) | (int(col[3]) << 8)
            idx = int.from_bytes(bytes(col[4:8]), "little")
            p0, p1 = _rgb565(c0), _rgb565(c1)
            palette = [[*p0, 255], [*p1, 255]]
            if dxt5 or c0 > c1:
                palette.append([(2 * p0[k] + p1[k]) // 3 for k in range(3)] + [255])
                palette.append([(p0[k] + 2 * p1[k]) // 3 for k in range(3)] + [255])
            else:
                palette.append([(p0[k] + p1[k]) // 2 for k in range(3)] + [255])
                palette.append([0, 0, 0, 0])
            for py in range(4):
                for px in range(4):
                    n = py * 4 + px
                    texel = palette[(idx >> (2 * n)) & 3]
                    if alpha is not None:
                        texel = [texel[0], texel[1], texel[2], alpha[(bits >> (3 * n)) & 7]]
                    out[by * 4 + py, bx * 4 + px] = texel
    return out[:height, :width]


def decode_dxt_bytes(data, width, height, dxt5, swap=True):
    """DXT1/DXT5 to RGBA bytes, row after row, without numpy.

    The .bat runs on stock Python, so the texture path cannot use the array
    version above; the arithmetic is the same, texel for texel.
    """
    width, height = max(1, width), max(1, height)
    if not data:
        return bytes(width * height * 4)
    if swap:
        pairs = bytearray(data)
        pairs[0::2] = data[1::2]
        pairs[1::2] = data[0::2]
        data = bytes(pairs)
    block = 16 if dxt5 else 8
    bw, bh = (width + 3) // 4, (height + 3) // 4
    need = bw * bh * block
    if len(data) < need:
        data = data + bytes(need - len(data))
    out = bytearray(width * height * 4)
    for by in range(bh):
        for bx in range(bw):
            off = (by * bw + bx) * block
            raw = data[off:off + block]
            if dxt5:
                a0, a1 = raw[0], raw[1]
                bits = int.from_bytes(raw[2:8], "little")
                alpha = [a0, a1]
                if a0 > a1:
                    alpha += [((7 - i) * a0 + i * a1) // 7 for i in range(1, 7)]
                else:
                    alpha += [((5 - i) * a0 + i * a1) // 5 for i in range(1, 5)] + [0, 255]
                col = raw[8:16]
            else:
                bits = 0
                alpha = None
                col = raw[0:8]
            c0 = col[0] | (col[1] << 8)
            c1 = col[2] | (col[3] << 8)
            idx = int.from_bytes(col[4:8], "little")
            p0, p1 = _rgb565(c0), _rgb565(c1)
            palette = [p0 + (255,), p1 + (255,)]
            if dxt5 or c0 > c1:
                palette.append(tuple((2 * p0[k] + p1[k]) // 3 for k in range(3)) + (255,))
                palette.append(tuple((p0[k] + 2 * p1[k]) // 3 for k in range(3)) + (255,))
            else:
                palette.append(tuple((p0[k] + p1[k]) // 2 for k in range(3)) + (255,))
                palette.append((0, 0, 0, 0))
            for py in range(4):
                y = by * 4 + py
                if y >= height:
                    break
                row = y * width
                for px in range(4):
                    x = bx * 4 + px
                    if x >= width:
                        continue
                    n = py * 4 + px
                    texel = palette[(idx >> (2 * n)) & 3]
                    if alpha is not None:
                        texel = (texel[0], texel[1], texel[2], alpha[(bits >> (3 * n)) & 7])
                    at = (row + x) * 4
                    out[at:at + 4] = bytes(texel)
    return bytes(out)


def texture_from_block(data):
    """One texture out of a decompressed block 2: a 33-byte header, then pixels.

    byte 0: low 6 bits the format (0x12 DXT1, 0x14 DXT5), high 2 bits the
    endianness (1 = swap every 16-bit word). Then u16 0x1A20, width, height,
    allocated bytes, bytes per frame, frames, flags (bit 0 = empty slot),
    height again, and a zero byte.
    """
    if len(data) < 33:
        return None
    fmt = data[0] & 0x3F
    endian = data[0] >> 6
    width, height = struct.unpack_from("<II", data, 4)
    _, per_frame, frames, flags, _ = struct.unpack_from("<IIIII", data, 12)
    if flags & 1 or not width or not height or not per_frame or fmt not in (0x12, 0x14):
        return None
    pixels = data[33:33 + per_frame]
    if len(pixels) < per_frame:
        return None
    return {"width": width, "height": height, "format": fmt, "endian": endian,
            "frames": frames, "pixels": len(pixels),
            "rgba": decode_dxt_bytes(pixels, width, height, fmt == 0x14, swap=endian == 1)}


def sample_texture(texture, u, v, clamp=False):
    """Nearest texel. Returns (r, g, b) in 0..1, or None when the slot is empty.

    clamp=True clamps outside 0..1 instead of wrapping: the head's eyebrow, eye
    and mouth slots are all clamp-addressed, and wrapping their masks copies the
    mouth onto the cheeks.
    """
    if not texture or texture["empty"] or not texture["data"]:
        return None
    if not hasattr(texture, "_pixels") or texture.get("_pixels") is None:
        texture["_pixels"] = decode_dxt(texture["data"], texture["width"], texture["height"],
                                        texture["format"] == 0x14,
                                        swap=texture["endian"] == 1)
    pixels = texture["_pixels"]
    h, w = pixels.shape[:2]
    if clamp:
        x = min(w - 1, max(0, int(min(max(u, 0.0), 1.0) * w)))
        y = min(h - 1, max(0, int(min(max(v, 0.0), 1.0) * h)))
    else:
        x = min(w - 1, max(0, int(u * w) % w))
        y = min(h - 1, max(0, int(v * h) % h))
    r, g, b, a = pixels[y, x]
    if a < 8:
        return None
    return (r / 255.0, g / 255.0, b / 255.0)


def read_model(data):
    """Triangle batches: vertices (lattice positions) and u16 indices."""
    s = BitStream(data)
    cpu_size = s.read_u32()
    gpu_size = s.read_u32()
    s.read_u32()  # texture buffer size
    s.read_u32()  # vertex buffer size
    s.read_u32()  # index buffer size
    batch_count = s.read_u32()
    texture_count = s.read_u32()
    s.read_u32()  # vertex buffer offset
    s.read_u32()  # index buffer offset
    s.read_u32()  # triangle batch array offset
    s.read_u32()  # texture array offset
    s.read_u32()  # texture scratch size
    if batch_count > 16 or texture_count > 18:
        raise Malformed("batch/texture count out of range")

    batches = []
    for _ in range(batch_count):
        shader_id = s.read_u32()
        param_count = s.read_u8_bits(5)
        triangle_count = s.read_u32()
        vertex_count = s.read_u32()
        uv_count = s.read_u32()
        vertex_size = s.read_u32()
        s.read_u32()  # index size
        s.read_u32()  # vertex array offset
        s.read_u32()  # index array offset
        s.align_to_next_byte()
        # A retail costume can carry more than eight thousand vertices in one
        # batch, so the bound is the u16 index range rather than the editor's
        # smaller assets; the buffer size catches anything that is really junk.
        if triangle_count > 65536 or vertex_count > 65536 or uv_count > 6:
            raise Malformed("batch counts out of range")
        expected = (32 + 4 * (uv_count - 1)) & 0xFFFFFFFF
        if vertex_size != expected:
            raise Malformed("vertex size %d does not match %d UVs (expected %d)"
                            % (vertex_size, uv_count, expected))
        # Material records: u32 type, u32 parameter id, 16 bytes of value. Type 1
        # is a texture binding: u16 texture index, u16 UV set, u32 address mode.
        # Type 3 is a float4. Parameter id 1 is the base colour texture.
        materials = []
        for _ in range(param_count):
            ptype = s.read_u32()
            pid = s.read_u32()
            if ptype == 1:
                tex = s.read_u16()
                uv_set = s.read_u16()
                mode = s.read_u32()
                s.advance(64)
                materials.append({"kind": "texture", "id": pid, "texture": tex,
                                  "uv_set": uv_set, "mode": mode})
            else:
                # Four floats: the part's own colour when the item states one,
                # and zero when it does not. Read rather than skipped, because
                # this is the only per-part colour an item carries - armour,
                # skin and gear are separate batches, each with its own.
                words = [s.read_u32() for _ in range(4)]
                value = [struct.unpack("<f", struct.pack("<I", word))[0]
                         for word in words]
                materials.append({"kind": "vector", "id": pid, "texture": None,
                                  "uv_set": None, "mode": None, "value": value})
            s.align_to_next_byte()

        local_count = s.read_u32()
        if local_count != vertex_count:
            raise Malformed("vertex count mismatch")
        position = VectorSerializer(s)
        normal = ValueSerializer(s, 32, signed=True)
        weight = ValueSerializer(s, 32)
        blend = ValueSerializer(s, 32)
        colour = ValueSerializer(s, 32)

        verts = []
        uvs = []
        joints = []
        weights = []
        colours = []
        for _ in range(vertex_count):
            p = position.read(s)
            normal.read(s)
            w = weight.read(s)
            b = blend.read(s)
            # Four bytes that are not a colour. Measured over all 583 models and
            # 342,442 vertices: the alpha byte is always 255 and the three colour
            # bytes always carry the same value, so the field is one grey scalar
            # replicated into RGB (median 230, p05 188). It reads as a baked
            # occlusion/shading term - the jeans' darkest vertices sit on the inner
            # seam, the shoe soles are darkest of all - but the shader that
            # consumes it is Xenos microcode, which says nothing about the name.
            colours.append(colour.read(s))
            sets = []
            for _ in range(uv_count):
                # Texture coordinates are half floats, not fixed point: read as
                # u16 and reinterpret. Treating them as u16/65535 squeezes the
                # whole head into u 0.11..0.24, where no face texture reaches.
                u = s.read_u16()
                v = s.read_u16()
                sets.append((half_to_float(u), half_to_float(v)))
            uvs.append(sets)
            verts.append(p)
            # Four bone indices and four weights, one byte each.
            joints.append(((b >> 0) & 0xFF, (b >> 8) & 0xFF, (b >> 16) & 0xFF, (b >> 24) & 0xFF))
            weights.append((((w >> 0) & 0xFF) / 255.0, ((w >> 8) & 0xFF) / 255.0,
                            ((w >> 16) & 0xFF) / 255.0, ((w >> 24) & 0xFF) / 255.0))
        s.align_to_next_byte()

        index_count = s.read_u32()
        if index_count != triangle_count * 3:
            raise Malformed("index count mismatch")
        index_serializer = ValueSerializer(s, 16)
        indices = [index_serializer.read(s) for _ in range(index_count)]
        s.align_to_next_byte()

        batches.append({
            "shader_id": shader_id,
            "vertices": verts,
            "uvs": uvs,
            "materials": materials,
            "joints": joints,
            "weights": weights,
            "colours": colours,
            "indices": indices,
        })

    # After the last mesh, texture_count entries of (offset, allocated size,
    # 33-byte header, pixels) into the model's texture memory.
    textures = read_texture_table(s, texture_count)
    if batches:
        batches[0]["textures"] = textures
    return batches


# ---------------------------------------------------------------- pack access

def record_indices(pack_path):
    """Asset name -> its record index in the pack: the value descriptions store."""
    here = os.path.dirname(os.path.abspath(pack_path))
    for candidate in (os.path.join(here, "avatar-assets.json"),
                      os.path.join(os.path.dirname(os.path.abspath(__file__)), "avatar-assets.json")):
        if os.path.exists(candidate):
            with open(candidate, "r", encoding="utf-8") as fh:
                doc = json.load(fh)
            assets = doc.get("assets", doc)
            return {entry["name"]: i for i, entry in enumerate(assets)}
    raise SystemExit("no avatar-assets.json next to the pack; run toc_parse.py first")


def load_pack_index(pack_path):
    """Asset name -> (offset, size), from the JSON toc_parse.py writes."""
    here = os.path.dirname(os.path.abspath(pack_path))
    for candidate in (os.path.join(here, "avatar-assets.json"),
                      os.path.join(os.path.dirname(os.path.abspath(__file__)), "avatar-assets.json")):
        if os.path.exists(candidate):
            with open(candidate, "r", encoding="utf-8") as fh:
                doc = json.load(fh)
            assets = doc.get("assets", doc)
            index = {}
            for entry in assets:
                index[entry["name"]] = (entry["offset"], entry["size"])
            return index
    raise SystemExit("no avatar-assets.json next to the pack; run toc_parse.py first")


def asset_bytes(pack_path, index, name):
    if name not in index:
        close = [n for n in index if name.lower() in n.lower()][:8]
        raise SystemExit("asset %r not in the pack. Near misses: %s" % (name, ", ".join(close)))
    offset, size = index[name]
    with open(pack_path, "rb") as fh:
        fh.seek(offset)
        return fh.read(size)


def to_upright(p, up_axis):
    """Pack space into Y-up.

    The body meshes are authored X-up, Y-across, Z-depth: a standing male body
    measures about 1.79 along x, 1.51 along y (arms out, bind pose) and 0.37
    along z. Baking them as-is lays the figure on its side.
    """
    x, y, z = p
    if up_axis == "x":
        return (y, x, z)
    if up_axis == "z":
        return (x, z, y)
    return (x, y, z)


def vertex_normals(vertices, indices):
    """One normal per vertex, averaged over the triangles that use it.

    Without these the file carries positions only, so every importer shades it
    flat: the model reads as faceted blocks rather than a surface.
    """
    normals = [[0.0, 0.0, 0.0] for _ in vertices]
    for i in range(0, len(indices) - 2, 3):
        a, b, c = indices[i], indices[i + 1], indices[i + 2]
        if max(a, b, c) >= len(vertices):
            continue
        ax, ay, az = vertices[a]
        bx, by, bz = vertices[b]
        cx, cy, cz = vertices[c]
        ux, uy, uz = bx - ax, by - ay, bz - az
        vx, vy, vz = cx - ax, cy - ay, cz - az
        # Un-normalised, so a large triangle pulls its share of the average.
        nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
        for slot in (a, b, c):
            normals[slot][0] += nx
            normals[slot][1] += ny
            normals[slot][2] += nz
    for normal in normals:
        length = math.sqrt(normal[0] ** 2 + normal[1] ** 2 + normal[2] ** 2)
        if length > 1e-12:
            normal[0] /= length
            normal[1] /= length
            normal[2] /= length
        else:
            normal[:] = [0.0, 0.0, 1.0]
    return normals


def write_obj(path, batches, up_axis="x", material=None):
    """Wavefront OBJ: positions, texture coordinates, triangles, materials.

    One ``vt`` is written per vertex, in the same order, so a face's texture
    index is its vertex index. The pack is top-left origin like D3D and OBJ is
    bottom-left, so v is flipped and the texture comes up the right way round.
    """
    lines = []
    if material:
        lines.append("mtllib %s" % material)
    base = 1
    for index, batch in enumerate(batches):
        # Named by position, not by shader id: a suit has two batches that share
        # one shader, and the same name gave both the same material - so their
        # colours merged into one.
        lines.append("o batch_%d" % index)
        lines.append("usemtl batch_%d" % index)
        for (x, y, z) in batch["vertices"]:
            x, y, z = to_upright((x, y, z), up_axis)
            lines.append("v %.6f %.6f %.6f" % (x, y, z))
        sets = batch.get("uvs") or []
        # The texture coordinates the base colour texture actually samples, so a
        # model with several UV sets uses the one its material names.
        uv_index = 0
        for record in batch.get("materials") or []:
            if record.get("kind") == "texture" and record.get("id") == 1:
                uv_index = record.get("uv_set") or 0
                break
        for entry in sets:
            u, v = entry[uv_index] if uv_index < len(entry) else (entry[0] if entry else (0.0, 0.0))
            lines.append("vt %.6f %.6f" % (u, 1.0 - v))
        idx = batch["indices"]
        # One vn per vertex, in order, so its index matches the position index.
        for (x, y, z) in vertex_normals(batch["vertices"], idx):
            x, y, z = to_upright((x, y, z), up_axis)
            lines.append("vn %.6f %.6f %.6f" % (x, y, z))
        # Smooth shading: with the normals above this is a surface, not facets.
        lines.append("s 1")
        for i in range(0, len(idx) - 2, 3):
            # One vt and one vn per vertex, in order, so both indices are the
            # vertex index - all 1-based, all offset by the batch base.
            a, b, c = base + idx[i], base + idx[i + 1], base + idx[i + 2]
            if sets:
                lines.append("f %d/%d/%d %d/%d/%d %d/%d/%d" % (a, a, a, b, b, b, c, c, c))
            else:
                lines.append("f %d//%d %d//%d %d//%d" % (a, a, b, b, c, c))
        base += len(batch["vertices"])
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")


def write_mtl(path, batches, map_name=None, colours=None, maps=None):
    """A material per batch, in that batch's own colour.

    ``colours`` is one RGB per batch, 0..255: armour, skin and gear are separate
    batches and each carries its own, so the model is not one flat colour.
    ``maps`` is one image per batch for the same reason; ``map_name`` is the
    single image used when every batch shares a colour.
    """
    lines = []
    for index, batch in enumerate(batches):
        lines.append("newmtl batch_%d" % index)
        lines.append("Ka 0.000000 0.000000 0.000000")
        if colours and index < len(colours) and colours[index]:
            lines.append("Kd %.6f %.6f %.6f"
                         % tuple(channel / 255.0 for channel in colours[index]))
        else:
            lines.append("Kd 0.800000 0.800000 0.800000")
        lines.append("Ks 0.000000 0.000000 0.000000")
        lines.append("d 1.000000")
        lines.append("illum 1")
        name = maps[index] if maps and index < len(maps) else map_name
        if name:
            lines.append("map_Kd %s" % name)
        # With no base map written, name no map at all. Naming a .dds that is
        # never created makes the importer show a missing texture instead of
        # the plain material colour.
        lines.append("")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")


# ------------------------------------------------------------ colour tables

def colour_table(payload):
    """Decode a CustomColorTable (STRB block 7): the item's choosable colours.

    Layout, measured on every table in the retail pack and the closet dump:

        u32              number of choosable colours
        24 bytes         three base colours, each RGBA then a u32 holding the
                         offset (from the end of the count) of the palette
        count x 9 bytes  one per colour: three RGB triples, the first of which
                         is the colour. A flat colour repeats itself three
                         times; a gradient stores three different triples.

    The 28-byte placeholder tables stop after the 24-byte head: their u32s are
    zero, there is no palette, and the base colours are the item's stand-ins.
    """
    if len(payload) < 12:
        return None
    count = struct.unpack_from("<I", payload, 0)[0]
    if count > 4096:
        return None
    body = payload[4:]
    bases = []
    for index in range(3):
        record = body[index * 8:index * 8 + 8]
        if len(record) < 4:
            break
        bases.append((tuple(record[:3]), record[3]))
    palette = []
    if 0 < count <= 64 and len(body) >= 24 + count * 9:
        for index in range(count):
            entry = body[24 + index * 9:24 + index * 9 + 9]
            palette.append(tuple(entry[:3]))
    return {"count": count, "bases": bases, "colours": palette}


# ------------------------------------------------------- the other blocks

# Block 6 (metadata, unversioned) and block 8 (metadata, versioned) say what the
# item is; block 4 says which of the body's triangles it covers up and which
# vertices it moves. Both layouts are the published ones for this format, and
# both are checked against retail items here: a tee's block 6 reads male,
# component, 0x08 shirt, 0xC9 tee, and its block 4 reads 222 triangles on the
# model whose header word is 0x3510 (MaleBody) with a 12-bit width.
GENDERS = {1: "male", 2: "female", 3: "male and female"}
ASSET_TYPES = {1: "component", 2: "texture", 3: "shape override",
               4: "animation", 5: "shape override, post"}
COMPONENTS = {0x08: "shirt", 0x40: "hat", 0x100: "mask"}
SKELETONS = {1: "NXE", 2: "Natal", 3: "NXE and Natal"}
SHAPE_TARGETS = {0x3510: "MaleBody", 0x3984: "FemaleBody", 0x13D4: "Head"}


def _named(table, value):
    return table.get(value, "0x%X" % value)


def read_metadata(payload, versioned=False):
    """Gender, asset type, component mask and subcategory from block 6 or 8.

    Little-endian, although the container around it is not. The versioned form
    starts with a version byte and ends with one saying which skeleton it was
    made for; the unversioned form is the same fields without those two.
    """
    size = 15 if versioned else 13
    if len(payload) < size:
        raise Malformed("metadata block is %d bytes, %d are needed"
                        % (len(payload), size))
    at = 1 if versioned else 0
    gender = payload[at]
    asset_type, components, subcategory = struct.unpack_from("<III", payload, at + 1)
    facts = {
        "form": "versioned" if versioned else "unversioned",
        "gender": _named(GENDERS, gender),
        "asset_type": _named(ASSET_TYPES, asset_type),
        "component_mask": "0x%02X" % components,
        "component": _named(COMPONENTS, components),
        "subcategory": "0x%X" % subcategory,
        "bytes": len(payload),
    }
    if versioned:
        facts["version"] = payload[0]
        facts["skeleton"] = _named(SKELETONS, payload[14])
    return facts


def read_shape_overrides(payload):
    """The body triangles an item hides, and the vertices it moves.

    Little-endian and not compressed. Two sections, each introduced by a count
    and the model it applies to: the first lists triangle numbers, the target's
    triangles to leave out (a tee hides the body under it); the second lists
    vertex overrides against the same model, which is how a garment pulls the
    body in.
    """
    if len(payload) < 32:
        raise Malformed("shape block is %d bytes" % len(payload))
    count, target = struct.unpack_from("<II", payload, 0)
    stock = payload[8:24]
    reserved, width = struct.unpack_from("<II", payload, 24)
    if reserved != 0:
        raise Malformed("shape block reserved word is not zero")
    if not 1 <= width <= 32:
        raise Malformed("shape block triangle width is %d bits" % width)
    if count > 1 << 24:
        raise Malformed("shape block claims %d triangles" % count)
    reader = BitStream(payload[32:])
    triangles = [reader.read(width) for _ in range(count)]
    at = 32 + (count * width + 7) // 8
    facts = {
        "target": _named(SHAPE_TARGETS, target),
        "target_word": "0x%X" % target,
        "stock_id": stock.hex(),
        "triangles": count,
        "first_triangles": triangles[:5],
        "last_triangle": triangles[-1] if triangles else None,
        "vertex_overrides": 0,
    }
    if at + 48 <= len(payload):
        overrides, vertex_target = struct.unpack_from("<II", payload, at)
        _reserved, vertex_width = struct.unpack_from("<II", payload, at + 24)
        step, min_x, min_y, min_z = struct.unpack_from("<ffff", payload, at + 32)
        if overrides <= 1 << 24 and vertex_width == 16:
            facts["vertex_overrides"] = overrides
            facts["vertex_target_word"] = "0x%X" % vertex_target
            facts["vertex_step"] = step
            facts["vertex_min"] = [min_x, min_y, min_z]
    return facts


# A skeleton block (id 5) is plain little-endian: eight header words, the bone
# count last, then a bit stream whose two groups quantise positions and
# rotations the way a mesh header does. Each bone then leads with its parent
# byte (255 for the root). The block ends on its last bone, and that is checked:
# a block that does not end there is refused rather than read as bones.
SKELETON_HEADER = 32


def _as_float(bits):
    return struct.unpack("<f", struct.pack("<I", bits))[0]


def _read_group(reader):
    """f32 step, f32 min x, y, z, then three 6-bit widths."""
    step = _as_float(reader.read(32))
    minimum = [_as_float(reader.read(32)) for _ in range(3)]
    widths = [reader.read(6) for _ in range(3)]
    return {"step": step, "min": minimum, "widths": widths}


def read_skeleton(payload):
    """The bone count and tree a prop's own skeleton block holds."""
    if len(payload) < SKELETON_HEADER:
        raise Malformed("skeleton block is %d bytes" % len(payload))
    bones = struct.unpack_from("<I", payload, 28)[0]
    if not 1 <= bones <= 512:
        raise Malformed("skeleton block claims %d bones" % bones)
    reader = BitStream(payload[SKELETON_HEADER:])
    position = _read_group(reader)
    rotation = _read_group(reader)
    position_bits = sum(position["widths"])
    rotation_bits = sum(rotation["widths"])
    if not 0 < position_bits <= 96 or not 0 < rotation_bits <= 96:
        raise Malformed("skeleton block widths are %r and %r"
                        % (position["widths"], rotation["widths"]))
    parents = []
    for _ in range(bones):
        parents.append(reader.read(8))
        for width in (position_bits, rotation_bits):
            left = width
            while left > 0:
                reader.read(min(64, left))
                left -= min(64, left)
    used = SKELETON_HEADER * 8 + reader.offset
    if used > len(payload) * 8 or used <= (len(payload) - 1) * 8:
        raise Malformed("skeleton block ends at bit %d of %d"
                        % (used, len(payload) * 8))
    roots = [index for index, parent in enumerate(parents) if parent == 255]
    if any(parent != 255 and parent >= index
           for index, parent in enumerate(parents)):
        raise Malformed("skeleton parent does not come before its bone")
    return {
        "bones": bones,
        "roots": len(roots),
        "root": roots[0] if roots else None,
        "parents": parents,
        "position": position,
        "rotation": rotation,
        "bytes": len(payload),
    }


def uv_coverage(batches, size=256, set_index=None):
    """One byte a texel: 255 where the item's own UV layout covers the canvas.

    Halo's shader samples the multipurpose and change-colour bitmaps in the same
    texture space as the base map, so the masks have to follow the mesh's own
    islands. Painting each triangle into that space gives exactly that; a single
    flat colour does not, and cannot show which island a mask belongs to.

    With no set named, each batch uses the UV set its base-colour material does,
    which is the space the shader will sample the masks in.
    """
    mask = bytearray(size * size)
    last = float(size - 1)
    painted = 0
    for batch in batches:
        uvs = batch.get("uvs") or []
        indices = batch.get("indices") or []
        if not uvs:
            continue
        chosen = set_index
        if chosen is None:
            chosen = 0
            for record in batch.get("materials") or []:
                if record.get("kind") == "texture" and record.get("id") == 1:
                    chosen = record.get("uv_set") or 0
                    break
        if chosen >= len(uvs[0]):
            continue
        for step in range(0, len(indices) - 2, 3):
            points = []
            for index in indices[step:step + 3]:
                if index >= len(uvs):
                    points = []
                    break
                u, v = uvs[index][chosen]
                # The pack is D3D top-left origin, so v runs down the image and
                # row = v. A mask written the other way up is a mirror of the
                # base map it has to sit beside.
                points.append((u * last, v * last))
            if len(points) != 3:
                continue
            (x1, y1), (x2, y2), (x3, y3) = points
            low_x = max(0, int(min(x1, x2, x3)))
            high_x = min(size - 1, int(max(x1, x2, x3)) + 1)
            low_y = max(0, int(min(y1, y2, y3)))
            high_y = min(size - 1, int(max(y1, y2, y3)) + 1)
            if (high_x - low_x) * (high_y - low_y) > size * size // 2:
                # A triangle that wraps the whole atlas is a bad reading of the
                # UVs, not a mask: skip it rather than flood the image.
                continue
            for y in range(low_y, high_y + 1):
                for x in range(low_x, high_x + 1):
                    d1 = (x - x2) * (y3 - y2) - (x3 - x2) * (y - y2)
                    d2 = (x3 - x1) * (y - y1) - (x - x1) * (y3 - y1)
                    d3 = (x1 - x2) * (y - y2) - (x2 - x1) * (y - y2)
                    if ((d1 >= 0 and d2 >= 0 and d3 >= 0)
                            or (d1 <= 0 and d2 <= 0 and d3 <= 0)):
                        mask[y * size + x] = 255
    for value in mask:
        if value:
            painted += 1
    return bytes(mask), painted


def bake_mask(batches, source, channel, size, from_set, to_set):
    """A mask carried from the UV set it is painted in to the one the shader uses.

    Halo's shader samples the multipurpose map in the base map's UV set, so a
    mask painted in a different set has to be carried across the geometry:
    walking each triangle in `to_set` space and reading the mask at the same
    point in `from_set` space puts the tint where the base map shows it. The
    Marine armour's mask sits in UV set 2 and its base map in set 0, and the two
    share no vertex, so reading one as the other tints the wrong parts.

    Texture coordinates are in tiles, not in 0..1 - the base map's own run from
    -3.6 to 4.0 - so both sides wrap, the way a repeating atlas does for the
    colour. Where tiles overlap a texel takes the last triangle that covers it.
    """
    width = source.get("width") or 0
    height = source.get("height") or 0
    rgba = source.get("rgba") or b""
    if width <= 0 or height <= 0 or len(rgba) < width * height * 4:
        return None
    mask = bytearray(size * size)
    last = float(size - 1)
    for batch in batches or []:
        uvs = batch.get("uvs") or []
        indices = batch.get("indices") or []
        if not uvs or not indices:
            continue
        for step in range(0, len(indices) - 2, 3):
            corners = indices[step:step + 3]
            if max(corners) >= len(uvs):
                continue
            destination = []
            sources = []
            for index in corners:
                entry = uvs[index]
                if to_set >= len(entry) or from_set >= len(entry):
                    destination = []
                    break
                destination.append(entry[to_set])
                sources.append(entry[from_set])
            if len(destination) != 3:
                continue
            # A triangle that crosses a tile edge has to be drawn once per tile
            # it reaches, or the part past the edge lands on the far side of
            # the atlas: the coordinates are tiles, not 0..1, so the canvas is
            # one tile of a repeating space.
            for shift_u in (-1, 0, 1):
                for shift_v in (-1, 0, 1):
                    points = [((u + shift_u) * last, (v + shift_v) * last)
                              for u, v in destination]
                    paint_triangle(mask, size, points, sources, rgba,
                                   width, height, channel)
    return bytes(mask)


def paint_triangle(mask, size, points, sources, rgba, width, height, channel):
    """Fill one triangle of the mask; False when it falls outside the canvas."""
    (x1, y1), (x2, y2), (x3, y3) = points
    low_x = max(0, int(min(x1, x2, x3)))
    high_x = min(size - 1, int(max(x1, x2, x3)) + 1)
    low_y = max(0, int(min(y1, y2, y3)))
    high_y = min(size - 1, int(max(y1, y2, y3)) + 1)
    if low_x > high_x or low_y > high_y:
        return False
    area = (y2 - y3) * (x1 - x3) + (x3 - x2) * (y1 - y3)
    if not area:
        return False
    if (high_x - low_x) * (high_y - low_y) > size * size // 2:
        # A triangle that covers half the atlas is a bad reading of the UVs, not
        # a mask: skip it rather than flood the image.
        return False
    for y in range(low_y, high_y + 1):
        row = y * size
        for x in range(low_x, high_x + 1):
            w1 = ((y2 - y3) * (x - x3) + (x3 - x2) * (y - y3)) / area
            w2 = ((y3 - y1) * (x - x3) + (x1 - x3) * (y - y3)) / area
            w3 = 1.0 - w1 - w2
            # A hair outside the edge still belongs to it: texel centres never
            # land exactly on a shared edge, and a mask with one texel seams
            # through it would tint in stripes.
            if w1 < -0.05 or w2 < -0.05 or w3 < -0.05:
                continue
            u = w1 * sources[0][0] + w2 * sources[1][0] + w3 * sources[2][0]
            v = w1 * sources[0][1] + w2 * sources[1][1] + w3 * sources[2][1]
            sx = int((u % 1.0) * width) % width
            sy = int((v % 1.0) * height) % height
            mask[row + x] = rgba[(sy * width + sx) * 4 + channel]
    return True


def main():
    parser = argparse.ArgumentParser(description="Decode an avatar mesh from the asset pack.")
    parser.add_argument("--pack", required=True, help="AvatarAssetPack.toc")
    parser.add_argument("--asset", action="append",
                        help="asset name, e.g. MaleBody (repeat to merge several)")
    parser.add_argument("--obj", help="write the mesh here")
    parser.add_argument("--up-axis", default="x", choices=("x", "y", "z"),
                        help="which pack axis is up (bodies are x)")
    parser.add_argument("--blocks", action="store_true", help="list the container's blocks")
    args = parser.parse_args()

    index = load_pack_index(args.pack)
    names = args.asset or ["MaleBody"]
    print("%d assets in pack" % len(index))

    all_batches = []
    for name in names:
        blob = asset_bytes(args.pack, index, name)
        print("%s: %d bytes" % (name, len(blob)))
        blocks = strb_blocks(blob)
        if args.blocks:
            for id_raw, count, entry_size, payload in blocks:
                print("  block %-3d %-26s count=%d entry=%d bytes=%d"
                      % (id_raw, BLOCK_NAMES.get(id_raw, "Other"), count, entry_size, len(payload)))

        models = [b for b in blocks if b[0] == 3]
        if not models:
            raise SystemExit("no Model block in %s" % name)

        verts = tris = 0
        for _, _, _, payload in models:
            for batch in read_model(decompress(payload)):
                verts += len(batch["vertices"])
                tris += len(batch["indices"]) // 3
                all_batches.append(batch)
        print("  decoded %d model block(s): %d vertices, %d triangles"
              % (len(models), verts, tris))

    if args.obj:
        write_obj(args.obj, all_batches, args.up_axis)
        print("wrote", args.obj)


if __name__ == "__main__":
    main()
