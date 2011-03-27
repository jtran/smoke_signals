require File.expand_path(File.join(File.dirname(__FILE__), 'test_helper'))

class SmokeSignalsTest < Test::Unit::TestCase

  S = SmokeSignals
  C = SmokeSignals::Condition

  def setup
    # This prevents brokenness in one test from affecting others.
    Thread.current[:SmokeSignalsHandlers] = nil
    Thread.current[:SmokeSignalsRestarts] = nil
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
    r = S.handle(lambda {|c| c.rescue(42) }) do
      C.new.signal!
    end
    assert_equal 42, r
    assert_equal [], S.class_eval { handlers }
  end

  def test_handle_condition_multiple_times
    a = []
    r = S.handle(lambda {|c| a << 8; c.rescue(42) }) do
      S.handle(lambda {|c| a << 7 }) do
        C.new.signal!
      end
    end
    assert_equal 42, r
    assert_equal [7, 8], a
    assert_equal [], S.class_eval { handlers }
  end

  def test_unsignaled_handlers_do_not_run
    a = []
    r = S.handle(String => lambda {|c| a << 9; c.rescue(9) },
                 C      => lambda {|c| a << 7 }) do
      C.new.signal
      42
    end
    assert_equal [7], a
    assert_equal r, 42
    assert_equal [], S.class_eval { handlers }
  end

  def test_unestablished_restart_raises
    assert_raise SmokeSignals::NoRestartError do
      S.handle(lambda {|c| c.restart(:some_restart_name) }) do
        C.new.signal!
      end
    end
  end

  def test_restart_with_hash
    r = S.handle(lambda {|c| c.restart(:use_square_of_value, 4) }) do
      r2 = S.with_restarts(:use_square_of_value => lambda {|v| v * v }) do
        C.new.signal!
      end
      assert_equal 16, r2
      r2 + 1
    end
    assert_equal 17, r
    assert_equal [], S.class_eval { handlers }
    assert_equal [], S.class_eval { restarts }
  end

  def test_restart_with_proc
    r = S.handle(lambda {|c| c.restart(:use_square_of_value, 4) }) do
      r2 = S.with_restarts(proc {
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
    assert_equal [], S.class_eval { handlers }
    assert_equal [], S.class_eval { restarts }
  end

  def test_restart_multiple_times
    a = [:use_square_of_value, :use_value]
    b = []
    a.each do |name|
      S.handle(lambda {|c| c.restart(name, 4) }) do
        r = S.with_restarts(:use_square_of_value => lambda {|v| v * v },
                            :use_value           => lambda {|v| v }) do
          C.new.signal!
        end
        b << r
      end
    end
    assert_equal [16, 4], b
    assert_equal [], S.class_eval { handlers }
    assert_equal [], S.class_eval { restarts }
  end

  def test_rescuing_executes_ensure_block
    a = []
    file = nil
    r = S.handle(lambda {|c| a << 7; c.rescue(42) }) do
      begin
        file = 'fake_file'
        C.new.signal
        fail 'should be handled with a rescue'
      ensure
        file = 'closed'
      end
    end
    assert_equal 42, r
    assert_equal 'closed', file
  end

  def test_restarting_executes_ensure_block
    a = []
    file = nil
    r = S.handle(lambda {|c| c.restart(:use_value, 42) }) do
      S.with_restarts(:use_value => lambda {|v| v }) do
        begin
          file = 'fake_file'
          C.new.signal
          fail 'should be handled with a restart'
        ensure
          file = 'closed'
        end
      end
    end
    assert_equal 42, r
    assert_equal 'closed', file
  end

  def test_restarting_executes_ensure_block_before_restart
    a = []
    r = S.handle(lambda {|c| c.restart(:use_value, 42) }) do
      S.with_restarts(:use_value => lambda {|v| a << 2; v }) do
        begin
          C.new.signal
          fail 'should be handled with a restart'
        ensure
          a << 1
        end
      end
    end
    assert_equal 42, r
    assert_equal [1, 2], a
  end

  def test_rescuing_from_nested_handlers
    a = []
    r = S.handle(C => lambda {|c| a << 3; c.rescue(42) }) do
      S.handle(String => lambda {|c| a << 4; c.rescue(5) }) do
        C.new.signal!
      end
      fail 'should be handled with a rescue'
    end
    assert_equal 42, r
    assert_equal [3], a
  end

  def test_restarting_from_nested_restarts
    a = []
    r = S.handle(lambda {|c| a << 3; c.restart(:use_value, 42) }) do
      r2 = S.with_restarts(:use_value => lambda {|v| a << 4; v }) do
        S.with_restarts(:use_square_of_value => lambda {|v| a << 5; v * v }) do
          C.new.signal!
          fail 'should be handled with a restart'
        end
        fail 'should be handled with a restart'
      end
      assert_equal [3, 4], a
      assert_equal 42, r2
      a << 6
      7
    end
    assert_equal [3, 4, 6], a
    assert_equal 7, r
  end

  def test_handle_in_multiple_threads
    S.handle(lambda {|c| 7 }) do
      t = Thread.new { assert_equal [], S.class_eval { handlers } }
      assert_equal 1, S.class_eval { handlers.size }
      t.join
    end
  end

  def test_restart_in_multiple_threads
    S.with_restarts(:use_value => lambda {|v| v }) do
      t = Thread.new { assert_equal [], S.class_eval { restarts } }
      assert_equal 1, S.class_eval { restarts.size }
      t.join
    end
  end

end
