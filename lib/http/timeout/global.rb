module HTTP
  module Timeout
    class Global < PerOperation
      attr_reader :time_left, :total_timeout

      def initialize(*args)
        super

        reset_counter
      end

      def reset_counter
        @time_left = @total_timeout = connect_timeout + read_timeout + write_timeout
      end

      def connect(socket_class, host, port)
        reset_timer
        ::Timeout.timeout(time_left, TimeoutError) do
          @socket = socket_class.open(host, port)
        end

        log_time
      end

      def connect_ssl
        reset_timer

        begin
          socket.connect_nonblock
        rescue IO::WaitReadable
          IO.select([socket], nil, nil, time_left)
          log_time
          retry
        rescue IO::WaitWritable
          IO.select(nil, [socket], nil, time_left)
          log_time
          retry
        end
      end

      # Read from the socket
      def readpartial(size)
        reset_timer

        begin
          socket.read_nonblock(size)
        rescue IO::WaitReadable
          IO.select([socket], nil, nil, time_left)
          log_time
          retry
        end
      end

      # Write to the socket
      def write(data)
        reset_timer

        begin
          socket << data
        rescue IO::WaitWritable
          IO.select(nil, [socket], nil, time_left)
          log_time
          retry
        end
      end

      alias_method :<<, :write

      private

      # Due to the run/retry nature of nonblocking I/O, it's easier to keep track of time
      # via method calls instead of a block to monitor.
      def reset_timer
        @started = Time.now
      end

      def log_time
        @time_left -= (Time.now - @started)
        if time_left <= 0
          fail TimeoutError, "Timed out after using the allocated #{total_timeout} seconds"
        end

        reset_timer
      end
    end
  end
end
