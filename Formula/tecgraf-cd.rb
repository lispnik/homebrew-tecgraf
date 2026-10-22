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
  # Lua 5.4, not "lua": that is 5.5 now, and IM's bindings -- which cdlua
  # links -- are pinned to 5.4 because they do not compile against 5.5.
  depends_on "lua@5.4"
  # cd_util.c converts text to UTF-8 with glib's g_convert on every platform
  # but Windows, and CD's CMake only finds glib's headers and library through
  # pangocairo. Without pango the build stops on "glib.h: No such file"; it
  # used to work on macOS only because something else had installed pango.
  depends_on "pango"

  on_linux do
    depends_on "libx11"
    # The XRender driver calls ten Xft functions. Without libxft CMake warns
    # and builds a libcd that fails every dlopen on "undefined symbol".
    depends_on "libxft"
    depends_on "libxrender"
  end

  def install
    lua = Formula["lua@5.4"]

    args = [
      "-DCMAKE_BUILD_TYPE=Release",
      "-DCD_ENABLE_CAIRO=ON",
      "-DCD_ENABLE_GL=ON",
      "-DCD_ENABLE_PDF=OFF",
      "-DCD_ENABLE_IM=ON",
      "-DCD_ENABLE_LUA=ON",
      "-DCD_ENABLE_PPTX=OFF",
      "-DCD_ENABLE_DIRECT2D=OFF",
      "-DCD_ENABLE_GDIPLUS=OFF",
      # CD's driver tables assign functions whose second parameter is a
      # concrete type to slots declared void*. Clang and GCC 14+ both make that
      # an error, under different names: clang's is the first flag, GCC's the
      # second (clang knows both, GCC only the second). The proper fix is casts
      # in CD's sources.
      "-DCMAKE_C_FLAGS=-Wno-incompatible-function-pointer-types -Wno-incompatible-pointer-types",
      # Named rather than found, so cdlua cannot pick up whichever Lua comes
      # first on the search path -- it has to be the one IM was built with.
      "-DLUA_INCLUDE_DIR=#{lua.opt_include}/lua5.4",
      "-DLUA_LIBRARY=#{lua.opt_lib}/#{shared_library("liblua5.4")}",
    ]

    # macOS needs no extra flags: the native Quartz driver
    # (CoreGraphics/CoreText) is enabled by default and provides every
    # context the Lua bindings need, clipboard included.
    if OS.linux?
      args << "-DCD_ENABLE_XRENDER=ON"
    end

    # Add explicit paths to IM Lua libraries. Lua modules are built with
    # IM's platform suffix -- imlua.so on Linux, imlua.dylib on macOS -- and
    # have no "lib" prefix, which shared_library would add, so name them here.
    im = Formula["lispnik/tecgraf/tecgraf-im"]
    im_lib_dir = im.opt_lib
    lua_module = OS.mac? ? "dylib" : "so"
    args += [
      # IM itself, named for the same reason as Lua: CD's CMake searches
      # ../im-git and /usr/local before anything Homebrew installed, so a
      # stray IM in /usr/local -- a manual install from before there was a
      # formula, say -- would otherwise be linked instead of this one.
      "-DIM_INCLUDE_DIR=#{im.opt_include}",
      "-DIM_LIBRARY=#{im_lib_dir}/#{shared_library("libim")}",
      "-DIMLUA_LIBRARY=#{im_lib_dir}/imlua.#{lua_module}",
      "-DIMLUA_PROCESS_LIBRARY=#{im_lib_dir}/imlua_process.#{lua_module}",
    ]

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