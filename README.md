# Piglet

Piglet is a computer-use driver that runs on your Windows machine, exposing a high-level API for desktop automation tasks.

### Objective

Piglet is maintained by [Pig](https://pig.dev), a Windows VM cloud offering APIs for automating desktop tasks.

We've quickly learned that automation tasks, either using traditional RPA scripts or guided by AI models, require a much more comprehensive view into the Windows desktop environment itself. And it's a space that's seemingly deeply lacking in good tools.

So we're happy to open source Piglet, to create a friendly and secure API into:
```
computer/
├── display/  # Getting screenshots, dimensions, and more
├── window/   # Reading and writing the element tree for precise control and context 
├── input/    # Keyboard and mouse control
├── fs/       # Reading and writing files
└── shell/    # Running commands
```

All natively integrated into the Windows OS (written in zig btw 😎).

### Features

**Platform Support:**
- Windows 7 and up

**Current APIs:**
```
computer/
├── display/
│   ├── screenshot
│   └── dimensions
├── input/
│   ├── keyboard/
│   │   ├── type
│   │   └── key
│   └── mouse/
│       ├── position
│       ├── move
│       └── click
```

**Access:**
- HTTP API served at `http://localhost:3000`

### Installation
The below PowerShell script will install Piglet onto your Windows machine, and add the `piglet` executable to your PATH.

```powershell
# Create tool directory
$toolDir = "$env:USERPROFILE\.piglet"
New-Item -ItemType Directory -Force -Path $toolDir

# Download piglet
Invoke-WebRequest -Uri "https://github.com/pig-dot-dev/piglet/releases/download/v0.0.0/piglet.exe" -OutFile "$toolDir\piglet.exe"

# Add to PATH if not already there
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*$toolDir*") {
    [Environment]::SetEnvironmentVariable("Path", $userPath + ";" + $toolDir, "User")
}

Write-Host "Piglet installed! You may need to restart your terminal for PATH changes to take effect."
```

Piglet can then be started with:
```powershell
piglet
```

### Roadmap
```
computer/
├── window/     
│   ├── active
│   ├── all
│   ├── find
│   └── elements  # DOM-like tree access
├── display/
│   ├── stream   # Screen streaming
│   └── record   # Screen recording
├── input/
│   └── mouse/
│       └── scroll
├── fs/
│   ├── read
│   ├── write
│   ├── list
│   └── watch
└── shell/
    ├── cmd/
    │   ├── exec      # Single commands
    │   └── session   # Interactive shell
    ├── powershell/
    │   ├── exec
    │   └── session
    └── wsl/
        ├── exec
        └── session
```

### And Pig?
We built Piglet to drive our own cloud machines, but this opens an incredible opportunity: open-sourcing the driver, and allowing any Windows machine in the world to run automations.

You can use Piglet standalone, no Pig account needed.

For those who want the full Pig experience, we're now working on:
- Allowing your Piglet(s) to subscribe to Pig cloud to accept and run jobs, securely across the internet.
- Migrating Pig Cloud to also run Piglets, offering the same OS-level access to users of our managed machines.
