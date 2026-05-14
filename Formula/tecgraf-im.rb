class TecgrafIm < Formula
  desc "Toolkit for digital imaging with simple API for scientific applications"
  homepage "https://github.com/lispnik/tecgraf-im"
  url "https://github.com/lispnik/tecgraf-im.git", branch: "master"
  version "3.8.2"
  license "MIT"

  depends_on "cmake" => :build
  depends_on "pkg-config" => :build
  depends_on "libtiff"
  depends_on "jpeg-turbo"
  depends_on "libpng"
  depends_on "zlib"
  depends_on "libexif"
  depends_on "lz4"
  depends_on "fftw"
  depends_on "openjpeg"

  def install
    system "cmake", "-S", ".", "-B", "build",
                    "-DCMAKE_BUILD_TYPE=Release",
                    "-DIM_BUILD_PROCESS=ON",
                    "-DIM_BUILD_PROCESS_OMP=ON",
                    "-DIM_BUILD_FFTW3=ON",
                    "-DIM_BUILD_JP2=ON",
                    "-DIM_BUILD_LUA=OFF",
                    *std_cmake_args

    system "cmake", "--build", "build"
    system "cmake", "--install", "build"
  end

  test do
    # Create a simple test program
    (testpath/"test.c").write <<~EOS
      #include <im.h>
      #include <im_lib.h>
      #include <im_format_jp2.h>
      #include <stdio.h>
      #include <string.h>

      int main() {
          printf("IM version: %s\\n", imVersion());

          // Test JP2 support
          imFormatRegisterJP2();

          char* format_list[50];
          int format_count;
          imFormatList(format_list, &format_count);

          int jp2_found = 0;
          for (int i = 0; i < format_count; i++) {
              if (strcmp(format_list[i], "JP2") == 0) {
                  jp2_found = 1;
                  break;
              }
          }

          if (jp2_found) {
              printf("JP2 support: enabled\\n");
              return 0;
          } else {
              printf("JP2 support: missing\\n");
              return 1;
          }
      }
    EOS

    system ENV.cc, "test.c", "-I#{include}", "-L#{lib}", "-lim", "-lim_jp2", "-o", "test"
    output = shell_output("./test")
    assert_match /IM version:/, output
    assert_match /JP2 support: enabled/, output
  end
end