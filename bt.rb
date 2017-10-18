require "digest/md5"

module BT
  module_function

  if ENV.key?("BT_INIT")
    def start(name)
      return if ENV.key?("BT_DISABLED") and ENV["BT_DISABLED"] != "0"
      caller, desc_checksum, timestamp = _metadata(name)

      file = "/tmp/bt.#{desc_checksum}.#{timestamp}"
      file_alias = "/tmp/bt.#{desc_checksum}"

      File.write(file, "#{caller} #{name}\n")
      File.symlink(file, file_alias)
    end

    def end(name)
      return if ENV.key?("BT_DISABLED") and ENV["BT_DISABLED"] != "0"
      caller, desc_checksum, timestamp = _metadata(name)

      File.open("/tmp/bt.#{desc_checksum}", 'a') do |f|
        f.puts("#{timestamp} #{caller} #{name}")
      end
    end

    def _metadata(name)
      caller = /([[:alnum:]\.\/\-]+\:[[:digit:]]+)/.match(caller_locations(1, 1)[0].to_s)[0]
      desc_checksum = Digest::MD5.hexdigest(name)
      time = Time.now
      timestamp = "#{time.to_i}#{time.nsec}".ljust(19, '0')

      [caller, desc_checksum, timestamp]
    end
  else
    def start(name)
    end

    def end(name)
    end
  end

  def time(name)
    self.start(name)
    yield
  ensure
    self.end(name)
  end
end
