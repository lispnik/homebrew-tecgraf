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
  depends_on "fftw" => :optional
  depends_on "jasper" => :optional
  depends_on "lua" => :optional

  def install
    system "cmake", "-S", ".", "-B", "build",
                    "-DCMAKE_BUILD_TYPE=Release",
                    "-DIM_BUILD_PROCESS=ON",
                    "-DIM_BUILD_PROCESS_OMP=ON",
                    "-DIM_BUILD_JP2=#{build.with?("jasper") ? "ON" : "OFF"}",
                    "-DIM_BUILD_FFTW3=#{build.with?("fftw") ? "ON" : "OFF"}",
                    "-DIM_BUILD_LUA=#{build.with?("lua") ? "ON" : "OFF"}",
                    *std_cmake_args

    system "cmake", "--build", "build"
    system "cmake", "--install", "build"
  end

  test do
    # Create a simple test program
    (testpath/"test.cpp").write <<~EOS
      #include <im.h>
      #include <iostream>

      int main() {
          std::cout << "IM version: " << imVersion() << std::endl;
          return 0;
      }
    EOS

    system ENV.cxx, "test.cpp", "-I#{include}", "-L#{lib}", "-lim", "-o", "test"
    assert_match /IM version:/, shell_output("./test")
  end
end