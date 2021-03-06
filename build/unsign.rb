#!/usr/bin/env ruby
# Deactivates any embedded code signatures in a Mach-O binary.
 
module MachO
  class Unsign
    def self.unsign(filename)
      File.open(filename, "r+") do |f|
        Unsign.new(f).headers
      end
    end
 
    attr_accessor :headers
 
    protected
 
    FatHeader = Struct.new(:cpu_type, :cpu_subtype, :offset, :size, :align, :mach)
    MachHeader = Struct.new(:cpu_type, :cpu_subtype, :filetype, :ncmds, :sizeofcmds, :flags, :reserved, :cmds)
    LoadCommand = Struct.new(:cmd, :cmdsize)
 
    def initialize(f)
      @f = f
      @headers = process
    end
 
    def debug(message)
      puts message if ENV["DEBUG"]
    end
 
    def word_type
      @big_endian ? 'N' : 'V'
    end
 
    def patch_code_signature(lc)
      # just change LC_CODE_SIGNATURE to a high value that will be ignored by the loader
      debug "PATCHING LC_CODE_SIGNATURE"
      @f.seek(-8, IO::SEEK_CUR)
      @f.write([0xff, lc.cmdsize].pack("#{word_type}2"))
      lc
    end
 
    def process_mach
      len = @x86_64 ? 7 : 6
      header = MachHeader.new(*@f.read(len*4).unpack("#{word_type}#{len}"))
      debug "MACH HEADER: #{header.inspect}"
      header.cmds = (1..(header.ncmds)).collect do
        lc = LoadCommand.new(*@f.read(8).unpack("#{word_type}2"))
        debug "LOAD COMMAND: #{lc.inspect}"
 
        lc = case lc.cmd
        when 0x1d then patch_code_signature(lc)
        else lc
        end
 
        @f.seek(lc.cmdsize - 8, IO::SEEK_CUR)
 
        lc
      end
      header
    end
 
    def process_fat
      num_arches, = @f.read(4).unpack("N")
      arches = (1..num_arches).collect do
        FatHeader.new(*@f.read(20).unpack("N5"))
      end
      debug "FAT HEADER: #{arches.inspect}"
      arches.each do |arch|
        @f.seek(arch.offset)
        arch.mach = process
      end
      arches
    end
 
    def process
      magic, = @f.read(4).unpack("N")
      debug "MAGIC: 0x%08x" % magic
      case magic
      when 0xcafebabe then @big_endian, @x86_64 = false, false; process_fat
      when 0xfeedface then @big_endian, @x86_64 = true,  false; process_mach
      when 0xcffaedfe then @big_endian, @x86_64 = false, true;  process_mach
      when 0xcefaedfe then @big_endian, @x86_64 = false, false; process_mach
      else raise "unknown magic: 0x%08x" % magic
      end
    end
  end
end
 
# command line driver
if __FILE__ == $0
  if ARGV.empty?
    $stderr.puts "usage:  #{$0} filename ..."
    exit 1
  end
 
  ARGV.each do |filename|
    puts "removing signatures from: #{filename}"
    MachO::Unsign::unsign(filename)
  end
end