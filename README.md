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

### Installation
The below PowerShell script will install Piglet onto your Windows machine, and add the `piglet` executable to your PATH.

```powershell
# Create tool directory
$toolDir = "$env:USERPROFILE\.piglet"
New-Item -ItemType Directory -Force -Path $toolDir

# Download piglet
Invoke-WebRequest -Uri "https://github.com/pig-dot-dev/piglet/releases/download/v0.0.7/piglet.exe" -OutFile "$toolDir\piglet.exe"

# Add to PATH if not already there
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*$toolDir*") {
    [Environment]::SetEnvironmentVariable("Path", $userPath + ";" + $toolDir, "User")
}

Write-Host "Piglet installed! You may need to restart your terminal for PATH changes to take effect."
```

Piglet can then be started with:
```powershell
piglet start
```

Or subscribed for remote use via Pig cloud:
```powershell
piglet join --secret SK-YOUR-SECRET-KEY
```
> [Get your API key here](https://pig.dev/login)

### API

Piglet currently supports:
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

- GET `/computer/display/screenshot`
  - Returns body: image/png bytes
- GET `/computer/display/dimensions` 
  - Returns json body: `{ width: number, height: number }`
- POST `/computer/input/keyboard/type`
  - Requires json body: `{ text: string }`
- POST `/computer/input/keyboard/key`
  - Requires json body: `{ text: string }`
- GET `/computer/input/mouse/position`
  - Returns json body: `{ x: number, y: number }`
- POST `/computer/input/mouse/move`
  - Requires json body: `{ x: number, y: number }`
- POST `/computer/input/mouse/click`
  - Requires json body: `{ x: number, y: number, button: "left"|"right", down: boolean }`
 
You can call the API directly at localhost, or use the [Pig Python SDK](https://github.com/pig-dot-dev/pig-python):
```bash
pip install pig-python
```

In local mode:
```python
from pig import Client
client = Client()

# Select your local machine
machine = client.machines.local()

# Start a connection and send a workflow
with machine.connect() as conn:
    conn.key("super")                     # Press Windows key
    conn.type("hello world!")             # Type text
```

Or across the internet (requires [Pig](https://pig.dev) account)
```python
from pig import Client
client = Client()

# Select your remote machine by ID
machine = client.machines.remote(id="YOUR_MACHINE_ID")

# Start a connection and send a workflow
with machine.connect() as conn:
    conn.key("super")                     # Press Windows key
    conn.type("hello world!")             # Type text
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
- Migrating Pig Cloud to also run Piglets, offering the same OS-level access to users of our managed machines.
