class TecgrafIm < Formula
  desc "Toolkit for digital imaging with simple API for scientific applications"
  homepage "https://github.com/lispnik/tecgraf-im"
  url "https://github.com/lispnik/tecgraf-im/archive/refs/tags/v2.2.2.tar.gz"
  sha256 "ce2b52a9e07c08537271ffc1de501eb1175536727650bc1d0e7b955e6b3eef2d"
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
    #
    # Also links libim_process and runs operations from it. Format
    # registration alone would pass identically whatever libim_process
    # contains, and on a version bump that adds to it the test should be able
    # to tell the two versions apart -- so each release that adds operations
    # gets one exercised here. Decorrelation stretch arrived in 2.1.0,
    # watershed segmentation in 2.2.0. 2.2.1 added no operations but fixed a
    # crash reachable only through libim_process_omp, which nothing here
    # linked -- see the second program below. 2.2.2 added none either, and
    # stopped the writers putting memory they never set into files -- see
    # the third.
    (testpath/"test.c").write <<~EOS
      #include <im.h>
      #include <im_lib.h>
      #include <im_image.h>
      #include <im_process.h>
      #include <im_format_heif.h>
      #ifdef WITH_JP2
      #include <im_format_jp2.h>
      #endif
      #include <stdio.h>
      #include <string.h>

      /* A decorrelation stretch has to change a correlated image and leave a
         flat one alone. Cheap, and it fails if libim_process is missing, is
         from another version, or was built without the operation. */
      static int decorrelation_works(void)
      {
          imImage* src = imImageCreate(16, 16, IM_RGB, IM_BYTE);
          imImage* dst = imImageCreate(16, 16, IM_RGB, IM_BYTE);
          unsigned char** in;
          unsigned char** out;
          int i, plane, differing = 0;

          if (!src || !dst)
              return 0;

          in = (unsigned char**)src->data;
          for (i = 0; i < src->count; i++)
          {
              /* one shared ramp plus a small per-plane offset: strongly
                 correlated, but not degenerate */
              int base = 60 + (i % 128);
              for (plane = 0; plane < 3; plane++)
                  in[plane][i] = (unsigned char)(base + 3 * plane + (i % 5));
          }

          if (!imProcessDecorrelationStretch(src, dst, IM_DECORR_LDS, 3.0))
              return 0;

          out = (unsigned char**)dst->data;
          for (i = 0; i < dst->count; i++)
              for (plane = 0; plane < 3; plane++)
                  if (out[plane][i] != in[plane][i])
                      differing++;

          imImageDestroy(src);
          imImageDestroy(dst);

          return differing > dst->count / 4;
      }

      /* WatershedSegment splits objects that touch, which imAnalyzeFindRegions
         cannot: two overlapping discs are ONE connected component and two
         regions. Added in 2.2.0, so without this the test would pass unchanged
         against 2.1.1. */
      static int watershed_works(void)
      {
          imImage* bin = imImageCreate(40, 24, IM_BINARY, IM_BYTE);
          imImage* out = imImageCreate(40, 24, IM_GRAY, IM_USHORT);
          unsigned char* b;
          int x, y, regions = 0, ok;

          if (!bin || !out)
              return 0;

          b = (unsigned char*)bin->data[0];
          for (y = 0; y < 24; y++)
              for (x = 0; x < 40; x++)
              {
                  int d1 = (x - 12) * (x - 12) + (y - 12) * (y - 12);
                  int d2 = (x - 26) * (x - 26) + (y - 12) * (y - 12);
                  b[y * 40 + x] = (d1 <= 64 || d2 <= 64) ? 1 : 0;
              }

          ok = imProcessWatershedSegment(bin, out, 8, 1, &regions);

          imImageDestroy(bin);
          imImageDestroy(out);

          return ok && regions == 2;
      }

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
          printf("decorrelation stretch: %s\\n",
                 decorrelation_works() ? "working" : "broken");
          printf("watershed: %s\\n", watershed_works() ? "working" : "broken");

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

    cflags = ["-I#{include}", "-L#{lib}", "-lim", "-lim_process", "-lim_heif"]
    cflags += ["-DWITH_JP2", "-lim_jp2"] if jp2_built

    system ENV.cc, "test.c", *cflags, "-o", "test"
    output = shell_output("./test")

    # Nothing above links libim_process_omp, which this formula also builds:
    # the program uses libim_process, so an OpenMP build that was broken,
    # missing, or linked against the wrong libomp would install silently.
    #
    # Not a hypothetical gap. Up to 2.2.0 the OpenMP progress counter freed a
    # lock it had never allocated, so imAnalyzeFindRegions and imProcessCanny
    # killed the process at address 0 -- but only in that library, and only
    # with a callback attached, which is the one thing the test above never
    # does. This program does both, and segfaults against 2.2.0.
    (testpath/"omp.c").write <<~EOS
      #include <im.h>
      #include <im_image.h>
      #include <im_counter.h>
      #include <im_process.h>
      #include <stdio.h>

      static int calls = 0;

      static int on_progress(int counter, void* user_data, const char* text, int progress)
      {
          (void)counter; (void)user_data; (void)text; (void)progress;
          calls++;
          return 1;
      }

      /* Labels a square and finds its edges with a callback attached the whole
         time. A callback is what makes the counter do anything at all: without
         one imCounterBegin returns -1 and every path through it is skipped. */
      int main(void)
      {
          imImage* bin = imImageCreate(64, 64, IM_BINARY, IM_BYTE);
          imImage* labels = imImageCreate(64, 64, IM_GRAY, IM_USHORT);
          imImage* gray = imImageCreate(64, 64, IM_GRAY, IM_BYTE);
          imImage* edges = imImageCreate(64, 64, IM_GRAY, IM_BYTE);
          unsigned char* b;
          unsigned char* g;
          int x, y, regions = 0, ok;

          if (!bin || !labels || !gray || !edges)
              return 1;

          b = (unsigned char*)bin->data[0];
          g = (unsigned char*)gray->data[0];
          for (y = 0; y < 64; y++)
              for (x = 0; x < 64; x++)
              {
                  int inside = (x >= 16 && x < 48 && y >= 16 && y < 48);
                  b[y * 64 + x] = inside ? 1 : 0;
                  g[y * 64 + x] = inside ? 255 : 0;
              }

          imCounterSetCallback(NULL, on_progress);
          ok = imAnalyzeFindRegions(bin, labels, 8, 1, &regions);
          ok = imProcessCanny(gray, edges, 1.4) && ok;
          imCounterSetCallback(NULL, NULL);

          printf("progress callback: %s (%d calls, %d region)\\n",
                 (ok && regions == 1 && calls > 0) ? "working" : "broken",
                 calls, regions);

          imImageDestroy(bin);
          imImageDestroy(labels);
          imImageDestroy(gray);
          imImageDestroy(edges);

          return (ok && regions == 1 && calls > 0) ? 0 : 1;
      }
    EOS

    system ENV.cc, "omp.c", "-I#{include}", "-L#{lib}",
           "-lim", "-lim_process_omp", "-o", "omp_test"
    omp_output = shell_output("./omp_test")

    # Up to 2.2.1 four writers put memory they had never set into the files
    # they wrote, where it could carry anything the process had in memory --
    # and the files decoded correctly, so no round trip could see it. This
    # writes the three that are reachable from a plain save over memory
    # filled with 0xAA, and checks the bytes that leaked: BMP line padding
    # (heap), the GIF interlaced flag (heap) and the unused PCX palette
    # entries (stack). MallocScribble=1 is what makes macOS fill every new
    # heap block, MALLOC_PERTURB_ the same on glibc; the program fills the
    # stack itself. Fails all three against 2.2.1.
    (testpath/"unset.c").write <<~EOS
      #include <im.h>
      #include <im_image.h>
      #include <im_util.h>
      #include <stdio.h>
      #include <string.h>

      /* Fills the stack the save will run on, so a stack byte the writer did not
         set is 0xAA. Volatile, or the compiler drops the stores as dead. */
      static __attribute__((noinline)) void soil_stack(void)
      {
          unsigned char buffer[256 * 1024];
          volatile unsigned char* p = buffer;
          for (size_t i = 0; i < sizeof(buffer); i++)
              p[i] = 0xAA;
      }

      static long read_file(const char* name, unsigned char* data, long size)
      {
          FILE* file = fopen(name, "rb");
          long got;
          if (!file)
              return -1;
          got = (long)fread(data, 1, (size_t)size, file);
          fclose(file);
          return got;
      }

      static unsigned char data[65536];

      int main(void)
      {
          int clean = 1, i, y;
          long size;

          /* BMP lines are padded to 4 bytes: a 37-pixel RGB line is 111 bytes and
             one of padding, which came from the heap. */
          imImage* rgb = imImageCreate(37, 23, IM_RGB, IM_BYTE);
          imImageClear(rgb);
          soil_stack();
          imFileImageSave("black.bmp", "BMP", rgb);
          size = read_file("black.bmp", data, sizeof(data));
          if (size < 54 + 23 * 112)
              clean = 0;
          else
              for (y = 0; y < 23; y++)
                  if (data[54 + y * 112 + 111] != 0)
                      clean = 0;
          printf("BMP line padding: %s\\n", clean ? "zeros" : "unset memory");

          /* The GIF interlaced flag, bit 0x40 of the image descriptor's flags,
             came from a field nothing set. */
          imImage* gray = imImageCreate(37, 23, IM_GRAY, IM_BYTE);
          imImageClear(gray);
          soil_stack();
          imFileImageSave("gray.gif", "GIF", gray);
          size = read_file("gray.gif", data, sizeof(data));
          int gif_clean = size > 22 && data[13] == ',' && (data[22] & 0x40) == 0;
          printf("GIF interlaced flag: %s\\n", gif_clean ? "clear" : "unset memory");

          /* PCX writes 256 palette entries at the end of the file; of these 5 are
             used, and the rest came from the stack. */
          imImage* map = imImageCreate(37, 23, IM_MAP, IM_BYTE);
          imImageClear(map);
          for (i = 0; i < 5; i++)
              map->palette[i] = imColorEncode((imbyte)(i * 50), 0, 0);
          map->palette_count = 5;
          soil_stack();
          imFileImageSave("map.pcx", "PCX", map);
          size = read_file("map.pcx", data, sizeof(data));
          int pcx_clean = size > 768;
          for (i = 5 * 3; pcx_clean && i < 768; i++)
              if (data[size - 768 + i] != 0)
                  pcx_clean = 0;
          printf("PCX palette tail: %s\\n", pcx_clean ? "zeros" : "unset memory");

          imImageDestroy(rgb);
          imImageDestroy(gray);
          imImageDestroy(map);
          return (clean && gif_clean && pcx_clean) ? 0 : 1;
      }
    EOS

    system ENV.cc, "unset.c", "-I#{include}", "-L#{lib}", "-lim", "-o", "unset_test"
    unset_output = shell_output("MallocScribble=1 MALLOC_PERTURB_=85 ./unset_test")

    assert_match(/IM version:/, output)
    assert_match(/decorrelation stretch: working/, output)
    assert_match(/watershed: working/, output)
    assert_match(/HEIF support: enabled/, output)
    assert_match(/AVIF support: enabled/, output)
    assert_match(/JP2 support: enabled/, output) if jp2_built
    assert_match(/progress callback: working/, omp_output)
    assert_match(/BMP line padding: zeros/, unset_output)
    assert_match(/GIF interlaced flag: clear/, unset_output)
    assert_match(/PCX palette tail: zeros/, unset_output)
  end
end
