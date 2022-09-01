// zig fmt: off
pub const upload_dir       = "/tmp/uploaded_files";
pub const buffer_size      = 1024;
pub const client_heap_size = 2048;
pub const max_clients      = 1024;

// Opts: .poll, .epoll, .uring
pub const ev_type: EvType  = .poll;

// Poll
pub const poll_timeout     = 1000;
pub const kernel_backlog   = 128;

// Epoll
pub const epoll_timeout    = 1000;

// Uring / IO_Uring


//
// Do not edit the following lines
//
pub const EvType = enum {
    poll,
    epoll,
    uring,
};

// Check whether `upload_dir` ends with '/' or not,
// if true use that, else append a '/'
pub const __upload_dir = if (upload_dir[upload_dir.len - 1] == '/') brk: {
    break :brk upload_dir;
} else brk: {
    break :brk upload_dir ++ "/";
};
