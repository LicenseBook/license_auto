require 'log4r'
require 'license_auto/config/config'

module LicenseAuto
  def self.logger
    return @logger if @logger
    @logger = Log4r::Logger.new("license_auto")
    @logger.trace = true
    @logger.level = LUTO_LOG_LEVEL

    @logger.add(Log4r::Outputter.stderr)
    @logger.add(Log4r::Outputter.stdout)

    stdout_output = Log4r::StdoutOutputter.new('stdout')
    file_output = Log4r::FileOutputter.new("file_output",
                                           :filename => LUTO_CONF.logger.file,
                                           :trunc => false,
                                           :level => LUTO_LOG_LEVEL)
    date_file_output = Log4r::DateFileOutputter.new("data_file_output",
                                                    :dirname => File.dirname(LORK_CONF.logger.file),
                                                    :date_pattern => '%Y%m%d%H',
                                                    :trunc => false)
    formatter = Log4r::PatternFormatter.new(:pattern => "%C %.1l %d %p => %M  %t")
    stdout_output.formatter = formatter
    file_output.formatter = formatter
    date_file_output.formatter = formatter

    @logger.outputters = [stdout_output,  date_file_output]

    @logger
  end
end
