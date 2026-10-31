#!/usr/bin/env python3
"""
Reference implementation of the Korg M1 SysEx program codec, in Python.

Used to (a) sanity-check the maths against byte counts reported in the wild
(170-byte program dump, 16,350-byte all-program dump) and (b) generate
test vectors for the Swift M1Core unit tests.

Wire format (M1 owner's manual, MIDI data format section):
  F0 42 3g 19 ff dd .. dd F7
    42 = Korg, 3g = global channel g (0-15), 19 = M1 family, ff = function

Korg 7-in-8 packing: each group of up to 7 data bytes is sent as 8 MIDI bytes.
The first byte carries bit 7 of each of the following 7 bytes (bit 0 -> first
data byte), and the following bytes are the data bytes with bit 7 cleared.
"""
import json
import os
import random
import sys

KORG = 0x42
M1_FAMILY = 0x19
PROGRAM_SIZE = 143
PROGRAM_COUNT = 100

FN = {
    "mode_request": 0x12,
    "program_dump_request": 0x10,
    "all_program_dump_request": 0x1C,
    "combination_dump_request": 0x19,
    "all_combination_dump_request": 0x1D,
    "global_dump_request": 0x0E,
    "all_data_dump_request": 0x0F,
    "program_write_request": 0x11,
    "combination_write_request": 0x1A,
    "program_dump": 0x40,
    "all_program_dump": 0x4C,
    "combination_dump": 0x49,
    "all_combination_dump": 0x4D,
    "global_dump": 0x51,
    "all_data_dump": 0x50,
    "parameter_change": 0x41,
    "mode_change": 0x4E,
    "mode_data": 0x42,
    "write_completed": 0x21,
    "write_error": 0x22,
    "load_completed": 0x23,
    "load_error": 0x24,
    "format_error": 0x26,
}


def pack(data: bytes) -> bytes:
    out = bytearray()
    for i in range(0, len(data), 7):
        chunk = data[i : i + 7]
        msb = 0
        for j, b in enumerate(chunk):
            if b & 0x80:
                msb |= 1 << j
        out.append(msb)
        out.extend(b & 0x7F for b in chunk)
    return bytes(out)


def unpack(data: bytes) -> bytes:
    out = bytearray()
    for i in range(0, len(data), 8):
        chunk = data[i : i + 8]
        msb = chunk[0]
        for j, b in enumerate(chunk[1:]):
            out.append(b | (0x80 if msb & (1 << j) else 0))
    return bytes(out)


def header(channel: int, fn: int) -> bytes:
    assert 0 <= channel <= 15
    return bytes([0xF0, KORG, 0x30 | channel, M1_FAMILY, fn])


def program_dump(program: bytes, channel: int = 0) -> bytes:
    assert len(program) == PROGRAM_SIZE
    return header(channel, FN["program_dump"]) + pack(program) + b"\xF7"


def all_program_dump(programs: list, channel: int = 0) -> bytes:
    assert len(programs) == PROGRAM_COUNT
    return header(channel, FN["all_program_dump"]) + b"\x00" + pack(b"".join(programs)) + b"\xF7"


def program_dump_request(channel: int = 0) -> bytes:
    return header(channel, FN["program_dump_request"]) + b"\xF7"


def program_write_request(slot: int, channel: int = 0) -> bytes:
    assert 0 <= slot <= 99
    return header(channel, FN["program_write_request"]) + bytes([0x00, slot]) + b"\xF7"


def parameter_change(page: int, pos: int, value: int, channel: int = 0) -> bytes:
    """41 pg po vl vm — vl = bits 6-0, vm = bits 15-7 of a 16-bit (two's complement) value."""
    v = value & 0xFFFF
    return header(channel, FN["parameter_change"]) + bytes([page, pos, v & 0x7F, (v >> 7) & 0x7F]) + b"\xF7"


def parse(msg: bytes):
    if len(msg) < 6 or msg[0] != 0xF0 or msg[-1] != 0xF7:
        raise ValueError("not a complete sysex message")
    if msg[1] != KORG or (msg[2] & 0xF0) != 0x30 or msg[3] != M1_FAMILY:
        raise ValueError("not a Korg M1 message")
    channel = msg[2] & 0x0F
    fn = msg[4]
    body = msg[5:-1]
    if fn == FN["program_dump"]:
        prog = unpack(body)
        if len(prog) != PROGRAM_SIZE:
            raise ValueError(f"program dump unpacked to {len(prog)} bytes, expected {PROGRAM_SIZE}")
        return ("program_dump", channel, prog)
    if fn == FN["all_program_dump"]:
        data = unpack(body[1:])  # skip the 0* flag byte
        if len(data) != PROGRAM_SIZE * PROGRAM_COUNT:
            raise ValueError(f"all-program dump unpacked to {len(data)} bytes")
        return ("all_program_dump", channel, [data[i : i + PROGRAM_SIZE] for i in range(0, len(data), PROGRAM_SIZE)])
    return (fn, channel, body)


def default_program() -> bytes:
    """A plausible 'init' program: name INIT, single OSC, A.Piano, open filter."""
    p = bytearray(PROGRAM_SIZE)
    p[0:10] = b"INIT      "
    p[10] = 0            # single
    p[11] = 0            # poly, hold off
    p[12] = 0            # A.Piano
    p[13] = 0            # 8'
    p[19] = 0x60         # pitch MG: tri, osc1+osc2 enabled
    p[23] = 0x60
    p[32] = 2            # joystick bend +-2
    p[38] = 0            # Hall
    p[39] = 0x21         # Tru
    p[40] = p[41] = 50   # effect balances
    p[42] = p[43] = 50
    p[46] = 0x0F         # all effect channels on, parallel
    for base in (0, 40):
        v = 63 + base
        p[v + 0] = 0             # pitch EG start level
        p[v + 8] = 99            # VDF cutoff
        p[v + 9] = 60            # VDF kbd track center C4
        p[v + 23] = 99           # VDA osc level (86/126)
        p[v + 24] = 60           # VDA kbd track center
        p[v + 30] = 99           # VDA EG attack level (93/133)
        p[v + 34] = 99           # VDA EG sustain level (97/137)
    return bytes(p)


def random_program(rng: random.Random) -> bytes:
    p = bytearray(default_program())
    for i in range(10, PROGRAM_SIZE):
        p[i] = rng.randrange(256)  # exercise full 8-bit range for packing tests
    return bytes(p)


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "vectors"
    os.makedirs(out_dir, exist_ok=True)
    rng = random.Random(1989)

    # --- Sanity checks against published byte counts
    init = default_program()
    dump = program_dump(init)
    assert len(dump) == 170, len(dump)
    assert parse(dump)[2] == init
    all_dump = all_program_dump([init] * PROGRAM_COUNT)
    assert len(all_dump) == 16350, len(all_dump)
    assert parse(all_dump)[2][99] == init
    for _ in range(200):
        r = random_program(rng)
        assert unpack(pack(r)) == r
        assert parse(program_dump(r, channel=7))[2] == r
    print("sanity ok: program dump = 170 bytes, all-program dump = 16350 bytes, 200 random round-trips")

    # --- Test vectors for Swift
    vectors = {
        "packing": [],
        "programDumps": [],
        "requests": {
            "programDumpRequest_ch1": program_dump_request(0).hex(),
            "programWriteRequest_slot12_ch1": program_write_request(12, 0).hex(),
            "parameterChange_pg2_pos5_val_minus12_ch1": parameter_change(2, 5, -12, 0).hex(),
            "parameterChange_pg0_pos71_val99_ch16": parameter_change(0, 71, 99, 15).hex(),
        },
    }
    for n in (0, 1, 6, 7, 8, 14, 15, 143):
        raw = bytes(rng.randrange(256) for _ in range(n))
        vectors["packing"].append({"raw": raw.hex(), "packed": pack(raw).hex()})
    for i in range(4):
        prog = random_program(rng) if i else init
        vectors["programDumps"].append({"channel": i, "program": prog.hex(), "sysex": program_dump(prog, i).hex()})

    with open(os.path.join(out_dir, "m1-vectors.json"), "w") as f:
        json.dump(vectors, f, indent=1)
    with open(os.path.join(out_dir, "init-program.syx"), "wb") as f:
        f.write(dump)
    print("wrote", os.path.join(out_dir, "m1-vectors.json"))


if __name__ == "__main__":
    main()
