#!/usr/bin/env python3
"""Pack a directory tree into a deterministic gzip-compressed newc cpio.

The QEMU smoke guest uses this instead of requiring the host to have cpio or
an aarch64 userland. The archive is content-deterministic for a fixed input
tree: entries are sorted, ownership is root, every mtime is a fixed value, and
gzip stores no filename or timestamp. That lets CI compare the initramfs
checksum across builds and checkouts.

Usage: smoke-cpio.py --root DIR --output FILE
"""

import argparse
import gzip
import os
import stat
import sys

MAGIC = b"070701"
HEADER_SIZE = 110  # magic plus 13 eight-character fields
MAX_U32 = 0xFFFFFFFF


def field(value):
    value &= MAX_U32
    return b"%08x" % value


def header(mode, name, data_size, ino, nlink, mtime, rdevmajor, rdevminor):
    name_bytes = name.encode("utf-8") + b"\0"
    parts = [
        MAGIC,
        field(ino),  # inode
        field(mode),  # mode and type bits
        field(0),  # uid: root inside the guest
        field(0),  # gid: root inside the guest
        field(nlink),
        field(mtime),
        field(data_size),
        field(0),  # devmajor
        field(0),  # devminor
        field(rdevmajor),
        field(rdevminor),
        field(len(name_bytes)),
        field(0),  # check: ignored by Linux for newc
    ]
    result = b"".join(parts)
    if len(result) != HEADER_SIZE:
        raise AssertionError("bad newc header size: %d" % len(result))
    return result


def pad4(data):
    remainder = len(data) % 4
    return data if remainder == 0 else data + b"\0" * (4 - remainder)


def write_entry(out, name, mode, data, ino, nlink, mtime, devmajor=0, devminor=0):
    name_bytes = name.encode("utf-8") + b"\0"
    out.write(header(mode, name, len(data), ino, nlink, mtime, devmajor, devminor))
    # The 110-byte header is not itself 4-byte aligned, so pad the combined
    # header+name length, not the name in isolation.
    combined = HEADER_SIZE + len(name_bytes)
    out.write(name_bytes)
    out.write(b"\0" * ((4 - combined % 4) % 4))
    out.write(pad4(data))


def walk(root):
    """Yield paths relative to root, parents before children, sorted."""
    pending = [""]
    while pending:
        relative = pending.pop(0)
        path = os.path.join(root, relative) if relative else root
        try:
            with os.scandir(path) as scan:
                entries = sorted(scan, key=lambda entry: entry.name)
        except OSError as error:
            raise RuntimeError("cannot read %s: %s" % (path, error)) from error
        for entry in entries:
            child = os.path.join(relative, entry.name) if relative else entry.name
            yield child
            if entry.is_dir(follow_symlinks=False):
                pending.append(child)


def pack(root, out, mtime):
    ino = 1
    count = 0
    for relative in walk(root):
        path = os.path.join(root, relative)
        info = os.lstat(path)
        mode = info.st_mode
        permissions = stat.S_IMODE(mode)
        name = relative.replace(os.sep, "/")

        if stat.S_ISDIR(mode):
            write_entry(out, name, stat.S_IFDIR | permissions, b"", ino, 2, mtime)
        elif stat.S_ISREG(mode):
            with open(path, "rb") as source:
                data = source.read()
            write_entry(out, name, stat.S_IFREG | permissions, data, ino, 1, mtime)
        elif stat.S_ISLNK(mode):
            target = os.readlink(path).encode("utf-8")
            write_entry(out, name, stat.S_IFLNK | permissions, target, ino, 1, mtime)
        elif stat.S_ISCHR(mode) or stat.S_ISBLK(mode):
            kind = stat.S_IFCHR if stat.S_ISCHR(mode) else stat.S_IFBLK
            major = os.major(info.st_rdev)
            minor = os.minor(info.st_rdev)
            write_entry(out, name, kind | permissions, b"", ino, 1, mtime, major, minor)
        elif stat.S_ISFIFO(mode):
            write_entry(out, name, stat.S_IFIFO | permissions, b"", ino, 1, mtime)
        else:
            raise RuntimeError("unsupported file type: %s" % path)
        ino += 1
        count += 1

    name = "TRAILER!!!"
    write_entry(out, name, 0, b"", 0, 1, 0)
    return count


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, help="directory to pack")
    parser.add_argument("--output", required=True, help="gzip cpio destination")
    parser.add_argument(
        "--mtime",
        type=int,
        default=0,
        help="fixed mtime for every entry (default: 0, for reproducibility)",
    )
    args = parser.parse_args(argv)
    if args.mtime < 0 or args.mtime > 0xFFFFFFFF:
        parser.error("--mtime must fit in an unsigned 32-bit integer")

    if not os.path.isdir(args.root):
        parser.error("--root is not a directory: %s" % args.root)

    output_parent = os.path.dirname(os.path.abspath(args.output))
    os.makedirs(output_parent, exist_ok=True)

    with open(args.output, "wb") as raw:
        with gzip.GzipFile(
            filename="", mode="wb", compresslevel=9, fileobj=raw, mtime=0
        ) as archive:
            count = pack(os.path.abspath(args.root), archive, args.mtime)

    print("packed %d entries into %s" % (count, args.output), file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
