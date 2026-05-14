# Homebrew Tecgraf Tap

This Homebrew tap provides formulas for Tecgraf libraries maintained by lispnik:

- **tecgraf-im**: A toolkit for digital imaging with a simple API for scientific applications
- **tecgraf-cd**: A platform-independent 2D graphics library with support for multiple output formats

## Installation

First, add this tap to your Homebrew installation:

```bash
brew tap <username>/tecgraf
```

Then install the packages you need:

```bash
# Install the IM imaging library
brew install tecgraf-im

# Install the CD graphics library
brew install tecgraf-cd

# Install both with optional dependencies
brew install tecgraf-im --with-lua --with-fftw --with-jasper
brew install tecgraf-cd --with-lua --with-tecgraf-im
```

## Libraries

### Tecgraf IM (tecgraf-im)

A digital imaging toolkit that provides:
- Support for popular image formats (TIFF, BMP, PNG, JPEG, GIF, AVI)
- Scientific data types for image representation  
- Approximately 100 image processing operations
- Optional Lua bindings
- Optional FFTW3 support for FFT operations
- Optional JPEG 2000 support

### Tecgraf CD (tecgraf-cd)

A 2D graphics library that provides:
- Platform-independent vector graphics
- Multiple output backends (Cairo, OpenGL, PDF, native platform APIs)
- Integration with the IM library for image operations
- Optional Lua bindings
- Cross-platform support (macOS, Linux, Windows)

## Dependencies

Both libraries use CMake for building and have various optional dependencies that can be enabled with `--with-*` flags during installation.

## Source

- [tecgraf-im source](https://github.com/lispnik/tecgraf-im)
- [tecgraf-cd source](https://github.com/lispnik/tecgraf-cd)

These are maintained forks of the original Tecgraf libraries from PUC-Rio.