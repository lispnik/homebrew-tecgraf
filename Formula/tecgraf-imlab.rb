class TecgrafImlab < Formula
  desc "Graphical application for scientific image processing"
  homepage "https://github.com/lispnik/tecgraf-imlab"
  url "https://github.com/lispnik/tecgraf-imlab.git", branch: "main"
  version "3.3"
  license "MIT"

  depends_on "cmake" => :build
  depends_on "fftw"
  depends_on "lispnik/tecgraf/tecgraf-cd"
  depends_on "lispnik/tecgraf/tecgraf-im"
  depends_on "lispnik/tecgraf/tecgraf-iup"
  depends_on :macos # the CMake build and its fixes are for the Cocoa port of IUP

  def install
    # IMLAB_USE_SYSTEM_IUP: build against the installed tecgraf-iup rather than looking for an
    # IUP source tree, which is what the build prefers when it finds one.
    # ImLab loads ImLab.png from beside its executable and nowhere else (see
    # load_image_imlab_logo in src/splash.cpp), so the executable goes to libexec with its
    # images, and bin gets a symlink. The kernels are data the user opens through a file
    # dialog, so they go where data goes.
    system "cmake", "-S", ".", "-B", "build",
                    "-DIMLAB_USE_SYSTEM_IUP=ON",
                    "-DIMLAB_ENABLE_FFTW=ON",
                    "-DIMLAB_INSTALL_BINDIR=libexec",
                    "-DIMLAB_INSTALL_DATADIR=share/#{name}",
                    "-DIMLAB_INSTALL_APPDIR=libexec",
                    *std_cmake_args

    system "cmake", "--build", "build"
    system "cmake", "--install", "build"

    # A symlink rather than a wrapper script: IUP resolves EXEFILENAME through realpath, so
    # ImLab still finds the images next to the real executable in libexec.
    bin.install_symlink libexec/"imlab"
  end

  def caveats
    <<~EOS
      ImLab is a graphical application, so it is also installed as a bundle. Link it into
      Applications to have it in the Finder and the Dock:

        ln -sfn #{opt_libexec}/ImLab.app /Applications/ImLab.app

      The convolution kernels it ships are installed in

        #{opt_pkgshare}/krn
    EOS
  end

  test do
    # ImLab is a GUI application: it opens a window and runs an event loop, so it cannot be
    # started in a test environment that may have no window server. What can be checked
    # without one is that the executable exists, that it is linked against the libraries this
    # formula went to the trouble of arranging, and that the resources it loads at startup
    # were installed beside it.
    assert_predicate libexec/"imlab", :executable?
    assert_predicate bin/"imlab", :symlink?

    linkage = shell_output("otool -L #{libexec}/imlab")
    assert_match "tecgraf-iup/Frameworks/iup.framework", linkage
    assert_match "tecgraf-cd/lib/libcd", linkage
    assert_match "tecgraf-im/lib/libim", linkage
    assert_match "libfftw3", linkage

    # Startup reads ImLab.png from beside the real executable, so it has to be in libexec --
    # in bin it would be next to a symlink and never found.
    assert_path_exists libexec/"ImLab.png"

    # The bundle has to be complete enough for LaunchServices to accept it: an executable where
    # Info.plist says, and a signature, which Apple silicon requires before it will launch one.
    assert_path_exists libexec/"ImLab.app/Contents/MacOS/imlab"
    assert_path_exists libexec/"ImLab.app/Contents/Resources/ImLab.icns"
    # In the bundle the images are in Resources -- Contents/MacOS holds the executable and
    # nothing else, or codesign will not sign it.
    assert_path_exists libexec/"ImLab.app/Contents/Resources/ImLab.png"
    assert_equal ["imlab"], Dir.children(libexec/"ImLab.app/Contents/MacOS")
    system "codesign", "--verify", "--strict", libexec/"ImLab.app"
    assert_operator Dir["#{pkgshare}/krn/*.krn"].count, :>, 0
  end
end
