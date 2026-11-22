"""LZX decompression, ported from libmspack's lzxd.c as used by the avatar packs.

The AvatarAssetPack blobs and the .AvatarAnimation files are LZX-compressed in
8 KiB frames, wrapped in 12-byte block headers (see compression.py). This is a
faithful port of the reduction libmspack/xenia use: regular LZX, no reset
interval, no delta filter, 32 KiB window.

Bit order matters: the stream is read as 16-bit little-endian words, most
significant bit first, and matches may wrap the window.
"""

FRAME_SIZE = 32768
MIN_MATCH = 2
NUM_CHARS = 256
NUM_PRIMARY_LENGTHS = 7
NUM_SECONDARY_LENGTHS = 249
LENTABLE_SAFETY = 64
HUFF_MAXBITS = 16
PRETREE_MAXSYMBOLS = 20
PRETREE_TABLEBITS = 6
MAINTREE_TABLEBITS = 12
LENGTH_TABLEBITS = 12
ALIGNED_TABLEBITS = 7

BLOCKTYPE_INVALID = 0
BLOCKTYPE_VERBATIM = 1
BLOCKTYPE_ALIGNED = 2
BLOCKTYPE_UNCOMPRESSED = 3

POSITION_SLOTS = (30, 32, 34, 36, 38, 42, 50, 66, 98, 162, 290)
EXTRA_BITS = (0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8,
              9, 9, 10, 10, 11, 11, 12, 12, 13, 13, 14, 14, 15, 15, 16, 16)


def _build_position_base():
    table = [0] * 290
    for i in range(1, 290):
        prev = i - 1
        if prev < 4:
            extra = 0
        elif prev < 36:
            extra = prev // 2 - 1
        else:
            extra = 17
        table[i] = table[prev] + (1 << extra)
    return tuple(table)


POSITION_BASE = _build_position_base()


class LzxError(Exception):
    pass


class Bits:
    """MSB-first reader over 16-bit little-endian words, as LZX defines it."""

    def __init__(self, data):
        self.input = data
        self.pos = 0
        self.bit_buffer = 0
        self.bits_left = 0

    def next_byte(self):
        if self.pos < len(self.input):
            b = self.input[self.pos]
            self.pos += 1
            return b
        # The reference implementation fakes two zero bytes at the end.
        if self.pos - len(self.input) >= 2:
            raise LzxError("out of input bytes")
        self.pos += 1
        return 0

    def read_bytes(self):
        b0 = self.next_byte()
        b1 = self.next_byte()
        data = (b1 << 8) | b0
        self.bit_buffer = (self.bit_buffer | (data << (32 - 16 - self.bits_left))) & 0xFFFFFFFF
        self.bits_left += 16

    def ensure(self, nbits):
        while self.bits_left < nbits:
            self.read_bytes()

    def peek(self, nbits):
        if nbits == 0:
            return 0
        return self.bit_buffer >> (32 - nbits)

    def remove(self, nbits):
        self.bit_buffer = 0 if nbits >= 32 else (self.bit_buffer << nbits) & 0xFFFFFFFF
        self.bits_left -= nbits

    def read(self, nbits):
        self.ensure(nbits)
        v = self.peek(nbits)
        self.remove(nbits)
        return v

    def read_huffsym(self, h):
        self.ensure(HUFF_MAXBITS)
        sym = h.table[self.peek(h.nbits)]
        if sym >= h.nsyms:
            idx = 1 << (32 - h.nbits)
            while True:
                idx >>= 1
                if idx == 0:
                    raise LzxError("huffman traverse overrun")
                bit = 1 if (self.bit_buffer & idx) else 0
                i = (sym << 1) | bit
                if i >= len(h.table):
                    raise LzxError("huffman traverse overrun")
                sym = h.table[i]
                if sym < h.nsyms:
                    break
        self.remove(h.len[sym])
        return sym

    def raw_byte(self):
        return self.next_byte()


class Huffman:
    def __init__(self, nsyms, nbits):
        self.len = [0] * (nsyms + LENTABLE_SAFETY)
        self.table = [0] * ((1 << nbits) + nsyms * 2)
        self.nsyms = nsyms
        self.nbits = nbits
        self.empty = False

    def build(self):
        """make_decode_table, MSB bit order. False when the lengths are not a full tree."""
        nsyms = self.nsyms
        nbits = self.nbits
        length = self.len
        table = self.table
        pos = 0
        table_mask = 1 << nbits
        bit_mask = table_mask >> 1

        for bit_num in range(1, nbits + 1):
            for sym in range(nsyms):
                if length[sym] != bit_num:
                    continue
                leaf = pos
                pos += bit_mask
                if pos > table_mask:
                    return False
                for _ in range(bit_mask):
                    table[leaf] = sym
                    leaf += 1
            bit_mask >>= 1

        if pos == table_mask:
            return True

        for sym in range(pos, table_mask):
            table[sym] = 0xFFFF

        next_symbol = nsyms if (table_mask >> 1) < nsyms else (table_mask >> 1)

        pos <<= 16
        table_mask <<= 16
        bit_mask = 1 << 15

        for bit_num in range(nbits + 1, HUFF_MAXBITS + 1):
            for sym in range(nsyms):
                if length[sym] != bit_num:
                    continue
                if pos >= table_mask:
                    return False
                leaf = pos >> 16
                for fill in range(bit_num - nbits):
                    if leaf >= len(table):
                        return False
                    entry = table[leaf]
                    if entry == 0xFFFF:
                        a = next_symbol << 1
                        if a + 1 >= len(table):
                            return False
                        table[a] = 0xFFFF
                        table[a + 1] = 0xFFFF
                        table[leaf] = next_symbol
                        next_symbol += 1
                    leaf = table[leaf] << 1
                    if (pos >> (15 - fill)) & 1:
                        leaf += 1
                if leaf >= len(table):
                    return False
                table[leaf] = sym
                pos += bit_mask
            bit_mask >>= 1

        return pos == table_mask

    def build_maybe_empty(self):
        self.empty = False
        if not self.build():
            if any(l > 0 for l in self.len[: self.nsyms]):
                raise LzxError("bad huffman table")
            self.empty = True


class Decoder:
    def __init__(self, data, window_bits, output_length):
        if not 15 <= window_bits <= 21:
            raise LzxError("unsupported window size")
        self.bits = Bits(data)
        self.window_size = 1 << window_bits
        self.window = bytearray(self.window_size)
        self.window_posn = 0
        self.frame_posn = 0
        self.frame = 0
        self.offset = 0
        self.length = output_length
        self.r0 = self.r1 = self.r2 = 1
        self.header_read = False
        self.block_remaining = 0
        self.block_length = 0
        self.block_type = BLOCKTYPE_INVALID
        self.intel_filesize = 0
        self.intel_started = False
        self.num_offsets = POSITION_SLOTS[window_bits - 15] << 3
        self.pretree = Huffman(PRETREE_MAXSYMBOLS, PRETREE_TABLEBITS)
        self.maintree = Huffman(NUM_CHARS + 290 * 8, MAINTREE_TABLEBITS)
        self.length_tree = Huffman(NUM_SECONDARY_LENGTHS + 1, LENGTH_TABLEBITS)
        self.aligned = Huffman(8, ALIGNED_TABLEBITS)

    def _set_len(self, lens, x, v):
        if x >= len(lens):
            raise LzxError("code length run overflows table")
        lens[x] = v
        return x + 1

    @staticmethod
    def _delta_len(lens, x, z):
        if x >= len(lens):
            raise LzxError("code length run overflows table")
        v = lens[x] - z
        if v < 0:
            v += 17
        return v

    def read_lens(self, which, first, last):
        for x in range(20):
            self.pretree.len[x] = self.bits.read(4)
        if not self.pretree.build():
            raise LzxError("bad pretree")
        lens = self.maintree.len if which == "main" else self.length_tree.len
        x = first
        while x < last:
            z = self.bits.read_huffsym(self.pretree)
            if z == 17:
                y = self.bits.read(4) + 4
                for _ in range(y):
                    x = self._set_len(lens, x, 0)
            elif z == 18:
                y = self.bits.read(5) + 20
                for _ in range(y):
                    x = self._set_len(lens, x, 0)
            elif z == 19:
                y = self.bits.read(1) + 4
                z2 = self.bits.read_huffsym(self.pretree)
                v = self._delta_len(lens, x, z2)
                for _ in range(y):
                    x = self._set_len(lens, x, v)
            else:
                v = self._delta_len(lens, x, z)
                x = self._set_len(lens, x, v)

    def decode_frame(self, payload, output_size):
        """One XCompress frame: its own bitstream, this decoder's state carried over.

        XNB bodies are stored as 32 KiB output frames that each restart the
        bitstream at a byte boundary, while the window, the repeated offsets and
        the Huffman tables continue - MonoGame's LzxDecoderStream seeks back to
        the frame start for exactly this reason."""
        self.bits = Bits(payload)
        self.length = self.offset + output_size
        return self.decompress(bytes(output_size))

    def decompress(self, out):
        out = bytearray(out)
        out_bytes = len(out)
        if out_bytes == 0:
            return bytes(out)

        window_size = self.window_size
        window = self.window
        end_frame = (self.offset + out_bytes) // FRAME_SIZE + 1
        out_pos = 0
        e8_buf = bytearray(FRAME_SIZE)

        while self.frame < end_frame:
            if not self.header_read:
                i = self.bits.read(1)
                j = 0
                if i != 0:
                    i = self.bits.read(16)
                    j = self.bits.read(16)
                self.intel_filesize = (i << 16) | j
                self.header_read = True

            frame_size = FRAME_SIZE
            if self.length != 0 and self.length - self.offset < frame_size:
                frame_size = self.length - self.offset

            bytes_todo = self.frame_posn + frame_size - self.window_posn
            while bytes_todo > 0:
                if self.block_remaining == 0:
                    if self.block_type == BLOCKTYPE_UNCOMPRESSED and (self.block_length & 1):
                        self.bits.raw_byte()
                    self.block_type = self.bits.read(3)
                    i = self.bits.read(16)
                    j = self.bits.read(8)
                    self.block_length = (i << 8) | j
                    self.block_remaining = self.block_length

                    if self.block_type in (BLOCKTYPE_ALIGNED, BLOCKTYPE_VERBATIM):
                        if self.block_type == BLOCKTYPE_ALIGNED:
                            for k in range(8):
                                self.aligned.len[k] = self.bits.read(3)
                            if not self.aligned.build():
                                raise LzxError("bad aligned table")
                        self.read_lens("main", 0, 256)
                        self.read_lens("main", 256, NUM_CHARS + self.num_offsets)
                        if not self.maintree.build():
                            raise LzxError("bad main table")
                        if self.maintree.len[0xE8] != 0:
                            self.intel_started = True
                        self.read_lens("length", 0, NUM_SECONDARY_LENGTHS)
                        self.length_tree.build_maybe_empty()
                    elif self.block_type == BLOCKTYPE_UNCOMPRESSED:
                        self.intel_started = True
                        if self.bits.bits_left == 0:
                            self.bits.ensure(16)
                        self.bits.bits_left = 0
                        self.bits.bit_buffer = 0
                        buf = bytes(self.bits.raw_byte() for _ in range(12))
                        self.r0 = int.from_bytes(buf[0:4], "little")
                        self.r1 = int.from_bytes(buf[4:8], "little")
                        self.r2 = int.from_bytes(buf[8:12], "little")
                    else:
                        raise LzxError("bad block type")

                this_run = self.block_remaining
                if this_run > bytes_todo:
                    this_run = bytes_todo
                bytes_todo -= this_run
                self.block_remaining -= this_run

                if self.block_type in (BLOCKTYPE_ALIGNED, BLOCKTYPE_VERBATIM):
                    remaining = this_run
                    while remaining > 0:
                        main_element = self.bits.read_huffsym(self.maintree)
                        if main_element < NUM_CHARS:
                            window[self.window_posn] = main_element
                            self.window_posn += 1
                            remaining -= 1
                            continue
                        main_element -= NUM_CHARS
                        match_length = main_element & NUM_PRIMARY_LENGTHS
                        if match_length == NUM_PRIMARY_LENGTHS:
                            if self.length_tree.empty:
                                raise LzxError("length symbol needed but tree is empty")
                            match_length += self.bits.read_huffsym(self.length_tree)
                        match_length += MIN_MATCH

                        slot = main_element >> 3
                        if slot == 0:
                            match_offset = self.r0
                        elif slot == 1:
                            self.r1, self.r0 = self.r0, self.r1
                            match_offset = self.r0
                        elif slot == 2:
                            self.r2, self.r0 = self.r0, self.r2
                            match_offset = self.r0
                        else:
                            extra = 17 if slot >= 36 else EXTRA_BITS[slot]
                            m = (POSITION_BASE[slot] - 2) & 0xFFFFFFFF
                            if extra >= 3 and self.block_type == BLOCKTYPE_ALIGNED:
                                if extra > 3:
                                    m = (m + (self.bits.read(extra - 3) << 3)) & 0xFFFFFFFF
                                m = (m + self.bits.read_huffsym(self.aligned)) & 0xFFFFFFFF
                            elif extra != 0:
                                m = (m + self.bits.read(extra)) & 0xFFFFFFFF
                            self.r2 = self.r1
                            self.r1 = self.r0
                            self.r0 = m
                            match_offset = m

                        if self.window_posn + match_length > window_size:
                            raise LzxError("match ran over window wrap")

                        dest = self.window_posn
                        i = match_length
                        if match_offset > self.window_posn:
                            if match_offset > self.offset:
                                raise LzxError("match offset beyond stream")
                            j = match_offset - self.window_posn
                            if j > window_size:
                                raise LzxError("match offset beyond window")
                            src = window_size - j
                            if j < i:
                                i -= j
                                while j > 0:
                                    window[dest] = window[src]
                                    dest += 1
                                    src += 1
                                    j -= 1
                                src = 0
                            while i > 0:
                                window[dest] = window[src]
                                dest += 1
                                src += 1
                                i -= 1
                        else:
                            src = dest - match_offset
                            while i > 0:
                                window[dest] = window[src]
                                dest += 1
                                src += 1
                                i -= 1

                        remaining -= match_length
                        self.window_posn += match_length

                    this_run = remaining
                elif self.block_type == BLOCKTYPE_UNCOMPRESSED:
                    start = self.window_posn
                    self.window_posn += this_run
                    for k in range(this_run):
                        window[start + k] = self.bits.raw_byte()
                    this_run = 0
                else:
                    raise LzxError("bad block type")

                if this_run < 0:
                    over = -this_run
                    if over > self.block_remaining:
                        raise LzxError("match overran block")
                    self.block_remaining -= over

            if self.window_posn - self.frame_posn != frame_size:
                raise LzxError("decode beyond output frame limits")

            if self.bits.bits_left > 0:
                self.bits.ensure(16)
            if self.bits.bits_left & 15:
                self.bits.remove(self.bits.bits_left & 15)

            fp = self.frame_posn
            fs = frame_size
            if self.intel_started and self.intel_filesize != 0 and self.frame < 32768 and fs > 10:
                e8_buf[:fs] = window[fp:fp + fs]
                dataend = fs - 10
                d = 0
                curpos = self.offset
                filesize = self.intel_filesize
                while d < dataend:
                    b = e8_buf[d]
                    d += 1
                    if b != 0xE8:
                        curpos += 1
                        continue
                    abs_off = int.from_bytes(bytes(e8_buf[d:d + 4]), "little", signed=True)
                    if -curpos <= abs_off < filesize:
                        rel = abs_off - curpos if abs_off >= 0 else abs_off + filesize
                        e8_buf[d:d + 4] = rel.to_bytes(4, "little", signed=True)
                    d += 4
                    curpos += 5
                frame_data = e8_buf[:fs]
            else:
                frame_data = window[fp:fp + fs]

            n = min(out_bytes, fs)
            out[out_pos:out_pos + n] = frame_data[:n]
            out_pos += n
            self.offset += n
            out_bytes -= n

            self.frame_posn += frame_size
            self.frame += 1
            if self.window_posn == window_size:
                self.window_posn = 0
            if self.frame_posn == window_size:
                self.frame_posn = 0

        if out_bytes != 0:
            raise LzxError("bytes left to output")
        return bytes(out)


def decompress_frames(frames, window_size=0x10000):
    """Decode XCompress frames: (payload, output size) pairs, in order."""
    if not frames:
        raise LzxError("no frames")
    total = sum(size for _, size in frames)
    decoder = Decoder(b"", window_size.bit_length() - 1, total)
    out = bytearray()
    for payload, size in frames:
        out += decoder.decode_frame(payload, size)
    return bytes(out)


def decompress(data, output_length, window_size=0x8000):
    if window_size & (window_size - 1):
        raise LzxError("window size is not a power of two")
    return Decoder(data, window_size.bit_length() - 1, output_length).decompress(
        bytes(output_length)
    )
