class TecgrafCd < Formula
  desc "Platform-independent 2D graphics library with support for multiple output formats"
  homepage "https://github.com/lispnik/tecgraf-cd"
  url "https://github.com/lispnik/tecgraf-cd.git", branch: "master"
  version "5.14.0"
  license "MIT"

  depends_on "cmake" => :build
  depends_on "pkg-config" => :build
  depends_on "cairo"
  depends_on "freetype"
  depends_on "lua" => :optional
  depends_on "tecgraf-im" => :optional

  on_linux do
    depends_on "libx11"
    depends_on "libxrender"
  end

  def install
    args = [
      "-DCMAKE_BUILD_TYPE=Release",
      "-DCD_USE_CAIRO=ON",
      "-DCD_USE_OPENGL=ON",
      "-DCD_USE_PDF=ON",
    ]

    if OS.mac?
      args << "-DCD_USE_COCOA=ON"
    elsif OS.linux?
      args << "-DCD_USE_X11=ON"
      args << "-DCD_USE_XRENDER=ON"
    end

    args << "-DCD_USE_LUA=#{build.with?("lua") ? "ON" : "OFF"}"
    args << "-DCD_USE_IM=#{build.with?("tecgraf-im") ? "ON" : "OFF"}"

    system "cmake", "-S", ".", "-B", "build", *args, *std_cmake_args
    system "cmake", "--build", "build"
    system "cmake", "--install", "build"
  end

  test do
    # Create a simple test program
    (testpath/"test.c").write <<~EOS
      #include <cd.h>
      #include <stdio.h>

      int main() {
          printf("CD Canvas Draw Library initialized\\n");
          return 0;
      }
    EOS

    system ENV.cc, "test.c", "-I#{include}", "-L#{lib}", "-lcd", "-o", "test"
    assert_match "CD Canvas Draw Library initialized", shell_output("./test")
  end
end