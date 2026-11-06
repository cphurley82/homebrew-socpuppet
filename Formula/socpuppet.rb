# socpuppet's Homebrew formula, rendered by tools/tap.py from a release's
# macOS wheels: edit tools/socpuppet.rb.in in socpuppet's repository, and
# not the copy in the tap.
class Socpuppet < Formula
  desc "A whole SoC simulated in SystemC, with Python pulling the strings."
  homepage "https://github.com/cphurley82/socpuppet"
  version "0.0.1"
  license "MIT"

  # The release's wheel for each processor. A wheel is a zip, and
  # :nounzip keeps Homebrew from unpacking it.
  on_arm do
    url "https://github.com/cphurley82/socpuppet/releases/download/v0.0.1/socpuppet-0.0.1-cp315-cp315-macosx_13_0_arm64.whl", using: :nounzip
    sha256 "b5db181059bf44f6c379843ac8b4225fc0db3bdee3735174f328c901441acdd0"
  end
  on_intel do
    url "https://github.com/cphurley82/socpuppet/releases/download/v0.0.1/socpuppet-0.0.1-cp315-cp315-macosx_13_0_x86_64.whl", using: :nounzip
    sha256 "63686e6f4db74caa99e5a2371ad26e3ff70743e2693c112eff56b3cb444c70c1"
  end

  # 🔌 libslirp is the cable to this machine's network, which socpuppet
  # finds at run time; the Python is the one the wheels are built for.
  depends_on "libslirp"
  depends_on "python@3.15"

  # socpuppet's one dependency, pure Python, as uv.lock pins it.
  resource "platformdirs" do
    url "https://files.pythonhosted.org/packages/45/b8/fd1af06b079af236f5423f7c1821264419cc8f6b4803f79353acbb8bfa53/platformdirs-4.13.3-py3-none-any.whl", using: :nounzip
    sha256 "f6ad7f447f24f8a3b82cce5976387428bff894a0eca6c3488f4a17f153c130c4"
  end

  # Homebrew's own Python helper uses this one, which carries pip.
  def python3
    Formula["python@3.15"].opt_libexec/"bin/python"
  end

  def install
    # Into this formula's libexec, and a .pth file that `brew link` puts
    # where Homebrew's Python looks, so that its Python finds them and no
    # other package's files are in the way. Homebrew's own pip arguments
    # refuse a wheel, so pip is told by hand, and --no-index makes a
    # missing dependency a failure rather than a download.
    site_packages = Language::Python.site_packages(python3)
    pip = [python3, "-m", "pip", "install", "--no-deps", "--no-index",
           "--ignore-installed", "--no-compile", "--prefix=#{libexec}"]
    resource("platformdirs").stage { system(*pip, Dir["*.whl"].first) }
    system(*pip, Dir[buildpath/"*.whl"].first)
    (prefix/site_packages/"socpuppet.pth").write "#{libexec/site_packages}\n"
    bin.install_symlink libexec/"bin/socpuppet"
  end

  test do
    # The README's smaller show, which has no CPU: nothing is fetched.
    (testpath/"show.py").write <<~'PYTHON'
      import socpuppet as sp

      RAM = 0x8000_0000

      def script():                                  # 🧵 each yield is one bus operation
          yield sp.write32(RAM, 0xC0FFEE)
          value = yield sp.read32(RAM)               # a read sends its value back in
          yield sp.expect32(RAM, value)

      platform = sp.Platform()
      compute, io = platform.group("compute"), platform.group("io")   # two dies

      cpu = compute.add("cpu", sp.ScriptedBusMaster(script))          # 🎭 stands in for the CPU
      d2d = platform.link("d2d", sp.PassThroughLink(), compute, io)   # 🎭 stands in for the die-to-die link
      bus = io.add("bus", sp.Router())
      ram = io.add("ram", sp.Memory(size=64 * 1024))

      platform.connect(cpu.socket, d2d.a.target, trace=True)
      platform.connect(d2d.b.initiator, bus.target)
      bus.map(ram.socket, base=RAM)

      platform.build()
      platform.run()
      print(sp.render_trace(platform.trace))
    PYTHON
    assert_match '0 ns  write 0x80000000  ee ff c0 00  ✅  compute.cpu.socket → compute.d2d.target', shell_output("#{python3} #{testpath}/show.py")
    assert_match "usage: socpuppet", shell_output("#{bin}/socpuppet --help")
  end
end
