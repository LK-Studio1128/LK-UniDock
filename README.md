# LK_Studio

GPU-accelerated molecular docking tools, packaged and maintained for [LKDock](https://github.com/).

## Repository Structure

```
LK_Studio/
├── Uni-Dock-main/        # Uni-Dock source code (CPU + GPU)
├── UniDock-Pro-main/     # UniDock-Pro source code (classical + similarity + hybrid)
└── UniDock/              # Pre-built binaries (all platforms)
    ├── UniDock-macos-arm64/
    ├── UniDock-linux86/
    └── UniDock-win64/
```

## Pre-built Binaries

| Platform | Folder | Binaries |
|---|---|---|
| macOS arm64 | `UniDock/UniDock-macos-arm64/` | `Uni-Dock` (CPU), `UniDock-Pro` (CPU) |
| Linux x86_64 | `UniDock/UniDock-linux86/` | `Uni-Dock-GPU`, `UniDock-Pro-GPU`, `split` |
| Windows x64 | `UniDock/UniDock-win64/` | `Uni-Dock-GPU.exe`, `UniDock-Pro-GPU.exe` |

> macOS binaries are CPU-only (NVIDIA CUDA is not supported on Apple Silicon).
> Linux and Windows binaries require a compatible NVIDIA GPU.

## Quick Start

### macOS (arm64, CPU-only)
```bash
cd UniDock/UniDock-macos-arm64
./Uni-Dock --help
./UniDock-Pro --help
```

### Linux (GPU required)
```bash
cd UniDock/UniDock-linux86
./Uni-Dock-GPU --help
./UniDock-Pro-GPU --help
```

### Windows (GPU required)
```powershell
cd UniDock\UniDock-win64\Uni-Dock-GPU
.\Uni-Dock-GPU.exe --help
```

## Building from Source

Each source folder contains platform-specific build scripts:

```bash
# macOS
cd Uni-Dock-main && bash build_mac.sh --clean
cd UniDock-Pro-main && bash build_mac.sh --clean

# Linux (requires CUDA Toolkit >= 11.8)
cd Uni-Dock-main && bash build_linux.sh
cd UniDock-Pro-main && bash build_linux.sh

# Windows (requires CUDA Toolkit >= 11.8 + Visual Studio)
cd Uni-Dock-main && build_windows.bat
cd UniDock-Pro-main && build_windows.bat
```

## Source Code

- **[Uni-Dock-main/](./Uni-Dock-main/)** — GPU-accelerated docking (fork of [dptech-corp/Uni-Dock](https://github.com/dptech-corp/Uni-Dock)), with Windows/CUDA compatibility patches
- **[UniDock-Pro-main/](./UniDock-Pro-main/)** — Extended version with ligand similarity searching and hybrid docking (fork of [NiBoyang/UniDock-Pro](https://github.com/NiBoyang/UniDock-Pro))

## License

Apache License 2.0. See [`Uni-Dock-main/LICENSE`](./Uni-Dock-main/LICENSE) and [`UniDock-Pro-main/LICENSE`](./UniDock-Pro-main/LICENSE).
