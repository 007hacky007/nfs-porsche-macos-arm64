"""com.apple.quarantine on what comes from the player's game copy.

A downloaded copy's quarantine stays on every file taken from it, so macOS still checks anything
hidden in it: copies keep it (clone_tree), and files extracted from a disc image get the image's
value (Disc.extract). Python has no xattr calls on macOS, so this uses libc directly.
"""
import ctypes
import errno
import os
from pathlib import Path

NAME = b'com.apple.quarantine'
XATTR_NOFOLLOW = 0x0001
ENOATTR = 93  # macOS <sys/errno.h>

_libc = ctypes.CDLL(None, use_errno=True)
_libc.getxattr.argtypes = (ctypes.c_char_p, ctypes.c_char_p, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_uint32,
                           ctypes.c_int)
_libc.getxattr.restype = ctypes.c_ssize_t
_libc.setxattr.argtypes = (ctypes.c_char_p, ctypes.c_char_p, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_uint32,
                           ctypes.c_int)
_libc.setxattr.restype = ctypes.c_int


def _error(path):
    code = ctypes.get_errno()
    return OSError(code, os.strerror(code), str(path))


def quarantine_of(path):
    """The quarantine value of `path` itself (links not followed), or None."""
    name = os.fsencode(path)
    size = _libc.getxattr(name, NAME, None, 0, 0, XATTR_NOFOLLOW)
    if size < 0:
        if ctypes.get_errno() in (ENOATTR, errno.ENOTSUP):
            return None
        raise _error(path)
    buffer = ctypes.create_string_buffer(size)
    size = _libc.getxattr(name, NAME, buffer, size, 0, XATTR_NOFOLLOW)
    if size < 0:
        raise _error(path)
    return buffer.raw[:size]


def set_quarantine(path, value):
    if _libc.setxattr(os.fsencode(path), NAME, value, len(value), 0, XATTR_NOFOLLOW):
        raise _error(path)


def quarantine_tree(root, value):
    """Puts `value` on `root` and everything below it (nothing when `value` is None)."""
    if value is None:
        return
    root = Path(root)
    set_quarantine(root, value)
    if root.is_dir() and not root.is_symlink():
        for folder, directories, names in os.walk(root):
            for name in directories + names:
                if not os.path.islink(os.path.join(folder, name)):
                    set_quarantine(os.path.join(folder, name), value)


def require_quarantine_kept(source, copy):
    """Fails when an item of `source` has quarantine and its copy in `copy` has none."""
    source, copy = Path(source), Path(copy)
    items = [Path()]
    if source.is_dir() and not source.is_symlink():
        for folder, directories, names in os.walk(source):
            items += [Path(folder, name).relative_to(source) for name in directories + names]
    for item in items:
        if quarantine_of(source / item) is not None and (
                not os.path.lexists(copy / item) or quarantine_of(copy / item) is None):
            raise OSError(f'the copy of {source / item} lost its quarantine')
