# ruby-macho is vendored with Homebrew but is not loaded into a formula's context, so the
# Pathname helpers that use it (change_dylib_id, change_install_name) raise "uninitialized
# constant MachO" without this.
require "macho"

class TecgrafIup < Formula
  desc "Portable toolkit for building graphical user interfaces"
  homepage "https://github.com/lispnik/tecgraf-iup"
  url "https://github.com/lispnik/tecgraf-iup.git", branch: "master"
  version "3.32"
  license "MIT"

  depends_on "cmake" => :build
  depends_on "lispnik/tecgraf/tecgraf-cd"
  depends_on "lispnik/tecgraf/tecgraf-im"
  depends_on :macos # this fork is the Cocoa port; the GTK build is not wired up here

  def install
    cd_formula = Formula["lispnik/tecgraf/tecgraf-cd"]
    im_formula = Formula["lispnik/tecgraf/tecgraf-im"]

    # IUP's CMakeLists says it plainly: on macOS only the Xcode generator works,
    # the Makefile generator is broken. It also has no install() rules at all,
    # so everything below is installed by hand rather than with `cmake --install`.
    # One architecture, this one: the Xcode generator otherwise builds a universal binary,
    # and the x86_64 slice cannot link against Homebrew's single-architecture CD and IM.
    system "cmake", "-S", ".", "-B", "build", "-G", "Xcode",
                    "-DCMAKE_BUILD_TYPE=Release",
                    "-DCMAKE_OSX_ARCHITECTURES=#{Hardware::CPU.arch}",
                    "-DWANTS_BUILD_SHARED_LIBRARY=ON",
                    "-DWANTS_BUILD_FRAMEWORK=ON",
                    # Room to rewrite the install names below to the absolute paths these end
                    # up at, which are longer than the @rpath ones they are built with.
                    "-DCMAKE_SHARED_LINKER_FLAGS=-Wl,-headerpad_max_install_names"

    # Only the libraries. The project also defines sample and test applications, which are of
    # no use once installed and are a large part of the build time.
    library_targets = %w[iup iupcd iupcontrols iupgl iupglcontrols iupimglib iupweb]
    system "cmake", "--build", "build", "--config", "Release",
           "--target", *library_targets

    built = Pathname.new("build/Release")

    # Frameworks rather than plain dylibs: the Cocoa driver compiles .xib files
    # into the framework bundle and loads them from it at run time (the text
    # spinner is one), so a bare dylib would build but lose those resources.
    framework_names = library_targets
    framework_names.each do |name|
      bundle = built/"#{name}.framework"
      next unless bundle.exist?

      frameworks.install bundle

      # As built, each framework's install name is @rpath-relative, which leaves
      # every consumer having to pass -rpath. Point them at where they actually
      # live, the way a Homebrew dylib refers to its opt path, and fix the
      # references between them to match.
      binary = frameworks/"#{name}.framework/Versions/A/#{name}"
      next unless binary.exist?

      binary.change_dylib_id("#{opt_frameworks}/#{name}.framework/Versions/A/#{name}")

      # Only the references this binary actually has: ruby-macho raises rather than shrugging
      # when asked to rename a dylib that is not linked, and most of these link only iup.
      linked = MachO.open(binary.to_s).linked_dylibs

      framework_names.each do |dependency|
        rpath_name = "@rpath/#{dependency}.framework/Versions/A/#{dependency}"
        next unless linked.include?(rpath_name)

        binary.change_install_name(
          rpath_name,
          "#{opt_frameworks}/#{dependency}.framework/Versions/A/#{dependency}",
        )
      end

      # Editing the load commands invalidates the ad-hoc signature every arm64 binary carries.
      system "codesign", "--force", "--sign", "-", "--timestamp=none", binary
    end

    # IupPlot and IupIm are shipped as source in this tree and are in no CMake target, so
    # upstream's own build compiles them per application. They are part of what IUP means to
    # anyone using it -- IupPlot in particular -- so build them here as static libraries rather
    # than leaving every consumer to rediscover that. Static because they are small, and it
    # avoids a second round of install-name juggling.
    #
    # This has to happen before the headers are installed: include.install MOVES them out of
    # the source tree, and these compile against them.
    mkdir "extra" do
      plot_objects = Dir["#{buildpath}/srcplot/*.cpp"].map do |source|
        object = File.basename(source, ".cpp") + ".o"
        system ENV.cxx, "-c", "-O2", "-std=c++11", "-o", object, source,
               "-I#{buildpath}/include", "-I#{buildpath}/src",
               "-I#{buildpath}/srcplot", "-I#{buildpath}/srccd",
               "-I#{cd_formula.opt_include}"
        object
      end
      system "ar", "rcs", "libiup_plot.a", *plot_objects

      system ENV.cc, "-c", "-O2", "-o", "iup_im.o", "#{buildpath}/srcim/iup_im.c",
             "-I#{buildpath}/include", "-I#{buildpath}/src",
             "-I#{im_formula.opt_include}"
      system "ar", "rcs", "libiupim.a", "iup_im.o"

      lib.install "libiup_plot.a", "libiupim.a"
    end

    include.install Dir["include/*.h"], "include/iup_class_cbs.hpp"
  end

  def caveats
    <<~EOS
      The libraries are installed as macOS frameworks, so build against them with:

        -F#{opt_frameworks} -framework iup -framework iupcontrols

      IupPlot and IupIm are static libraries instead, because IUP ships them as
      source with no build of their own:

        #{opt_lib}/libiup_plot.a  #{opt_lib}/libiupim.a
    EOS
  end

  test do
    # IupOpen needs a window server, which a bottle build or a CI runner may not
    # have, so the test asks only for what can be answered without one: that the
    # framework links, that its version is the one this formula claims, and that
    # a control class from a second framework resolves.
    (testpath/"test.c").write <<~EOS
      #include <iup.h>
      #include <iupcontrols.h>
      #include <stdio.h>

      int main(void)
      {
          printf("IUP version: %s\\n", IupVersion());
          printf("IupDial address: %p\\n", (void*)IupDial);
          return 0;
      }
    EOS

    system ENV.cc, "test.c", "-o", "test",
           "-I#{include}",
           "-F#{frameworks}", "-framework", "iup", "-framework", "iupcontrols",
           "-framework", "Cocoa"

    output = shell_output("./test")
    assert_match "IUP version: #{version}", output

    # The static extras must actually contain their symbols -- an empty archive
    # links happily and fails only when something calls into it.
    assert_match "IupPlot", shell_output("nm #{lib}/libiup_plot.a 2>&1")
    assert_match "IupLoadImage", shell_output("nm #{lib}/libiupim.a 2>&1")
  end
end
