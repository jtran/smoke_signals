class SmokeSignals

  # This is raised by Condition#signal! if no handler rescues or
  # restarts.
  class UnhandledSignalError < RuntimeError
    attr_accessor :condition
    def initialize(condition)
      super("condition was not rescued or restarted by any handlers: #{condition}")
      self.condition = condition
    end
  end

  # This is raised when a signal handler attempts to execute a restart
  # that has not been established.
  class NoRestartError < RuntimeError
    attr_accessor :restart_name
    def initialize(restart_name)
      super("no established restart with name: #{restart_name}")
      self.restart_name = restart_name
    end
  end

  # You should never rescue this exception or any of its subclasses in
  # normal usage.  If you do, you should re-raise it.  It is raised to
  # unwind the stack and allow +ensure+ blocks to execute as you would
  # expect.  Normally, you should not be rescuing Exception, anyway,
  # without re-raising it.  A bare +rescue+ clause only rescues
  # StandardError, a subclass of Exception, which is probably what you
  # want.
  class StackUnwindException < Exception
    attr_reader :nonce
    def initialize(nonce)
      super("This exception is an implementation detail of SmokeSignals.  If you're seeing this, either there is a bug in SmokeSignals or you are rescuing a SmokeSignals::StackUnwindException when you shouldn't be.  If you rescue this, you should re-raise it.")
      @nonce = nonce
    end
  end

  # You should never rescue this exception.  See StackUnwindException.
  class RescueException < StackUnwindException
    attr_reader :return_value
    def initialize(nonce, return_value)
      super(nonce)
      @return_value = return_value
    end
  end

  # You should never rescue this exception.  See StackUnwindException.
  class RestartException < StackUnwindException
    attr_reader :restart_receiver, :restart_args
    def initialize(nonce, restart_receiver, restart_args)
      super(nonce)
      @restart_receiver = restart_receiver
      @restart_args = restart_args
    end
  end

  class Extensible #:nodoc:
    attr_accessor :user_module

    def initialize(&extension)
      m = Module.new(&extension)
      self.metaclass.instance_eval { include m }
      self.user_module = m
    end

    def metaclass
      class << self; self; end
    end

    def extended_with?(name)
      # In Ruby 1.8 instance_methods returns strings.  In 1.9,
      # symbols.  We go to string to prevent unnecessary symbol
      # generation.
      methods = self.user_module.instance_methods(false)
      methods.map(&:to_s).include?(name.to_s)
    end
  end

  # This is the base class for all conditions.
  class Condition

    attr_accessor :nonce

    # Signals this Condition.
    def signal
      SmokeSignals.signal(self, false)
    end

    # Signals this Condition.  If it is not rescued or restarted by a
    # handler, UnhandledSignalError is raised.
    def signal!
      SmokeSignals.signal(self, true)
    end

    # This should only be called from within a signal handler.  It
    # unwinds the stack to the point where SmokeSignals::handle was
    # called and returns from SmokeSignals::handle with the given
    # return value.
    def rescue(return_value=nil)
      raise RescueException.new(self.nonce, return_value)
    end

    # This should only be called from within a signal handler.  It
    # unwinds the stack up to the point where
    # SmokeSignals::with_restarts was called establishing the given
    # restart, calls the restart with the given arguments, and returns
    # the restart's return value from SmokeSignals::with_restarts.
    def restart(name, *args)
      SmokeSignals.restart(name, *args)
    end

    # When a Condition is signaled, this method is called by the
    # internals of SmokeSignals to determine whether it should be
    # handled by a given handler.
    #
    # If you override this method in subclasses of Condition, return a
    # Proc taking the Condition as an argument that should be run to
    # handle the signal.  Return nil to ignore the signal.
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

    def to_s
      self.class.to_s
    end

  end

  class << self

    # Establishes one or more signal handlers for the given block and
    # executes it.  Returns either the return value of the block or
    # the value passed to Condition#rescue in a handler.
    def handle(*new_handlers, &block)
      orig_handlers = handlers
      nonce = Object.new
      if new_handlers.last.is_a?(Hash)
        new_handlers.pop.reverse_each {|entry| new_handlers.push(entry) }
      end
      self.handlers = orig_handlers + new_handlers.map {|entry| [entry,nonce] }.reverse
      begin
        block.call
      rescue RescueException => e
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

    # Establishes one or more restarts for the given block and
    # executes it.  Returns either the return value of the block or
    # that of the restart if one was run.
    def with_restarts(extension, &block)
      orig_restarts = restarts
      nonce = Object.new
      if extension.is_a?(Proc)
        new_restarts = Extensible.new(&extension)
      else
        new_restarts = Extensible.new do
          extension.each_pair {|name,fn| define_method(name, &fn) }
        end
      end

      self.restarts = orig_restarts + [[new_restarts,nonce]]
      begin
        block.call
      rescue RestartException => e
        if nonce.equal?(e.nonce)
          e.restart_receiver.send(*e.restart_args)
        else
          raise e
        end
      ensure
        self.restarts = orig_restarts
      end
    end

    def restart(name, *args)
      fn = find_restart(name)
      if fn
        fn.call(*args)
      else
        raise NoRestartError.new(name)
      end
    end

    def find_restart(name)
      restarts.reverse_each do |extensible, nonce|
        next unless extensible.extended_with?(name)
        return lambda {|*args| raise RestartException.new(nonce, extensible, [name] + args) }
      end
      nil
    end

    private

    def handlers
      Thread.current[:SmokeSignalsHandlers] ||= []
    end

    def handlers=(arr)
      Thread.current[:SmokeSignalsHandlers] = arr
    end

    def restarts
      Thread.current[:SmokeSignalsRestarts] ||= []
    end

    def restarts=(arr)
      Thread.current[:SmokeSignalsRestarts] = arr
    end

  end

end
