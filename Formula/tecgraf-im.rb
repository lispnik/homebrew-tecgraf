class TecgrafIm < Formula
  desc "Toolkit for digital imaging with simple API for scientific applications"
  homepage "https://github.com/lispnik/tecgraf-im"
  url "https://github.com/lispnik/tecgraf-im/archive/refs/tags/v2.0.2.tar.gz"
  sha256 "9bca9a6eebb1c41cf29ded8a19d431c34adceb4cdebde808220e5aa78777e456"
  license "MIT"
  head "https://github.com/lispnik/tecgraf-im.git", branch: "master"

  # JasPer, the JP2 backend, has a long run of unfixed CVEs and was dropped
  # from Debian after 18.04, so JP2 is off by default. Opt back in with
  # --with-jp2, which pulls in jasper and builds libim_jp2.
  option "with-jp2", "Build JP2 support (adds the jasper dependency)"

  depends_on "cmake" => :build
  depends_on "pkg-config" => :build

  depends_on "fftw"
  depends_on "jasper" if build.with? "jp2"
  depends_on "jpeg-turbo"
  depends_on "libexif"
  depends_on "libheif"     # HEIC/AVIF
  depends_on "liblzf"
  depends_on "libomp"      # IM_BUILD_PROCESS_OMP
  depends_on "libpng"
  depends_on "libtiff"
  # IM does not compile against Lua 5.5 -- macros that changed in 5.5 break the
  # bindings -- so pin 5.4 rather than following the "lua" formula, which is
  # 5.5 now. The CI workflows pin it the same way.
  depends_on "lua@5.4"
  depends_on "lz4"
  depends_on "zlib"

  def install
    lua = Formula["lua@5.4"]

    args = [
      "-DCMAKE_BUILD_TYPE=Release",
      "-DIM_BUILD_PROCESS=ON",
      "-DIM_BUILD_PROCESS_OMP=ON",
      "-DIM_BUILD_FFTW3=ON",
      "-DIM_BUILD_HEIF=ON",
      "-DIM_BUILD_CAPTURE=ON",   # macOS: AVFoundation backend, SDK frameworks only
      "-DIM_BUILD_LUA=ON",
      "-DLUA_INCLUDE_DIR=#{lua.opt_include}/lua5.4",
      "-DLUA_LIBRARY=#{lua.opt_lib}/liblua5.4.dylib",
    ]
    args << (build.with?("jp2") ? "-DIM_BUILD_JP2=ON" : "-DIM_BUILD_JP2=OFF")

    system "cmake", "-S", ".", "-B", "build", *args, *std_cmake_args
    system "cmake", "--build", "build"
    system "cmake", "--install", "build"
  end

  test do
    # Exercises the add-ons with external dependencies easiest to get wrong in
    # the formula: HEIF/AVIF (libheif) always, and JP2 (jasper) when it was
    # built in. Both register at run time, so a missing or mismatched library
    # shows up here rather than as a silently absent format. The WITH_JP2 gate
    # tracks --with-jp2 so the test checks exactly what was built.
    (testpath/"test.c").write <<~EOS
      #include <im.h>
      #include <im_lib.h>
      #include <im_format_heif.h>
      #ifdef WITH_JP2
      #include <im_format_jp2.h>
      #endif
      #include <stdio.h>
      #include <string.h>

      static int has_format(const char* wanted)
      {
          char* format_list[50];
          int format_count = 0;
          imFormatList(format_list, &format_count);

          for (int i = 0; i < format_count; i++)
              if (strcmp(format_list[i], wanted) == 0)
                  return 1;

          return 0;
      }

      int main(void)
      {
          printf("IM version: %s\\n", imVersion());

          imFormatRegisterHEIF();   /* registers both HEIF and AVIF */
      #ifdef WITH_JP2
          imFormatRegisterJP2();
      #endif

          const char* wanted[] = {
              "HEIF", "AVIF",
      #ifdef WITH_JP2
              "JP2",
      #endif
          };
          int missing = 0;

          for (int i = 0; i < (int)(sizeof(wanted)/sizeof(wanted[0])); i++)
          {
              int found = has_format(wanted[i]);
              printf("%s support: %s\\n", wanted[i], found ? "enabled" : "missing");
              if (!found)
                  missing = 1;
          }

          return missing;
      }
    EOS

    # Detect JP2 by the library that was actually built rather than by
    # build.with?: current Homebrew does not record a plain `option` in the
    # install receipt, so build.with? reads false here even after --with-jp2.
    # The presence of libim_jp2 is the ground truth.
    jp2_built = (lib/shared_library("libim_jp2")).exist?

    cflags = ["-I#{include}", "-L#{lib}", "-lim", "-lim_heif"]
    cflags += ["-DWITH_JP2", "-lim_jp2"] if jp2_built

    system ENV.cc, "test.c", *cflags, "-o", "test"
    output = shell_output("./test")

    assert_match(/IM version:/, output)
    assert_match(/HEIF support: enabled/, output)
    assert_match(/AVIF support: enabled/, output)
    assert_match(/JP2 support: enabled/, output) if jp2_built
  end
end
