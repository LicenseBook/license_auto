module LicenseAuto
  # Returns the version of the currently loaded Rails as a <tt>Gem::Version</tt>
  def self.gem_version
    Gem::Version.new VERSION::STRING
  end

  module VERSION
    MAJOR = 0
    MINOR = 1
    TINY  = 1
    PRE   = '3'

    STRING =
        if PRE.empty?
          [MAJOR, MINOR, TINY].compact.join(".")
        else
          [MAJOR, MINOR, TINY, PRE].compact.join(".")
        end
  end
end