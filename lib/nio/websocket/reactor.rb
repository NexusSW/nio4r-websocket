require 'nio'

module NIO
  module WebSocket
    class Reactor
      class << self
        def queue_task(&blk)
          return unless block_given?
          task_mutex.synchronize do
            @task_queue ||= []
            @task_queue << blk
          end
          selector.wakeup
        end

        def selector
          @selector ||= NIO::Selector.new
        end

        def reset
          @reactor.exit if @reactor
          @selector = nil
          @reactor = nil
          @task_queue = nil
          @task_mutex = nil
        end

        def start
          WebSocket.logger.debug 'Starting reactor' unless @reactor
          @reactor ||= Thread.start do
            Thread.current.abort_on_exception = true
            WebSocket.logger.info 'Reactor started'
            begin
              loop do
                queue = []
                task_mutex.synchronize do
                  queue = @task_queue || []
                  @task_queue = []
                end
                # If something queues up while this runs, then the selector will also be awoken & won't block
                queue.each(&:call)

                selector.select 1 do |monitor|
                  begin
                    monitor.value.call if monitor.value.respond_to? :call
                  rescue => e
                    WebSocket.logger.error "Error occured in callback on socket #{monitor.io}.  No longer handling this connection."
                    WebSocket.logger.error "#{e.class}: #{e.message}"
                    e.backtrace.map { |s| WebSocket.logger.error "\t#{s}" }
                    monitor.close # protect global loop from being crashed by a misbehaving driver, or a sloppy disconnect
                  end
                end
                Thread.pass # give other threads a chance at manipulating our selector (e.g. a new connection on the main thread trying to register)
              end
            rescue => e
              WebSocket.logger.fatal 'Error occured in reactor subsystem.'
              WebSocket.logger.fatal "#{e.class}: #{e.message}"
              e.backtrace.map { |s| WebSocket.logger.fatal "\t#{s}" }
              raise
            end
          end
        end

        private

        def task_mutex
          @task_mutex ||= Mutex.new
        end
      end
    end
  end
end
