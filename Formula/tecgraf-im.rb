class TecgrafIm < Formula
  desc "Toolkit for digital imaging with simple API for scientific applications"
  homepage "https://github.com/lispnik/tecgraf-im"
  url "https://github.com/lispnik/tecgraf-im.git", branch: "master"
  version "3.15"
  license "MIT"

  depends_on "cmake" => :build
  depends_on "pkg-config" => :build

  depends_on "fftw"
  depends_on "jasper"      # JP2; the build wants jasper, not openjpeg
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

    system "cmake", "-S", ".", "-B", "build",
                    "-DCMAKE_BUILD_TYPE=Release",
                    "-DIM_BUILD_PROCESS=ON",
                    "-DIM_BUILD_PROCESS_OMP=ON",
                    "-DIM_BUILD_FFTW3=ON",
                    "-DIM_BUILD_JP2=ON",
                    "-DIM_BUILD_HEIF=ON",
                    "-DIM_BUILD_LUA=ON",
                    "-DLUA_INCLUDE_DIR=#{lua.opt_include}/lua5.4",
                    "-DLUA_LIBRARY=#{lua.opt_lib}/liblua5.4.dylib",
                    *std_cmake_args

    system "cmake", "--build", "build"
    system "cmake", "--install", "build"
  end

  test do
    # Exercises the two add-ons with external dependencies that are easiest to
    # get wrong in the formula: JP2 (jasper) and HEIF/AVIF (libheif). Both
    # register at run time, so a missing or mismatched library shows up here
    # rather than as a silently absent format.
    (testpath/"test.c").write <<~EOS
      #include <im.h>
      #include <im_lib.h>
      #include <im_format_jp2.h>
      #include <im_format_heif.h>
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

          imFormatRegisterJP2();
          imFormatRegisterHEIF();   /* registers both HEIF and AVIF */

          const char* wanted[] = { "JP2", "HEIF", "AVIF" };
          int missing = 0;

          for (int i = 0; i < 3; i++)
          {
              int found = has_format(wanted[i]);
              printf("%s support: %s\\n", wanted[i], found ? "enabled" : "missing");
              if (!found)
                  missing = 1;
          }

          return missing;
      }
    EOS

    system ENV.cc, "test.c", "-I#{include}", "-L#{lib}",
                   "-lim", "-lim_jp2", "-lim_heif", "-o", "test"
    output = shell_output("./test")

    assert_match(/IM version:/, output)
    assert_match(/JP2 support: enabled/, output)
    assert_match(/HEIF support: enabled/, output)
    assert_match(/AVIF support: enabled/, output)
  end
end
