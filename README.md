% The FUSE Wire Protocol

This document tries to summarize and structure what I have
learned about the
FUSE (Filesystem in Userspace) protocol and Linux kernel internals during the development
of [gocryptfs](https://nuetzlich.net/gocryptfs/).

The Markdown source code of this document is available at
<https://github.com/rfjakob/the-fuse-wire-protocol> - pull requests welcome!

The rendered HTML should always be available at <https://nuetzlich.net/the-fuse-wire-protocol/>.

Linux Filesystem Stack
----------------------

To understand how FUSE works it is important to know how the Linux
filesystem stack looks like. FUSE is designed to fit seamlessly into
the existing model.

Let's take `unlink("/tmp/foo")` on an ext4 filesystem as an example.
Like many other system calls, `unlink()` operates on a file path, while
Linux interally operates on `dentry` ("directory entry") structs
([definiton](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/include/linux/dcache.h?h=v4.13-rc7#n89)).

Each `dentry` has a pointer to an `inode` struct
([definiton](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/include/linux/fs.h?h=v4.13-rc7#n566))
that is filled by the filesystem (in our example, ext4).  
Each `inode` struct in turn contains a list of function pointers in an `inode_operations` struct
([definition](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/include/linux/fs.h?h=v4.13-rc7#n1704)).

The overall structure looks like this:

* `dentry`
    * `inode`
        * `inode_operations`
            * `lookup()`
            * `unlink()`
            * ...

The Linux VFS layer splits the path into segments. In our case, `/`, `tmp`, `foo`.  
The `/` (root directory) `dentry` is created
at mount-time and serves as the starting point for the recursive walk:

1. The VFS calls `lookup("tmp")` on the `dentry` corresponding to `/` and receives the `dentry` for `tmp`
2. The VFS calls `lookup("foo")` on the `dentry` corresponding to `tmp` and receives the `dentry` for `foo`
3. The VFS calls `unlink()` on the `dentry` corresponding to `foo`

The `lookup()` and `unlink()` functions are, in our example, implemented by the ext4 filesystem.

For a FUSE filesystem, the functions in `inode_operations` are implemented in the
userspace filesystem. The FUSE module in the Linux kernel provides stub implementations
([definition](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/fs/fuse/dir.c?h=v4.13-rc7#n1792))
that forward the requests to the userspace filesystem and convert between kernel API and FUSE wire protocol.

Directory Entry Cache - `dcache`
--------------------------------

Translating paths to `dentry` structs is a performance-critical operation. To avoid calling the
filesystem's `lookup()` function for each segment, the Linux kernel implements a directory entry
cache called `dcache`.

For local filesystems like ext4, the cached entries never expire. For FUSE filesystems, the default
timeout is 1 second, but it can be set to an arbitrary value using the `entry_timeout` mount option
in libfuse (see `man 8 fuse`) or the `EntryTimeout`
[field](https://godoc.org/github.com/hanwen/go-fuse/fuse/nodefs#Options) in go-fuse.

Request Forwarding
------------------

The Linux kernel and the userspace filesystem communicate by sending messages through the
`/dev/fuse` device. On the kernel side, message parsing and generation is handled by the FUSE
module. On the userspace side this is usually handled by a FUSE library.
[libfuse](https://github.com/libfuse/libfuse) is the reference implementation and is developed
in lockstep with the kernel. Alternative FUSE libraries like
[go-fuse](https://github.com/hanwen/go-fuse)
follow the developments in libfuse.

Message Format
--------------

Both sides have the message format defined correspondingly in C header files.
As there is no other formal specification, these header files define the building
blocks of the FUSE wire protocol:

* Userspace:
  [libfuse/include/fuse_kernel.h](https://github.com/libfuse/libfuse/blob/21b55a05a158b1c225ba312529bc068cadd5431d/include/fuse_kernel.h)
* Kernel:
  [linux/include/uapi/linux/fuse.h](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/include/uapi/linux/fuse.h?h=v4.12)

Every message from the kernel to userspace starts with the `fuse_in_header` struct
([definition](https://github.com/libfuse/libfuse/blob/21b55a05a158b1c225ba312529bc068cadd5431d/include/fuse_kernel.h#L690)),
the most interesting fields are:

* `opcode` ... the operation the kernel wants to perform (a uint32 from
  [enum fuse_opcode](https://github.com/libfuse/libfuse/blob/e16fdc06d7473f00499b6b03fb7bd06259a22135/include/fuse_kernel.h#L333))
* `nodeid` ... the file or directory to operate on (arbitrary uint64 identifier)

The opcode defines the data that follows the header. An opcode-specific struct and up to
two filenames may follow. A `RENAME` message uses all of those fields and looks like this:

* `fuse_in_header` struct
* `fuse_rename_in` struct
* filename
* filename

Whereas an `UNLINK` message looks like this:

* `fuse_in_header` struct
* filename

The [go-fuse](https://github.com/hanwen/go-fuse) library has two nice tables
listing what data follows the header for each opcode. Due to Go naming conventions,
the struct names are slightly
different than the C names, but the correlation should be clear enough.

* [opcode-specific structs](https://github.com/hanwen/go-fuse/blob/204b45dba899dfa147235c255908236d5fde2d32/fuse/opcode.go#L609)
* [number of appended filenames](https://github.com/hanwen/go-fuse/blob/204b45dba899dfa147235c255908236d5fde2d32/fuse/opcode.go#L637)

The `LOOKUP` Opcode
-------------------

The `nodeid` field in `fuse_in_header` identifies which file or directory the operation
should be performed on. The kernel has to obtain the `nodeid` from the
userspace filesystem before it can perform any other operation.

The process is the same for in-kernel filesystems: See the section "The Inode Object"
in <https://www.kernel.org/doc/Documentation/filesystems/vfs.txt>.

The `LOOKUP` opcode allows the kernel to get a `nodeid` for a filename in a directory.
A `LOOKUP` message looks like this:

* `fuse_in_header` struct
* filename

The userspace filesystem replies with the `nodeid` corresponding to
the filename in the directory identified by the `nodeid` in the header.
The root directory has a fixed `nodeid` of 1.

The `nodeid` is an arbitrary value that is chosen by the userspace
filesystem. The userspace filesystem must remember which file or
directory the `nodeid` corresponds to.

See Also
--------
* Writing a FUSE Filesystem: a Tutorial  
  Joseph J. Pfeiffer Jr.  
  <https://www.cs.nmsu.edu/~pfeiffer/fuse-tutorial/>

* Overview of the Linux Virtual File System  
  Richard Gooch, Pekka Enberg  
  <https://www.kernel.org/doc/Documentation/filesystems/vfs.txt>