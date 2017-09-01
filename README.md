% The FUSE Wire Protocol

The Linux kernel and the userspace filesystem communicate by sending messages through the
/dev/fuse device. While the kernel has its own message parser, on the userspace side
this is usually handled by a FUSE library.
[libfuse](https://github.com/libfuse/libfuse) is the reference implementation and is developed
in lockstep with the kernel.

Message Format
--------------

Both sides have the message format defined correspondingly in C header files.
As there is no other formal specification, these header files define the building
blocks of the FUSE wire protocol:

* Userspace: [libfuse/include/fuse_kernel.h](https://github.com/libfuse/libfuse/blob/21b55a05a158b1c225ba312529bc068cadd5431d/include/fuse_kernel.h)
* Kernel: [linux/include/uapi/linux/fuse.h](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/include/uapi/linux/fuse.h?h=v4.12)

Every message from the kernel to userspace starts with the `fuse_in_header` struct,
the most interesting fields are:

* `opcode` ... the operation the kernel wants to perform (a uint32 from
  [enum fuse_opcode](https://github.com/libfuse/libfuse/blob/e16fdc06d7473f00499b6b03fb7bd06259a22135/include/fuse_kernel.h#L333)
  )
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
This is what the `LOOKUP` opcode is for. A `LOOKUP` message looks like this:

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
*  Writing a FUSE Filesystem: a Tutorial  
   Joseph J. Pfeiffer, Jr., Ph.D.  
   <https://www.cs.nmsu.edu/~pfeiffer/fuse-tutorial/>