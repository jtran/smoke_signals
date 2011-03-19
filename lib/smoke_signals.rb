require 'continuation' unless defined?(callcc)

module SmokeSignals

  class UnhandledSignalError < RuntimeError
    attr_accessor :condition
    def initialize(condition)
      self.condition = condition
    end
  end

  class NoRestartError < RuntimeError
    attr_accessor :restart_name
    def initialize(restart_name)
      self.restart_name = restart_name
    end
  end

  class Extensible
    def metaclass
      class << self; self; end
    end
  end

  class Condition

    attr_accessor :rescue_cont

    def signal
      Condition.signal(self, false)
    end

    def signal!
      Condition.signal(self, true)
    end

    def rescue(*return_value)
      self.rescue_cont.call(*return_value)
    end

    def restart(name, *args)
      Condition.restart(name, *args)
    end

    class << self

      def handle(new_handlers, &block)
        orig_handlers = handlers
        begin
          callcc do |cont|
            # First handler goes on top of the stack so it will be signaled
            # first.
            self.handlers = orig_handlers + new_handlers.map {|k,v| [k,v,cont] }.reverse
            block.call
          end
        ensure
          self.handlers = orig_handlers
        end
      end

      def signal(c, raise_unless_handled)
        # Most recently set handlers are run first.
        handlers.reverse_each do |applies_to, handler_fn, cont|
          # Check if the condition being signaled applies to this
          # handler.
          applies = case applies_to
                    when Proc
                      applies_to.call(c)
                    when Array
                      applies_to.any? {|a| a === c }
                    else
                      applies_to === c
                    end
          next unless applies

          c.rescue_cont = cont
          handler_fn.call(c)
        end
        raise UnhandledSignalError.new(c) if raise_unless_handled
      end

      def with_restarts(extension, &block)
        orig_restarts = restarts
        if extension.is_a?(Proc)
          new_restarts = Extensible.new
          new_restarts.metaclass.instance_eval { include Module.new(&extension) }
        else
          new_restarts = extension
        end
        begin
          callcc do |cont|
            self.restarts = orig_restarts + [[new_restarts,cont]]
            block.call
          end
        ensure
          self.restarts = orig_restarts
        end
      end

      def restart(name, *args)
        restarts.reverse_each do |restarts_obj,cont|
          obj, all_args = case restarts_obj
                          when Extensible
                            restarts_obj.respond_to?(name) ? [restarts_obj, [name] + args] : nil
                          else
                            fn = restarts_obj[name]
                            fn ? [fn, [:call] + args] : nil
                          end
          next unless obj
          cont.call(obj.send(*all_args))
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
