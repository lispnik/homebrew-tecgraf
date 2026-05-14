class TecgrafCd < Formula
  desc "Platform-independent 2D graphics library with support for multiple output formats"
  homepage "https://github.com/lispnik/tecgraf-cd"
  url "https://github.com/lispnik/tecgraf-cd.git", branch: "main"
  version "5.14.0"
  license "MIT"

  depends_on "cmake" => :build
  depends_on "pkg-config" => :build
  depends_on "cairo"
  depends_on "fontconfig"
  depends_on "freetype"
  depends_on "ftgl"
  depends_on "lispnik/tecgraf/tecgraf-im"

  on_linux do
    depends_on "libx11"
    depends_on "libxrender"
  end

  def install
    args = [
      "-DCMAKE_BUILD_TYPE=Release",
      "-DCD_ENABLE_CAIRO=ON",
      "-DCD_ENABLE_GL=ON",
      "-DCD_ENABLE_PDF=OFF",
      "-DCD_ENABLE_IM=ON",
      "-DCD_ENABLE_LUA=OFF",
      "-DCD_ENABLE_PPTX=OFF",
      "-DCMAKE_C_FLAGS=-Wno-incompatible-function-pointer-types"
    ]

    if OS.mac?
      # On macOS, use X11 (could add native Cocoa backend later)
      args << "-DCD_PLATFORM_MACOS=ON"
    elsif OS.linux?
      args << "-DCD_ENABLE_XRENDER=ON"
    end

    system "cmake", "-S", ".", "-B", "build", *args, *std_cmake_args
    system "cmake", "--build", "build"
    system "cmake", "--install", "build"
  end

  test do
    # Create a simple test program
    (testpath/"test.c").write <<~EOS
      #include <cd.h>
      #include <im.h>
      #include <im_lib.h>
      #include <stdio.h>

      int main() {
          printf("CD version: %s\\n", cdVersion());
          printf("IM version: %s\\n", imVersion());
          return 0;
      }
    EOS

    system ENV.cc, "test.c", "-I#{include}", "-L#{lib}", "-L#{HOMEBREW_PREFIX}/lib", "-lcd", "-lim", "-o", "test"
    assert_match "CD version:", shell_output("./test")
    assert_match "IM version:", shell_output("./test")
  end
end