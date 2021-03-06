require 'zip'
require_relative 'extensions'
require_relative 'version'
require_relative 'utils'

BASE_URL="http://build.squeak.org/"
SRC=File.expand_path("#{File.expand_path(File.dirname(__FILE__))}/../..") # Oh, the horror!
TARGET_DIR = "#{SRC}/target"
TRUNK_IMAGE="TrunkImage"
SPUR_TRUNK_IMAGE="SpurTrunkImage"
@@COMMAND_COUNT = 0

class UnknownOS < Exception
  def initialize(os_name)
    @os_name = os_name
    super "Unknown OS #{os_name}"
  end

  attr_accessor :os_name
end

def as_relative_path(script_path)
  # Windows doesn't let you use a script with a full path, so we turn all script
  # references into relative paths.
  Pathname.new(script_path).relative_path_from(Pathname.new(TARGET_DIR)).to_s
end

# vm_type element_of [:mt, :mtht, :normal, :spur]
def assert_coglike_vm(os_name, vm_type)
  cog = COG_VERSION.dir_name(os_name, vm_type)
  cog_desc = "#{cog} r.#{COG_VERSION.svnid}"

  cog_dir = "#{TARGET_DIR}/#{cog}.r#{COG_VERSION.svnid}"

  cogs = Dir.glob("#{TARGET_DIR}/#{cog}.r*")
  cogs.delete(File.expand_path(cog_dir))
  cogs.each { |stale_cog|
    log("Deleting stale #{cog} at #{stale_cog}")
    FileUtils.rm_rf(stale_cog)
  }
  if File.exists?(cog_dir) then
    log("Using existing #{cog_desc}")
    COG_VERSION.cog_location(Pathname.new(TARGET_DIR), os_name, vm_type)
  else
    assert_target_dir
    log("Installing new #{cog_desc} (#{vm_type})")
    FileUtils.mkdir_p(cog_dir)
    begin
      begin
        download_cog(os_name, vm_type, COG_VERSION, cog_dir)
        lib_dir = COG_VERSION.lib_dir(TARGET_DIR, os_name, vm_type)
        COG_VERSION.cog_location(Pathname.new(TARGET_DIR), os_name, vm_type)
      rescue UnknownOS => e
        log("Unknown OS #{e.os_name} for Cog VM. Aborting.")
        raise e
      end
    rescue => e
      FileUtils.rm_rf(cog_dir)
      log("Cleaning up failed install of #{cog_desc} (#{e.message})")
      nil
    end
  end
end

def assert_cog_vm(os_name)
  return case os_name
         when "linux", "linux64" then assert_coglike_vm(os_name, :ht)
         else assert_coglike_vm(os_name, :normal)
         end
end

def assert_cogmt_vm(os_name)
  return assert_coglike_vm(os_name, :mt)
end

def assert_cogmtht_vm(os_name)
  return assert_coglike_vm(os_name, :mtht)
end

def assert_cog_spur_vm(os_name)
  return assert_coglike_vm(os_name, :spur)
end

def assert_interpreter_compatible_image(interpreter_vm, image_name, os_name)
  # Double parent because "parent" means "dir of"
  interpreter_vm_dir = Pathname.new(interpreter_vm).parent.parent.to_s
  ckformat = nil
  # Gag at the using-side-effects nonsense.
  Pathname.new(SRC).find {|path| ckformat = path if path.basename.to_s == 'ckformat'}

  if ckformat then
    format = run_cmd("#{ckformat} #{TARGET_DIR}/#{image_name}.image")
    puts "Before format conversion: \"#{TARGET_DIR}/#{image_name} image format #{format}"
  else
    puts "WARNING: no ckformat found"
  end

  if File.exists?(interpreter_vm) then
    # Attempted workaround to address the different args used by the different VMs.
    args = if os_name == "osx" then ["-vm-display-null"] else vm_args(os_name) end
    run_image_with_cmd(interpreter_vm, args, image_name, "#{SRC}/save-image.st")
  else
    puts "WARNING: #{interpreter_vm} not found, image not converted to format 6504"
  end

  if ckformat then
    image_location = "#{TARGET_DIR}/#{image_name}.image"
    format = run_cmd("#{ckformat} #{image_location}")
    puts "After format conversion: \"#{image_location}\" image format #{format}"
  end
end

def assert_interpreter_vm(os_name)
  # word_size is 32 or 64, for 32-bit or 64-bit.

  raise "Missing Cmake. Please install it!" unless run_cmd "cmake"

  word_size = if (os_name == "linux64") then
                64
              else
                32
              end

  interpreter_src_dir = "#{TARGET_DIR}/Squeak-#{INTERPRETER_VERSION}-src-#{word_size}"
  if File.exist?(interpreter_vm_location(os_name)) then
    log("Using existing interpreter VM in #{interpreter_src_dir}")
  else
    assert_target_dir
    case os_name
    when "linux", "linux64", "freebsd"
      log("Downloading Interpreter VM #{INTERPRETER_VERSION}")
      Dir.chdir(TARGET_DIR) {
        Dir.glob("*-src-*") {|stale_interpreter| FileUtils.rm_rf(stale_interpreter)}
        run_cmd("curl -sSo interpreter.tgz http://www.squeakvm.org/unix/release/Squeak-#{INTERPRETER_VERSION}-src.tar.gz")
        if not File.exist?("interpreter.tgz") then
          run_cmd("curl -sSo interpreter.tgz http://havnor.angband.za.org/squeak/vm/interpreter/Squeak-#{INTERPRETER_VERSION}-src.tar.gz")
        end
        run_cmd("tar zxf interpreter.tgz")
        FileUtils.mv("Squeak-#{INTERPRETER_VERSION}-src", interpreter_src_dir)
        FileUtils.mkdir_p("#{interpreter_src_dir}/bld")
        Dir.chdir("#{interpreter_src_dir}/bld") {
          run_cmd("../unix/cmake/configure")
          run_cmd("make WIDTH=#{word_size}")
          assert_ssl("#{interpreter_src_dir}/bld", os_name)
        }
      }
    when "windows"
      log("Downloading Interpreter VM #{WINDOWS_INTERPRETER_VERSION}")
      interpreter_src_dir = "#{TARGET_DIR}/Squeak-#{WINDOWS_INTERPRETER_VERSION}-src-#{word_size}"
      FileUtils.rm_rf(interpreter_src_dir) if File.exist?(interpreter_src_dir)
      Dir.chdir(TARGET_DIR) {
        run_cmd "curl -sSo interpreter.zip http://www.squeakvm.org/win32/release/Squeak#{WINDOWS_INTERPRETER_VERSION}.win32-i386.zip"
        unzip('interpreter.zip')
        FileUtils.mv("Squeak#{WINDOWS_INTERPRETER_VERSION}", interpreter_src_dir)
      }
    when "osx"
      log("At the moment, Frank can't get the Interpreter VM building on OS X. Aborting.")
    else
      log("Unknown OS #{os_name} for Interpreter VM. Aborting.")
    end
  end
  interpreter_vm_location(os_name)
end

def assert_ssl(target_dir, os_name)
  # My hope is that this becomes a standard plugin, and this function can disappear.
  raise "Can't install SSL on #{os_name}" if not ["linux", "linux64", "windows"].include?(os_name)
  if not File.exist?("#{target_dir}/SqueakSSL") then
    Dir.chdir(target_dir) {
      run_cmd("curl -sSO https://squeakssl.googlecode.com/files/SqueakSSL-bin-0.1.5.zip")
      unzip('SqueakSSL-bin-0.1.5.zip')
      FileUtils.mkdir_p("SqueakSSL")
      case os_name
      when "windows" then
        FileUtils.cp("SqueakSSL-bin/win/SqueakSSL.dll", "#{target_dir}/SqueakSSL.dll")
      else
        FileUtils.cp("SqueakSSL-bin/unix/so.SqueakSSL", "#{target_dir}/SqueakSSL")
      end
      FileUtils.rm_rf("SqueakSSL-bin")
    }
  end
end

def assert_trunk_image
  if File.exists?("#{TARGET_DIR}/#{TRUNK_IMAGE}.image") then
    log("Using existing #{TRUNK_IMAGE}")
  else
    log("Downloading new #{TRUNK_IMAGE}")
    Dir.chdir(TARGET_DIR) {
      run_cmd "curl -sSO #{BASE_URL}/job/SqueakTrunk/lastSuccessfulBuild/artifact/target/#{TRUNK_IMAGE}.image"
      run_cmd "curl -sSO #{BASE_URL}/job/SqueakTrunk/lastSuccessfulBuild/artifact/target/#{TRUNK_IMAGE}.changes"
    }
  end
end

def assert_target_dir
  FileUtils.mkdir_p(TARGET_DIR)
  ["SqueakV41.sources", "HudsonBuildTools.st"].each { |name|
    FileUtils.cp("#{SRC}/#{name}", "#{TARGET_DIR}/#{name}")
  }
end

def cog_archive_name(os_name, vm_type, cog_version)
  suffix, ext = case os_name
                when "freebsd"
                  ["fbsd", "tgz"]
                when "linux", "linux64"
                  ["linux", "tgz"]
                when "osx"
                  ["osx", "tgz"]
                when "windows"
                  ["win", "zip"]
                else
                  raise UnknownOS.new(os_name)
                end
  "#{cog_version.dir_name(os_name, vm_type)}#{suffix}.#{ext}"
end

def debug?
  # For the nonce, always output debug info
  true
#  ! ENV['DEBUG'].nil?
end

def download_cog(os_name, vm_type, cog_version, cog_dir)
  local_name = cog_archive_name(os_name, vm_type, cog_version)
  download_url = "http://www.mirandabanda.org/files/Cog/VM/VM.r#{COG_VERSION.svnid}/#{COG_VERSION.filename(os_name, vm_type)}"
  Dir.chdir(cog_dir) {
    run_cmd "curl -sSo #{local_name} #{download_url}"

    case os_name
    when "windows"
      unzip(local_name)
    else
      run_cmd "tar zxf #{local_name}"
#      rc = run_cmd "tar zxf #{local_name}"
#      raise "Cog zip broken: no such Cog?" if rc != 0
    end
  }
end

def identify_os
  return "windows" if (/cygwin|mswin|mingw|bccwin|wince|emx/ =~ RUBY_PLATFORM)

  str = `uname -a`
  return "linux" if str.include?("Linux") && ! str.include?("x86_64")
  return "linux64" if str.include?("Linux") && str.include?("x86_64")
  return "osx" if str.include?("Darwin")
  return "UNKNOWN"
end

def interpreter_vm_location(os_name)
  word_size = if (os_name == "linux64") then
                64
              else
                32
              end

  version = if os_name == "windows" then
              WINDOWS_INTERPRETER_VERSION
            else
              INTERPRETER_VERSION
            end

  interpreter_src_dir = "#{TARGET_DIR}/Squeak-#{version}-src-#{word_size}"

  case os_name
  when "linux", "linux64", "freebsd", "osx" then "#{interpreter_src_dir}/bld/squeak.sh"
  when "windows" then "#{interpreter_src_dir}/Squeak#{version}.exe"
  else
    nil
  end
end

# timeout in seconds
def run_image_with_cmd(vm_name, arr_of_vm_args, image_name, cmd, timeout = 240)
  log(cmd)
  base_cmd = "#{vm_name} #{arr_of_vm_args.join(" ")} \"#{TARGET_DIR}/#{image_name}.image\" #{as_relative_path(Pathname.new(cmd))}"
  case identify_os
    when "windows" then begin
                          log(base_cmd)
                          system(base_cmd)
                        end
  else
    if identify_os == "osx" then base_cmd = "unset DISPLAY && #{base_cmd}" end

    cmd_count = @@COMMAND_COUNT
    log("spawning command #{cmd_count} with timeout #{timeout.to_s} seconds: #{base_cmd}")
    # Don't nice(1), because then the PID we get it nice's PID, not the Squeak process'
    # PID. We need this so we can send the process a USR1.
    pid = spawn("#{base_cmd} && echo command #{cmd_count} finished")
    log("(Command started with PID #{pid})")
    @@COMMAND_COUNT += 1
    Thread.new {
      kill_time = Time.now + timeout.seconds
      process_gone = false
      while (Time.now < kill_time)
        sleep(1.second)
        begin
          Process.kill(0, pid)
        rescue Errno::ESRCH
          # The process is gone
          process_gone = true
          break
        end
      end

      if ! process_gone then
        log("!!! Killing command #{cmd_count} for exceeding allotted time: #{base_cmd}.")
        # Dump out debug info from the image before we kill it. Don't use Process.kill
        # because we want to capture stdout.
        output = run_cmd("kill -USR1 #{pid}")
        puts output
        puts "-------------"
#        output = run_cmd("pstree #{pid}")
#        $stdout.puts output
        begin
          Process.kill('KILL', pid)
        rescue Errno::ESRCH => e
            puts "Tried to kill process #{pid} but it's gone"
            raise e
        end
        puts "-------------"
        log("!!! Killed command #{cmd_count}")
        raise "Command #{cmd_count} killed: timed out."
      end
    }
    Process.wait(pid)
    raise "Process #{pid} failed with exit status #{$?.exitstatus}" if $?.exitstatus != 0
  end
end

def latest_downloaded_trunk_version(base_path)
  if File.exist?('#{base_path}/target/#{TRUNK_IMAGE}.version') then
    v = File.read('#{base_path}/target/#{TRUNK_IMAGE}.version', 'r') { |f| f.read }
    v.to_i
  else
    0
  end
end

def unzip(file_name)
  Zip::File.open(file_name) { |z|
    z.each { |f|
      f_path = File.join(Dir.pwd, f.name)
      FileUtils.mkdir_p(File.dirname(f_path))
      z.extract(f, f_path) unless File.exist?(f_path)
    }
  }
end

def vm_args(os_name)
  case os_name
  when "osx"
    ["-headless"]
  when "linux", "linux64", "freebsd"
    ["-vm-sound-null", "-vm-display-null"]
  when "windows"
    ["-headless"]
  else
    raise UnknownOS.new(os_name)
  end
end
