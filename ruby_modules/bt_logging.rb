require 'logging'

module Bt_logging

  @loggers = Hash.new

  def self.create_logging(className)

    if @loggers.has_key? className
      return @loggers[className]
    end

    Logging.color_scheme( 'bright',
      :levels => {
        :info  => :green,
        :warn  => :yellow,
        :error => :red,
        :fatal => [:white, :on_red]
      },
      :date => :blue,
      :logger => :cyan,
      :message => :magenta
    )

    Logging.appenders.stderr(
    'stderr',
    :layout => Logging.layouts.pattern(
      :pattern => '[%d] %-5l %c: %m\n',
      :color_scheme => 'bright'
      )
    )
    log = Logging.logger[(!className.nil? && !className.empty?) ? className : "bt_logging"]
    log.add_appenders Logging.appenders.stderr
    log.level = :debug

    @loggers[className] = log

    return log
  end
end
