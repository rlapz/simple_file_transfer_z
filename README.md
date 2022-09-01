# simple_file_transfer_z
Socket programing exercise (based on https://github.com/teainside/simple_file_transfer)

Zig version: [0.10.0-dev.3840+2b92c5a23](https://ziglang.org/builds/zig-linux-x86_64-0.10.0-dev.3840+2b92c5a23.tar.xz)

How to build:
1. Release Safe
```bash
zig build -Drelease-safe
```

2. Release Fast
```bash
zig build -Drelease-fast
```

3. Relase Debug
```bash
zig build
```

How to change the configuration(s):
1. Edit file `./src/config.zig`
2. Rebuild

How to run:
1. Server:
```bash
./zig-out/bin/simple_file_transfer_z server [IP] [PORT]
```
2. Client:
```bash
./zig-out/bin/simple_file_transfer_z client [IP TARGET] [PORT TARGET] [FILE]
```


---
Event handlers:
- [x] Poll
- [ ] Epoll
- [ ] IO Uring
