# Before You Contribute

Note that Piglet is an early project by Pig so we're going to be making changes relatively frequently. We'd love contributions but there's always the chance the our directional needs at the time aren't exactly what you're looking for. If you're not sure, ask us first!

# How to Contribute

There's a sample size of n=1 for this build working, so bear with me.

Requirements:
- Zig 0.13.0
- ZLS 0.13.0
- A Windows machine, or a MacOS machine with Parallels installed. I'm currently developing this via Parallels.

On mac, the build script expects 
```
brew install mingw-w64
```
Make sure you brew install the same version found in the `build.zig` file.
This pulls in the windows headers for ZLS. 
All libraries currently used are standard and dynamically linked, so you just need the headers for your language server to work.

## Building
```
# for debug. Note image operations may be slow.
zig build -Dtarget=x86_64-windows-gnu

# for release
zig build -Dtarget=x86_64-windows-gnu -Drelease-safe
```

## Testing
From within a Windows machine, navigate to your `zig-out/bin` directory and run the `piglet.exe` file.