module SmokeSignals

  class UnhandledSignalError < RuntimeError
    attr_accessor :condition
    def initialize(condition)
      super('condition was not rescued or restarted by any handlers')
      self.condition = condition
    end
  end

  class NoRestartError < RuntimeError
    attr_accessor :restart_name
    def initialize(restart_name)
      super("no established restart with name: #{restart_name}")
      self.restart_name = restart_name
    end
  end

  # You should never rescue this exception in normal usage.  If you
  # do, you should re-raise it.  It is raised to allow ensure blocks
  # to execute as you would expect.  Normally, you should not be
  # rescuing Exception anyway, without re-raising it.  A bare rescue
  # only rescues StandardError, a subclass of Exception.
  class RollbackException < Exception
    attr_reader :nonce, :return_value
    def initialize(nonce, return_value)
      @nonce = nonce
      @return_value = return_value
    end
  end

  class Extensible
    def metaclass
      class << self; self; end
    end
  end

  class Condition

    attr_accessor :nonce

    def signal
      Condition.signal(self, false)
    end

    def signal!
      Condition.signal(self, true)
    end

    def rescue(return_value)
      raise RollbackException.new(self.nonce, return_value)
    end

    def restart(name, *args)
      Condition.restart(name, *args)
    end

    def handle_by(handler)
      if handler.is_a?(Proc)
        # No pattern given, so handler applies to everything.
        handler
      else
        applies_to, handler_fn = handler
        applies = case applies_to
                  when Proc
                    applies_to.call(self)
                  when Array
                    applies_to.any? {|a| a === self }
                  else
                    applies_to === self
                  end
        applies ? handler_fn : nil
      end
    end

    class << self

      def handle(*new_handlers, &block)
        orig_handlers = handlers
        nonce = Object.new
        if new_handlers.last.is_a?(Hash)
          new_handlers.pop.reverse_each {|entry| new_handlers.push(entry) }
        end
        self.handlers = orig_handlers + new_handlers.map {|entry| [entry,nonce] }.reverse
        begin
          block.call
        rescue RollbackException => e
          if nonce.equal?(e.nonce)
            e.return_value
          else
            raise e
          end
        ensure
          self.handlers = orig_handlers
        end
      end

      def signal(c, raise_unless_handled)
        # Most recently set handlers are run first.
        handlers.reverse_each do |handler, nonce|
          # Check if the condition being signaled applies to this
          # handler.
          handler_fn = c.handle_by(handler)
          next unless handler_fn

          c.nonce = nonce
          handler_fn.call(c)
        end
        raise UnhandledSignalError.new(c) if raise_unless_handled
      end

      def with_restarts(extension, &block)
        orig_restarts = restarts
        nonce = Object.new
        if extension.is_a?(Proc)
          new_restarts = Extensible.new
          new_restarts.metaclass.instance_eval { include Module.new(&extension) }
        else
          new_restarts = extension
        end

        self.restarts = orig_restarts + [[new_restarts,nonce]]
        begin
          block.call
        rescue RollbackException => e
          if nonce.equal?(e.nonce)
            e.return_value
          else
            raise e
          end
        ensure
          self.restarts = orig_restarts
        end
      end

      def restart(name, *args)
        restarts.reverse_each do |restarts_obj, nonce|
          obj, all_args = case restarts_obj
                          when Extensible
                            restarts_obj.respond_to?(name) ? [restarts_obj, [name] + args] : nil
                          else
                            fn = restarts_obj[name]
                            fn ? [fn, [:call] + args] : nil
                          end
          next unless obj
          raise RollbackException.new(nonce, obj.send(*all_args))
        end
        raise NoRestartError.new(name)
      end

      private

      def handlers
        Thread.current[:ConditionHandlers] ||= []
      end

      def handlers=(arr)
        Thread.current[:ConditionHandlers] = arr
      end

      def restarts
        Thread.current[:ConditionRestarts] ||= []
      end

      def restarts=(arr)
        Thread.current[:ConditionRestarts] = arr
      end

    end

  end

end
