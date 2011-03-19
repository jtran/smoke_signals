require File.expand_path(File.join(File.dirname(__FILE__), 'test_helper'))

class SmokeSignalsTest < Test::Unit::TestCase

  C = SmokeSignals::Condition

  def setup
    # This prevents brokenness in one test from affecting others.
    Thread.current[:ConditionHandlers] = nil
    Thread.current[:ConditionRestarts] = nil
  end

  def test_unhandled_signal_is_ignored
    C.new.signal
  end

  def test_unhandled_signal_raises_for_bang_version
    assert_raise SmokeSignals::UnhandledSignalError do
      C.new.signal!
    end
  end

  def test_handle_condition
    r = C.handle(C => lambda {|c| c.rescue(42) }) do
      C.new.signal!
    end
    assert_equal 42, r
    assert_equal [], C.class_eval { handlers }
  end

  def test_handle_condition_multiple_times
    a = []
    r = C.handle(C => lambda {|c| a << 8; c.rescue(42) }) do
      C.handle(C => lambda {|c| a << 7 }) do
        C.new.signal!
      end
    end
    assert_equal 42, r
    assert_equal [7, 8], a
    assert_equal [], C.class_eval { handlers }
  end

  def test_unsignaled_handlers_do_not_run
    a = []
    r = C.handle(String => lambda {|c| a << 9; c.rescue(9) },
                 C      => lambda {|c| a << 7 }) do
      C.new.signal
      42
    end
    assert_equal [7], a
    assert_equal r, 42
    assert_equal [], C.class_eval { handlers }
  end

  def test_unestablished_restart_raises
    assert_raise SmokeSignals::NoRestartError do
      C.handle(C => lambda {|c| C.restart(:some_restart_name) }) do
        C.new.signal!
      end
    end
  end

  def test_restart_with_hash
    r = C.handle(C => lambda {|c| C.restart(:use_square_of_value, 4) }) do
      r2 = C.with_restarts(:use_square_of_value => lambda {|v| v * v }) do
        C.new.signal!
      end
      assert_equal 16, r2
      r2 + 1
    end
    assert_equal 17, r
    assert_equal [], C.class_eval { handlers }
    assert_equal [], C.class_eval { restarts }
  end

  def test_restart_with_proc
    r = C.handle(C => lambda {|c| C.restart(:use_square_of_value, 4) }) do
      r2 = C.with_restarts(proc {
                             def use_square_of_value(v)
                               v * v
                             end

                             def use_nil
                               nil
                             end
                           }) do
        C.new.signal!
      end
      assert_equal 16, r2
      r2 + 1
    end
    assert_equal 17, r
    assert_equal [], C.class_eval { handlers }
    assert_equal [], C.class_eval { restarts }
  end

  def test_restart_multiple_times
    a = [:use_square_of_value, :use_value]
    b = []
    a.each do |name|
      C.handle(C => lambda {|c| C.restart(name, 4) }) do
        r = C.with_restarts(:use_square_of_value => lambda {|v| v * v },
                            :use_value           => lambda {|v| v }) do
          C.new.signal!
        end
        b << r
      end
    end
    assert_equal [16, 4], b
    assert_equal [], C.class_eval { handlers }
    assert_equal [], C.class_eval { restarts }
  end

end
